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
