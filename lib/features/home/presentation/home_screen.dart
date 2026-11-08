import 'package:flutter/material.dart';
import 'course_carousel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../shared/arena_motion.dart';
import '../../../shared/arena_panel.dart';
import '../../../shared/player_avatar.dart';
import '../../../shared/widgets.dart';
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
        maxWidth: 840,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Row(
              children: [
                const SJMark(size: 34),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('SJ E-Learning', style: context.type.titleMedium),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const CourseCarousel(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE, d MMMM').format(today),
                        style: context.type.bodySmall,
                      ),
                      Text(
                        'Hello, ${profile.firstName}',
                        style: context.type.headlineMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Open your profile',
                  onPressed: () => context.go('/profile'),
                  icon: PlayerAvatar(
                    name: profile.fullName,
                    reference: profile.avatarUrl,
                    size: 46,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ArenaPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quiz arena',
                              style: context.type.titleSmall?.copyWith(
                                color: arenaMint,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '1v1 Battle',
                              style: context.type.headlineLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                height: 1.02,
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Pick a subject and face an opponent.',
                              style: TextStyle(
                                color: Color(0xffe0e2f4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Image.asset(
                          'assets/arena/duel.webp',
                          height: 125,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => context.push('/categories?mode=battle'),
                    style: FilledButton.styleFrom(
                      backgroundColor: arenaMint,
                      foregroundColor: arenaInk,
                    ),
                    icon: const Icon(Icons.bolt_rounded),
                    label: const Text('Play 1v1'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ArenaCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LobbyStat(
                    icon: Icons.emoji_events_rounded,
                    label: profile.tier,
                    number: profile.rating,
                    color: context.tokens.warning,
                  ),
                  _LobbyStat(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Day streak',
                    number: profile.currentStreak,
                    color: context.tokens.warning,
                  ),
                  _LobbyStat(
                    icon: Icons.bolt_rounded,
                    label: 'Level',
                    number: profile.level,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Your practice', style: context.type.titleLarge),
            const SizedBox(height: 10),
            ArenaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _Destination(
                    icon: Icons.calendar_today_rounded,
                    title: 'Daily challenge',
                    detail: 'Today’s shared quiz',
                    color: ArenaTokens.teal,
                    onTap: () => context.push('/daily'),
                  ),
                  const Divider(indent: 70),
                  _Destination(
                    icon: Icons.menu_book_rounded,
                    title: 'Subject practice',
                    detail: 'Choose a topic and pace',
                    color: ArenaTokens.blue,
                    onTap: () => context.push('/categories?mode=practice'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Your arena', style: context.type.titleLarge),
            const SizedBox(height: 10),
            ArenaCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _Destination(
                    icon: Icons.leaderboard_outlined,
                    title: 'Leaderboard',
                    color: ArenaTokens.blue,
                    onTap: () => context.go('/leaderboard'),
                  ),
                  const Divider(indent: 70),
                  _Destination(
                    icon: Icons.insights_rounded,
                    title: 'Your progress',
                    detail:
                        '${profile.xp % 100}/100 XP to level ${profile.level + 1}',
                    color: ArenaTokens.teal,
                    onTap: () => context.go('/profile'),
                  ),
                  const Divider(indent: 70),
                  _Destination(
                    icon: Icons.history_rounded,
                    title: 'Battle history',
                    color: ArenaTokens.coral,
                    onTap: () => context.go('/history'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LobbyStat extends StatelessWidget {
  const _LobbyStat({
    required this.icon,
    required this.label,
    required this.number,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int number;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(height: 4),
        CountMetric(number, style: context.type.titleLarge),
        Text(label, textAlign: TextAlign.center, style: context.type.bodySmall),
      ],
    ),
  );
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.icon,
    required this.title,
    this.detail,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? detail;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: Theme.of(context).brightness == Brightness.dark
            ? context.tokens.ink
            : color,
        size: 21,
      ),
    ),
    title: Text(title),
    subtitle: detail == null ? null : Text(detail!),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: onTap,
  );
}
