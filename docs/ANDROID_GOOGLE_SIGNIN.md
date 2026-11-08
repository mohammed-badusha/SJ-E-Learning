# Android Google sign-in — development registration

The Web client ID is configured in `config/dev.json` and included in the rebuilt debug APK. The owner has now created an Android OAuth client in the same Google Cloud project. The owner confirmed that native Google sign-in now opens Home or Complete Profile on the Moto g64 5G.

- Application type: **Android**
- Package name: `in.sjacademy.quiz_arena`
- Debug SHA-1: `30:EA:72:DE:8E:EB:F4:FF:29:14:DC:BE:E2:8A:C3:E1:AB:28:2E:F7`
- Debug SHA-256: `0E:F9:75:EF:11:9B:D9:C2:6D:E6:F9:76:12:AB:C7:62:84:AF:81:96:5A:4A:DB:4C:BD:DA:6C:03:07:FF:99:4B`

These are public certificate fingerprints from this machine’s debug signing key. Google’s Android OAuth client form requests the SHA-1 fingerprint. Register separate release/Play App Signing fingerprints before distribution. Never share or commit the signing keystore.

The Flutter app continues to use the **Web** client ID as `serverClientId`; do not replace it with the Android client ID. Add native client IDs to the Supabase Google provider if required by its audience configuration, keeping the Web client ID first.

Debug build: `build/app/outputs/flutter-apk/app-debug.apk`. This is for development testing, not Play Store release.

The SHA-1 above has been verified from the actual APK using `apksigner`, not only from the keystore. The Web client ID is also present in the compiled app. Registering the Android client is a Google Cloud change; keep the app and Supabase pointed at the existing Web client ID.

Registered Android OAuth client (reported by owner): `811073865944-8tuslp47n3b2bi8uafb93s5vcgc0t6g2.apps.googleusercontent.com`. Its project-number prefix matches the Web client. This ID is recorded for setup reference; the native app correctly continues to send the Web ID as `serverClientId`.

## Verification result

On 8 November 2026, after creating the Android OAuth client, the owner retried sign-in on the installed APK and confirmed that Home or Complete Profile opens. The existing Web client ID remains in the app and Supabase provider configuration.
