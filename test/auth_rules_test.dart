import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/features/auth/domain/models.dart';
import 'package:quiz_arena/features/practice/data/quiz_repository.dart';

void main() {
  test('Every route is gated until the required profile is complete', () {
    for (final path in ['/', '/admin', '/quiz', '/battle/id', '/history']) {
      expect(
        routeRedirect(
          signedIn: true,
          completed: false,
          role: AdminRole.superAdmin,
          path: path,
        ),
        '/complete-profile',
      );
    }
    expect(
      routeRedirect(
        signedIn: false,
        completed: false,
        role: AdminRole.student,
        path: '/admin',
      ),
      '/login',
    );
    expect(
      routeRedirect(
        signedIn: true,
        completed: true,
        role: AdminRole.student,
        path: '/admin/question',
      ),
      '/',
    );
    expect(
      routeRedirect(
        signedIn: true,
        completed: true,
        role: AdminRole.viewer,
        path: '/admin',
      ),
      isNull,
    );
  });
  test(
    'Indian phone validation handles the country code and rejects invalid numbers',
    () {
      expect(validatePhone('+91 98765 43210'), isNull);
      expect(validatePhone('9876543210'), isNull);
      for (final value in [
        '1234567890',
        '987654321',
        '+449876543210',
        'abcd',
        '',
      ]) {
        expect(validatePhone(value), isNotNull);
      }
      expect(validateName(' A '), isNotNull);
      expect(validateName('Ananya Nair'), isNull);
    },
  );
  test('Preview score stays bounded and doubles only the final round', () {
    expect(
      previewScore(correct: true, remainingMs: 15000, durationMs: 15000),
      20,
    );
    expect(
      previewScore(correct: true, remainingMs: -100, durationMs: 15000),
      10,
    );
    expect(
      previewScore(
        correct: true,
        remainingMs: 7500,
        durationMs: 15000,
        finalRound: true,
      ),
      30,
    );
    expect(
      previewScore(correct: false, remainingMs: 15000, durationMs: 15000),
      0,
    );
  });
}
