import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/rewards.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final profile = session.profile!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 800,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Center(child: AvatarBadge(name: profile.fullName, size: 88)),
            const SizedBox(height: 16),
            Text(
              profile.fullName,
              textAlign: TextAlign.center,
              style: context.type.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${profile.tier} · Level ${profile.level}',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tokens.muted),
            ),
            const SizedBox(height: 24),
            ArenaCard(child: TierProgress(rating: profile.rating)),
            const SizedBox(height: 20),
            Center(child: StreakFlame(days: profile.currentStreak, size: 32)),
            const SizedBox(height: 24),
            ArenaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Progress to level ${profile.level + 1}',
                        style: context.type.titleMedium,
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (profile.xp % 100) / 100,
                      minHeight: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${profile.xp % 100}/100 XP to the next level',
                    style: TextStyle(color: context.tokens.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ArenaCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _metric(context, '${profile.rating}', 'Rating'),
                  _metric(context, '${profile.currentStreak}', 'Day streak'),
                  _metric(context, '${profile.bestStreak}', 'Best streak'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('Category accuracy', style: context.type.titleLarge),
            const SizedBox(height: 16),
            if (session.preview)
              const ArenaCard(
                child: Text(
                  'Explore a practice round to start a saved answer review. Your preview progress stays on this device.',
                ),
              )
            else
              FutureBuilder(
                future: QuizRepository(session).rpc('get_my_stats'),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'Your stats couldn’t load. Pull up this page again when connected.',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const ArenaCard(
                      child: Text('Loading your progress…'),
                    );
                  }
                  final data = snapshot.data!;
                  return Column(
                    children: [
                      ArenaCard(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _metric(context, '${data['matches']}', 'Matches'),
                            _metric(context, '${data['wins']}', 'Wins'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...(data['categories'] as List).map(
                        (c) => ListTile(
                          title: Text(c['name']),
                          subtitle: LinearProgressIndicator(
                            value: (c['played'] as num) == 0
                                ? 0
                                : (c['correct'] as num) / (c['played'] as num),
                          ),
                          trailing: Text('${c['correct']}/${c['played']}'),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          ...(data['badges'] as List).map(
                            (b) => Chip(
                              avatar: Icon(
                                Icons.workspace_premium_rounded,
                                color: context.tokens.warning,
                              ),
                              label: Text(b['name']),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String value, String label) => Column(
    children: [
      Text(value, style: context.type.headlineMedium),
      Text(label, style: TextStyle(color: context.tokens.muted, fontSize: 12)),
    ],
  );
}
