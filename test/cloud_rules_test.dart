import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/features/auth/data/session.dart';
import 'package:quiz_arena/features/battle/domain/battle_report.dart';
import 'package:quiz_arena/features/categories/presentation/category_screen.dart';
import 'package:quiz_arena/shared/arena_motion.dart';
import 'package:quiz_arena/core/theme.dart';

void main() {
  test(
    'Fractional battle marks survive JSON decoding and chart accumulation',
    () {
      final data = <String, dynamic>{
        'players': [
          {'id': 'me', 'score': 9.125, 'speed_bonus': 1.125},
        ],
        'question_count': 4,
        'questions': [
          {'points': 2.25},
          {'points': 2.125},
          {'points': 2.5},
          {'points': 2.25},
        ],
      };
      final report = BattleReport.fromJson(data, initialState: data);
      expect(report.player('me').score, 9.125);
      expect(report.player('me').speedBonus, 1.125);
      expect(report.cumulativeScores(), [0, 2.25, 4.375, 6.875, 9.125]);
    },
  );
  testWidgets('Score counters display decimal marks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountMetric(2.25))),
    );
    await tester.pumpAndSettle();
    expect(find.text('2.25'), findsOneWidget);
  });
  testWidgets(
    'Battle setup uses all four subjects and handles live invalidation and disposal',
    (tester) async {
      final session = SessionController(null)..enterPreview();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith((ref) => session)],
          child: MaterialApp(
            theme: arenaTheme(Brightness.light),
            home: const CategoryScreen(mode: 'battle'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Four-subject battle'), findsOneWidget);
      expect(
        find.text('Reasoning 40s · GK 15s\nMaths 40s · English 15s'),
        findsOneWidget,
      );
      expect(find.text('Choose a subject'), findsNothing);
      session.dataChanges.value++;
      await tester.pumpAndSettle();
      expect(find.text('Find my opponent'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
