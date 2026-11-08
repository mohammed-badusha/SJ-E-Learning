import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quiz_arena/features/auth/presentation/sign_in_error.dart';

void main() {
  test('An incomplete Google flow is not misreported as a broken provider', () {
    const error = GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );
    final message = signInErrorMessage(error, configured: true);
    expect(message, contains('not completed'));
    expect(message, isNot(contains('not configured')));
    expect(signInDiagnosticCode(error), 'google/canceled');
  });
  test(
    'A native client configuration failure has a precise safe reference',
    () {
      const error = GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'Private provider details',
        details: 'sensitive credential',
      );
      final message = signInErrorMessage(
        error,
        configured: true,
        includeDiagnosticCode: true,
      );
      expect(message, contains('not configured for this app build'));
      expect(message, contains('google/clientConfigurationError'));
      expect(message, isNot(contains('sensitive credential')));
      expect(message, isNot(contains('Private provider details')));
    },
  );
  test('Backend verification failures do not expose returned credentials', () {
    const error = AuthException(
      'Sensitive raw response',
      code: 'invalid_credentials',
    );
    final message = signInErrorMessage(
      error,
      configured: true,
      includeDiagnosticCode: true,
    );
    expect(message, contains('could not be verified'));
    expect(message, contains('supabase/invalid_credentials'));
    expect(message, isNot(contains('Sensitive raw response')));
  });
}
