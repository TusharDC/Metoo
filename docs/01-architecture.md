# Shararat — Dating & Chat App: Architecture & Product Breakdown

> Rebuild of `com.shararat.app` (original source lost). This document is the ground
> truth for the rebuilt application. The original app could not be decompiled or
> observed directly, so this spec is based on the owner's feature list plus
> established patterns from the dating/social category (Tinder, Bumble, Hinge).
> If the original APK or screenshots surface later, we reconcile against this.

**Stack decision:** Flutter (Android + iOS) client · Supabase (Postgres + Auth +
Realtime + Storage) backend · Edge Functions (Deno) for privileged logic.

---

## 1. Screens

### Auth & Onboarding
| Screen | Purpose |
|---|---|
| Splash / Gate | Decide route: logged-out → Welcome, logged-in-incomplete → Onboarding, logged-in-complete → Home |
| Welcome | Logo, "Continue with phone", "Continue with email/Google/Apple" |
| Phone / Email entry | Collect identifier, send OTP |
| OTP verification | 6-digit code, resend timer |
| Onboarding: Name & DOB | Legal age gate (18+), stored once |
| Onboarding: Gender & "Looking for" | Identity + preference |
| Onboarding: Photos | Upload 1–6 photos, first = primary |
| Onboarding: Bio & Interests | Free text + tag chips |
| Onboarding: Location permission | Geolocation for distance-based discovery |
| Onboarding: Notifications permission | Push opt-in |

### Main App (bottom nav)
| Tab | Screen | Purpose |
|---|---|---|
| Discover | Swipe/card stack | Browse candidate profiles, like/pass/superlike |
| Discover | Filters sheet | Age range, distance, gender, verified-only |
| Discover | Profile detail | Full-screen profile with photo carousel |
| Likes | Who liked you | Grid of incoming likes (premium-gated blur optional) |
| Matches | It's a Match modal | Celebration on mutual like |
| Chats | Conversation list | Matches + active threads, last message, unread badge, presence dot |
| Chats | Chat room | 1:1 realtime messages, typing, read receipts, media |
| Profile | My profile | Preview as others see it |
| Profile | Edit profile | Photos, bio, interests, prompts |
| Profile | Settings | Account, discovery prefs, notifications, privacy, blocked list, logout, delete account |

### Supporting
- Report user flow (reason picker → confirm)
- Block confirmation
- Empty states (no more profiles, no matches, no messages)
- Profile of another user (read-only, with Report/Block/Unmatch actions)

---

## 2. Major Features

1. **Authentication** — phone OTP (primary; matches the region/style of the original), email OTP, OAuth (Google/Apple). Age gate 18+.
2. **Profiles** — photos (1–6), display name, age (derived from DOB, never raw DOB), gender, bio, interests, optional prompts, location (city + coarse geo).
3. **Discover** — distance + preference filtered candidate feed, swipe deck. Excludes already-swiped, blocked, and self.
4. **Like / Pass / Superlike** — recorded as swipes; mutual like → match.
5. **Matching** — server-side mutual-like detection creates a `match` + a `conversation`.
6. **Realtime 1:1 chat** — text + images, delivered via Supabase Realtime, persisted in Postgres.
7. **Presence** — online/offline + last-seen, typing indicators, read receipts.
8. **Search / Filters** — age, distance, gender, interests, verified-only.
9. **Notifications** — push (FCM/APNs via Edge Function) for new match, new message, new like; in-app badges.
10. **Block / Report / Unmatch** — safety primitives that immediately cut off interaction and feed moderation.
11. **Settings & privacy** — discovery visibility, notification toggles, account deletion (GDPR-style), data export.
12. **Verification (optional, phase 2)** — selfie/photo verification badge.
13. **Monetization hooks (phase 2)** — premium tier (see who liked you, unlimited likes, boosts). Schema leaves room; not in MVP.

---

## 3. User Flows & Navigation

```
Splash
 ├─ not authed ─────────────► Welcome ─► Phone/Email ─► OTP ─► [new user] Onboarding ─► Home
 ├─ authed, profile incomplete ─────────────────────────────► Onboarding ─► Home
 └─ authed, profile complete ───────────────────────────────► Home (Discover tab)

Home (bottom nav: Discover · Likes · Chats · Profile)

Discover: card → swipe right (like) → if reciprocal → "It's a Match!" → open chat or keep swiping
Likes:    tap liker → profile → like back → match → chat
Chats:    list → chat room → send/receive realtime → (overflow) Unmatch / Block / Report
Profile:  view → Edit / Settings → Logout / Delete
```

Routing: declarative router (`go_router`) with an auth/onboarding redirect guard driven
by auth state + a `profiles.onboarding_complete` flag.

---

## 4. UI/UX Structure

- **Design language:** Material 3 with a custom warm brand palette (primary magenta/pink,
  playful — "shararat" = mischief/playfulness). Dark mode supported.
- **Navigation:** persistent bottom nav (4 tabs) + modal routes for chat, profile detail, settings.
- **Components:** swipeable card deck, photo carousel, chat bubbles, presence dot,
  tag chips, filter bottom sheet, match celebration overlay.
- **State management:** Riverpod (providers for auth, profile, discover deck, chat streams, presence).
- **Offline/resilience:** optimistic message send with pending/sent/read states; cached profile.

---

## 5. Backend Requirements

- **Identity & auth:** Supabase Auth (phone/email OTP + OAuth). JWT issued to client.
- **Data:** Postgres (profiles, swipes, matches, conversations, messages, blocks, reports, devices, settings).
- **Authorization:** Row-Level Security (RLS) on every table — users can only read/write their own rows and rows they're party to.
- **Realtime:** Supabase Realtime (Postgres changes + presence + broadcast) for chat, typing, online status.
- **Storage:** Supabase Storage buckets for profile photos (public-read with transform) and chat media (private, signed URLs).
- **Privileged logic (Edge Functions, service role):** push-notification fan-out, report handling, account deletion, discover-feed ranking (optional), moderation actions.
- **Scheduled jobs (pg_cron):** purge stale presence, expire boosts, recompute daily like counts.

---

## 6. Database Structure (high level — see `backend/supabase/migrations`)

```
auth.users (managed by Supabase)
profiles            1:1 with auth.users — public-facing identity + prefs + geo
profile_photos      N photos per profile, ordered, one primary
interests           lookup table of interest tags
profile_interests   M:N profile↔interest
swipes              (actor → target, action: like/pass/superlike), unique(actor,target)
matches             (user_a, user_b) unordered pair, created on mutual like
conversations       1:1 with match
messages            conversation messages (text/image), sender, read_at
blocks              (blocker → blocked)
reports             (reporter → reported, reason, status) → moderation queue
devices             push tokens per user/platform
user_settings       notification + privacy toggles
presence            last_seen / online (also via Realtime presence channel)
```

Key rules:
- `matches` stores the pair with `user_a < user_b` (canonical order) + unique constraint → no dup matches.
- `swipes` unique on (actor_id, target_id) → idempotent swiping.
- Match creation is a **trigger/RPC**, not client logic — client can't fabricate matches.
- Age derived from `date_of_birth`; raw DOB never exposed via RLS select to other users.

---

## 7. APIs Required

Supabase gives us an auto-generated REST + Realtime API over tables (guarded by RLS).
On top we add **RPCs (Postgres functions)** and **Edge Functions** for anything that
must be atomic or run with elevated privilege:

| Endpoint | Type | Purpose |
|---|---|---|
| `auth.*` | Supabase Auth | OTP send/verify, OAuth, session refresh |
| `get_discover_feed(limit, filters)` | RPC | Ranked, filtered, de-duplicated candidate list |
| `swipe(target_id, action)` | RPC | Record swipe atomically, create match if reciprocal, return match result |
| `get_conversations()` | RPC/view | Threads with last message + unread count + presence |
| `send_message(conversation_id, body, media)` | RPC/insert | Insert message (RLS-guarded), triggers push |
| `mark_read(conversation_id)` | RPC | Set read receipts |
| `block_user(target_id)` | RPC | Block + unmatch + hide both ways |
| `report_user(target_id, reason, details)` | RPC | File report into moderation queue |
| `register_device(token, platform)` | RPC | Store push token |
| `delete_account()` | Edge Function | Cascade-delete user data, revoke auth |
| `push-fanout` | Edge Function (webhook on message/match insert) | Send FCM/APNs notifications |

---

## 8. Authentication System

- Supabase Auth, phone OTP primary + email OTP + Google/Apple OAuth.
- JWT (short-lived access + refresh) stored in secure storage (`flutter_secure_storage`).
- Auth state → router redirect guard. Session auto-refresh.
- **Age gate:** DOB collected at onboarding; server rejects < 18 via check constraint + trigger.
- **RLS everywhere**; no table is open. Service-role key lives only in Edge Functions, never in the app.

---

## 9. Chat / Realtime Architecture

- **Transport:** Supabase Realtime.
  - *Postgres Changes* channel on `messages` filtered by `conversation_id` → new message delivery + persistence in one path (no separate socket server to run).
  - *Presence* channel per-user for online/offline + last-seen.
  - *Broadcast* for ephemeral typing indicators (not persisted).
- **Delivery states:** `pending` (optimistic local) → `sent` (insert ack) → `read` (`read_at` set by recipient).
- **Ordering:** server `created_at` + sequence; client sorts and de-dupes by id.
- **Media:** upload to private Storage bucket → store path in message → recipient gets signed URL.
- **Scale note:** Realtime is fine to low-millions of messages; if chat volume outgrows it, the message schema is transport-agnostic and can move behind a dedicated Socket.IO/Centrifugo service without a data migration.

---

## 10. Notifications

- **Push:** Firebase Cloud Messaging (Android + iOS via APNs key in FCM).
- **Trigger:** DB webhook (or Realtime-driven Edge Function) on insert into `messages`, `matches`, `swipes(like)` → `push-fanout` Edge Function looks up recipient devices + settings → sends FCM.
- **In-app:** unread counts via conversation view; match/like badges.
- **Preferences:** `user_settings` toggles per category (messages, matches, likes, marketing).
- **Quiet hours / dedupe:** handled in the fan-out function.

---

## 11. Admin / Moderation Requirements

- **Reports queue:** `reports` table with status (`pending`/`reviewing`/`actioned`/`dismissed`).
- **Actions:** warn, shadow-ban, suspend, hard-delete — represented as `moderation_actions`.
- **Auto-safety:** blocking is immediate and mutual-invisible; repeated reports can auto-limit.
- **Admin surface (phase 2):** a lightweight web dashboard (Next.js or Supabase Studio + SQL views) reading the moderation tables via a restricted admin role. Not in the mobile app.
- **Content safety:** image moderation hook (e.g. Rekognition/Sightengine) on photo upload — stubbed in MVP, pluggable in `push-fanout`-style function.
- **Compliance:** 18+ gate, report/block required by app stores for dating apps, account deletion + data export for GDPR/Play policy.

---

## Project Layout

```
shararat/
├── docs/                      # this spec + decisions
├── backend/
│   └── supabase/
│       ├── migrations/        # versioned SQL (schema, RLS, functions, triggers)
│       ├── functions/         # Edge Functions (Deno/TS)
│       └── seed.sql           # interests lookup, dev seed data
└── app/                       # Flutter client
    └── lib/
        ├── core/              # config, theme, router, supabase client, errors
        ├── features/
        │   ├── auth/          # welcome, otp, onboarding
        │   ├── profile/       # view, edit, photos
        │   ├── discover/      # swipe deck, filters
        │   ├── matches/       # likes + match modal
        │   ├── chat/          # list, room, realtime, presence
        │   └── settings/      # settings, block/report
        └── shared/            # widgets, models, providers, utils
```

## AI Companions (hybrid "pro" layer — added after reviewing shararat.app)

The live shararat.app is an **AI-companion** product: AI characters with
personality, memory, voice, and AI selfies. We keep the human dating/chat app
above AND add AI companions as a parallel surface (5th bottom-nav tab).

- **Characters:** six seeded personas (Aarya, Divya, Ishita, Meher, Nyra, Zoya),
  each with a system prompt, mood, accent color, traits. App-authored content.
- **Chat engine:** `ai-chat` Edge Function → **Anthropic SDK, `claude-opus-4-8`**.
  The persona is a prompt-cached stable prefix behind a non-negotiable **SFW
  safety prefix**; recent history + distilled long-term memory are injected.
- **Memory:** every turn persists; a cheap Haiku call extracts durable facts into
  `ai_memories` in the background (`EdgeRuntime.waitUntil`).
- **Voice notes:** optional TTS (ElevenLabs) of the reply, stored in `ai-media`.
- **AI photos / videos:** Google **Imagen** (`ai-selfie`) and Google **Veo**
  (`ai-video`, the engine behind Google Flow) via the Gemini API. Veo is
  long-running: start → poll → store.
- **Data:** `ai_characters`, `ai_conversations` (1 per user+character),
  `ai_messages`, `ai_memories`. RLS: characters readable by all signed-in users;
  conversations/messages/memories owner-only; AI message **inserts happen only in
  the service-role Edge Functions**.
- **Safety:** 18+ gate inherited; SFW enforced in the LLM system prefix and image
  safety settings; media is private (owner-scoped signed URLs).

## Build phases
- **MVP (now):** auth + onboarding, profiles + photos, discover + swipe, match, realtime chat, presence, block/report, settings.
- **Phase 2:** push notifications polish, verification badge, admin dashboard, image moderation, premium/monetization, search enrichment, boosts.
