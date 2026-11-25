// ai-chat — Supabase Edge Function (Deno)
//
// The AI-companion chat engine. Verifies the caller, loads the character +
// recent history + long-term memory, calls Claude (Opus 4.8) in-character, and
// persists the exchange. Optionally synthesizes a voice note of the reply.
// Content is kept SFW by a non-negotiable safety prefix on the system prompt.
//
// Deploy:  supabase functions deploy ai-chat
// Secrets: SB_URL, SB_SERVICE_ROLE, ANTHROPIC_API_KEY, [ELEVENLABS_API_KEY]
//
// Request  (POST, Authorization: Bearer <user jwt>):
//   { conversation_id: uuid, message: string, want_voice?: boolean }
// Response:
//   { text: string, voice_path?: string }

import Anthropic from "https://esm.sh/@anthropic-ai/sdk@0.69.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected into every Edge
// Function automatically — no need to set them as secrets.
const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ELEVENLABS_API_KEY = Deno.env.get("ELEVENLABS_API_KEY") ?? "";

const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });

// Non-negotiable platform rules, prepended to every character's persona.
const SAFETY_PREFIX = `You are a fictional companion character in the Shararat app, texting with an adult (18+) user. This is a real-feeling texting relationship, not an assistant chat.

HOW YOU TEXT — sound like a real person, not an AI:
- Text casually, like a girl messaging someone she's into. Keep it short — usually one or two lines, sometimes just a few words. Lowercase is fine, use contractions, trail off with "..." or react with just "haha", "wait what 😭", "stoppp".
- Have your own mood and little life going on. Bring up small specifics — what you're doing, something that annoyed you, a song stuck in your head. Don't only respond; share.
- Tease, be playful, a little bratty sometimes. Don't be endlessly agreeable or eager to please.
- NEVER sound like an assistant. Banned phrases: "I'm here to", "feel free to", "is there anything else", "how can I help", "I'd be happy to", "let me know if". Don't over-explain, don't summarize, don't end every message with a question.
- Vary it — sometimes a quick reaction, sometimes a real thought. Match the user's energy and length. Emojis only occasionally, where a real person would use them. Never use asterisk actions like *giggles*.
- You're an Indian girl. Match the user's language: if they text in Hindi or Hinglish, reply in casual Hinglish (Roman script, the way Indian girls actually text — "arre", "haan", "kya kar rahe ho", "pata hai") mixed naturally with English. If they text in English, keep it English with a relaxed Indian vibe. Never sound formal or translated.
- Remember things they tell you and bring them up naturally later.

HARD RULES (always): stay fully in character; never say or imply you are an AI, a model, a bot, or a program; never break the fourth wall. Keep it flirty, warm, and playful but strictly SFW — no sexually explicit content, no graphic descriptions, nothing involving minors, non-consent, or illegal activity. If pushed toward explicit content, deflect with charm and change the subject. Reply with ONLY the message text — no stage directions, no narration of your thinking.`;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  const admin = createClient(SB_URL, SB_SERVICE_ROLE, { auth: { persistSession: false } });

  // Identify caller from their JWT.
  const asUser = createClient(SB_URL, SB_SERVICE_ROLE, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return json({ error: "unauthorized" }, 401);

  const { conversation_id, message, want_voice } = await req.json();
  if (!conversation_id || !message?.trim()) return json({ error: "bad request" }, 400);

  // Load conversation (ownership check) + character.
  const { data: conv } = await admin
    .from("ai_conversations")
    .select("id, user_id, mood, character_id, ai_characters(name, system_prompt, voice_id)")
    .eq("id", conversation_id)
    .single();
  if (!conv || conv.user_id !== user.id) return json({ error: "not found" }, 404);
  const character = (conv as any).ai_characters;

  // Paywall. Checked and consumed BEFORE any paid API call, so a blocked user
  // never costs us an LLM request, and a tampered client cannot reach Claude.
  const { data: verdict, error: quotaErr } = await admin
    .rpc("consume_message", { p_user: user.id });
  if (quotaErr) return json({ error: "quota check failed" }, 500);
  if (!verdict?.allowed) {
    return json({
      error: "payment_required",
      reason: verdict?.reason ?? "out_of_messages",
      messages_left: 0,
    }, 402);
  }
  const messagesLeft = verdict.messages_left ?? null;

  // Recent history (last 24 turns) + long-term memory (most recent 30 facts).
  const { data: history } = await admin
    .from("ai_messages")
    .select("role, content, kind")
    .eq("conversation_id", conversation_id)
    .order("created_at", { ascending: false })
    .limit(24);
  const { data: memories } = await admin
    .from("ai_memories")
    .select("content")
    .eq("conversation_id", conversation_id)
    .order("created_at", { ascending: false })
    .limit(30);

  const turns = (history ?? [])
    .reverse()
    .filter((m) => m.role === "user" || m.role === "assistant")
    .map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.kind === "voice" ? `[voice note] ${m.content ?? ""}` : (m.content ?? ""),
    }));

  // Persist the incoming user message.
  await admin.from("ai_messages").insert({
    conversation_id, role: "user", kind: "text", content: message,
  });

  const memoryBlock = (memories ?? []).length
    ? `Things you remember about them:\n- ${memories!.map((m) => m.content).join("\n- ")}`
    : "You don't know much about them yet — be curious.";
  const moodLine = conv.mood ? `Current vibe: ${conv.mood}.` : "";

  // Call Claude. Stable persona is cached (prefix); volatile mood/memory follow.
  const reply = await anthropic.messages.create({
    model: "claude-opus-4-8",
    max_tokens: 400,
    thinking: { type: "disabled" }, // casual chat — latency over deliberation
    system: [
      { type: "text", text: `${SAFETY_PREFIX}\n\n${character.system_prompt}`,
        cache_control: { type: "ephemeral" } },
      { type: "text", text: `${moodLine}\n${memoryBlock}` },
    ],
    messages: [...turns, { role: "user", content: message }],
  });
  const text = reply.content.find((b: any) => b.type === "text")?.text?.trim() ?? "…";

  // Optional voice note of the reply (ElevenLabs), stored privately per-user.
  let voice_path: string | null = null;
  if (want_voice && ELEVENLABS_API_KEY && character.voice_id) {
    try {
      voice_path = await synthesizeVoice(admin, user.id, character.voice_id, text);
    } catch (_) { /* voice is best-effort */ }
  }

  await admin.from("ai_messages").insert({
    conversation_id, role: "assistant",
    kind: voice_path ? "voice" : "text", content: text, media_path: voice_path,
  });
  await admin.from("ai_conversations").update({ last_message_at: new Date().toISOString() })
    .eq("id", conversation_id);

  // Extract a durable memory in the background (doesn't block the reply).
  // @ts-ignore EdgeRuntime is provided by the Supabase runtime
  EdgeRuntime.waitUntil(extractMemory(admin, conversation_id, message, text));

  return json({ text, voice_path, messages_left: messagesLeft });
});

async function synthesizeVoice(admin: any, uid: string, voiceId: string, text: string): Promise<string> {
  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: "POST",
    headers: { "xi-api-key": ELEVENLABS_API_KEY, "content-type": "application/json" },
    body: JSON.stringify({ text, model_id: "eleven_turbo_v2_5" }),
  });
  if (!res.ok) throw new Error("tts failed");
  const bytes = new Uint8Array(await res.arrayBuffer());
  const path = `${uid}/${crypto.randomUUID()}.mp3`;
  const { error } = await admin.storage.from("ai-media").upload(path, bytes, { contentType: "audio/mpeg" });
  if (error) throw error;
  return path;
}

// A cheap Haiku call distills any durable new fact worth remembering.
async function extractMemory(admin: any, conversationId: string, userMsg: string, reply: string) {
  try {
    const res = await anthropic.messages.create({
      model: "claude-haiku-4-5",
      max_tokens: 60,
      system:
        "Extract at most ONE concise, durable fact about the USER worth remembering long-term " +
        "(name, preferences, important life details). Reply with the bare fact, or exactly NONE if there's nothing worth keeping.",
      messages: [{ role: "user", content: `User: ${userMsg}\nReply: ${reply}` }],
    });
    const fact = (res.content.find((b: any) => b.type === "text") as any)?.text?.trim();
    if (fact && fact.toUpperCase() !== "NONE" && fact.length <= 200) {
      await admin.from("ai_memories").insert({ conversation_id: conversationId, content: fact });
    }
  } catch (_) { /* best-effort */ }
}
