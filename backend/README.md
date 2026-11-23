# Shararat — Backend (Supabase)

Postgres + Auth + Realtime + Storage + Edge Functions. No server to run; the
schema, RLS policies, and RPCs *are* the backend.

## Layout
```
supabase/
├── migrations/
│   ├── 0001_schema.sql      tables, enums, indexes
│   ├── 0002_rls.sql         row-level security (deny-by-default)
│   ├── 0003_functions.sql   RPCs + triggers (matching, chat, moderation)
│   └── 0004_storage.sql     photo / chat-media buckets + policies
├── functions/
│   └── push-fanout/         FCM push notification Edge Function
└── seed.sql                 interest tags
```

## Option A — Hosted project (recommended to start)
1. Create a project at https://supabase.com (free tier is fine for dev).
2. In the SQL editor, run the migrations **in order** (0001 → 0004), then `seed.sql`.
   Or with the CLI: `supabase link --project-ref <ref>` then `supabase db push`.
3. Auth → Providers: enable **Phone** (Twilio/MessageBird) and/or **Email**; add
   Google/Apple later. Set "Confirm" to OTP.
4. Realtime: enable replication for the `messages` table (Database → Replication)
   so chat deltas stream to clients.
5. Storage: buckets `photos` and `chat-media` are created by `0004_storage.sql`.
6. Grab **Project URL** + **anon key** (Settings → API) for the Flutter app's
   `--dart-define` / env (see `app/README.md`). Never ship the service-role key.

## Option B — Local dev
Requires Docker + the Supabase CLI:
```
brew install supabase/tap/supabase
supabase start           # boots local Postgres, Auth, Realtime, Studio
supabase db reset        # applies migrations + seed
```

## Push notifications
```
supabase functions deploy push-fanout --no-verify-jwt
supabase secrets set SB_URL=<url> SB_SERVICE_ROLE=<service_role_key> FCM_SERVER_KEY=<fcm_key>
```
Then Database → Webhooks: create INSERT webhooks on `messages` and `matches`
pointing at the function URL.

## AI Companions (the "pro" layer)
Migrations `0006_ai_companions.sql` + `0007_ai_seed.sql` add LLM characters with
persistent memory, mood, voice notes, and AI-generated photos/videos.

Edge Functions:
```
supabase functions deploy ai-chat      # Claude Opus 4.8 persona chat + memory
supabase functions deploy ai-selfie    # Google Imagen still images
supabase functions deploy ai-video     # Google Veo short video clips
```
Secrets:
```
supabase secrets set \
  SB_URL=<url> SB_SERVICE_ROLE=<service_role> \
  ANTHROPIC_API_KEY=<key> \        # character chat (Claude)
  GEMINI_API_KEY=<key> \           # Imagen + Veo (Google generative media)
  ELEVENLABS_API_KEY=<key>         # optional: character voice notes (TTS)
```
Notes:
- Character chat uses the **official Anthropic SDK** on `claude-opus-4-8`; the
  persona is sent as a prompt-cached stable prefix with a non-negotiable **SFW
  safety prefix**; long-term memory is distilled by a cheap Haiku call in the
  background.
- Photos use **Google Imagen** and video clips use **Google Veo** via the Gemini
  API (Veo is the engine behind Google Flow). Veo is long-running — `ai-video`
  starts the job and polls; the client retries while `status:"pending"`.
  Verify the exact Imagen/Veo model IDs at deploy time (they evolve).
- Media lands in the private `ai-media` bucket, readable only by its owner.

## Security model (summary)
- RLS denies everything by default; policies grant only self-owned or
  match-party access.
- Other users' profiles are never selected directly — they come through
  `SECURITY DEFINER` RPCs (`get_discover_feed`, `get_profile`, ...) that strip
  date-of-birth and exact geolocation (expose age + coarse distance only).
- Matches are created only inside the `swipe()` RPC, so a client cannot forge one.
- Blocking is immediate and tears down the match + conversation both ways.
- 18+ age gate is a table check constraint, not just client validation.
