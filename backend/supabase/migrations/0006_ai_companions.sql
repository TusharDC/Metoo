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
