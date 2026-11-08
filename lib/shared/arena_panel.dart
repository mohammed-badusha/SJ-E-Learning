import 'package:flutter/material.dart';

/// The two sides of the arena share these colours from entry to scorecard.
const arenaInk = Color(0xff19244a);
const arenaMint = Color(0xffaaf1d5);
const arenaLilac = Color(0xffc6bcff);

class ArenaPanel extends StatelessWidget {
  const ArenaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: DecoratedBox(
      decoration: const BoxDecoration(color: arenaInk),
      child: CustomPaint(
        painter: const _CourtMarkings(),
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class _CourtMarkings extends CustomPainter {
  const _CourtMarkings();
  @override
  void paint(Canvas canvas, Size size) {
    final edge = size.width * .73;
    canvas.drawPath(
      Path()
        ..moveTo(edge, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(edge - size.height * .45, size.height)
        ..close(),
      Paint()..color = const Color(0xff303578),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x287e92e9);
    final origin = Offset(size.width, size.height * .55);
    for (final r in [45.0, 71.0, 98.0, 125.0]) {
      canvas.drawCircle(origin, r, line);
    }
    canvas.drawLine(
      Offset(edge - 8, 0),
      Offset(edge - size.height * .45 - 8, size.height),
      line,
    );
  }

  @override
  bool shouldRepaint(_CourtMarkings old) => false;
}

class ArenaPortrait extends StatelessWidget {
  const ArenaPortrait({super.key, required this.child, required this.accent});
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    ),
  );
}
