// push-fanout — Supabase Edge Function (Deno)
//
// Invoked by a Database Webhook on INSERT into `messages` and `matches`.
// Looks up the recipient(s), checks their notification settings + quiet hours,
// and sends an FCM push. Runs with the service-role key (set as a secret), so it
// can read across RLS. The anon/app client never touches this.
//
// Deploy:  supabase functions deploy push-fanout --no-verify-jwt
// Secrets: supabase secrets set FCM_SERVER_KEY=... SB_SERVICE_ROLE=... SB_URL=...
// Webhook: Database > Webhooks > on INSERT messages & matches -> this function URL

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVER_KEY = Deno.env.get("FCM_SERVER_KEY")!;

const admin = createClient(SB_URL, SB_SERVICE_ROLE, {
  auth: { persistSession: false },
});

type WebhookPayload = {
  type: "INSERT";
  table: "messages" | "matches";
  record: Record<string, unknown>;
};

function inQuietHours(start: number | null, end: number | null): boolean {
  if (start == null || end == null) return false;
  const h = new Date().getUTCHours(); // NOTE: use per-user tz in production
  return start <= end ? h >= start && h < end : h >= start || h < end;
}

async function recipientsForMessage(record: Record<string, unknown>) {
  const conversationId = record.conversation_id as string;
  const senderId = record.sender_id as string;
  const { data } = await admin
    .from("conversations")
    .select("match_id, matches(user_a, user_b)")
    .eq("id", conversationId)
    .single();
  const m = (data as any)?.matches;
  if (!m) return [];
  return [m.user_a, m.user_b].filter((u: string) => u !== senderId);
}

async function sendToUser(userId: string, category: "messages" | "matches" | "likes",
                          title: string, body: string, payload: Record<string, string>) {
  const { data: settings } = await admin
    .from("user_settings")
    .select("notify_messages, notify_matches, notify_likes, quiet_hours_start, quiet_hours_end")
    .eq("user_id", userId)
    .single();
  if (!settings) return;
  const enabled = { messages: settings.notify_messages, matches: settings.notify_matches, likes: settings.notify_likes }[category];
  if (!enabled) return;
  if (inQuietHours(settings.quiet_hours_start, settings.quiet_hours_end)) return;

  const { data: devices } = await admin.from("devices").select("token").eq("user_id", userId);
  if (!devices?.length) return;

  await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: { "Authorization": `key=${FCM_SERVER_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      registration_ids: devices.map((d) => d.token),
      notification: { title, body },
      data: payload,
      android: { priority: "high" },
    }),
  });
}

Deno.serve(async (req) => {
  try {
    const { table, record } = (await req.json()) as WebhookPayload;

    if (table === "messages") {
      const recipients = await recipientsForMessage(record);
      const preview = (record.kind === "text" ? (record.body as string) : "📷 Photo") ?? "New message";
      for (const uid of recipients) {
        await sendToUser(uid, "messages", "New message", preview.slice(0, 120), {
          type: "message", conversation_id: String(record.conversation_id),
        });
      }
    } else if (table === "matches") {
      for (const uid of [record.user_a, record.user_b] as string[]) {
        await sendToUser(uid, "matches", "It's a match! 🎉", "You have a new match. Say hi!", {
          type: "match", match_id: String(record.id),
        });
      }
    }
    return new Response("ok");
  } catch (e) {
    console.error(e);
    return new Response("error", { status: 500 });
  }
});
