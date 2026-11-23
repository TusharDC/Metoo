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
