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
