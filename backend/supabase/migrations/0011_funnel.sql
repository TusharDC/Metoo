-- ============================================================================
-- Shararat — the freemium funnel
--
--   10 free swipes -> 1-2 matches -> 10 free messages -> paywall
--
-- Everything here is enforced server-side. The client only ever *displays*
-- counters; it never decides whether a swipe, a match or a message is allowed.
-- A reinstall or a tampered build therefore buys nothing.
--
-- Payment provider is deliberately not modelled. `entitlements` records what a
-- user is owed; how they paid for it is the provider's problem, recorded in
-- `payments.provider` so Razorpay / Play Billing / Stripe can all slot in.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Tunables. Kept in a table, not constants, so the admin panel can change the
-- funnel without a migration.
-- ---------------------------------------------------------------------------
create table if not exists app_config (
  key   text primary key,
  value jsonb not null,
  note  text
);

insert into app_config (key, value, note) values
  ('free_swipes',      '10'::jsonb,      'Swipes allowed before the paywall'),
  ('free_messages',    '10'::jsonb,      'Messages allowed before the paywall'),
  ('match_positions',  '[3, 8]'::jsonb,  'Which like-numbers are guaranteed to match'),
  ('paid_match_rate',  '0.35'::jsonb,    'Match probability per like once paying'),
  ('daily_message_cap','200'::jsonb,     'Hard per-user daily ceiling, abuse guard')
on conflict (key) do nothing;

create or replace function cfg(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  select value from app_config where key = p_key;
$$;

-- ---------------------------------------------------------------------------
-- Per-user counters. One row per user, created on demand.
-- ---------------------------------------------------------------------------
create table if not exists user_quotas (
  user_id        uuid primary key references profiles(id) on delete cascade,
  swipes_used    int not null default 0,
  likes_used     int not null default 0,   -- likes only; passes are free
  messages_used  int not null default 0,
  matches_made   int not null default 0,
  messages_today int not null default 0,
  day            date not null default current_date,
  updated_at     timestamptz not null default now()
);

-- Credits and/or an active subscription. Provider-agnostic.
create table if not exists entitlements (
  user_id         uuid primary key references profiles(id) on delete cascade,
  message_credits int not null default 0 check (message_credits >= 0),
  subscribed_until timestamptz,
  updated_at      timestamptz not null default now()
);

-- Audit trail of anything that granted entitlement.
create table if not exists payments (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references profiles(id) on delete cascade,
  provider    text not null,              -- 'razorpay' | 'play' | 'stripe' | 'manual'
  provider_ref text,                      -- order/receipt id from that provider
  amount_minor int,                       -- in paise/cents, provider currency
  currency    text,
  credits_granted int not null default 0,
  days_granted    int not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists payments_user_idx on payments (user_id, created_at desc);

alter table app_config   enable row level security;
alter table user_quotas  enable row level security;
alter table entitlements enable row level security;
alter table payments     enable row level security;

-- Users may read their own counters, never write them. Writes happen inside
-- SECURITY DEFINER functions and the service-role Edge Functions only.
create policy quotas_self_read on user_quotas
  for select using (user_id = auth.uid());
create policy entitlements_self_read on entitlements
  for select using (user_id = auth.uid());
create policy payments_self_read on payments
  for select using (user_id = auth.uid());
-- app_config has no policy at all: readable only through cfg() / the panel.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function ensure_quota(p_user uuid)
returns user_quotas language plpgsql security definer set search_path = public as $$
declare q user_quotas;
begin
  insert into user_quotas(user_id) values (p_user) on conflict (user_id) do nothing;
  insert into entitlements(user_id) values (p_user) on conflict (user_id) do nothing;

  -- Roll the daily counter over at midnight.
  update user_quotas
  set messages_today = case when day < current_date then 0 else messages_today end,
      day            = greatest(day, current_date)
  where user_id = p_user
  returning * into q;

  return q;
end; $$;

-- Is this user currently paying for anything?
create or replace function is_paid(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    (select message_credits > 0 or (subscribed_until is not null and subscribed_until > now())
     from entitlements where user_id = p_user), false);
$$;

-- ---------------------------------------------------------------------------
-- ai_swipe: enforces the swipe quota and decides matches server-side.
--
-- Free users match on specific like-numbers (default the 3rd and 8th like) so
-- the first match lands well before the free swipes run out. Paying users
-- match probabilistically.
--
-- Returns { queued, matched_at_like, swipes_left, blocked, reason }.
-- `queued` stays true-on-match for client compatibility; the conversation is
-- still revealed on the existing 0009 delay.
-- ---------------------------------------------------------------------------
create or replace function ai_swipe(p_character_id smallint, p_action swipe_action)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v           uuid := auth.uid();
  q           user_quotas;
  free_swipes int  := (cfg('free_swipes'))::int;
  positions   jsonb := cfg('match_positions');
  paid        boolean;
  will_match  boolean := false;
  delay_secs  int;
  swipes_left int;
begin
  if v is null then raise exception 'not signed in'; end if;
  q := ensure_quota(v);
  paid := is_paid(v);

  -- Out of free swipes and not paying: refuse before recording anything.
  if not paid and q.swipes_used >= free_swipes then
    return jsonb_build_object(
      'queued', false, 'blocked', true, 'reason', 'out_of_swipes',
      'swipes_left', 0);
  end if;

  insert into ai_swipes(user_id, character_id, action)
  values (v, p_character_id, p_action)
  on conflict (user_id, character_id) do update set action = excluded.action;

  update user_quotas
  set swipes_used = swipes_used + 1,
      likes_used  = likes_used + case when p_action = 'pass' then 0 else 1 end,
      updated_at  = now()
  where user_id = v
  returning * into q;

  swipes_left := greatest(0, free_swipes - q.swipes_used);

  if p_action = 'pass' then
    return jsonb_build_object('queued', false, 'blocked', false,
                              'swipes_left', swipes_left);
  end if;

  -- Decide the match.
  if paid then
    will_match := random() < (cfg('paid_match_rate'))::numeric;
  else
    -- Guaranteed on the configured like-numbers, e.g. the 3rd and 8th like.
    will_match := positions @> to_jsonb(q.likes_used);
  end if;

  if not will_match then
    return jsonb_build_object('queued', false, 'blocked', false,
                              'swipes_left', swipes_left);
  end if;

  delay_secs := case when p_action = 'superlike'
                     then 30 + floor(random() * 31)::int
                     else 180 + floor(random() * 121)::int end;

  insert into ai_conversations(user_id, character_id, mood, revealed_at)
  values (v, p_character_id,
          (select default_mood from ai_characters where id = p_character_id),
          now() + (delay_secs || ' seconds')::interval)
  on conflict (user_id, character_id) do nothing;

  update user_quotas set matches_made = matches_made + 1 where user_id = v;

  return jsonb_build_object('queued', true, 'blocked', false,
                            'swipes_left', swipes_left);
end; $$;

-- ---------------------------------------------------------------------------
-- Message gating. `ai-chat` calls consume_message() BEFORE spending money on
-- an LLM call, and respects a false result.
-- ---------------------------------------------------------------------------
create or replace function can_send_message(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  q             user_quotas;
  free_messages int := (cfg('free_messages'))::int;
  daily_cap     int := (cfg('daily_message_cap'))::int;
begin
  select * into q from user_quotas where user_id = p_user;
  if q is null then
    return jsonb_build_object('allowed', true, 'messages_left', free_messages);
  end if;

  if q.day = current_date and q.messages_today >= daily_cap then
    return jsonb_build_object('allowed', false, 'reason', 'daily_cap');
  end if;

  if is_paid(p_user) then
    return jsonb_build_object('allowed', true, 'messages_left', null);
  end if;

  if q.messages_used >= free_messages then
    return jsonb_build_object('allowed', false, 'reason', 'out_of_messages',
                              'messages_left', 0);
  end if;

  return jsonb_build_object('allowed', true,
                            'messages_left', free_messages - q.messages_used);
end; $$;

-- Atomically check and consume. Spends a credit only once the free tier is up.
create or replace function consume_message(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  verdict       jsonb;
  free_messages int := (cfg('free_messages'))::int;
  q             user_quotas;
begin
  perform ensure_quota(p_user);
  verdict := can_send_message(p_user);
  if not (verdict->>'allowed')::boolean then
    return verdict;
  end if;

  update user_quotas
  set messages_used  = messages_used + 1,
      messages_today = messages_today + 1,
      updated_at     = now()
  where user_id = p_user
  returning * into q;

  -- Past the free allowance, burn a credit (subscribers burn none).
  if q.messages_used > free_messages
     and not exists (select 1 from entitlements e
                     where e.user_id = p_user
                       and e.subscribed_until is not null
                       and e.subscribed_until > now())
  then
    update entitlements
    set message_credits = greatest(0, message_credits - 1), updated_at = now()
    where user_id = p_user;
  end if;

  return jsonb_build_object('allowed', true,
    'messages_left', greatest(0, free_messages - q.messages_used));
end; $$;

-- ---------------------------------------------------------------------------
-- What the client shows: counters, never decisions.
-- ---------------------------------------------------------------------------
create or replace function get_my_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v uuid := auth.uid();
  q user_quotas;
  e entitlements;
  free_swipes   int := (cfg('free_swipes'))::int;
  free_messages int := (cfg('free_messages'))::int;
begin
  select * into q from user_quotas  where user_id = v;
  select * into e from entitlements where user_id = v;
  return jsonb_build_object(
    'swipes_left',   greatest(0, free_swipes   - coalesce(q.swipes_used, 0)),
    'messages_left', greatest(0, free_messages - coalesce(q.messages_used, 0)),
    'matches_made',  coalesce(q.matches_made, 0),
    'credits',       coalesce(e.message_credits, 0),
    'subscribed_until', e.subscribed_until,
    'is_paid',       is_paid(v)
  );
end; $$;

-- Grant entitlement. Service-role only: called by the payment webhook once a
-- provider confirms, never by the client.
create or replace function grant_entitlement(
  p_user uuid, p_provider text, p_provider_ref text,
  p_credits int default 0, p_days int default 0,
  p_amount_minor int default null, p_currency text default null
) returns void language plpgsql security definer set search_path = public as $$
begin
  perform ensure_quota(p_user);
  insert into payments(user_id, provider, provider_ref, amount_minor, currency,
                       credits_granted, days_granted)
  values (p_user, p_provider, p_provider_ref, p_amount_minor, p_currency,
          p_credits, p_days);

  update entitlements
  set message_credits  = message_credits + p_credits,
      subscribed_until = case when p_days > 0
        then greatest(coalesce(subscribed_until, now()), now()) + (p_days || ' days')::interval
        else subscribed_until end,
      updated_at = now()
  where user_id = p_user;
end; $$;

revoke execute on function grant_entitlement(uuid, text, text, int, int, int, text) from public, authenticated;
revoke execute on function consume_message(uuid)   from public, authenticated;
revoke execute on function can_send_message(uuid)  from public, authenticated;

grant execute on function ai_swipe(smallint, swipe_action), get_my_status to authenticated;
