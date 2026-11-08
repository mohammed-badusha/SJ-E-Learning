import '../../../shared/player_avatar.dart';
import '../../../shared/arena_panel.dart';
import '../../../shared/arena_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/rewards.dart';
import '../../../shared/campus_widgets.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<ProfileScreen> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final session = ref.read(sessionProvider);
    future = session.preview
        ? Future.value({
            'matches': 12,
            'wins': 8,
            'categories': [
              {'name': 'Quantitative Aptitude', 'played': 20, 'correct': 16},
              {'name': 'English', 'played': 15, 'correct': 10},
              {'name': 'Reasoning', 'played': 18, 'correct': 14},
              {'name': 'General Awareness', 'played': 12, 'correct': 7},
            ],
            'badges': [],
          })
        : QuizRepository(session).rpc('get_my_stats');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider), profile = session.profile!;
    return Scaffold(
      appBar: ArenaBar(
        title: const Text('Your progress'),
        actions: [
          IconButton(
            tooltip: 'Battle history',
            onPressed: () => context.go('/history'),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ArenaPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ArenaPortrait(
                        accent: arenaLilac,
                        child: PlayerAvatar(
                          name: profile.fullName,
                          reference: profile.avatarUrl,
                          size: 70,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Player profile',
                              style: context.type.bodySmall?.copyWith(
                                color: arenaMint,
                              ),
                            ),
                            Text(
                              profile.fullName,
                              style: context.type.titleLarge?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${profile.tier} · ${profile.rating} rating',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      if (!session.preview)
                        IconButton(
                          tooltip: 'Edit player profile',
                          color: Colors.white,
                          onPressed: () => context.push('/edit-profile'),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Level ${profile.level}',
                        style: context.type.titleSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${profile.xp % 100}/100 XP',
                        style: const TextStyle(color: arenaMint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (profile.xp % 100) / 100,
                    color: arenaMint,
                    backgroundColor: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ArenaCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StreakFlame(days: profile.currentStreak),
                  Text(
                    'Personal best · ${profile.bestStreak} days',
                    style: context.type.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionHeading(title: 'Battle record'),
            const SizedBox(height: 12),
            if (session.preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Sample progress · local preview',
                  style: context.type.bodySmall,
                ),
              ),
            FutureBuilder(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    title: 'Your stats couldn’t load',
                    message: 'Reconnect to see your latest progress.',
                    action: OutlinedButton(
                      onPressed: () => setState(load),
                      child: const Text('Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const ArenaSkeleton(layout: SkeletonLayout.profile);
                }
                final stats = snapshot.data!,
                    matches = (stats['matches'] as num).toInt(),
                    wins = (stats['wins'] as num).toInt();
                final categories = stats['categories'] as List;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ArenaCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: _Metric(value: '$matches', label: 'Battles'),
                          ),
                          Expanded(
                            child: _Metric(value: '$wins', label: 'Wins'),
                          ),
                          Expanded(
                            child: _Metric(
                              value: matches == 0
                                  ? '—'
                                  : '${(100 * wins / matches).round()}%',
                              label: 'Win rate',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    const SectionHeading(title: 'Your subject strengths'),
                    const SizedBox(height: 14),
                    ArenaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (categories.isEmpty)
                            const Text(
                              'Complete a round to start discovering your strengths.',
                            ),
                          for (final entry in categories)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry['name'],
                                          style: context.type.titleSmall,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '${entry['correct']}/${entry['played']}',
                                        style: context.type.bodySmall,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: (entry['played'] as num) == 0
                                          ? 0
                                          : (entry['correct'] as num) /
                                                (entry['played'] as num),
                                      color: ArenaTokens.teal,
                                      minHeight: 7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if ((stats['badges'] as List).isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const SectionHeading(title: 'Earned along the way'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final badge in stats['badges'])
                            Chip(
                              avatar: Icon(
                                Icons.workspace_premium_rounded,
                                color: context.tokens.warning,
                              ),
                              label: Text(badge['name']),
                            ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            ArenaCard(child: TierProgress(rating: profile.rating)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.go('/history'),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Revisit your battles'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (int.tryParse(value.replaceAll('%', '')) case final int n)
        CountMetric(
          n,
          format: (x) => value.endsWith('%') ? '$x%' : '$x',
          style: context.type.headlineSmall,
        )
      else
        Text(value, style: context.type.headlineSmall),
      const SizedBox(height: 4),
      Text(label, textAlign: TextAlign.center, style: context.type.bodySmall),
    ],
  );
}
