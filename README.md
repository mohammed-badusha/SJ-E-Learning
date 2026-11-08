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
- Google sign-in integration (native ID-token flow, web OAuth), mandatory name/India-phone completion with optional illustrated portraits or a cropped gallery photo, typed routes, role guard, role refresh on resume and safe sign-out.
- Home, database categories/subtopics, timed/untimed practice, explanations, results and local answer-review history.
- Server-authoritative human matching and bot fallback, row-locked single-match creation, immutable question snapshots, scoring, Elo/XP, bot plans, deadline/grace enforcement, first-answer locking, private Realtime broadcasts, server-owned advancement, heartbeat/reconnect/forfeit handling, results and review.
- Daily shared questions, one resumable attempt, server-owned deadlines, automatic completion, IST date boundaries, streak freezes and badges.
- Rating/weekly/daily leaderboards, trophy/medal/diamond rank tiers, tier progress, fire streak indicators, profile stats, match history and settings.
- Original bundled game cues and instrumental background music, independent saved volume controls, lifecycle pausing, and server-reveal-only answer sounds.
- Detailed battle reports with both players’ timing, accuracy and score breakdowns, cumulative score charts, subject accuracy and answer-by-answer review.
- Role-protected responsive admin dashboard, question editor/preview, CSV/XLSX draft import, category management, staff roles, bans, reports, daily auto-scheduling, analytics and settings.
- Account anonymisation/deletion Edge Function and in-app deletion entry point.
- Ten versioned migrations, first-install SQL package, deterministic sample seeds (4 categories, 12 topics, 160 questions, 20 bots), local Postgres checks and CI workflow.

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
python3 tools/generate_seed.py
python3 tools/prepare_setup.py
flutter test tools/render_brand.dart
```

Seeds are educational examples, not a reviewed exam question bank. Review explanations and replace them with academy-approved content before production. Question snapshots preserve old matches when the bank changes; used questions are duplicated for correction rather than rewritten.

The approved light UI refinement is documented in [docs/ui/UNSLOP.md](docs/ui/UNSLOP.md). See [the rewards and reports update](docs/ui/REWARDS_AND_REPORTS.md) and [audio authoring guide](docs/audio/README.md) for the latest additions. ElevenLabs authoring uses a local ignored `.env`; no authoring credential is required at runtime.

The reference-led visual revamp, screen changes and accessibility checks are documented in [docs/ui/REVAMP.md](docs/ui/REVAMP.md).
