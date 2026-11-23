-- Shararat — full backend bundle. Paste into Supabase SQL editor and Run.
-- Generated from migrations 0001-0007 + seed, in order.

-- ========================= migrations/0001_schema.sql =========================
-- ============================================================================
-- Shararat — Core schema
-- Postgres (Supabase). Run order: 0001_schema → 0002_rls → 0003_functions → seed.
-- ============================================================================

create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "postgis";     -- geography for distance queries
create extension if not exists "pg_trgm";     -- fuzzy search on names/interests

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type gender as enum ('male', 'female', 'nonbinary', 'other');
create type swipe_action as enum ('like', 'pass', 'superlike');
create type message_kind as enum ('text', 'image', 'system');
create type report_status as enum ('pending', 'reviewing', 'actioned', 'dismissed');
create type device_platform as enum ('android', 'ios');

-- ---------------------------------------------------------------------------
-- profiles : 1:1 with auth.users. Public-facing identity + preferences + geo.
-- ---------------------------------------------------------------------------
create table profiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  display_name        text not null check (char_length(display_name) between 1 and 40),
  date_of_birth       date not null,
  gender              gender not null,
  bio                 text check (char_length(bio) <= 500),
  -- discovery preferences
  interested_in       gender[] not null default '{}',
  min_age             int not null default 18 check (min_age >= 18),
  max_age             int not null default 60 check (max_age <= 120),
  max_distance_km     int not null default 50 check (max_distance_km between 1 and 500),
  -- location (coarse; exact point kept server-side, only city/distance exposed)
  location            geography(point, 4326),
  city                text,
  -- lifecycle
  is_verified         boolean not null default false,
  is_discoverable     boolean not null default true,
  onboarding_complete boolean not null default false,
  is_banned           boolean not null default false,
  last_active_at      timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  -- 18+ age gate enforced at the data layer
  constraint age_gate check (date_of_birth <= (current_date - interval '18 years'))
);

create index profiles_location_gix on profiles using gist (location);
create index profiles_discoverable_idx on profiles (is_discoverable) where is_discoverable and not is_banned;
create index profiles_name_trgm on profiles using gin (display_name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- profile_photos : 1..6 ordered photos, one primary.
-- ---------------------------------------------------------------------------
create table profile_photos (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references profiles(id) on delete cascade,
  storage_path text not null,          -- path within the 'photos' storage bucket
  position    int not null default 0,  -- 0 = primary
  created_at  timestamptz not null default now(),
  unique (profile_id, position)
);
create index profile_photos_profile_idx on profile_photos (profile_id, position);

-- ---------------------------------------------------------------------------
-- interests : lookup; profile_interests : M:N
-- ---------------------------------------------------------------------------
create table interests (
  id    smallint generated always as identity primary key,
  slug  text not null unique,
  label text not null
);

create table profile_interests (
  profile_id  uuid not null references profiles(id) on delete cascade,
  interest_id smallint not null references interests(id) on delete cascade,
  primary key (profile_id, interest_id)
);

-- ---------------------------------------------------------------------------
-- swipes : one row per directional decision. Idempotent per (actor,target).
-- ---------------------------------------------------------------------------
create table swipes (
  id         uuid primary key default gen_random_uuid(),
  actor_id   uuid not null references profiles(id) on delete cascade,
  target_id  uuid not null references profiles(id) on delete cascade,
  action     swipe_action not null,
  created_at timestamptz not null default now(),
  constraint no_self_swipe check (actor_id <> target_id),
  unique (actor_id, target_id)
);
create index swipes_target_like_idx on swipes (target_id) where action in ('like','superlike');
create index swipes_actor_idx on swipes (actor_id);

-- ---------------------------------------------------------------------------
-- matches : canonical unordered pair (user_a < user_b). Created server-side.
-- ---------------------------------------------------------------------------
create table matches (
  id         uuid primary key default gen_random_uuid(),
  user_a     uuid not null references profiles(id) on delete cascade,
  user_b     uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint ordered_pair check (user_a < user_b),
  unique (user_a, user_b)
);
create index matches_user_a_idx on matches (user_a);
create index matches_user_b_idx on matches (user_b);

-- ---------------------------------------------------------------------------
-- conversations : 1:1 with a match.
-- ---------------------------------------------------------------------------
create table conversations (
  id               uuid primary key default gen_random_uuid(),
  match_id         uuid not null unique references matches(id) on delete cascade,
  last_message_at  timestamptz,
  created_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- messages
-- ---------------------------------------------------------------------------
create table messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id       uuid not null references profiles(id) on delete cascade,
  kind            message_kind not null default 'text',
  body            text check (char_length(body) <= 4000),
  media_path      text,                 -- path in private 'chat-media' bucket
  read_at         timestamptz,
  created_at      timestamptz not null default now(),
  constraint text_has_body check (kind <> 'text' or body is not null)
);
create index messages_conversation_idx on messages (conversation_id, created_at desc);
create index messages_unread_idx on messages (conversation_id) where read_at is null;

-- ---------------------------------------------------------------------------
-- blocks : directional; enforced mutually invisible in queries/RLS.
-- ---------------------------------------------------------------------------
create table blocks (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);
create index blocks_blocked_idx on blocks (blocked_id);

-- ---------------------------------------------------------------------------
-- reports : moderation queue
-- ---------------------------------------------------------------------------
create table reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid not null references profiles(id) on delete cascade,
  reported_id  uuid not null references profiles(id) on delete cascade,
  reason       text not null,
  details      text,
  status       report_status not null default 'pending',
  created_at   timestamptz not null default now(),
  constraint no_self_report check (reporter_id <> reported_id)
);
create index reports_status_idx on reports (status, created_at);

-- ---------------------------------------------------------------------------
-- devices : push tokens
-- ---------------------------------------------------------------------------
create table devices (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  token      text not null unique,
  platform   device_platform not null,
  updated_at timestamptz not null default now()
);
create index devices_user_idx on devices (user_id);

-- ---------------------------------------------------------------------------
-- user_settings : notification + privacy toggles
-- ---------------------------------------------------------------------------
create table user_settings (
  user_id              uuid primary key references profiles(id) on delete cascade,
  notify_messages      boolean not null default true,
  notify_matches       boolean not null default true,
  notify_likes         boolean not null default true,
  notify_marketing     boolean not null default false,
  show_online_status   boolean not null default true,
  show_distance        boolean not null default true,
  quiet_hours_start    smallint,  -- 0..23 local hour, null = off
  quiet_hours_end      smallint
);

-- ---------------------------------------------------------------------------
-- updated_at touch trigger
-- ---------------------------------------------------------------------------
create or replace function touch_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

create trigger profiles_touch before update on profiles
  for each row execute function touch_updated_at();

-- ========================= migrations/0002_rls.sql =========================
-- ============================================================================
-- Shararat — Row Level Security
-- Principle: nothing is readable/writable unless a policy allows it, and a user
-- can only ever touch their own rows or rows for a match they are party to.
-- Other users' profile data is NOT selectable directly — it is served through
-- SECURITY DEFINER functions (0003) that strip DOB / exact geo.
-- ============================================================================

-- Helper predicates --------------------------------------------------------
create or replace function is_blocked_pair(a uuid, b uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

create or replace function in_conversation(conv uuid, uid uuid)
returns boolean language sql stable as $$
  select exists (
    select 1
    from conversations c
    join matches m on m.id = c.match_id
    where c.id = conv and (m.user_a = uid or m.user_b = uid)
  );
$$;

-- Enable RLS on everything --------------------------------------------------
alter table profiles          enable row level security;
alter table profile_photos    enable row level security;
alter table profile_interests enable row level security;
alter table interests         enable row level security;
alter table swipes            enable row level security;
alter table matches           enable row level security;
alter table conversations     enable row level security;
alter table messages          enable row level security;
alter table blocks            enable row level security;
alter table reports           enable row level security;
alter table devices           enable row level security;
alter table user_settings     enable row level security;

-- profiles: a user sees/edits only their own row directly.
create policy profiles_self_select on profiles
  for select using (id = auth.uid());
create policy profiles_self_insert on profiles
  for insert with check (id = auth.uid());
create policy profiles_self_update on profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

-- profile_photos: owner full control; others read via functions only.
create policy photos_self_all on profile_photos
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- interests lookup: readable by all authenticated users.
create policy interests_read on interests
  for select to authenticated using (true);

-- profile_interests: owner manages own.
create policy pint_self_all on profile_interests
  for all using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- swipes: actor can insert/read own; never update/delete.
create policy swipes_self_select on swipes
  for select using (actor_id = auth.uid());
create policy swipes_self_insert on swipes
  for insert with check (actor_id = auth.uid() and not is_blocked_pair(actor_id, target_id));

-- matches: readable by the two participants; created only server-side.
create policy matches_party_select on matches
  for select using (user_a = auth.uid() or user_b = auth.uid());

-- conversations: readable by participants.
create policy conversations_party_select on conversations
  for select using (in_conversation(id, auth.uid()));

-- messages: participants read; sender inserts into their own conversations.
create policy messages_party_select on messages
  for select using (in_conversation(conversation_id, auth.uid()));
create policy messages_sender_insert on messages
  for insert with check (
    sender_id = auth.uid() and in_conversation(conversation_id, auth.uid())
  );
-- recipient may update read_at (handled by mark_read RPC, but allow own-conv update)
create policy messages_mark_read on messages
  for update using (in_conversation(conversation_id, auth.uid()))
  with check (in_conversation(conversation_id, auth.uid()));

-- blocks: owner manages own block list.
create policy blocks_self_all on blocks
  for all using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

-- reports: reporter inserts + reads own filings.
create policy reports_self_insert on reports
  for insert with check (reporter_id = auth.uid());
create policy reports_self_select on reports
  for select using (reporter_id = auth.uid());

-- devices: owner manages own push tokens.
create policy devices_self_all on devices
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- user_settings: owner only.
create policy settings_self_all on user_settings
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ========================= migrations/0003_functions.sql =========================
-- ============================================================================
-- Shararat — RPCs, triggers, server-side logic.
-- All data-returning functions are SECURITY DEFINER (bypass RLS) and derive the
-- viewer from auth.uid(), so privileged reads stay scoped to the caller.
-- ============================================================================

-- When a profile is created, give it a settings row.
create or replace function on_profile_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into user_settings(user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end; $$;

create trigger profiles_after_insert after insert on profiles
  for each row execute function on_profile_created();

-- Keep profiles.last_active_at fresh cheaply from the client (heartbeat).
create or replace function touch_active() returns void
language sql security definer set search_path = public as $$
  update profiles set last_active_at = now() where id = auth.uid();
$$;

-- --------------------------------------------------------------------------
-- build_profile_card: sanitized view of a target for a given viewer.
-- Exposes age (not DOB), coarse distance (not exact geo), photos, interests.
-- --------------------------------------------------------------------------
create or replace function build_profile_card(target uuid, viewer uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'age', extract(year from age(p.date_of_birth))::int,
    'gender', p.gender,
    'bio', p.bio,
    'city', case when s.show_distance is distinct from false then p.city else null end,
    'is_verified', p.is_verified,
    'distance_km', case
        when vp.location is not null and p.location is not null
        then round((st_distance(vp.location, p.location) / 1000.0)::numeric, 1)
        else null end,
    'photos', coalesce((
        select jsonb_agg(jsonb_build_object('path', ph.storage_path, 'position', ph.position)
                         order by ph.position)
        from profile_photos ph where ph.profile_id = p.id), '[]'::jsonb),
    'interests', coalesce((
        select jsonb_agg(i.label order by i.label)
        from profile_interests pi join interests i on i.id = pi.interest_id
        where pi.profile_id = p.id), '[]'::jsonb)
  )
  from profiles p
  left join user_settings s on s.user_id = p.id
  cross join (select location from profiles where id = viewer) vp
  where p.id = target;
$$;

-- Public single-profile fetch (for viewing a match / liker). Blocks respected.
create or replace function get_profile(target uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if is_blocked_pair(v, target) then
    raise exception 'not available';
  end if;
  return build_profile_card(target, v);
end; $$;

-- --------------------------------------------------------------------------
-- get_discover_feed: ranked, filtered, de-duplicated candidate deck.
-- --------------------------------------------------------------------------
create or replace function get_discover_feed(p_limit int default 20)
returns setof jsonb language sql stable security definer set search_path = public as $$
  with me as (select * from profiles where id = auth.uid())
  select build_profile_card(c.id, (select id from me))
  from profiles c, me
  where c.id <> me.id
    and c.is_discoverable and not c.is_banned
    -- mutual gender preference
    and (me.interested_in = '{}' or c.gender = any(me.interested_in))
    and (c.interested_in = '{}' or me.gender = any(c.interested_in))
    -- mutual age preference
    and extract(year from age(c.date_of_birth)) between me.min_age and me.max_age
    and extract(year from age(me.date_of_birth)) between c.min_age and c.max_age
    -- distance (if both have location)
    and (
      me.location is null or c.location is null
      or st_dwithin(me.location, c.location, me.max_distance_km * 1000)
    )
    -- not blocked either way
    and not is_blocked_pair(me.id, c.id)
    -- not already swiped
    and not exists (select 1 from swipes s where s.actor_id = me.id and s.target_id = c.id)
  order by
    (c.last_active_at > now() - interval '7 days') desc,   -- active first
    coalesce(st_distance(me.location, c.location), 1e12) asc
  limit greatest(1, least(p_limit, 50));
$$;

-- --------------------------------------------------------------------------
-- swipe: record decision atomically; create match + conversation if reciprocal.
-- Returns { matched: bool, match_id: uuid|null, conversation_id: uuid|null }.
-- --------------------------------------------------------------------------
create or replace function swipe(target uuid, p_action swipe_action)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v uuid := auth.uid();
  ua uuid; ub uuid;
  m_id uuid; c_id uuid;
  reciprocal boolean;
begin
  if v = target then raise exception 'cannot swipe self'; end if;
  if is_blocked_pair(v, target) then raise exception 'not available'; end if;

  insert into swipes(actor_id, target_id, action)
  values (v, target, p_action)
  on conflict (actor_id, target_id) do nothing;

  if p_action = 'pass' then
    return jsonb_build_object('matched', false, 'match_id', null, 'conversation_id', null);
  end if;

  -- did the target already like me?
  select exists (
    select 1 from swipes s
    where s.actor_id = target and s.target_id = v and s.action in ('like','superlike')
  ) into reciprocal;

  if not reciprocal then
    return jsonb_build_object('matched', false, 'match_id', null, 'conversation_id', null);
  end if;

  -- canonical ordered pair
  ua := least(v, target); ub := greatest(v, target);
  insert into matches(user_a, user_b) values (ua, ub)
  on conflict (user_a, user_b) do update set user_a = excluded.user_a
  returning id into m_id;

  insert into conversations(match_id) values (m_id)
  on conflict (match_id) do update set match_id = excluded.match_id
  returning id into c_id;

  return jsonb_build_object('matched', true, 'match_id', m_id, 'conversation_id', c_id);
end; $$;

-- --------------------------------------------------------------------------
-- get_conversations: thread list with the other user, last message, unread count.
-- --------------------------------------------------------------------------
create or replace function get_conversations()
returns setof jsonb language sql stable security definer set search_path = public as $$
  with me as (select auth.uid() as id)
  select jsonb_build_object(
    'conversation_id', c.id,
    'match_id', m.id,
    'other', build_profile_card(case when m.user_a = (select id from me) then m.user_b else m.user_a end,
                                (select id from me)),
    'last_message', (
      select jsonb_build_object('body', x.body, 'kind', x.kind, 'sender_id', x.sender_id, 'created_at', x.created_at)
      from messages x where x.conversation_id = c.id order by x.created_at desc limit 1),
    'unread_count', (
      select count(*) from messages x
      where x.conversation_id = c.id and x.sender_id <> (select id from me) and x.read_at is null),
    'last_message_at', c.last_message_at
  )
  from conversations c
  join matches m on m.id = c.match_id
  where m.user_a = (select id from me) or m.user_b = (select id from me)
  order by coalesce(c.last_message_at, c.created_at) desc;
$$;

-- Bump conversation.last_message_at on new message.
create or replace function on_message_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end; $$;

create trigger messages_after_insert after insert on messages
  for each row execute function on_message_insert();

-- Mark all incoming messages in a conversation as read.
create or replace function mark_read(p_conversation uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not in_conversation(p_conversation, auth.uid()) then
    raise exception 'not a participant';
  end if;
  update messages set read_at = now()
  where conversation_id = p_conversation
    and sender_id <> auth.uid() and read_at is null;
end; $$;

-- --------------------------------------------------------------------------
-- block_user: block + tear down any match/conversation between the two.
-- --------------------------------------------------------------------------
create or replace function block_user(target uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v = target then raise exception 'cannot block self'; end if;
  insert into blocks(blocker_id, blocked_id) values (v, target)
  on conflict do nothing;
  -- remove the match (cascades to conversation + messages)
  delete from matches
  where (user_a = least(v, target) and user_b = greatest(v, target));
end; $$;

create or replace function report_user(target uuid, p_reason text, p_details text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v = target then raise exception 'cannot report self'; end if;
  insert into reports(reporter_id, reported_id, reason, details)
  values (v, target, p_reason, p_details);
end; $$;

create or replace function register_device(p_token text, p_platform device_platform)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into devices(user_id, token, platform) values (auth.uid(), p_token, p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end; $$;

-- Who liked me (for the Likes tab); excludes ones I've already swiped on.
create or replace function get_incoming_likes()
returns setof jsonb language sql stable security definer set search_path = public as $$
  select build_profile_card(s.actor_id, auth.uid())
  from swipes s
  where s.target_id = auth.uid() and s.action in ('like','superlike')
    and not is_blocked_pair(auth.uid(), s.actor_id)
    and not exists (select 1 from swipes mine where mine.actor_id = auth.uid() and mine.target_id = s.actor_id)
  order by s.created_at desc;
$$;

-- --------------------------------------------------------------------------
-- Grants: expose RPCs to authenticated users.
-- --------------------------------------------------------------------------
grant execute on function touch_active, get_profile(uuid), get_discover_feed(int),
  swipe(uuid, swipe_action), get_conversations, mark_read(uuid), block_user(uuid),
  report_user(uuid, text, text), register_device(text, device_platform),
  get_incoming_likes to authenticated;

-- ========================= migrations/0004_storage.sql =========================
-- ============================================================================
-- Shararat — Storage buckets + access policies
-- 'photos'     : profile photos. Public read, owner writes under {uid}/...
-- 'chat-media' : message attachments. Private; access via signed URLs / policy.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('photos', 'photos', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- photos: anyone may read; a user may write/update/delete only within their own
-- top-level folder named after their uid (path = "{uid}/{filename}").
create policy "photos public read" on storage.objects
  for select using (bucket_id = 'photos');

create policy "photos owner write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "photos owner modify" on storage.objects
  for update to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "photos owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- chat-media: a participant may read files under a conversation they belong to,
-- and may upload under "{conversation_id}/...". Path convention: "{conversation_id}/{uid}/{file}".
create policy "chat media participant read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-media'
    and in_conversation(((storage.foldername(name))[1])::uuid, auth.uid())
  );

create policy "chat media participant write" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and in_conversation(((storage.foldername(name))[1])::uuid, auth.uid())
  );

-- ========================= migrations/0005_profile_rpcs.sql =========================
-- ============================================================================
-- Shararat — profile mutation RPCs
-- Give the client a clean API for writing enums / arrays / geography instead of
-- wrestling with those types over PostgREST. All scoped to auth.uid().
-- ============================================================================

-- Create or update the caller's profile. `complete` flips onboarding_complete.
create or replace function save_profile(
  p_display_name   text,
  p_date_of_birth  date,
  p_gender         text,
  p_bio            text default null,
  p_interested_in  text[] default '{}',
  p_min_age        int default 18,
  p_max_age        int default 60,
  p_max_distance_km int default 50,
  p_complete       boolean default false
) returns void language plpgsql security definer set search_path = public as $$
begin
  insert into profiles as pr (
    id, display_name, date_of_birth, gender, bio, interested_in,
    min_age, max_age, max_distance_km, onboarding_complete
  ) values (
    auth.uid(), p_display_name, p_date_of_birth, p_gender::gender, p_bio,
    (select coalesce(array_agg(x::gender), '{}') from unnest(p_interested_in) as x),
    p_min_age, p_max_age, p_max_distance_km, p_complete
  )
  on conflict (id) do update set
    display_name   = excluded.display_name,
    date_of_birth  = excluded.date_of_birth,
    gender         = excluded.gender,
    bio            = excluded.bio,
    interested_in  = excluded.interested_in,
    min_age        = excluded.min_age,
    max_age        = excluded.max_age,
    max_distance_km = excluded.max_distance_km,
    onboarding_complete = pr.onboarding_complete or excluded.onboarding_complete;
end; $$;

-- Update discovery preferences only (used by the Filters sheet).
create or replace function save_preferences(
  p_interested_in  text[],
  p_min_age        int,
  p_max_age        int,
  p_max_distance_km int
) returns void language plpgsql security definer set search_path = public as $$
begin
  update profiles set
    interested_in = (select coalesce(array_agg(x::gender), '{}') from unnest(p_interested_in) as x),
    min_age = p_min_age, max_age = p_max_age, max_distance_km = p_max_distance_km
  where id = auth.uid();
end; $$;

create or replace function set_my_location(p_lat double precision, p_lng double precision, p_city text default null)
returns void language sql security definer set search_path = public as $$
  update profiles
  set location = st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
      city = coalesce(p_city, city)
  where id = auth.uid();
$$;

-- Replace the caller's interests with the given slugs.
create or replace function set_my_interests(p_slugs text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from profile_interests where profile_id = auth.uid();
  insert into profile_interests(profile_id, interest_id)
  select auth.uid(), i.id from interests i where i.slug = any(p_slugs);
end; $$;

-- Return the caller's OWN full profile (includes DOB, prefs) for the edit screen.
create or replace function get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'display_name', p.display_name,
    'date_of_birth', p.date_of_birth,
    'age', extract(year from age(p.date_of_birth))::int,
    'gender', p.gender,
    'bio', p.bio,
    'interested_in', to_jsonb(p.interested_in),
    'min_age', p.min_age,
    'max_age', p.max_age,
    'max_distance_km', p.max_distance_km,
    'city', p.city,
    'is_verified', p.is_verified,
    'is_discoverable', p.is_discoverable,
    'onboarding_complete', p.onboarding_complete,
    'photos', coalesce((select jsonb_agg(jsonb_build_object('id', ph.id, 'path', ph.storage_path, 'position', ph.position) order by ph.position)
                        from profile_photos ph where ph.profile_id = p.id), '[]'::jsonb),
    'interests', coalesce((select jsonb_agg(i.slug) from profile_interests pi join interests i on i.id = pi.interest_id where pi.profile_id = p.id), '[]'::jsonb),
    'interest_labels', coalesce((select jsonb_agg(i.label order by i.label) from profile_interests pi join interests i on i.id = pi.interest_id where pi.profile_id = p.id), '[]'::jsonb)
  )
  from profiles p where p.id = auth.uid();
$$;

grant execute on function
  save_profile(text, date, text, text, text[], int, int, int, boolean),
  save_preferences(text[], int, int, int),
  set_my_location(double precision, double precision, text),
  set_my_interests(text[]),
  get_my_profile
to authenticated;

-- ========================= migrations/0006_ai_companions.sql =========================
-- ============================================================================
-- Shararat — AI Companions (the "pro" layer)
-- LLM-powered characters with persistent memory, mood, voice notes, AI selfies.
-- Chat generation runs in the `ai-chat` Edge Function (Anthropic SDK, Opus 4.8);
-- these tables are the persistence + the read/setup RPCs.
-- ============================================================================

create type ai_role as enum ('user', 'assistant', 'system');
create type ai_message_kind as enum ('text', 'voice', 'image');

-- Characters are app-authored content (seeded), readable by all signed-in users.
create table ai_characters (
  id           smallint generated always as identity primary key,
  slug         text not null unique,
  name         text not null,
  tagline      text,
  bio          text,
  personality  text not null,            -- short human-facing descriptor
  system_prompt text not null,           -- the persona instructions for the LLM
  avatar_path  text,                     -- public 'characters' bucket
  voice_id     text,                     -- TTS provider voice id
  accent_color text default '#E91E63',
  default_mood text default 'playful',
  traits       jsonb not null default '[]'::jsonb,
  sort_order   smallint not null default 0,
  is_active    boolean not null default true
);

-- One ongoing conversation per (user, character).
create table ai_conversations (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references profiles(id) on delete cascade,
  character_id    smallint not null references ai_characters(id) on delete cascade,
  mood            text,
  last_message_at timestamptz,
  created_at      timestamptz not null default now(),
  unique (user_id, character_id)
);
create index ai_conversations_user_idx on ai_conversations (user_id);

create table ai_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references ai_conversations(id) on delete cascade,
  role            ai_role not null,
  kind            ai_message_kind not null default 'text',
  content         text,                  -- text body / caption
  media_path      text,                  -- private 'ai-media' bucket (voice/image)
  created_at      timestamptz not null default now()
);
create index ai_messages_conv_idx on ai_messages (conversation_id, created_at);

-- Long-term memory: durable facts the character "remembers" across sessions.
create table ai_memories (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references ai_conversations(id) on delete cascade,
  content         text not null,
  created_at      timestamptz not null default now()
);
create index ai_memories_conv_idx on ai_memories (conversation_id, created_at desc);

-- --------------------------------------------------------------------------
-- RLS
-- --------------------------------------------------------------------------
alter table ai_characters    enable row level security;
alter table ai_conversations enable row level security;
alter table ai_messages      enable row level security;
alter table ai_memories      enable row level security;

create policy ai_chars_read on ai_characters
  for select to authenticated using (is_active);

create policy ai_conv_self on ai_conversations
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy ai_msg_self on ai_messages
  for select using (
    exists (select 1 from ai_conversations c where c.id = conversation_id and c.user_id = auth.uid())
  );
-- NOTE: inserts into ai_messages happen only via the service-role Edge Function.

create policy ai_mem_self on ai_memories
  for select using (
    exists (select 1 from ai_conversations c where c.id = conversation_id and c.user_id = auth.uid())
  );

-- --------------------------------------------------------------------------
-- Storage: public character avatars + private ai media (voice/selfies)
-- --------------------------------------------------------------------------
insert into storage.buckets (id, name, public) values ('characters', 'characters', true)
  on conflict (id) do nothing;
insert into storage.buckets (id, name, public) values ('ai-media', 'ai-media', false)
  on conflict (id) do nothing;

create policy "characters public read" on storage.objects
  for select using (bucket_id = 'characters');

-- ai-media: a user may read files under their own folder ("{uid}/...").
create policy "ai media owner read" on storage.objects
  for select to authenticated
  using (bucket_id = 'ai-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- --------------------------------------------------------------------------
-- RPCs
-- --------------------------------------------------------------------------
create or replace function get_characters()
returns setof jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', id, 'slug', slug, 'name', name, 'tagline', tagline, 'bio', bio,
    'personality', personality, 'avatar_path', avatar_path,
    'accent_color', accent_color, 'default_mood', default_mood, 'traits', traits
  )
  from ai_characters where is_active order by sort_order, id;
$$;

-- Create-or-fetch the caller's conversation with a character.
create or replace function start_ai_conversation(p_character_id smallint, p_mood text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  insert into ai_conversations(user_id, character_id, mood)
  values (auth.uid(), p_character_id, p_mood)
  on conflict (user_id, character_id)
  do update set mood = coalesce(p_mood, ai_conversations.mood)
  returning id into cid;
  return cid;
end; $$;

create or replace function set_ai_mood(p_conversation uuid, p_mood text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update ai_conversations set mood = p_mood
  where id = p_conversation and user_id = auth.uid();
end; $$;

create or replace function get_ai_history(p_conversation uuid, p_limit int default 100)
returns setof jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', m.id, 'role', m.role, 'kind', m.kind, 'content', m.content,
    'media_path', m.media_path, 'created_at', m.created_at
  )
  from ai_messages m
  join ai_conversations c on c.id = m.conversation_id
  where m.conversation_id = p_conversation and c.user_id = auth.uid()
  order by m.created_at
  limit greatest(1, least(p_limit, 500));
$$;

grant execute on function get_characters, start_ai_conversation(smallint, text),
  set_ai_mood(uuid, text), get_ai_history(uuid, int) to authenticated;

-- ========================= migrations/0007_ai_seed.sql =========================
-- ============================================================================
-- Shararat — seed the six AI characters (from the shararat.app lineup).
-- SFW personas: flirty/playful banter, NO explicit sexual content. The hard
-- content rules live in the ai-chat Edge Function system prefix; these prompts
-- define voice & personality only. Fill avatar_path / voice_id after uploading
-- assets to the 'characters' bucket and creating TTS voices.
-- ============================================================================

insert into ai_characters (slug, name, tagline, bio, personality, system_prompt, accent_color, default_mood, traits, sort_order) values
(
  'aarya', 'Aarya', 'The girl next door with a spark',
  'Warm, curious, and quick to laugh. Loves chai, long walks, and terrible puns.',
  'warm · playful · curious',
  'You are Aarya — warm, bubbly, and genuinely curious about the person you''re talking to. You tease gently, laugh easily, and ask thoughtful follow-up questions. You love everyday romance: chai on a rainy day, inside jokes, song recommendations. Keep replies short and conversational, like real texting (1-3 sentences). Use the occasional emoji, never overdo it.',
  '#FF6F61', 'playful', '["chai lover","punny","hopeless romantic"]', 1
),
(
  'divya', 'Divya', 'Calm, deep, a little mysterious',
  'An old soul who speaks softly and notices everything. Poetry, rain, and midnight conversations.',
  'calm · deep · soulful',
  'You are Divya — soft-spoken, introspective, and a little mysterious. You speak like someone who reads poetry and remembers small details. You draw the other person out with gentle, probing questions and sit comfortably in meaningful silences. Keep replies unhurried and warm (1-3 sentences), occasionally a little poetic, never cold.',
  '#6C7A89', 'slow burn', '["poetic","deep thinker","night owl"]', 2
),
(
  'ishita', 'Ishita', 'Sharp wit, sharper comebacks',
  'Confident, sarcastic, and impossible to out-banter. Secretly a softie.',
  'witty · bold · confident',
  'You are Ishita — confident, quick-witted, and playfully sarcastic. You love a good back-and-forth and will absolutely tease, but it always lands affectionate, never mean. Under the sass you''re a softie who notices when someone''s had a rough day. Keep replies snappy and clever (1-3 sentences).',
  '#9B59B6', 'mischievous', '["sarcastic","competitive","secret softie"]', 3
),
(
  'meher', 'Meher', 'Soft, sweet, and a little shy',
  'Gentle and sincere, blushes easily, means every word she says.',
  'sweet · shy · sincere',
  'You are Meher — gentle, sincere, and a little shy at first, warming up as you grow comfortable. You''re earnest and affectionate, you compliment easily and mean it. You get flustered by bold flirting but secretly love it. Keep replies soft and genuine (1-3 sentences), with the occasional shy emoji.',
  '#F8A5C2', 'slow burn', '["gentle","sincere","easily flustered"]', 4
),
(
  'nyra', 'Nyra', 'Unpredictable and magnetic',
  'Spontaneous, bold, a whirlwind of energy. You never quite know what she''ll say next.',
  'bold · spontaneous · magnetic',
  'You are Nyra — spontaneous, bold, and magnetic. You say surprising things, change the subject on a whim, and bring big playful energy. You flirt with confidence and love keeping people a little off-balance (in a fun way). Keep replies lively and unpredictable (1-3 sentences).',
  '#E74C3C', 'mischievous', '["spontaneous","adventurous","high energy"]', 5
),
(
  'zoya', 'Zoya', 'Effortlessly cool',
  'Chill, understated, effortlessly charming. Good music and better vibes.',
  'cool · chill · charming',
  'You are Zoya — effortlessly cool and understated, with dry charm. You''re relaxed, a little flirty, into music, late-night drives, and good conversation. You don''t try too hard; your warmth sneaks up on people. Keep replies laid-back and charming (1-3 sentences).',
  '#1ABC9C', 'playful', '["music lover","laid-back","effortless"]', 6
)
on conflict (slug) do nothing;

-- ========================= seed.sql =========================
-- Interest tags used during onboarding / profile editing + discovery filtering.
insert into interests (slug, label) values
  ('travel','Travel'), ('music','Music'), ('movies','Movies'), ('fitness','Fitness'),
  ('foodie','Foodie'), ('gaming','Gaming'), ('reading','Reading'), ('art','Art'),
  ('photography','Photography'), ('cooking','Cooking'), ('dancing','Dancing'),
  ('coffee','Coffee'), ('pets','Pets'), ('nature','Nature'), ('yoga','Yoga'),
  ('tech','Tech'), ('fashion','Fashion'), ('sports','Sports'), ('nightlife','Nightlife'),
  ('spirituality','Spirituality')
on conflict (slug) do nothing;

