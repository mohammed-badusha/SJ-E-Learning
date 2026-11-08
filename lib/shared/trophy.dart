import 'package:flutter/material.dart';

/// Small enamel cup drawn at device resolution; does not depend on emoji fonts.
class Trophy extends StatelessWidget {
  const Trophy({
    super.key,
    this.size = 32,
    this.metal = const Color(0xffffbf49),
  });
  final double size;
  final Color metal;
  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Cup(metal)),
    ),
  );
}

class _Cup extends CustomPainter {
  const _Cup(this.metal);
  final Color metal;
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 40, s.height / 40);
    final shade = Color.lerp(metal, const Color(0xff402737), .46)!;
    final gleam = Color.lerp(metal, Colors.white, .64)!;
    final pen = Paint()
      ..color = shade
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    c.drawPath(
      Path()
        ..moveTo(9, 9)
        ..lineTo(3, 9)
        ..quadraticBezierTo(2, 19, 12, 20)
        ..moveTo(31, 9)
        ..lineTo(37, 9)
        ..quadraticBezierTo(38, 19, 28, 20),
      pen,
    );
    c.drawPath(
      Path()
        ..moveTo(8, 5)
        ..lineTo(32, 5)
        ..lineTo(30, 17)
        ..quadraticBezierTo(28, 25, 22, 26)
        ..lineTo(22, 30)
        ..lineTo(27, 32)
        ..lineTo(27, 34)
        ..lineTo(13, 34)
        ..lineTo(13, 32)
        ..lineTo(18, 30)
        ..lineTo(18, 26)
        ..quadraticBezierTo(10, 23, 10, 17)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          colors: [gleam, metal, shade],
          stops: const [0, .5, 1],
        ).createShader(const Rect.fromLTWH(8, 5, 24, 30)),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(7, 4, 26, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = gleam,
    );
    c.drawPath(
      Path()
        ..moveTo(20, 10)
        ..lineTo(21.7, 14)
        ..lineTo(26, 14.4)
        ..lineTo(22.6, 17.2)
        ..lineTo(23.5, 21.3)
        ..lineTo(20, 19)
        ..lineTo(16.4, 21.3)
        ..lineTo(17.4, 17.2)
        ..lineTo(14, 14.4)
        ..lineTo(18.3, 14)
        ..close(),
      Paint()..color = gleam,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 34, 20, 4),
        const Radius.circular(1.5),
      ),
      Paint()..color = shade,
    );
    c.restore();
  }

  @override
  bool shouldRepaint(_Cup old) => metal != old.metal;
}
