import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/rewards.dart';
import '../../auth/data/session.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile!;
    final today = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    return Scaffold(
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const SJMark(size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SJ E-Learning', style: context.type.titleMedium),
                      Text(
                        'Competitive exam practice',
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Settings',
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your practice', style: context.type.headlineMedium),
                      const SizedBox(height: 8),
                      Text(
                        '${DateFormat('EEE, d MMM').format(today)} · ${profile.firstName}',
                        style: TextStyle(
                          color: context.tokens.secondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                AvatarBadge(name: profile.fullName, size: 44),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.tokens.line),
                  bottom: BorderSide(color: context.tokens.line),
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: StreakFlame(days: profile.currentStreak)),
                  Text(
                    profile.currentStreak == 0
                        ? 'Start with today’s challenge'
                        : 'Daily challenge streak',
                    style: context.type.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final battle = _BattleCard(
                  onTap: () => context.push('/categories?mode=battle'),
                );
                final daily = _DailyCard(
                  today: today,
                  onTap: () => context.push('/daily'),
                );
                if (constraints.maxWidth > 760) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: battle),
                      const SizedBox(width: 24),
                      Expanded(flex: 2, child: daily),
                    ],
                  );
                }
                return Column(
                  children: [battle, const SizedBox(height: 16), daily],
                );
              },
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: Text('Your progress', style: context.type.titleLarge),
                ),
                TextButton(
                  onPressed: () => context.go('/profile'),
                  child: const Text('View profile'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ArenaCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Rating',
                        value: '${profile.rating}',
                      ),
                    ),
                    VerticalDivider(width: 24, color: context.tokens.line),
                    Expanded(
                      child: _Metric(
                        label: 'Rank tier',
                        value: profile.tier,
                        rating: profile.rating,
                      ),
                    ),
                    VerticalDivider(width: 24, color: context.tokens.line),
                    Expanded(
                      child: _Metric(label: 'Level', value: '${profile.level}'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text('More ways to prepare', style: context.type.titleLarge),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: context.tokens.card,
                border: Border.all(color: context.tokens.line),
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _Shortcut(
                    icon: Icons.edit_note_rounded,
                    title: 'Solo practice',
                    subtitle: 'Choose a subject and review explanations',
                    onTap: () => context.push('/categories?mode=practice'),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Divider(color: context.tokens.line),
                  ),
                  _Shortcut(
                    icon: Icons.leaderboard_outlined,
                    title: 'Leaderboard',
                    subtitle: 'Weekly, all-time and daily rankings',
                    onTap: () => context.go('/leaderboard'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Bank · SSC · PSC · Railway · Placements',
              textAlign: TextAlign.center,
              style: context.type.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _BattleCard extends StatelessWidget {
  const _BattleCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ArenaCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text('1v1 quiz battle', style: context.type.headlineSmall),
            ),
            const _AnswerMarks(),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Choose a subject. Race a learner or a practice opponent.',
          style: TextStyle(
            color: context.tokens.secondary,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(Icons.timer_outlined, size: 16, color: context.tokens.muted),
            const SizedBox(width: 8),
            Text('Timed MCQs', style: context.type.bodySmall),
            const SizedBox(width: 20),
            Icon(
              Icons.swap_horiz_rounded,
              size: 16,
              color: context.tokens.muted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Live scoring', style: context.type.bodySmall),
            ),
          ],
        ),
        const SizedBox(height: 20),
        PrimaryButton(label: 'Play 1v1', onPressed: onTap),
      ],
    ),
  );
}

class _AnswerMarks extends StatelessWidget {
  const _AnswerMarks();
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final letter in ['A', 'B', 'C', 'D'])
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              width: 16,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.tokens.line)),
              ),
              child: Text(letter, style: context.type.bodySmall),
            ),
          ),
      ],
    ),
  );
}

class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.today, required this.onTap});
  final DateTime today;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.tokens.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: context.tokens.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: context.tokens.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMM').format(today),
                    style: context.type.bodySmall,
                  ),
                  Text('${today.day}', style: context.type.titleLarge),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily challenge', style: context.type.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'One attempt per day',
                    style: TextStyle(
                      color: context.tokens.secondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: context.tokens.muted,
              size: 20,
            ),
          ],
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.rating});
  final int? rating;
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          if (rating != null) ...[
            TierBadge(rating: rating!, size: 24),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label, style: context.type.bodySmall)),
        ],
      ),
      const SizedBox(height: 8),
      Text(value, style: context.type.headlineSmall?.copyWith(fontSize: 24)),
    ],
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.tokens.secondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.type.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.tokens.secondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.tokens.muted,
            ),
          ],
        ),
      ),
    ),
  );
}
