# Shararat — Flutter app

Dating & chat client. Flutter (Android + iOS) + Supabase.

## Prerequisites
- Flutter SDK 3.4+ (`flutter doctor` all green)
- A Supabase project with the migrations in `../backend` applied
  (see `../backend/README.md`)

## First run
The Android/iOS platform folders are not committed. Generate them once inside
this `app/` directory:
```
flutter create --platforms=android,ios .
flutter pub get
```

Then run, passing your Supabase credentials as compile-time defines (never
hard-code them):
```
flutter run \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key>
```
Tip: put those in a `env.json` and use `--dart-define-from-file=env.json`.

## Project structure
```
lib/
├── main.dart              entrypoint + config guard
├── core/                  config, supabase client, theme, router, session
├── shared/
│   ├── models/            ProfileCard, Message, ConversationSummary
│   └── widgets/           PhotoPager
└── features/
    ├── auth/              welcome, otp, onboarding
    ├── discover/          swipe deck, filters, repository
    ├── matches/           likes grid, "it's a match" dialog
    ├── chat/              chat list, realtime chat room, repository
    ├── companions/        AI character grid + AI chat (text/voice/photo/video)
    ├── profile/           my profile, detail (block/report), edit, repositories
    ├── settings/          settings + account deletion
    └── shell/             5-tab home shell (Discover·Likes·Companions·Chats·Profile)
```

## Architecture notes
- **State:** Riverpod. `sessionProvider` (auth + onboarding) drives go_router redirects.
- **Data access:** every feature has a thin repository calling Supabase RPCs; UI
  never embeds SQL and never sees other users' DOB/exact location.
- **Realtime chat:** `messages` table stream (Supabase Realtime) + a per-room
  channel for presence (online) and typing broadcasts.
- **Security:** anon key only; all authorization is enforced server-side by RLS.

## Not yet wired (phase 2)
- FCM push on the client (token registration via `register_device` RPC + the
  `push-fanout` Edge Function backend is ready; add `firebase_messaging` and call
  `register_device` after permission grant).
- Photo reordering, profile prompts, verification badge, premium tier.
```
