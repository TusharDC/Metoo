// admin-api — Supabase Edge Function (Deno)
//
// The only way the admin panel touches the database. The panel is a static
// page: it holds no keys and talks to no table directly. It sends the admin
// password in `x-admin-token`; this function verifies it and does the work
// with the service-role key, which never leaves the server.
//
// Deploy:  supabase functions deploy admin-api
// Secrets: supabase secrets set ADMIN_TOKEN=<a long random string>
//          (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected)
//
// Request (POST): { action: string, ...args }
//
// NOTE: a shared password gives no audit trail of who changed what, and
// anyone it is shared with has full access until it is rotated. Rotate by
// setting ADMIN_TOKEN again; no redeploy needed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_TOKEN = Deno.env.get("ADMIN_TOKEN") ?? "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-admin-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), {
    status: s,
    headers: { ...cors, "content-type": "application/json" },
  });

/// Constant-time compare, so the response time can't be used to guess the
/// token character by character.
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const admin = createClient(SB_URL, SB_SERVICE_ROLE, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  if (!ADMIN_TOKEN) return json({ error: "admin api not configured" }, 503);
  const token = req.headers.get("x-admin-token") ?? "";
  if (!safeEqual(token, ADMIN_TOKEN)) {
    // Blunt delay to make online guessing tedious.
    await new Promise((r) => setTimeout(r, 1000));
    return json({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad request" }, 400);
  }
  const action = String(body.action ?? "");

  try {
    switch (action) {
      // ---------------------------------------------------------- characters
      case "list_characters": {
        const { data, error } = await admin
          .from("ai_characters")
          .select("*")
          .order("sort_order")
          .order("id");
        if (error) throw error;
        return json({ characters: data });
      }

      case "upsert_character": {
        const c = body.character as Record<string, unknown>;
        if (!c?.slug || !c?.name) return json({ error: "slug and name required" }, 400);
        const row = {
          slug: c.slug,
          name: c.name,
          tagline: c.tagline ?? null,
          bio: c.bio ?? null,
          personality: c.personality ?? "",
          system_prompt: c.system_prompt ?? "",
          avatar_path: c.avatar_path ?? null,
          voice_id: c.voice_id ?? null,
          accent_color: c.accent_color ?? "#E91E63",
          default_mood: c.default_mood ?? "playful",
          traits: c.traits ?? [],
          sort_order: c.sort_order ?? 0,
          is_active: c.is_active ?? true,
        };
        const { data, error } = await admin
          .from("ai_characters")
          .upsert(row, { onConflict: "slug" })
          .select()
          .single();
        if (error) throw error;
        return json({ character: data });
      }

      case "set_character_active": {
        const { error } = await admin
          .from("ai_characters")
          .update({ is_active: body.is_active })
          .eq("id", body.id);
        if (error) throw error;
        return json({ ok: true });
      }

      // Avatars: the panel uploads base64, we put it in the public bucket.
      case "upload_avatar": {
        const slug = String(body.slug ?? "");
        const b64 = String(body.data_base64 ?? "");
        const ext = String(body.ext ?? "jpg");
        if (!slug || !b64) return json({ error: "slug and data required" }, 400);
        const bytes = Uint8Array.from(atob(b64), (ch) => ch.charCodeAt(0));
        const path = `${slug}.${ext}`;
        const { error: upErr } = await admin.storage
          .from("characters")
          .upload(path, bytes, {
            contentType: ext === "png" ? "image/png" : "image/jpeg",
            upsert: true,
          });
        if (upErr) throw upErr;
        await admin.from("ai_characters").update({ avatar_path: path }).eq("slug", slug);
        return json({ avatar_path: path });
      }

      // --------------------------------------------------------------- users
      case "list_users": {
        const limit = Number(body.limit ?? 50);
        const { data, error } = await admin
          .from("profiles")
          .select(
            "id, display_name, date_of_birth, gender, is_banned, created_at, last_active_at",
          )
          .order("created_at", { ascending: false })
          .limit(limit);
        if (error) throw error;

        const ids = (data ?? []).map((u) => u.id);
        const { data: quotas } = await admin
          .from("user_quotas")
          .select("*")
          .in("user_id", ids);
        const { data: ents } = await admin
          .from("entitlements")
          .select("*")
          .in("user_id", ids);

        const byId = (rows: any[] | null, key = "user_id") =>
          Object.fromEntries((rows ?? []).map((r) => [r[key], r]));
        const q = byId(quotas);
        const e = byId(ents);
        return json({
          users: (data ?? []).map((u) => ({ ...u, quota: q[u.id] ?? null, entitlement: e[u.id] ?? null })),
        });
      }

      case "set_user_banned": {
        const { error } = await admin
          .from("profiles")
          .update({ is_banned: body.is_banned })
          .eq("id", body.user_id);
        if (error) throw error;
        return json({ ok: true });
      }

      case "grant_entitlement": {
        const { error } = await admin.rpc("grant_entitlement", {
          p_user: body.user_id,
          p_provider: "manual",
          p_provider_ref: "admin-panel",
          p_credits: Number(body.credits ?? 0),
          p_days: Number(body.days ?? 0),
        });
        if (error) throw error;
        return json({ ok: true });
      }

      // ------------------------------------------------------- conversations
      case "list_conversations": {
        const { data, error } = await admin
          .from("ai_conversations")
          .select(
            "id, user_id, character_id, mood, revealed_at, last_message_at, ai_characters(name, slug), profiles(display_name)",
          )
          .order("last_message_at", { ascending: false, nullsFirst: false })
          .limit(Number(body.limit ?? 50));
        if (error) throw error;
        return json({ conversations: data });
      }

      case "get_transcript": {
        const { data: messages, error } = await admin
          .from("ai_messages")
          .select("id, role, kind, content, media_path, created_at")
          .eq("conversation_id", body.conversation_id)
          .order("created_at");
        if (error) throw error;
        const { data: memories } = await admin
          .from("ai_memories")
          .select("content, created_at")
          .eq("conversation_id", body.conversation_id)
          .order("created_at", { ascending: false });
        return json({ messages, memories });
      }

      // ---------------------------------------------------------- moderation
      case "list_reports": {
        const { data, error } = await admin
          .from("reports")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(Number(body.limit ?? 100));
        if (error) throw error;
        return json({ reports: data });
      }

      case "set_report_status": {
        const { error } = await admin
          .from("reports")
          .update({ status: body.status })
          .eq("id", body.id);
        if (error) throw error;
        return json({ ok: true });
      }

      // --------------------------------------------------------------- stats
      case "stats": {
        const count = async (table: string, q?: (b: any) => any) => {
          let b = admin.from(table).select("*", { count: "exact", head: true });
          if (q) b = q(b);
          const { count: n } = await b;
          return n ?? 0;
        };
        const since = (days: number) =>
          new Date(Date.now() - days * 86400_000).toISOString();

        const [users, users7, convs, msgs, msgs1, matches, paying, chars] =
          await Promise.all([
            count("profiles"),
            count("profiles", (b) => b.gte("created_at", since(7))),
            count("ai_conversations"),
            count("ai_messages"),
            count("ai_messages", (b) => b.gte("created_at", since(1))),
            count("ai_conversations", (b) => b.lte("revealed_at", new Date().toISOString())),
            count("entitlements", (b) => b.gt("message_credits", 0)),
            count("ai_characters", (b) => b.eq("is_active", true)),
          ]);

        // Most popular characters by conversation count.
        const { data: convRows } = await admin
          .from("ai_conversations")
          .select("character_id, ai_characters(name)");
        const tally: Record<string, number> = {};
        for (const r of convRows ?? []) {
          const n = (r as any).ai_characters?.name ?? `#${(r as any).character_id}`;
          tally[n] = (tally[n] ?? 0) + 1;
        }
        const top = Object.entries(tally)
          .sort((a, b) => b[1] - a[1])
          .slice(0, 10)
          .map(([name, n]) => ({ name, conversations: n }));

        return json({
          stats: {
            users, users_last_7d: users7, conversations: convs,
            messages: msgs, messages_last_24h: msgs1,
            matches_revealed: matches, paying_users: paying,
            active_characters: chars,
          },
          top_characters: top,
        });
      }

      case "get_config": {
        const { data, error } = await admin.from("app_config").select("*").order("key");
        if (error) throw error;
        return json({ config: data });
      }

      case "set_config": {
        const { error } = await admin
          .from("app_config")
          .update({ value: body.value })
          .eq("key", body.key);
        if (error) throw error;
        return json({ ok: true });
      }

      default:
        return json({ error: `unknown action: ${action}` }, 400);
    }
  } catch (e) {
    console.error(action, e);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
