import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/core/theme.dart';
import 'package:quiz_arena/features/auth/data/session.dart';
import 'package:quiz_arena/features/battle/domain/battle_report.dart';
import 'package:quiz_arena/features/history/presentation/review_screen.dart';
import 'package:quiz_arena/features/profile/domain/rank_tier.dart';
import 'package:quiz_arena/features/results/presentation/battle_result_screen.dart';
import 'support/battle_fixture.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final font in ['Inter', 'PlusJakartaSans']) {
      await (FontLoader(
        font,
      )..addFont(rootBundle.load('assets/fonts/$font.ttf'))).load();
    }
  });
  test('Rank boundaries agree with the actual rating thresholds', () {
    expect(RankTier.forRating(1099), RankTier.bronze);
    expect(RankTier.forRating(1100), RankTier.silver);
    expect(RankTier.forRating(1300), RankTier.gold);
    expect(RankTier.forRating(1500), RankTier.platinum);
    expect(RankTier.forRating(1700), RankTier.diamond);
    expect(RankTier.silver.pointsToNext(1200), 100);
    expect(RankTier.silver.progress(1200), .5);
    expect(RankTier.diamond.progress(1900), 1);
    expect(RankTier.diamond.next, isNull);
  });
  test(
    'Reports preserve real timing, unanswered rounds and cumulative points',
    () {
      final report = BattleReport.fromJson(
        battleFixture,
        initialState: battleFixture,
      );
      expect(report.advanced, isTrue);
      expect(report.player('me').unanswered, 1);
      expect(report.player('me').ratingChange, 8);
      expect(report.cumulativeScores(), [0, 12, 12, 35]);
      expect(report.cumulativeScores(opponent: true), [0, 12, 12, 12]);
      expect(answerTime(null), '—');
      expect(answerTime(2400), '2.4s');
      expect(answerAccuracy(66.7), '66.7%');
      final legacy = BattleReport.fromJson(
        {'questions': []},
        initialState: {
          'players': [
            {'id': 'me', 'rating': 1000},
            {'id': 'other', 'rating': 1050},
          ],
        },
      );
      expect(legacy.advanced, isFalse);
      expect(legacy.player('me').avgResponseMs, isNull);
    },
  );

  testWidgets(
    'Full battle report and answer review fit a small phone at large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionController(null)..enterPreview();
      addTearDown(session.dispose);
      final key = GlobalKey();
      Widget app(Widget screen) => ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => session)],
        child: MaterialApp(
          theme: arenaTheme(Brightness.light),
          home: RepaintBoundary(key: key, child: screen),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
        ),
      );
      await tester.pumpWidget(
        app(
          BattleResultScreen(
            matchId: 'test',
            initialState: battleFixture,
            viewerId: 'me',
            reportLoader: () async => battleFixture,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('You won'), findsOneWidget);
      expect(find.text('Silver tier'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        await File(
          'docs/screenshots/battle-report.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.scrollUntilVisible(
        find.text('How the battle unfolded'),
        300,
      );
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Review every answer'), 300);
      expect(
        find.text('3 of 3 questions played · 34.2s match time'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(
          ReviewScreen(
            questions: List<Map<String, dynamic>>.from(
              battleFixture['questions'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Opponent answer').first,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('A · 144'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byType(Switch).first,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('Unanswered'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
