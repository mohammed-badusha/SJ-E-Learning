import 'package:flutter/material.dart';

import '../core/theme.dart';

const arenaEase = ArenaTokens.ease;
Duration motionTime(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Animate the painted child without rebuilding it for each frame.
class Arrive extends StatelessWidget {
  const Arrive({
    super.key,
    required this.child,
    this.from = const Offset(0, 12),
    this.duration = 240,
  });
  final Widget child;
  final Offset from;
  final int duration;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: duration),
      curve: arenaEase,
      child: child,
      builder: (_, progress, child) => Transform.translate(
        offset: from * (1 - progress),
        child: Opacity(opacity: progress, child: child),
      ),
    );
  }
}

class CountMetric extends StatelessWidget {
  const CountMetric(this.value, {super.key, this.style, this.format});
  final num value;
  final TextStyle? style;
  final String Function(int)? format;
  @override
  Widget build(BuildContext context) {
    String label(num n) =>
        format?.call(n.round()) ??
        (value is int ? '${n.round()}' : n.toStringAsFixed(2));
    Widget display(num n) => Text(
      label(n),
      style: style?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return display(value);
    return Semantics(
      label: label(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 280),
        curve: arenaEase,
        tween: Tween(begin: 0, end: value.toDouble()),
        builder: (_, n, _) => display(n),
      ),
    );
  }
}
