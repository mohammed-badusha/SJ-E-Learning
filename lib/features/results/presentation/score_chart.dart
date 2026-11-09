import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme.dart';

class ScoreChart extends StatelessWidget {
  const ScoreChart({
    super.key,
    required this.yours,
    required this.opponent,
    required this.opponentName,
  });
  final List<num> yours, opponent;
  final String opponentName;
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Cumulative score by question. You: ${yours.skip(1).join(', ')}. $opponentName: ${opponent.skip(1).join(', ')}.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Legend(label: 'You', color: Theme.of(context).colorScheme.primary),
            _Legend(
              label: opponentName,
              color: context.tokens.muted,
              dashed: true,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 180,
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : ArenaTokens.normal,
            tween: Tween(
              begin: MediaQuery.disableAnimationsOf(context) ? 1.0 : 0.0,
              end: 1,
            ),
            curve: ArenaTokens.ease,
            builder: (context, progress, _) => CustomPaint(
              painter: _ScorePainter(
                yours,
                opponent,
                Theme.of(context).colorScheme.primary,
                context.tokens.muted,
                context.tokens.line,
                MediaQuery.textScalerOf(context).scale(12),
                progress,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.color,
    this.dashed = false,
  });
  final String label;
  final Color color;
  final bool dashed;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 22,
        child: Row(
          children: [
            Expanded(
              child: ColoredBox(color: color, child: const SizedBox(height: 2)),
            ),
            if (dashed) ...[
              const SizedBox(width: 4),
              Expanded(
                child: ColoredBox(
                  color: color,
                  child: const SizedBox(height: 2),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(width: 8),
      Flexible(child: Text(label, style: context.type.bodySmall)),
    ],
  );
}

class _ScorePainter extends CustomPainter {
  _ScorePainter(
    this.you,
    this.other,
    this.accent,
    this.muted,
    this.line,
    this.fontSize,
    this.progress,
  );
  final List<num> you, other;
  final Color accent, muted, line;
  final double fontSize, progress;
  @override
  void paint(Canvas canvas, Size size) {
    if (you.length < 2) return;
    final maxValue = math.max(
      2.5,
      math.max(you.fold<num>(0, math.max), other.fold<num>(0, math.max)),
    );
    final top = 8.0,
        left = 40.0,
        width = size.width - 48,
        height = size.height - 36;
    void label(String value, Offset offset) {
      final text = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: muted,
            fontSize: fontSize,
            fontFamily: 'Inter',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, offset);
    }

    for (var i = 0; i < 3; i++) {
      final y = top + height * (1 - i / 2);
      canvas.drawLine(
        Offset(left, y),
        Offset(left + width, y),
        Paint()
          ..color = line
          ..strokeWidth = 1,
      );
      label((maxValue * i / 2).toStringAsFixed(2), Offset(0, y - fontSize / 2));
    }
    void series(List<num> data, Color color, bool dashed) {
      for (var i = 1; i < data.length; i++) {
        final a = Offset(
          left + width * (i - 1) / (data.length - 1),
          top + height * (1 - data[i - 1] / maxValue),
        );
        final b = Offset(
          left + width * i / (data.length - 1),
          top + height * (1 - data[i] / maxValue),
        );
        final pen = Paint()
          ..color = color
          ..strokeWidth = dashed ? 1.8 : 2.8
          ..strokeCap = StrokeCap.round;
        if (!dashed) {
          canvas.drawLine(a, b, pen);
        } else {
          final length = (b - a).distance;
          for (double d = 0; d < length; d += 10) {
            canvas.drawLine(
              Offset.lerp(a, b, d / length)!,
              Offset.lerp(a, b, math.min(d + 5, length) / length)!,
              pen,
            );
          }
        }
      }
    }

    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        left - 2,
        top - 2,
        left + (width + 2) * progress,
        top + height + 2,
      ),
    );
    series(other, muted, true);
    series(you, accent, false);
    canvas.restore();
    label('Start', Offset(left, top + height + 10));
    label('Q${you.length - 1}', Offset(left + width - 26, top + height + 10));
  }

  @override
  bool shouldRepaint(_ScorePainter old) =>
      old.you != you ||
      old.other != other ||
      old.accent != accent ||
      old.muted != muted ||
      old.line != line ||
      old.fontSize != fontSize ||
      old.progress != progress;
}
