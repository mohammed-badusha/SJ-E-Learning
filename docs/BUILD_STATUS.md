# Build status — 8 November 2026

This is a runnable initial implementation. The eight acceptance phases in the brief are **not all complete**. The document was treated as a product specification; its embedded agent-role and approval instructions were not adopted as new authority.

## Verified locally

- **20 Flutter widget/unit tests passed; analyzer has zero issues.** Coverage: profile-route guards, validation, bounded preview scoring, option states, accessible timer, practice answer locking/advancement, light/dark home at 375 px and 130% text scale.
- **23 embedded Postgres checks passed.** Coverage: migrations (excluding Cron), seeds, profile completion/phone uniqueness, role detection/revocation, private data and answer-key access, protected rating writes, restricted admin RPCs, scoring, human matching, duplicate submissions, reveal gates, idempotent rewards, bot race recovery, complete bot round, daily one-attempt/resume and automatic finish/streak.
- Browser walkthrough: login → explicitly labelled local preview → Home → category → matchmaking explanation → quiz → locked answer with explanation → Home. Phone viewport 375 × 812 and desktop layout inspected.
- Optimized release web build and Android debug APK build succeeded. APK: `build/app/outputs/flutter-apk/app-debug.apk` (Web Google client ID is configured; native sign-in was confirmed by the owner).
- Screenshots in `docs/screenshots/`; supplied PNG logo and launcher export in `assets/brand/`.

## Needs your account configuration

1. Initial SQL setup was run by the owner. The owner also confirmed the new battle-report migration `202611080009_battle_reports.sql` succeeded.
2. Web and Android Google clients are configured. The owner confirmed successful browser sign-in and then successful native sign-in on the installed Moto g64 APK.
3. Deploy the account-deletion Edge Function.
4. Review/accept local Android SDK licenses; configure signing before a release build.

The owner reports running the hosted setup SQL and enabling Google. Read-only Auth API checks confirmed Google is enabled, the provider client ID matches local config, and Google redirects back to this project’s Auth callback. The owner confirmed real browser and native Google sign-in. Hosted row counts and the remaining staging integrations still need verification. No OAuth/provider changes have been made by the agent. Public project configuration alone cannot authorise those operations. No secrets are needed in chat.

## Acceptance gaps and remaining work

- Native release sign-in, real two-device Realtime, Cron execution and Edge Function deletion still need staging tests. The embedded harness stubs Auth identity and Realtime transport and cannot demonstrate these integrations.
- Rematch requests/acceptance, result-card sharing, Lottie celebrations, illustrated avatars, optional exam/avatar onboarding and the intro carousel remain to implement.
- Push notification delivery/reminders, Sentry and release analytics configuration are not implemented. FCM requires a notification project and server-side credentials.
- Core admin editing is functional. Advanced content tools remain: rich text/LaTeX and media upload/rendering, full subtopic management UI, drag reorder, question bulk actions, duplicate-similarity detection, CSV error-report export, and manual daily question picking. The SQL supports subtopic changes and manual daily question lists; the UI currently uses auto-fill scheduling. CSV/XLSX imports produce drafts and report invalid rows before import.
- Leaderboards currently query live data and cap results; materialised-view refresh, all category filtering variants and full keyset pagination need finishing. Profile uses category progress bars rather than a radar chart.
- Presence is implemented through server heartbeats/reconnection status, not Realtime Presence tracking. A single match-owning-device lease, background grace semantics and quit-priority/suspicious-play review need hardening. Heartbeats currently stop when the app is backgrounded; clients have a 15-second reconnection window.
- The first question image and all image-bearing answers are not yet rendered. Do not add image-dependent questions until that path is implemented.
- Daily attempts keep server-owned fixed question windows. Early answers show an explanation and wait until the next window. Offline histories are cached locally; cached profile/category startup and resumable practice across app restarts need additional work.
- Account deletion preserves a pseudonymous profile ID for historical match references, removes personal fields and deletes the Auth user through the Edge Function. Hosted failure/retry behaviour and audit-data review need staging verification.
- No 500-user concurrency test, physical-device frame-time measurement, cold-start target, APK size target, golden regression baseline or Play Store AAB release certification has been completed. CI is supplied but has not been run on GitHub.
- The installed/tested SDK is Flutter 3.35.5, not the latest stable version requested in the brief. Upgrade and revalidate dependencies before release. App fonts are bundled for offline rendering.

## Deployment safety

All app tables default-deny access. Correct answers and immutable question snapshots are inaccessible through direct student SELECTs. Privileged actions use server-validated roles, a locked-down search path and narrow grants. The first-install script is transactional and refuses an existing app schema. It does not drop existing tables or reset the hosted project.

The seed question bank contains intentionally simple development examples. Academy staff should review or replace it before student use.

## Light UI update

The approved light UI direction has been applied across the theme, shared controls and student screens. See [the design report](ui/UNSLOP.md) for the audit, nine passes, preserved before screenshots and attribution. A Moto g64 5G is authorised over USB for development installation.

The updated light APK has been installed successfully on the connected Moto g64. Its compiled Web client ID and debug signing certificate were verified. Phone sign-in still requires native OAuth verification. The app now distinguishes incomplete Google flows, native configuration failures and Supabase verification failures, with safe debug references instead of one catch-all setup message.

The owner reports creating the Android OAuth client using the package name and SHA-1 verified from the installed APK. Its ID is recorded in `docs/ANDROID_GOOGLE_SIGNIN.md`; successful native sign-in has now been confirmed by the owner.

## Phone sign-in confirmed

After Android OAuth registration, the owner confirmed that the installed app successfully signs in and opens Home or Complete Profile. The approved light UI is installed on the Moto g64 5G; 14 Flutter tests and zero-issue analysis passed. This confirms development native sign-in, not Play Store release signing or all other production acceptance criteria.

## Logo, rewards, audio and battle report update

The supplied SJ open-book logo replaces the placeholder mark and platform icons. Rank tiers have trophy/medal/diamond badges and rating progress; streaks have fire icons. Twelve original short cues and a 30-second instrumental loop were generated through the owner-authorised ElevenLabs account and bundled locally. Effects/music have independent saved volume controls, background pausing and cue deduplication. The authoring key remains in ignored `.env` and is not an app asset.

Completed battles now show actual comparative timing, accuracy, unanswered rounds, base/speed points, cumulative score and subject accuracy. Answer review shows both choices and explanations; History opens the detailed report. The owner confirmed the hosted report SQL migration succeeded. See `docs/ui/REWARDS_AND_REPORTS.md` and `docs/audio/README.md`.

Validation: all 20 Flutter tests, zero-issue analysis, and 23 embedded PostgreSQL checks passed. These checks do not substitute for a real two-device battle or personal listening review.

Android debug APK and optimized web builds succeeded for this update. The APK was installed successfully over USB on Moto g64 5G, launched to the signed-in Home screen, and the new logo, fire streak and tier badge were visually checked. Native audio players decoded the bundled 44.1 kHz assets with no `SJ_AUDIO_UNAVAILABLE` or unhandled-exception markers during the observed session. A live bot battle was in progress during verification, so automated taps stopped; final loudness and full new-report review on a real completed match remain user listening/staging checks. Both bundles were checked for the ElevenLabs authoring credential: absent. The APK contains 13 playable MP3 files and excludes the raw originals and `.env`.
