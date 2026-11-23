// ai-selfie — Supabase Edge Function (Deno)
//
// Generates an in-world "selfie" still for an AI character via fal.ai
// (text-to-image) and stores it privately for the user. SFW-constrained.
// TEMP: using fal.ai while the Gemini image quota is topped up; to switch back
// to Google Imagen/Gemini-image, restore the generateContent variant.
//
// Deploy:  supabase functions deploy ai-selfie
// Secrets: FAL_KEY   (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY auto-injected)
//
// Request (POST, Bearer user jwt): { conversation_id: uuid, scene?: string }
// Response: { image_path: string, caption: string }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FAL_KEY = Deno.env.get("FAL_KEY") ?? "";
// Default text-to-image model. Swap for a character-specific fal.ai model/LoRA
// for consistent faces.
const FAL_MODEL = "fal-ai/flux/schnell";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!FAL_KEY) return json({ error: "image generation not configured" }, 503);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const admin = createClient(SB_URL, SB_SERVICE_ROLE, { auth: { persistSession: false } });
  const asUser = createClient(SB_URL, SB_SERVICE_ROLE, {
    global: { headers: { Authorization: authHeader } }, auth: { persistSession: false },
  });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  const { conversation_id, scene } = await req.json();
  const { data: conv } = await admin
    .from("ai_conversations")
    .select("id, user_id, ai_characters(name, bio)")
    .eq("id", conversation_id)
    .single();
  if (!conv || conv.user_id !== user.id) return json({ error: "not found" }, 404);
  const character = (conv as any).ai_characters;

  const prompt =
    `Candid smartphone selfie portrait of a woman named ${character.name}. ${character.bio ?? ""}. ` +
    `${scene ? scene + ". " : ""}Natural lighting, warm friendly expression, fully clothed, tasteful, SFW, photorealistic.`;

  const res = await fetch(`https://fal.run/${FAL_MODEL}`, {
    method: "POST",
    headers: { "Authorization": `Key ${FAL_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({ prompt, image_size: "portrait_4_3", num_images: 1, enable_safety_checker: true }),
  });
  if (!res.ok) return json({ error: "generation failed", detail: await res.text() }, 502);
  const out = await res.json();
  const imageUrl = out?.images?.[0]?.url;
  if (!imageUrl) return json({ error: "no image", detail: out }, 502);

  const imgBytes = new Uint8Array(await (await fetch(imageUrl)).arrayBuffer());
  const path = `${user.id}/${crypto.randomUUID()}.jpg`;
  const { error } = await admin.storage.from("ai-media").upload(path, imgBytes, { contentType: "image/jpeg" });
  if (error) return json({ error: "storage failed" }, 500);

  const caption = scene ? `Here you go 📸` : `Thought you'd like this 😊`;
  await admin.from("ai_messages").insert({
    conversation_id, role: "assistant", kind: "image", content: caption, media_path: path,
  });
  await admin.from("ai_conversations").update({ last_message_at: new Date().toISOString() })
    .eq("id", conversation_id);

  return json({ image_path: path, caption });
});
