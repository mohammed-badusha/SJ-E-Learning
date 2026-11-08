# Activate SJ E-Learning

The public URL and key you provided are already in local `config/dev.json`. The Web Google client ID has also been added to local config. The owner reports installing the SQL and enabling the Google provider; end-to-end sign-in still needs verification. No privileged Supabase credentials have been supplied.

## 1. Install the database

1. Open [your Supabase project](https://supabase.com/dashboard/project/wbijwfqtcajkfltfnntb).
2. Open **SQL Editor → New query**.
3. Open `supabase/setup.sql` from this project, copy the entire file into the editor, and run it once.
4. The script creates the app schema, RLS, RPCs, Cron jobs and sample data in one transaction. It stops if an existing `profiles` table or `sj_private` schema is found. If this project already contains another app's tables, use a new Supabase project instead of replacing or deleting existing data.
5. In **Table Editor**, confirm `categories` has 4 rows, `questions` has 160 rows, and `admin_users` contains `badushamc312@gmail.com` with role `super_admin` and `is_active = true`.
6. Check **Integrations → Cron** for `sj-match-engine` (every second), `sj-daily-resume`, and `sj-daily-generate`. The engine must remain enabled for real battles. [Supabase Cron documentation](https://supabase.com/docs/guides/cron).

For later upgrades use versioned migrations; do not run the combined first-install script again. CLI alternative for a new project:

```sh
supabase login
supabase link --project-ref wbijwfqtcajkfltfnntb
supabase db push --include-seed
```

CLI login/password prompts stay on your machine. Never send them through chat.

## 2. Enable Google sign-in (start with web)

1. Open [Google Cloud Console](https://console.cloud.google.com/) and select or create a project.
2. In **Google Auth Platform**, configure branding as **SJ E-Learning**, choose the intended audience and add your own Google accounts as test users while the app is in testing.
3. Create an OAuth client of type **Web application**. Add these JavaScript origins for local testing:
   - `http://localhost:5173`
   - `http://127.0.0.1:5173`
4. Set its authorised redirect URI to:

   ```text
   https://wbijwfqtcajkfltfnntb.supabase.co/auth/v1/callback
   ```

5. Copy the **Web client ID**. Put it in `config/dev.json` as `GOOGLE_WEB_CLIENT_ID`. You can send this public ID to me to wire it up.
6. In Supabase **Authentication → Sign In / Providers → Google**, enable Google. Paste the Web client ID and its client secret there. **Keep the client secret in Supabase; do not put it in the app or chat.** If adding multiple platform IDs, put the web ID first.
7. In Supabase **Authentication → URL Configuration**, use `http://localhost:5173` as the development Site URL and add these redirect URLs:
   - `http://localhost:5173`
   - `http://127.0.0.1:5173`
   - `in.sjacademy.quiz://login-callback`
8. Disable unwanted sign-in providers, including email/password and anonymous sign-in, in the dashboard. The app implements Google only.

The app requests Google identity only. It uses browser OAuth on web and exchanges the native Google ID token through Supabase on phones. Provider setup reference: [Supabase Google sign-in](https://supabase.com/docs/guides/auth/social-sign-in/auth-google).

Run:

```sh
flutter run -d chrome --web-port 5173 --dart-define-from-file=config/dev.json
```

Sign in with Google, complete the mandatory name and mobile number, and confirm Home opens. Signing in as `badushamc312@gmail.com` should also show the **Admin** tab. Test a second account with the same phone: it should be rejected.

## 3. Add Android Google sign-in

1. Create an **Android OAuth client** in the same Google Cloud project.
2. Use package name **`in.sjacademy.quiz_arena`**.
3. Get the SHA-1/SHA-256 values with `cd android` then `./gradlew signingReport`. If SDK licenses are requested, review and accept them yourself using `flutter doctor --android-licenses` before continuing. This machine currently reports unaccepted Android SDK licenses.
4. Register the debug signing SHA for development. Register release and Play App Signing SHA values before store distribution.
5. Keep the **Web** client ID in `GOOGLE_WEB_CLIENT_ID`: it is the native plugin's `serverClientId`. No Firebase Auth or `google-services.json` is required for this configuration. [Official Android plugin setup](https://pub.dev/packages/google_sign_in_android).

```sh
flutter run --dart-define-from-file=config/dev.json
flutter build apk --debug --dart-define-from-file=config/dev.json
```

## 4. iOS (when needed)

Create an iOS OAuth client matching the Runner bundle ID shown in Xcode. Put its public ID in `GOOGLE_IOS_CLIENT_ID`. Add the corresponding reversed client ID to `CFBundleURLTypes` in `ios/Runner/Info.plist`, alongside the existing callback scheme. Native client IDs are passed from Dart; the reversed URL scheme still must be configured. [Official iOS plugin setup](https://pub.dev/packages/google_sign_in_ios).

## 5. Define admins directly in Supabase

Open **Table Editor → admin_users → Insert row**:

| Field | Value |
| --- | --- |
| `email` | Staff member's Google email, lowercase |
| `role` | `viewer`, `editor`, or `super_admin` |
| `is_active` | `true` |
| `user_id` | Leave blank; linked on their first sign-in |

`viewer` reads admin pages; `editor` manages learning content; `super_admin` also manages staff and settings. Set `is_active = false` to revoke access. Server checks apply immediately; the app refreshes the displayed role when resumed. Super admins can also do this under **Admin → Users & roles**.

The initial SQL seeds your requested email. There is no service-role key or admin email allow-list in the Flutter client.

## 6. Edge Functions and Realtime

With Supabase CLI authenticated locally:

```sh
supabase functions deploy start_bot_match --project-ref wbijwfqtcajkfltfnntb
supabase functions deploy delete_account --project-ref wbijwfqtcajkfltfnntb
```

Both handlers validate the bearer token using Supabase Auth. Account deletion uses the service-role credential only inside the Edge Function. Hosted Supabase supplies its standard server environment variables.

The app's bot fallback also has a guarded direct RPC, so it works without the optional Edge wrapper. Game advancement is handled by the database Cron engine. `match_tick` is an optional server-only recovery endpoint; configure `MATCH_TICK_SECRET` as an Edge secret before deploying it, and never expose that secret to the app.

Private Realtime channels are used for match events. Keep **Allow public access** disabled in Realtime settings. The migration installs a membership-based receive policy and no client broadcast permission. [Realtime authorisation reference](https://supabase.com/docs/guides/realtime/authorization).

## 7. Before release

Use separate projects/configs for staging and production. Review [BUILD_STATUS.md](BUILD_STATUS.md), replace sample questions, complete the outstanding features, configure real Android signing, and verify on two physical phones. Do not publish the debug build as a production release.
