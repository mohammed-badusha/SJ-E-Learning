import 'dart:io';
import 'package:quiz_arena/core/audio/audio_controller.dart';
import 'support/fake_audio.dart';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/core/theme.dart';
import 'package:quiz_arena/main.dart';
import 'package:quiz_arena/features/auth/presentation/auth_screens.dart';
import 'package:quiz_arena/features/categories/presentation/category_screen.dart';
import 'package:quiz_arena/features/profile/presentation/profile_screen.dart';
import 'package:quiz_arena/features/settings/presentation/settings_screen.dart';
import 'package:quiz_arena/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:quiz_arena/features/daily_challenge/presentation/daily_screen.dart';
import 'package:quiz_arena/features/auth/data/session.dart';
import 'package:quiz_arena/features/home/presentation/home_screen.dart';
import 'package:quiz_arena/features/practice/presentation/quiz_screen.dart';
import 'package:quiz_arena/shared/widgets.dart';
import 'package:go_router/go_router.dart';

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
  test('Light is the default appearance', () {
    final session = SessionController(null);
    expect(session.themeMode, ThemeMode.light);
    session.dispose();
  });
  testWidgets('Student screens fit a small phone at 130 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionController(null)..enterPreview();
    for (final screen in const <Widget>[
      LoginScreen(),
      CategoryScreen(),
      ProfileScreen(),
      LeaderboardScreen(),
      DailyScreen(),
      SettingsScreen(),
    ]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => session),
            audioBackendProvider.overrideWith((ref) => FakeAudioBackend()),
          ],
          child: MaterialApp(
            theme: arenaTheme(Brightness.light),
            home: screen,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
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
        reason: screen.runtimeType.toString(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
    session.dispose();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'Home renders in ${brightness.name}, small phone and large text',
      (tester) async {
        tester.view.physicalSize = const Size(375, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = SessionController(null)..enterPreview();
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, state) => const HomeScreen()),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWith((ref) => session),
              audioBackendProvider.overrideWith((ref) => FakeAudioBackend()),
            ],
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              theme: arenaTheme(brightness),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: child!,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your practice'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        session.dispose();
      },
    );
    testWidgets('Home screenshot ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionController(null)..enterPreview();
      final key = GlobalKey();
      session.setTheme(
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      );
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
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ImageByteFormat.png);
        await Directory('docs/screenshots').create(recursive: true);
        await File(
          'docs/screenshots/home-${brightness.name}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    });
  }
  testWidgets('All option states and timer have readable semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: arenaTheme(Brightness.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final state in OptionState.values)
                  OptionTile(label: 'A', text: state.name, state: state),
                const TimerRing(remaining: 4, total: 15),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('4 seconds remaining')),
      findsOneWidget,
    );
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Practice locks an answer, explains it, and advances', (
    tester,
  ) async {
    final session = SessionController(null)..enterPreview();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          audioBackendProvider.overrideWith((ref) => FakeAudioBackend()),
        ],
        child: MaterialApp(
          theme: arenaTheme(Brightness.light),
          home: const QuizScreen(timed: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('4% decrease'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Correct · +10'), 200);
    expect(find.text('Correct · +10'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsWidgets);
    await tester.ensureVisible(find.text('Next question'));
    await tester.tap(find.text('Next question'));
    await tester.pumpAndSettle();
    expect(find.text('Question 2 of 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
  });
}
