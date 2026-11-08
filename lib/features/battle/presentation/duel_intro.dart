import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/arena_panel.dart';
import '../../../shared/player_avatar.dart';
import '../../../core/theme.dart';

class DuelIntro extends StatelessWidget {
  const DuelIntro({
    super.key,
    required this.name,
    required this.rival,
    required this.ownPortrait,
    required this.rivalPortrait,
    required this.matchId,
    required this.ownRank,
    required this.rivalRank,
    required this.bot,
    required this.onLeave,
  });
  final String name, rival, matchId, ownRank, rivalRank;
  final String? ownPortrait, rivalPortrait;
  final bool bot;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: arenaInk,
        body: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight;
            final compact = box.maxHeight < 550;
            Widget contender(bool mine) {
              final accent = mine ? arenaLilac : arenaMint;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ArenaPortrait(
                    accent: accent,
                    child: !mine && rival.isEmpty
                        ? CircleAvatar(
                            radius: compact ? 26 : 41,
                            child: const Icon(Icons.person_outline_rounded),
                          )
                        : PlayerAvatar(
                            name: mine ? name : rival,
                            reference: mine ? ownPortrait : rivalPortrait,
                            matchId: mine ? null : matchId,
                            size: compact ? 52 : 82,
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mine
                        ? 'You'
                        : bot
                        ? 'Practice opponent'
                        : 'Opponent',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    mine
                        ? name
                        : rival.isEmpty
                        ? 'Connecting…'
                        : rival,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.headlineSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    mine ? ownRank : rivalRank,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              );
            }

            Widget enter(Widget child, bool mine) =>
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduced ? 1.0 : 0.0, end: 1),
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 640),
                  curve: ArenaTokens.ease,
                  child: child,
                  builder: (_, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(
                        (mine ? -1 : 1) * (1 - t) * 72,
                        (mine ? -1 : 1) * (1 - t) * 12,
                      ),
                      child: child,
                    ),
                  ),
                );
            final seal = TweenAnimationBuilder<double>(
              tween: Tween(begin: reduced ? 1.0 : .70, end: 1),
              duration: reduced
                  ? Duration.zero
                  : const Duration(milliseconds: 480),
              curve: Curves.easeOutBack,
              child: Transform.rotate(
                angle: -.10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffffdc87),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'VS',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: arenaInk,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                    ),
                  ),
                ),
              ),
              builder: (_, t, c) => Transform.scale(scale: t, child: c),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduced ? 1.0 : 0.0, end: 1),
                  duration: reduced
                      ? Duration.zero
                      : const Duration(milliseconds: 950),
                  builder: (_, progress, _) =>
                      CustomPaint(painter: _DuelField(wide, progress)),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: onLeave,
                            tooltip: 'Leave match',
                            color: Colors.white,
                            icon: const Icon(Icons.close_rounded),
                          ),
                          const Expanded(
                            child: Text(
                              'Match found',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, space) {
                            final left = enter(contender(true), true),
                                right = enter(contender(false), false);
                            if (wide) {
                              return Center(
                                child: SingleChildScrollView(
                                  child: Row(
                                    children: [
                                      Expanded(child: left),
                                      seal,
                                      Expanded(child: right),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: space.maxHeight,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      left,
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: seal,
                                      ),
                                      right,
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DuelField extends CustomPainter {
  const _DuelField(this.wide, this.progress);
  final double progress;
  final bool wide;
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final split = wide
        ? (Path()
            ..moveTo(w * .61, 0)
            ..lineTo(w * .39, h))
        : (Path()
            ..moveTo(0, h * .61)
            ..lineTo(w, h * .43));
    final field = Path.from(split)..lineTo(w, h);
    if (wide) {
      field.lineTo(w, 0);
    } else {
      field.lineTo(0, h);
    }
    c.drawRect(
      Offset.zero & s,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff49418c), arenaInk],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & s),
    );
    c.drawPath(field..close(), Paint()..color = const Color(0xff10454c));
    final rings = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x207ec8c2)
      ..strokeWidth = 1.5;
    for (var i = 1; i <= 4; i++) {
      c.drawCircle(Offset(w, h), math.min(w, h) * (.25 + i * .16), rings);
      c.drawCircle(Offset.zero, math.min(w, h) * (.20 + i * .13), rings);
    }
    c.drawPath(
      split,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = arenaMint,
    );
    if (progress < 1) {
      final first = wide ? Offset(w * .61, 0) : Offset(0, h * .61);
      final last = wide ? Offset(w * .39, h) : Offset(w, h * .43);
      final lead = Offset.lerp(first, last, progress * 1.4)!;
      final tail = Offset.lerp(first, last, progress * 1.4 - .35)!;
      c.drawLine(
        tail,
        lead,
        Paint()
          ..strokeWidth = 4
          ..shader = LinearGradient(
            colors: const [Colors.transparent, Colors.white],
          ).createShader(Rect.fromPoints(tail, lead)),
      );
    }
  }

  @override
  bool shouldRepaint(_DuelField old) =>
      wide != old.wide || progress != old.progress;
}
