# SJ E-Learning

Flutter app for competitive-exam practice, timed quiz battles and daily challenges, backed by Supabase. Android, iOS and responsive web sources are included.

## Run it

```sh
flutter pub get
flutter run -d chrome --web-port 5173 --dart-define-from-file=config/dev.json
```

The supplied local `config/dev.json` has the project URL and **public** publishable key provided by the owner. It is ignored by Git. Copy `config/example.json` for staging/production and use separate Supabase projects. Never add a service-role key or Google client secret to these files.

The login screen offers Google sign-in only. Tests inject a local session for offline screen and gameplay checks.

Follow [SETUP.md](docs/SETUP.md) to install the database and enable Google sign-in. The first super admin is `badushamc312@gmail.com`. Other admins can be defined in Supabase's `admin_users` table or by a super admin inside the app.

## Implemented

- Supplied SJ open-book logo, bundled Poppins typography, navy light-first design, light/dark themes, responsive dashboard, podium leaderboard, subject cards, progress screens and reusable game controls.
- Google sign-in through the native account picker on Android and Supabase browser OAuth on web, with Supabase owning both sessions; mandatory name/India-phone completion with optional illustrated portraits or a cropped gallery photo, typed routes, role guard, role refresh on resume and safe sign-out. Android requires a Google Cloud OAuth client for the app's package and signing certificate; see [Android setup](docs/ANDROID_GOOGLE_SIGNIN.md).
- Signed-in learners see each other's chosen profile pictures across matches, results, leaderboards and history. Google account photos appear by default when provided by Google. Gallery photos are stored as small private database thumbnails and served through an authenticated RPC; replacing a picture removes its old thumbnail.
- Home, database categories/subtopics, timed/untimed practice, explanations, results and local answer-review history.
- Server-authoritative human matching and bot fallback, row-locked single-match creation, immutable question snapshots, scoring, fixed battle trophy payouts (+15 win, −5 loss, 0 draw), XP, bot plans, deadline/grace enforcement, first-answer locking, private Realtime broadcasts, server-owned advancement, heartbeat/reconnect/forfeit handling, results and review.
- Daily shared questions, one resumable attempt, server-owned deadlines, automatic completion, IST date boundaries, streak freezes and badges.
- Trophy/weekly/daily leaderboards, a weekly top-three podium with profile portraits, Bronze (0), Silver (1,000), Gold (3,000), Platinum (6,000) and Diamond (10,000) thresholds, tier progress, fire streak indicators, profile stats, match history and settings. New accounts start at 0 trophies; trophies cannot go negative and falling below a threshold demotes the tier.
- Original bundled game cues and instrumental background music, independent saved volume controls, lifecycle pausing, and server-reveal-only answer sounds.
- Detailed battle reports with both players’ timing, accuracy and score breakdowns, cumulative score charts, subject accuracy and answer-by-answer review.
- Role-protected responsive admin dashboard, question editor/preview, CSV/XLSX and JSON import, category management, staff roles, bans, reports, daily auto-scheduling, analytics and settings.
- Account anonymisation/deletion Edge Function and in-app deletion entry point.
- Versioned migrations, first-install SQL package, four subjects with 56 approved topics, an empty question bank for academy content, local Postgres checks and CI workflow.

## Verification

```sh
flutter analyze --fatal-infos
flutter test
npm ci --prefix tools/db-check
npm test --prefix tools/db-check
flutter build web --release --dart-define-from-file=config/dev.json
```

The database harness uses **real embedded Postgres** with a minimal Auth identity stub and a captured Realtime send function. It executes the migrations (except `pg_cron`) and RLS/RPC tests. It does **not** prove hosted Google OAuth, real Realtime delivery, Cron scheduling, simultaneous network transactions, or Edge Function deployment. Those need staging verification. No 500-user load/performance claim is made.

Development used Flutter **3.35.5 / Dart 3.9.2**, the installed SDK. CI is pinned to this tested version. Upgrade the project SDK separately before release rather than silently changing the machine's global installation.

See [BUILD_STATUS.md](docs/BUILD_STATUS.md) for remaining work and acceptance gaps. This is an initial working implementation, **not a release-certified or fully accepted production app**.

## Regenerate

```sh
dart run build_runner build --delete-conflicting-outputs
node tools/prepare_setup.mjs
flutter test tools/render_brand.dart
```

The question bank starts empty. Staff add playable questions through the editor or import. The approved subject and topic catalog is in migration `202611110023_question_catalog_reset.sql`; the seed only adds configuration and badges. Question snapshots preserve old matches when the bank changes; used questions are duplicated for correction rather than rewritten.

The approved light UI refinement is documented in [docs/ui/UNSLOP.md](docs/ui/UNSLOP.md). See [the rewards and reports update](docs/ui/REWARDS_AND_REPORTS.md) and [audio authoring guide](docs/audio/README.md) for the latest additions. ElevenLabs authoring uses a local ignored `.env`; no authoring credential is required at runtime.

The reference-led visual revamp, screen changes and accessibility checks are documented in [docs/ui/REVAMP.md](docs/ui/REVAMP.md).
