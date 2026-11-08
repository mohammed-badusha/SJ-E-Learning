import 'trophy.dart';
import 'arena_motion.dart';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../features/profile/domain/rank_tier.dart';

extension TierAppearance on RankTier {
  Color get color => switch (this) {
    RankTier.bronze => const Color(0xFF9B5C32),
    RankTier.silver => const Color(0xFF607086),
    RankTier.gold => const Color(0xFF9A690D),
    RankTier.platinum => const Color(0xFF20747D),
    RankTier.diamond => const Color(0xFF5B4CFF),
  };
  IconData get icon => switch (this) {
    RankTier.bronze || RankTier.silver => Icons.emoji_events_outlined,
    RankTier.gold => Icons.emoji_events_rounded,
    RankTier.platinum => Icons.workspace_premium_rounded,
    RankTier.diamond => Icons.diamond_rounded,
  };
}

class TierBadge extends StatelessWidget {
  const TierBadge({
    super.key,
    required this.rating,
    this.size = 44,
    this.showLabel = false,
  });
  final int rating;
  final double size;
  final bool showLabel;
  @override
  Widget build(BuildContext context) {
    final tier = RankTier.forRating(rating);
    final badge = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tier.color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(size * .28),
        border: Border.all(color: tier.color.withValues(alpha: .22)),
      ),
      child: tier.index <= RankTier.gold.index
          ? Trophy(
              size: size * .72,
              metal: switch (tier) {
                RankTier.bronze => const Color(0xffdd986b),
                RankTier.silver => const Color(0xffacbdcc),
                _ => const Color(0xffffbf49),
              },
            )
          : Icon(tier.icon, size: size * .56, color: tier.color),
    );
    return Semantics(
      label: '${tier.label} rank tier',
      image: true,
      child: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                badge,
                const SizedBox(width: 8),
                Text(tier.label, style: context.type.titleSmall),
              ],
            )
          : badge,
    );
  }
}

class TierProgress extends StatelessWidget {
  const TierProgress({super.key, required this.rating});
  final int rating;
  @override
  Widget build(BuildContext context) {
    final tier = RankTier.forRating(rating);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TierBadge(rating: rating, size: 48),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tier.label} tier', style: context.type.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    tier.next == null
                        ? 'Highest tier reached'
                        : '${tier.pointsToNext(rating)} rating to ${tier.next!.label}',
                    style: TextStyle(
                      color: context.tokens.secondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            CountMetric(rating, style: context.type.headlineSmall),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: tier.progress(rating),
            color: tier.color,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final step in RankTier.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    step.icon,
                    size: 16,
                    color: rating >= step.floor
                        ? step.color
                        : context.tokens.muted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: rating >= step.floor
                          ? context.tokens.ink
                          : context.tokens.muted,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class StreakFlame extends StatelessWidget {
  const StreakFlame({
    super.key,
    required this.days,
    this.size = 24,
    this.showCount = true,
  });
  final int days;
  final double size;
  final bool showCount;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$days day streak',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          days > 0
              ? Icons.local_fire_department_rounded
              : Icons.local_fire_department_outlined,
          size: size,
          color: days > 0 ? const Color(0xFFC65B19) : context.tokens.muted,
        ),
        if (showCount) ...[
          const SizedBox(width: 8),
          Text('$days day streak', style: context.type.titleSmall),
        ],
      ],
    ),
  );
}
