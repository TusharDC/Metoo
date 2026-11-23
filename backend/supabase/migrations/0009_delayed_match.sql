-- ============================================================================
-- Shararat — delayed matches
-- Right-swipe no longer pops an instant match. Instead the match "reveals" after
-- a random 3-5 minute delay (superlike ~30-60s) and appears in the Matches tab.
-- Implemented purely with a `revealed_at` timestamp — no background job needed:
-- the Matches list simply filters `revealed_at <= now()`.
-- ============================================================================

alter table ai_conversations
  add column if not exists revealed_at timestamptz not null default now();

-- Re-point ai_swipe: like/superlike creates a conversation revealed in the future.
-- Returns {queued: true} (the client shows no popup).
create or replace function ai_swipe(p_character_id smallint, p_action swipe_action)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v uuid := auth.uid();
  delay_secs int;
begin
  insert into ai_swipes(user_id, character_id, action)
  values (v, p_character_id, p_action)
  on conflict (user_id, character_id) do update set action = excluded.action;

  if p_action = 'pass' then
    return jsonb_build_object('queued', false);
  end if;

  -- superlike reveals quickly (30-60s); a normal like takes 3-5 min.
  delay_secs := case when p_action = 'superlike'
                     then 30 + floor(random() * 31)::int
                     else 180 + floor(random() * 121)::int end;

  insert into ai_conversations(user_id, character_id, mood, revealed_at)
  values (v, p_character_id,
          (select default_mood from ai_characters where id = p_character_id),
          now() + (delay_secs || ' seconds')::interval)
  on conflict (user_id, character_id) do nothing;

  return jsonb_build_object('queued', true);
end; $$;

-- Directly-opened conversations (Companions grid) should be visible immediately.
create or replace function start_ai_conversation(p_character_id smallint, p_mood text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  insert into ai_conversations(user_id, character_id, mood, revealed_at)
  values (auth.uid(), p_character_id, p_mood, now())
  on conflict (user_id, character_id)
  do update set mood = coalesce(p_mood, ai_conversations.mood), revealed_at = least(ai_conversations.revealed_at, now())
  returning id into cid;
  return cid;
end; $$;

-- The Matches tab: revealed conversations with character + last message.
create or replace function get_ai_matches()
returns setof jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'conversation_id', c.id,
    'revealed_at', c.revealed_at,
    'character', jsonb_build_object(
      'id', ch.id, 'slug', ch.slug, 'name', ch.name, 'tagline', ch.tagline,
      'bio', ch.bio, 'personality', ch.personality, 'avatar_path', ch.avatar_path,
      'accent_color', ch.accent_color, 'default_mood', ch.default_mood, 'traits', ch.traits),
    'last_message', (
      select jsonb_build_object('role', m.role, 'kind', m.kind, 'content', m.content, 'created_at', m.created_at)
      from ai_messages m where m.conversation_id = c.id order by m.created_at desc limit 1),
    'is_new', not exists (select 1 from ai_messages m where m.conversation_id = c.id)
  )
  from ai_conversations c
  join ai_characters ch on ch.id = c.character_id
  where c.user_id = auth.uid() and c.revealed_at <= now()
  order by coalesce(c.last_message_at, c.revealed_at) desc;
$$;

grant execute on function ai_swipe(smallint, swipe_action),
  start_ai_conversation(smallint, text), get_ai_matches to authenticated;
