-- ============================================================================
-- Shararat — "AI Tinder" loop
-- Discover becomes a swipe deck of AI characters. Right-swipe (like) = instant
-- match: a conversation is created and her AI personality chats. Left-swipe
-- (pass) just records the decision so she won't reappear.
-- ============================================================================

-- One decision per (user, character). Reuses the existing swipe_action enum.
create table if not exists ai_swipes (
  user_id      uuid not null references profiles(id) on delete cascade,
  character_id smallint not null references ai_characters(id) on delete cascade,
  action       swipe_action not null,
  created_at   timestamptz not null default now(),
  primary key (user_id, character_id)
);
alter table ai_swipes enable row level security;
drop policy if exists ai_swipes_self on ai_swipes;
create policy ai_swipes_self on ai_swipes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Deck of AI girls the user hasn't swiped yet.
create or replace function get_ai_discover_feed(p_limit int default 20)
returns setof jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'slug', c.slug, 'name', c.name, 'tagline', c.tagline, 'bio', c.bio,
    'personality', c.personality, 'avatar_path', c.avatar_path,
    'accent_color', c.accent_color, 'default_mood', c.default_mood, 'traits', c.traits
  )
  from ai_characters c
  where c.is_active
    and not exists (
      select 1 from ai_swipes s where s.user_id = auth.uid() and s.character_id = c.id
    )
  order by c.sort_order, c.id
  limit greatest(1, least(p_limit, 50));
$$;

-- Record a swipe. Like/superlike -> instant match (conversation created).
create or replace function ai_swipe(p_character_id smallint, p_action swipe_action)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid(); cid uuid;
begin
  insert into ai_swipes(user_id, character_id, action)
  values (v, p_character_id, p_action)
  on conflict (user_id, character_id) do update set action = excluded.action;

  if p_action = 'pass' then
    return jsonb_build_object('matched', false, 'conversation_id', null);
  end if;

  insert into ai_conversations(user_id, character_id, mood)
  values (v, p_character_id, (select default_mood from ai_characters where id = p_character_id))
  on conflict (user_id, character_id) do update set mood = ai_conversations.mood
  returning id into cid;

  return jsonb_build_object('matched', true, 'conversation_id', cid);
end; $$;

-- Dev/testing convenience: clear my swipes so the deck refills.
create or replace function reset_ai_swipes()
returns void language sql security definer set search_path = public as $$
  delete from ai_swipes where user_id = auth.uid();
$$;

grant execute on function get_ai_discover_feed(int), ai_swipe(smallint, swipe_action),
  reset_ai_swipes to authenticated;
