import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quiz_arena/core/audio/audio_controller.dart';
import 'package:quiz_arena/core/theme.dart';
import 'package:quiz_arena/features/auth/data/session.dart';
import 'package:quiz_arena/features/categories/presentation/category_screen.dart';
import 'package:quiz_arena/features/home/presentation/home_screen.dart';
import 'package:quiz_arena/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:quiz_arena/features/profile/presentation/profile_screen.dart';
import 'package:quiz_arena/main.dart';
import 'support/fake_audio.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  testWidgets('Tied ranks and two-person podium preserve the server rank', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionController(null)..enterPreview();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => session)],
        child: MaterialApp(
          theme: arenaTheme(Brightness.light),
          home: LeaderboardScreen(
            dataLoader: (_) async => {
              'rows': [
                {
                  'id': 'preview',
                  'full_name': 'Alex Learner',
                  'rank': 1,
                  'metric': 0,
                  'rating': 1000,
                },
                {
                  'id': 'two',
                  'full_name': 'A learner with a very long name',
                  'rank': 1,
                  'metric': 0,
                  'rating': 1000,
                },
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Top rankings'), 200);
    expect(find.text('2'), findsNothing);
    expect(find.text('3'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
  testWidgets('Subject selection and timer feed the sticky start action', (
    tester,
  ) async {
    final session = SessionController(null)..enterPreview();
    final router = GoRouter(
      initialLocation: '/categories',
      routes: [
        GoRoute(
          path: '/categories',
          builder: (_, __) => const CategoryScreen(),
        ),
        GoRoute(
          path: '/quiz',
          builder: (_, state) => Scaffold(
            body: Text(
              '${state.uri.queryParameters['category']} / ${state.uri.queryParameters['timed']}',
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWith((ref) => session)],
        child: MaterialApp.router(
          theme: arenaTheme(Brightness.light),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('English'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(Switch),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Start practice'));
    await tester.pumpAndSettle();
    expect(find.text('english / false'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    session.dispose();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'Redesign fits phones, landscape, tablets and large text in ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final layout in [
          (375.0, 900.0, 1.3),
          (812.0, 375.0, 1.3),
          (1024.0, 900.0, 1.0),
          (375.0, 900.0, 2.0),
        ]) {
          tester.view.physicalSize = Size(layout.$1, layout.$2);
          for (final page in [
            (const HomeScreen(), '1v1 Battle'),
            (const LeaderboardScreen(), 'Rahul Sharma'),
            (const ProfileScreen(), 'Revisit your battles'),
            (const CategoryScreen(), 'Practise with a timer'),
          ]) {
            final session = SessionController(null)..enterPreview();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  sessionProvider.overrideWith((ref) => session),
                  audioBackendProvider.overrideWith(
                    (ref) => FakeAudioBackend(),
                  ),
                ],
                child: MaterialApp(
                  theme: arenaTheme(brightness),
                  home: page.$1,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(layout.$3),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '${page.$1.runtimeType} $layout',
            );
            await tester.scrollUntilVisible(
              find.text(page.$2),
              layout.$2 / 2,
              scrollable: find.byType(Scrollable).first,
              maxScrolls: 40,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'Scrolled ${page.$1.runtimeType} $layout',
            );
            await tester.pumpWidget(const SizedBox.shrink());
            session.dispose();
          }
        }
      },
    );
    testWidgets('Capture real navigation screens in ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionController(null)..enterPreview();
      session.setTheme(
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => session),
            audioBackendProvider.overrideWith((ref) => FakeAudioBackend()),
          ],
          child: RepaintBoundary(key: key, child: const SJLearningApp()),
        ),
      );
      await tester.pumpAndSettle();
      for (final tab in ['Leaderboard', 'Progress']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(tab),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final img =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await img.toByteData(format: ImageByteFormat.png);
          await File(
            'docs/screenshots/${tab.toLowerCase()}-${brightness.name}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          img.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }
  testWidgets(
    'Leaderboard periods, unranked state and retry use real load results',
    (tester) async {
      final session = SessionController(null)..enterPreview();
      final requested = <String>[];
      var fail = true;
      final daily = Completer<Map<String, dynamic>>();
      Future<Map<String, dynamic>> load(String type) async {
        requested.add(type);
        if (type == 'daily') return daily.future;
        if (fail) throw StateError('offline');
        return {
          'rows': [
            {
              'id': 'preview',
              'full_name': 'Alex Learner',
              'metric': 0,
              'rank': 1,
              'rating': 1000,
              'level': 1,
            },
          ],
        };
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sessionProvider.overrideWith((ref) => session)],
          child: MaterialApp(
            theme: arenaTheme(Brightness.light),
            home: LeaderboardScreen(dataLoader: load),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rankings couldn’t load'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      await tester.tap(find.text('All-time rating'));
      await tester.pumpAndSettle();
      expect(requested.last, 'all_time');
      await tester.tap(find.text('Daily quiz'));
      await tester.pump();
      expect(find.bySemanticsLabel('Updating the standings…'), findsOneWidget);
      daily.complete({'rows': []});
      await tester.pumpAndSettle();
      expect(find.text('Complete a round to get ranked'), findsOneWidget);
      expect(find.text('The podium is waiting'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );
}
