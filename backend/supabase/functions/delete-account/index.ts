// delete-account — Supabase Edge Function (Deno)
//
// Permanently deletes the calling user. Verifies the caller's JWT, then uses the
// service role to delete the auth user; the `profiles` FK (on delete cascade)
// removes all app data (photos rows, swipes, matches, conversations, messages,
// blocks, reports, devices, settings). Storage objects should be swept by a
// scheduled job or a storage trigger.
//
// Deploy:  supabase functions deploy delete-account
// Secrets: SB_URL, SB_SERVICE_ROLE (anon key is provided to the client call).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return new Response("unauthorized", { status: 401 });

  // Identify the caller from their JWT.
  const asUser = createClient(SB_URL, SB_SERVICE_ROLE, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await asUser.auth.getUser();
  if (error || !user) return new Response("unauthorized", { status: 401 });

  // Delete with elevated privileges.
  const admin = createClient(SB_URL, SB_SERVICE_ROLE, { auth: { persistSession: false } });

  // Best-effort: remove the user's photo folder from storage.
  try {
    const { data: files } = await admin.storage.from("photos").list(user.id);
    if (files?.length) {
      await admin.storage.from("photos").remove(files.map((f) => `${user.id}/${f.name}`));
    }
  } catch (_) { /* non-fatal */ }

  const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
  if (delErr) return new Response(delErr.message, { status: 500 });

  return new Response("ok");
});
