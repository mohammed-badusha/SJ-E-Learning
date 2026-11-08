import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/rewards.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardState();
}

class _LeaderboardState extends ConsumerState<LeaderboardScreen> {
  String type = 'weekly';
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
            'rows': [
              {
                'full_name': 'Ananya Nair',
                'metric': 1840,
                'rating': 1840,
                'rank': 1,
                'id': 'one',
              },
              {
                'full_name': 'Arjun Menon',
                'metric': 1760,
                'rating': 1760,
                'rank': 2,
                'id': 'two',
              },
              {
                'full_name': 'Meera Iyer',
                'metric': 1680,
                'rating': 1680,
                'rank': 3,
                'id': 'three',
              },
              {
                'full_name': 'Alex Learner',
                'metric': 1240,
                'rating': 1240,
                'rank': 4,
                'id': 'preview',
              },
            ],
          })
        : QuizRepository(session).rpc('get_leaderboard', {'type': type});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Leaderboard')),
    body: PageBody(
      maxWidth: 800,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 8,
              children: [
                for (final item in [
                  ('weekly', 'This week'),
                  ('all_time', 'All time'),
                  ('daily', 'Daily'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: type == item.$1,
                    onSelected: (_) => setState(() {
                      type = item.$1;
                      load();
                    }),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(
                    title: 'Leaderboard couldn’t load',
                    message: 'Check your connection and try again.',
                    action: OutlinedButton(
                      onPressed: () => setState(load),
                      child: const Text('Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData) return const SkeletonList();
                final rows = snapshot.data!['rows'] as List;
                if (rows.isEmpty) {
                  return const EmptyState(
                    title: 'The first spot is waiting',
                    message:
                        'Play a battle or complete today’s challenge to make your mark.',
                    icon: Icons.emoji_events_rounded,
                  );
                }
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    if (ref.read(sessionProvider).preview)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Sample leaderboard · preview data'),
                      ),
                    ...rows.map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ArenaCard(
                          color:
                              r['id'] == ref.read(sessionProvider).profile!.id
                              ? ArenaTokens.violet.withValues(alpha: .1)
                              : null,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                child: r['rank'] == 1
                                    ? Icon(
                                        Icons.emoji_events_rounded,
                                        color: context.tokens.warning,
                                      )
                                    : Text(
                                        '#${r['rank']}',
                                        style: context.type.titleMedium,
                                      ),
                              ),
                              if (r['rating'] != null)
                                TierBadge(rating: r['rating'], size: 36)
                              else
                                AvatarBadge(name: r['full_name'], size: 36),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  r['full_name'],
                                  style: context.type.titleMedium,
                                ),
                              ),
                              Text(
                                '${r['metric']}',
                                style: context.type.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
