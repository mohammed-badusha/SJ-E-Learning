import 'package:flutter/material.dart';

class SearchPulse extends StatefulWidget {
  const SearchPulse({super.key, this.color});
  final Color? color;
  @override
  State<SearchPulse> createState() => _SearchPulseState();
}

class _SearchPulseState extends State<SearchPulse>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && TickerMode.of(context)) {
      if (!controller.isAnimating) controller.repeat();
    } else {
      controller.stop();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: 64,
        child: CustomPaint(
          painter: _PulsePainter(controller, color),
          child: Icon(Icons.person_search_outlined, size: 30, color: color),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.animation, this.color) : super(repaint: animation);
  final Animation<double> animation;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, 22, Paint()..color = color.withValues(alpha: .1));
    for (final offset in [0.0, .5]) {
      final t = (animation.value + offset) % 1;
      canvas.drawCircle(
        c,
        21 + 11 * t,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: (1 - t) * .48),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      color != old.color || animation != old.animation;
}
