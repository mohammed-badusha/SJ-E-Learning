# Android Google sign-in

Android uses Google's native account picker through `google_sign_in`, then sends the Google ID and access tokens to Supabase Auth with `signInWithIdToken`. Supabase still owns the app session. The browser callback is no longer used for Android sign-in. Web continues to use Supabase browser OAuth.

## Required Google Cloud setup

1. In the **same Google Cloud project** as the existing Web OAuth client, open **Google Auth Platform → Clients** and create an **Android** OAuth client.
2. Use package name **`in.sjacademy.quiz_arena`**. This is the actual `applicationId` in `android/app/build.gradle.kts`; `com.sjelearning.quiz` is the old OAuth callback scheme, not the Android package name.
3. Add the SHA-1 fingerprint of every certificate used to sign an APK. For the current debug-signed build, inspect the debug keystore with:

   ```powershell
   & 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe' -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
   ```

   On this development machine, the debug key's SHA-1 is `92:38:71:D4:CB:9F:8D:28:D0:93:F7:BE:ED:E2:B7:00:F5:BC:61:DC`. Register the Play App Signing certificate too when distributing through Google Play, and register a separate release certificate if release signing changes. A missing fingerprint can appear as a cancelled account picker after an account is selected.
4. Keep the existing **Web** client ID in `GOOGLE_WEB_CLIENT_ID` in the local build configuration. Android uses it as `serverClientId`; it must also remain configured in **Supabase → Authentication → Providers → Google**. Keep the Web client secret only in Supabase.

No Firebase Authentication or `google-services.json` is required. The Android OAuth client ID is configured in Google Cloud and does not need to be embedded in the app.

Build and install a development APK:

```sh
flutter build apk --debug --dart-define-from-file=config/dev.json
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Tap **Continue with Google**. Google's account picker should appear over the app, and after selecting an account the app should open Complete Profile or Home without a browser redirect. A new user must still provide a name and phone number before reaching Home. If sign-in fails, check the Android package name, SHA-1 and Web client ID first.
