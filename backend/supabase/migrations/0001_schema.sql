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
