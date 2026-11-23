# Shararat

A production-grade dating & chat app — rebuild of the lost `com.shararat.app`.

- **Client:** Flutter (Android + iOS) — `app/`
- **Backend:** Supabase (Postgres + Auth + Realtime + Storage + Edge Functions) — `backend/`
- **Spec:** `docs/01-architecture.md` (screens, flows, data model, APIs, security, moderation)

## MVP status (built)
Auth (phone/email OTP) · onboarding · profiles + photos · discover swipe deck
with mutual age/distance/gender filtering · like / superlike / pass · server-side
matching · realtime 1:1 chat with presence + typing + read receipts · likes tab ·
block / report / unmatch · settings · account deletion.

## Getting an APK without a backend (demo build)

`--dart-define=DEMO=true` builds an offline UI-review APK: no Supabase project,
no login, no LLM calls. Every repository serves canned data from
`app/lib/core/demo/` — the 12-girl roster from `backend/scripts/roster.json`,
three pre-seeded conversations, scripted replies, and a fake own-profile.

```
cd app && flutter build apk --release --dart-define=DEMO=true
```

No local toolchain? Push this repo to GitHub and run the **Build Android APK**
workflow from the Actions tab — it generates `android/`, builds, and attaches
the APK as a downloadable artifact.

Works in demo: swipe deck, delayed match reveal (compressed to 8–25 s so it's
observable), Matches tab, chat with scripted replies, mood switching, Companions
grid, profile, settings toggles. Doesn't work: AI photos/videos, voice notes,
login/logout, account deletion, and the human Chats tab (shows its empty state).
Never ship a DEMO build — it bypasses the login and the 18+ gate.

## Get it running
1. **Backend** — follow `backend/README.md`: create a Supabase project, run the
   migrations in `backend/supabase/migrations` (0001→0005) then `seed.sql`,
   enable Phone/Email auth, enable Realtime on `messages`.
2. **App** — follow `app/README.md`: `flutter create --platforms=android,ios .`,
   `flutter pub get`, then `flutter run` with `--dart-define` Supabase creds.

## Security model (why this is production-shaped, not a demo)
- Row-Level Security denies everything by default; users touch only their own
  rows or rows for a match they're in.
- Other users' data is served only through `SECURITY DEFINER` RPCs that strip
  date-of-birth and exact geolocation (age + coarse distance only).
- Matches are forged server-side inside `swipe()`, never by the client.
- 18+ gate is a DB check constraint; blocking tears down the match both ways.
- The app ships only the anon key; the service-role key lives in Edge Functions.

## Roadmap (phase 2)
FCM push wiring on the client · verification badge · premium tier · admin/
moderation dashboard · image moderation on upload · photo reordering + prompts.
