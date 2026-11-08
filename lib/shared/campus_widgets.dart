import 'trophy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme.dart';
import 'widgets.dart';

class CampusHeader extends StatelessWidget {
  const CampusHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });
  final String title, subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [ArenaTokens.navy, Color(0xFF45388D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 28),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const SJMark(size: 42),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: context.type.titleLarge?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFFD7E2FF),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null)
                    IconTheme(
                      data: const IconThemeData(color: Colors.white),
                      child: trailing!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: context.type.titleLarge)),
      if (action != null)
        onAction == null
            ? Text(action!, style: context.type.bodySmall)
            : TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class FocusTile extends StatelessWidget {
  const FocusTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: context.tokens.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).brightness == Brightness.dark
                    ? context.tokens.ink
                    : color,
                size: 25,
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: context.type.titleSmall),
            const SizedBox(height: 5),
            Text(subtitle, style: context.type.bodySmall),
          ],
        ),
      ),
    ),
  );
}

class RankMedal extends StatelessWidget {
  const RankMedal({super.key, required this.rank, this.size = 44});
  final int rank;
  final double size;
  @override
  Widget build(BuildContext context) {
    final color = rank == 1
        ? ArenaTokens.gold
        : rank == 2
        ? ArenaTokens.silver
        : ArenaTokens.bronze;
    return Semantics(
      label: 'Rank $rank',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size * 1.15,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _MedalRibbonPainter()),
              ),
              Container(
                width: size * .76,
                height: size * .76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .7),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ArenaTokens.navy.withValues(alpha: .12),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Text(
                  '$rank',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: size * .35,
                    color: ArenaTokens.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedalRibbonPainter extends CustomPainter {
  const _MedalRibbonPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final left = Path()
      ..moveTo(size.width * .12, 0)
      ..lineTo(size.width * .43, 0)
      ..lineTo(size.width * .69, size.height * .47)
      ..lineTo(size.width * .39, size.height * .47)
      ..close();
    final right = Path()
      ..moveTo(size.width * .57, 0)
      ..lineTo(size.width * .88, 0)
      ..lineTo(size.width * .61, size.height * .47)
      ..lineTo(size.width * .31, size.height * .47)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xFF69B7E6));
    canvas.drawPath(right, Paint()..color = const Color(0xFF2581BA));
  }

  @override
  bool shouldRepaint(covariant _MedalRibbonPainter oldDelegate) => false;
}

class BattleArtwork extends StatelessWidget {
  const BattleArtwork({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 110,
      height: 122,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: -.16,
            child: Container(
              width: 88,
              height: 102,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: .15)),
              ),
            ),
          ),
          Transform.rotate(
            angle: .12,
            child: Container(
              width: 76,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF887BEE),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Trophy(size: 58),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: ArenaTokens.gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: ArenaTokens.navy,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
