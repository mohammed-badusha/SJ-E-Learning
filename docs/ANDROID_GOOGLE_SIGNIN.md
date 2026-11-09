# Android Google sign-in

The Android app signs in through the Supabase Google OAuth flow in the system browser. Supabase returns to `com.sjelearning.quiz://login-callback/`, which is registered in the Android manifest and Supabase Auth redirect URLs. The Android application ID remains `in.sjacademy.quiz_arena`.

In the Supabase dashboard, enable Google under **Authentication → Providers**. Under **Authentication → URL Configuration**, allow `com.sjelearning.quiz://login-callback/` exactly. Keep the Google Web OAuth client configured in the Supabase provider; its authorized redirect URI is the Supabase Auth callback shown in the dashboard. The Google client secret stays in Supabase and is never included in the app.

Build and install a development APK:

```sh
flutter build apk --debug --dart-define-from-file=config/dev.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

After selecting a Google account, the browser should return to the app. A new user must provide a name and phone number before reaching Home. If the browser instead lands on `localhost:5173`, check that the app's `AUTH_REDIRECT_URL` and the Supabase allowlist match the callback above. Do not share OAuth `code` query parameters when reporting errors.
