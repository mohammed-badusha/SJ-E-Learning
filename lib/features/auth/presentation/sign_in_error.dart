import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Safe support reference: never log credentials, tokens or provider details.
String signInDiagnosticCode(Object error) {
  if (error is GoogleSignInException) return 'google/${error.code.name}';
  if (error is AuthException) {
    final code = (error.code ?? error.statusCode ?? 'unknown').replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '',
    );
    return 'supabase/${code.substring(0, code.length.clamp(0, 64))}';
  }
  if (error is StateError) return 'app/configuration';
  return 'auth/unexpected';
}

String signInErrorMessage(
  Object error, {
  required bool configured,
  bool includeDiagnosticCode = false,
}) {
  final String message;
  if (!configured) {
    message =
        'Sign-in is not connected yet. You can explore the local preview.';
  } else if (error is GoogleSignInException) {
    message = switch (error.code) {
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google sign-in is not configured for this app build yet. Contact the academy.',
      // Android can also report some configuration failures as canceled.
      // Do not claim that the user canceled or that configuration is broken.
      GoogleSignInExceptionCode.canceled =>
        'Google sign-in was not completed. Please try again.',
      GoogleSignInExceptionCode.interrupted ||
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google sign-in was interrupted. Please try again.',
      _ => 'Google could not sign you in. Check your connection and try again.',
    };
  } else if (error is AuthException) {
    message = 'Your Google sign-in could not be verified. Please try again.';
  } else if (error is StateError) {
    message = 'Sign-in needs an app configuration update. Contact the academy.';
  } else {
    message = 'Sign-in could not finish. Check your connection and try again.';
  }
  return includeDiagnosticCode
      ? '$message\nReference: ${signInDiagnosticCode(error)}'
      : message;
}
