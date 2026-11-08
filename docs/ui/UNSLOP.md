# SJ E-Learning light UI pass

Applied with the user's approved direction on 8 November 2026.

## Direction

- **Product:** competitive-exam practice for SJ students
- **Character:** focused, friendly, competitive
- **World:** revision sheets and match scorecards
- **Moments:** one distinct battle entry card; semantic colour for answers and earned progress
- **Signature:** A–D answer markers and ruled score rows

The SJ monogram and flat violet brand accent are retained. Light is the initial appearance, with a one-time migration for existing installations. A subsequent choice of light, dark or system appearance is saved normally.

## Audit addressed

- Large saturated battle panel and competing amber action on Home
- Lavender surfaces and several competing icon colours
- Weight 700–800 headings and decorative stat icons
- Generic greetings, encouragement slogans and vague screen titles
- Repeated rounded boxes, inconsistent padding and nested corner radii
- Decorative floating blocks in the sign-in introduction
- Oversized coloured category icons and distracting selected-category washes
- Uppercase final-round labels and inconsistent numeric typography
- System-default appearance opening dark despite the requested light theme

## Nine passes

1. **Spacing:** retained a 4-point rhythm; 24-point page gutters, 20-point cards, 16-point option padding and consistent row alignment. Material touch targets remain at least 48 points.
2. **Colour:** white cards on a nearly white neutral background, three text roles and quiet rules. Violet is concentrated in the primary battle action and selections. Correct, wrong and timer states retain meaningful semantic colour.
3. **Icons:** kept Material icons, favoured outline variants, removed decorative stat icons and coloured icon boxes, and used small category dots for the existing category colours.
4. **Copy:** Home names the practice context. Navigation and screen titles say Profile, Settings, Leaderboard and Answer review. Buttons describe their next action; results and final-round labels use sentence case.
5. **Type:** retained the bundled Inter/Jakarta pair, reduced headings to weight 500, removed negative tracking from small text, and set tabular numerals for scores and figures.
6. **Layout:** retained section order and all routes/actions. Battle entry is compact, daily entry uses the current IST date, stats share one ruled row, and practice/leaderboard shortcuts share one list. Desktop navigation expands to a readable rail.
7. **Details:** cards use 16-point corners, controls 10, options 12 and small answer markers 4. Idle answers now include a neutral radio indicator; correct/wrong/locked icons remain. System-bar icon brightness follows the chosen theme.
8. **Visuals:** replaced floating shapes with a coded multiple-choice example on sign-in. Home's A–D marks and actual user stats carry the product context. No generated image was needed and no image prompt was used.
9. **Motion:** retained native press/focus feedback, no decorative loops or new entrance sequences. Timer state remains server-driven and does not animate layout. Shared easing is defined for future intentional transitions.

## Verification

- Flutter tests cover light default, 375-point screens at 130% text scale, light/dark Home, accessible option/timer states, and practice answer locking/advancement.
- New Home captures include the actual application navigation and clearly mark preview data.
- The previous Home screenshots are preserved in `docs/ui/before/`.
- No authentication, gameplay, scoring or database policy changes were made in this design pass.

## Attribution

Design workflow adapted from **unslop by Damir Sokolovsky (@heydamir)**, licensed **CC BY 4.0**. [Author and project](https://heydamir.design/unslop). This report records the adaptation and changes; the original skill remains at `/Users/salmanfaris/.codex/skills/unslop/SKILL.md`.

## Device verification

The light UI APK was installed over authorised USB on the Moto g64 5G (`ZD222M868Z`) and the app opened successfully. The native screen capture is `docs/screenshots/moto-g64-light.png`. Google login on the phone exposed a native sign-in failure; browser OAuth is separately configured. Android client registration must match package `in.sjacademy.quiz_arena` and the verified debug SHA-1 in `docs/ANDROID_GOOGLE_SIGNIN.md`. A generic catch-all sign-in message has been replaced with specific, safe failure references.

After the Android OAuth client was registered, the owner confirmed successful native Google sign-in on the installed light UI APK. The UI refinement, USB installation and development sign-in verification are complete.
