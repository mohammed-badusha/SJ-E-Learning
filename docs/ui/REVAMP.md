# SJ E-Learning visual revamp

## References and direction

The owner requested the interface of [SJLearnInitial](https://github.com/mohammed-badusha/SJLearnInitial), with additional design work, and supplied a leaderboard screenshot on 8 November 2026. The source was reviewed at commit `a69ca6e8c009465b9a236c7b535104fb6967b96d` in a temporary checkout. Its navy/indigo headers, Poppins typography, pale canvas, colourful learning cards and practice grid inform this implementation. The screenshot supplies the highlighted personal standing, second/first/third podium, ribbon medals and rounded ranking rows.

The local UI/UX skill search returned generic patterns that did not fit this exam-preparation app. No generated design-system recommendation was adopted. The owner's references determine the visual direction; the skill's general native accessibility, touch, layout and state guidance supplied the implementation checks.

## Design system

- Navy `#1D2E61` headers, blue `#354B9A` actions, teal `#087F73` standings/progress, amber rewards, white cards and a cool `#F5F7FB` canvas.
- Bundled Poppins Regular/Medium/SemiBold/Bold; font licenses are included as assets. Existing chart fonts remain available offline.
- Consistent 20–24 point card corners, subtle elevation, 20 point phone gutters, 12–24 point section spacing and native press feedback.
- Light remains the default; the dark palette was reviewed independently. Primary/secondary/muted text pairs meet 4.5:1 contrast, including muted text at 4.58:1 on the light canvas.
- Three student destinations: Home, Leaderboard and Progress. History remains accessible from Home and Progress and selects the Progress destination. Staff retain their authorised Admin destination.

## Implemented screens

Home has a branded header, personal rating/streak/level cards, daily challenge and live battle features, a vector trophy illustration, XP progress and a functional practice/history/progress grid. Features stack on phones and sit alongside each other on wide layouts.

Leaderboard has Battle arena / Daily quiz tabs, weekly points and all-time rating filters, a persistent personal standing card, vector ribbon medals, a podium and lazily built ranking cards. Server-provided ranks and ties are retained. It handles loading, offline/retry, empty standings, unranked users and podiums with fewer than three people. Pull-to-refresh is available. Each mode describes its actual scoring period.

Subject selection has coloured subject cards, explicit selected states, topic chips, a practice timer switch and a persistent safe-area start button. Progress combines identity, tier progress, XP, streak, real battle totals and subject strengths, with history and settings access. Login, daily challenge, matchmaking, live scorecards and answer options share the new design system; existing result/review/history/admin screens inherit the same theme and controls.

## Data and behavior

The reference was used for presentation. Existing Supabase authentication, roles, scoring, question safety, matchmaking, audio completion fix and battle reports remain in place. No database migration or OAuth change is needed for this pass.

The leaderboard's existing RPC returns rating, level, rank and the mode's metric. Those real fields are shown. Correct/wrong totals from the reference image are not invented. “Daily quiz” maps to the app's actual shared daily challenge. Sample Home, ranking and progress data appear only in explicitly labelled local preview mode.

## Verification

Automated checks cover Home, Leaderboard, Progress and subject selection at 375-point phone width, landscape, tablet width, 130% text, 200% text and reduced motion in both themes. Additional checks cover tied ranks, a two-person podium, loading/retry/unranked states, period switching and the selected subject/timer passed by the start action. Existing auth, gameplay, review and audio regression tests remain part of the suite.

Screenshots in `docs/screenshots/` include `home-light.png`, `leaderboard-light.png`, `progress-light.png` and their dark variants. They use the real application navigation with labelled preview accounts, not hosted match results. Build/device results are recorded in `docs/BUILD_STATUS.md`.
