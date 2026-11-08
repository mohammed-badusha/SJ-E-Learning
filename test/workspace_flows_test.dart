import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/core/audio/audio_controller.dart';
import 'package:quiz_arena/core/theme.dart';
import 'package:quiz_arena/features/admin/presentation/admin_directory.dart';
import 'package:quiz_arena/features/admin/presentation/question_import_screen.dart';
import 'package:quiz_arena/features/auth/data/session.dart';
import 'package:quiz_arena/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:quiz_arena/features/practice/data/quiz_repository.dart';
import 'package:quiz_arena/features/practice/presentation/quiz_screen.dart';
import 'support/fake_audio.dart';

void main() {
  testWidgets(
    'Daily answer proceeds automatically while there is still time left',
    (tester) async {
      final session = SessionController(null)..enterPreview();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((_) => session),
            audioBackendProvider.overrideWith((_) => FakeAudioBackend()),
          ],
          child: MaterialApp(
            theme: arenaTheme(Brightness.light),
            home: const QuizScreen(mode: 'daily'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('4% decrease'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 5'), findsOneWidget);
      expect(find.text('Next question'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  testWidgets(
    'Reopening standings shows the cached scores during a refresh and after a failure',
    (tester) async {
      final session = SessionController(null)..enterPreview();
      final open = ValueNotifier(true);
      final retry = Completer<Map<String, dynamic>>();
      var calls = 0;
      Future<Map<String, dynamic>> fetch(String _) async {
        if (++calls > 1) return retry.future;
        return {
          'rows': [
            {
              'id': 'preview',
              'full_name': 'Alex',
              'rank': 1,
              'metric': 123,
              'level': 1,
              'rating': 1000,
            },
          ],
        };
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith((_) => session)],
          child: MaterialApp(
            theme: arenaTheme(Brightness.light),
            home: ValueListenableBuilder<bool>(
              valueListenable: open,
              builder: (_, show, _) => show
                  ? LeaderboardScreen(dataLoader: fetch)
                  : const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('#1'), findsOneWidget);
      open.value = false;
      await tester.pump();
      open.value = true;
      await tester.pump();
      expect(calls, 2);
      expect(find.text('#1'), findsOneWidget);
      retry.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Showing saved standings'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
      open.dispose();
    },
  );
  testWidgets(
    'JSON example can be pasted and previewed with actionable validation',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = SessionController(null)..enterPreview();
      await tester.pumpWidget(
        MaterialApp(
          theme: arenaTheme(Brightness.light),
          home: QuestionImportScreen(repo: QuizRepository(session)),
        ),
      );
      final field = find.byType(TextField);
      await tester.enterText(field, '{"questions":[]}');
      await tester.ensureVisible(find.text('Preview import'));
      await tester.tap(find.text('Preview import'));
      await tester.pumpAndSettle();
      expect(find.text('Include 1–500 questions.'), findsOneWidget);
      await tester.enterText(field, jsonEncode(questionImportExample));
      await tester.ensureVisible(find.text('Preview import'));
      await tester.tap(find.text('Preview import'));
      await tester.pumpAndSettle();
      expect(find.text('2 questions ready to import'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );
  test('CSV preserves phone numbers and neutralises spreadsheet formulas', () {
    expect(csvCell('+919999999999'), "'+919999999999");
    expect(csvCell('=1+2'), "'=1+2");
    expect(csvCell(1250), '1250');
  });
}
