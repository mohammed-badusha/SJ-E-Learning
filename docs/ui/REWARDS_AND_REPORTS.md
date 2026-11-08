# Rewards, logo and battle reports — 8 November 2026

This pass follows the owner's request for trophy tiers, fire streaks, game audio, deeper battle feedback, and the supplied SJ open-book monogram. It extends the previously approved light interface.

- The supplied PNG is preserved unchanged in `assets/brand/sj-logo-source.png`. The in-app mark loads it directly. `flutter test tools/render_brand.dart` exports white-backed Android, iOS and web icons. Previous placeholder SVGs are archived under `docs/ui/before/`.
- Bronze and Silver use outlined trophies, Gold a filled trophy, Platinum a medal, and Diamond a diamond. Rating thresholds remain 1100 / 1300 / 1500 / 1700; the profile and report show progress to the next tier. Labels and shapes accompany colour.
- Current streaks use an orange fire icon; zero streaks use an outline. The count stays explicit.
- The battle report compares accuracy, correct/wrong/unanswered rounds, average response, fastest correct response, base points and speed bonus. A cumulative score chart and subject accuracy use actual played rounds. A forfeit does not count future unplayed questions as incorrect.
- Answer review shows both choices, timing, points, final-round multiplier and the question's stored explanation. History opens the full report. Missing timing in legacy data stays unavailable rather than being estimated.
- `202611080009_battle_reports.sql` preserves the existing review RPC and adds participant-only summaries. The private summary helper is not executable by students. The owner confirmed the hosted migration succeeded with “No rows returned”.
- Audio generation and controls are documented in `docs/audio/README.md`.

Validation: 20 Flutter tests and zero analyzer issues; 23 embedded PostgreSQL checks, including participant-only reports, exact score components, opponent choices and forfeit handling. Mobile report/review, profile, Home and Settings are checked at 375 points with 130% text. Screenshots use clearly identified fixtures or preview accounts; they are not hosted match results.

Remaining release/staging limitations are recorded in `docs/BUILD_STATUS.md`.

The update was installed and launched on the authorised Moto g64. The signed-in Home capture is `docs/screenshots/moto-g64-rewards.png`. Native player initialization/decoding produced no audio failure markers. Android and web bundles contain no ElevenLabs key. Automated phone input stopped when an ongoing live battle was observed.
