import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quiz_arena/core/theme.dart';
import 'package:quiz_arena/features/battle/presentation/duel_intro.dart';
import 'package:quiz_arena/features/auth/presentation/auth_screens.dart';
import 'package:quiz_arena/features/auth/presentation/portrait_picker.dart';
import 'package:quiz_arena/features/matchmaking/presentation/search_clock.dart';
import 'package:quiz_arena/shared/arena_motion.dart';
import 'support/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  testWidgets(
    'Queue ticks every second independently of polls and catches up after suspension',
    (tester) async {
      final start = DateTime.utc(2026, 1, 2);
      var now = start;
      final clock = SearchClock(now: () => now);
      clock.sync(joined: start, server: start, timeout: 20);
      expect(clock.value, 20);
      for (var i = 1; i <= 4; i++) {
        now = start.add(Duration(seconds: i));
        await tester.pump(const Duration(seconds: 1));
        if (i == 2) {
          clock.sync(
            joined: start,
            server: now.subtract(const Duration(milliseconds: 400)),
            timeout: 20,
          );
        }
        expect(clock.value, 20 - i);
      }
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(clock.value, 0);
      clock.dispose();
    },
  );
  testWidgets(
    'Gallery input becomes a small square PNG independent of input dimensions',
    (tester) async {
      await tester.runAsync(() async {
        final bytes = await portraitThumbnail(
          await File('assets/avatars/raman.webp').readAsBytes(),
        );
        final codec = await ui.instantiateImageCodec(bytes);
        final image = (await codec.getNextFrame()).image;
        expect([image.width, image.height], [192, 192]);
        expect(bytes.length, lessThan(180000));
        image.dispose();
        codec.dispose();
      });
    },
  );
  testWidgets(
    'Login has one sign-in path; onboarding supports selecting or clearing a portrait',
    (tester) async {
      tester.view.physicalSize = const Size(390, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: arenaTheme(Brightness.light),
          home: RepaintBoundary(key: key, child: child),
        ),
      );
      await tester.pumpWidget(host(const SizedBox()));
      await tester.runAsync(() async {
        for (final path in [
          'assets/brand/sj-logo-source.png',
          'assets/brand/google-g.png',
          for (final id in ['curie', 'raman', 'einstein', 'explorer'])
            'assets/avatars/$id.webp',
        ]) {
          await precacheImage(
            AssetImage(path),
            key.currentContext!,
            onError: (e, _) => fail('Portrait failed to decode: $e'),
          );
        }
      });
      await tester.pumpWidget(host(const LoginScreen()));
      await tester.pumpAndSettle();
      expect(find.byType(PortraitPicker), findsNothing);
      expect(find.text('Explore the local preview'), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/screenshots/login-portraits.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(host(const CompleteProfileScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Marie Curie'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PortraitPicker>(find.byType(PortraitPicker))
            .choice
            ?.reference,
        'preset:curie',
      );
      await tester.tap(find.text('Use initials'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PortraitPicker>(find.byType(PortraitPicker))
            .choice
            ?.reference,
        'initials',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Full screen matchup fits portrait and landscape and the leave action stays reachable',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final key = GlobalKey();
      var leaves = 0;
      Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: arenaTheme(Brightness.light),
          home: RepaintBoundary(key: key, child: child),
        ),
      );
      tester.view.physicalSize = const Size(390, 812);
      await tester.pumpWidget(host(const SizedBox()));
      await tester.runAsync(() async {
        for (final id in ['curie', 'raman']) {
          await precacheImage(
            AssetImage('assets/avatars/$id.webp'),
            key.currentContext!,
          );
        }
      });
      await tester.pumpWidget(
        host(
          DuelIntro(
            name: 'Alex',
            rival: 'Meera',
            ownPortrait: 'preset:curie',
            rivalPortrait: 'preset:raman',
            matchId: 'demo',
            ownRank: 'Silver',
            rivalRank: 'Gold',
            bot: false,
            onLeave: () => leaves++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/screenshots/match-found.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(812, 375);
      await tester.pumpAndSettle();
      expect(find.text('Meera'), findsOneWidget);
      await tester.tap(find.byTooltip('Leave match'));
      expect(leaves, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Reduced motion exposes the final metric on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: CountMetric(320),
        ),
      ),
    );
    expect(find.text('320'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CountMetric),
        matching: find.byType(TweenAnimationBuilder<double>),
      ),
      findsNothing,
    );
  });
}
