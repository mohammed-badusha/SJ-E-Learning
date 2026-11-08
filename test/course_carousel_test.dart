import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/core/theme.dart';
import 'package:quiz_arena/features/home/presentation/course_carousel.dart';

void main() {
  testWidgets(
    'Banners advance, accept swipes and wrap from the last course to the first',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: arenaTheme(Brightness.light),
          home: const Scaffold(body: CourseCarousel()),
        ),
      );
      expect(find.bySemanticsLabel('Banner 1 of 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Banner 2 of 3'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Banner 3 of 3'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Banner 1 of 3'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
