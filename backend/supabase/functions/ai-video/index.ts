// ai-video — Supabase Edge Function (Deno)
//
// Generates a short in-world video clip for an AI character via Google Veo
// (the engine behind Google Flow), using the Gemini API's long-running
// generation endpoint. SFW-constrained. Stored privately for the user.
//
// Veo generation is asynchronous and can take 1-3 minutes. This function starts
// the job and polls up to a bounded wall-clock budget; if it hasn't finished it
// returns {status:"pending", operation} so the client can call again to resolve.
//
// Deploy:  supabase functions deploy ai-video
// Secrets: SB_URL, SB_SERVICE_ROLE, GEMINI_API_KEY
//
// NOTE: Veo model IDs and the operation response shape on the Gemini API evolve;
// `veo-3.0-fast-generate-001` is the current documented fast id. Verify/adjust
// the model id and the `generatedSamples[].video.uri` path at deploy time.
//
// Request (POST, Bearer user jwt):
//   { conversation_id: uuid, scene?: string, operation?: string }  // pass operation to resume polling
// Response: { status: "done", video_path, caption } | { status: "pending", operation }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const VEO_MODEL = "veo-3.1-fast-generate-preview";
const BASE = "https://generativelanguage.googleapis.com/v1beta";
const POLL_BUDGET_MS = 110_000; // stay under the function wall-clock limit

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "content-type": "application/json" } });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!GEMINI_API_KEY) return json({ error: "video generation not configured" }, 503);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const admin = createClient(SB_URL, SB_SERVICE_ROLE, { auth: { persistSession: false } });
  const asUser = createClient(SB_URL, SB_SERVICE_ROLE, {
    global: { headers: { Authorization: authHeader } }, auth: { persistSession: false },
  });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  const { conversation_id, scene, operation } = await req.json();
  const { data: conv } = await admin
    .from("ai_conversations")
    .select("id, user_id, ai_characters(name, bio)")
    .eq("id", conversation_id)
    .single();
  if (!conv || conv.user_id !== user.id) return json({ error: "not found" }, 404);
  const character = (conv as any).ai_characters;

  // Start the job (unless resuming an existing operation).
  let opName = operation as string | undefined;
  if (!opName) {
    const prompt =
      `Short, candid selfie-style video of a woman named ${character.name}. ${character.bio ?? ""}. ` +
      `${scene ? scene + ". " : ""}Speaking warmly to camera, natural lighting, fully clothed, tasteful, SFW.`;
    const start = await fetch(`${BASE}/models/${VEO_MODEL}:predictLongRunning?key=${GEMINI_API_KEY}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        instances: [{ prompt }],
        parameters: { aspectRatio: "9:16", personGeneration: "allow_adult" },
      }),
    });
    if (!start.ok) return json({ error: "start failed", detail: await start.text() }, 502);
    opName = (await start.json())?.name;
    if (!opName) return json({ error: "no operation" }, 502);
  }

  // Poll the long-running operation within budget.
  const deadline = Date.now() + POLL_BUDGET_MS;
  let op: any = null;
  while (Date.now() < deadline) {
    await sleep(8000);
    const r = await fetch(`${BASE}/${opName}?key=${GEMINI_API_KEY}`);
    op = await r.json();
    if (op?.done) break;
  }
  if (!op?.done) return json({ status: "pending", operation: opName });

  const videoUri =
    op?.response?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri ??
    op?.response?.generatedSamples?.[0]?.video?.uri;
  if (!videoUri) return json({ error: "no video in result", detail: op }, 502);

  const dl = await fetch(`${videoUri}&key=${GEMINI_API_KEY}`);
  const bytes = new Uint8Array(await dl.arrayBuffer());
  const path = `${user.id}/${crypto.randomUUID()}.mp4`;
  const { error } = await admin.storage.from("ai-media").upload(path, bytes, { contentType: "video/mp4" });
  if (error) return json({ error: "storage failed" }, 500);

  const caption = `Made you something 🎬`;
  await admin.from("ai_messages").insert({
    conversation_id, role: "assistant", kind: "image", content: caption, media_path: path,
  });
  await admin.from("ai_conversations").update({ last_message_at: new Date().toISOString() })
    .eq("id", conversation_id);

  return json({ status: "done", video_path: path, caption });
});
