import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';
import '../../results/presentation/battle_result_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<HistoryScreen> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final session = ref.read(sessionProvider);
    future = session.preview
        ? Future.value({'matches': []})
        : QuizRepository(session).rpc('get_my_history');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final cached = Hive.isBoxOpen('review')
        ? Hive.box('review')
              .toMap()
              .entries
              .where(
                (e) => e.key.toString().startsWith('${session.profile!.id}:'),
              )
              .map((e) => Map<String, dynamic>.from(e.value))
              .toList()
              .reversed
              .toList()
        : <Map<String, dynamic>>[];
    return Scaffold(
      appBar: ArenaBar(title: const Text('Match history')),
      body: PageBody(
        maxWidth: 800,
        child: FutureBuilder(
          future: future,
          builder: (context, snapshot) {
            final matches = snapshot.data?['matches'] as List? ?? [];
            if (!snapshot.hasData && cached.isEmpty) {
              if (snapshot.hasError) {
                return EmptyState(
                  title: 'History couldn’t load',
                  message: 'Please reconnect and retry.',
                  action: OutlinedButton(
                    onPressed: () => setState(load),
                    child: const Text('Retry'),
                  ),
                );
              }
              return const SkeletonList();
            }
            if (matches.isEmpty && cached.isEmpty) {
              return EmptyState(
                title: 'Your story starts with a round',
                message:
                    'Your completed battles and saved practice reviews will appear here.',
                action: OutlinedButton(
                  onPressed: () => context.push('/categories?mode=practice'),
                  child: const Text('Try a practice round'),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (matches.isNotEmpty) ...[
                  Text('Battles', style: context.type.titleLarge),
                  const SizedBox(height: 16),
                ],
                ...matches.map(
                  (m) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    leading: Icon(
                      m['result'] == 'win'
                          ? Icons.emoji_events_rounded
                          : Icons.bolt_rounded,
                      color: ArenaTokens.violet,
                    ),
                    title: Text('You vs ${m['opponent']}'),
                    subtitle: Text('${m['result']} · ${m['score']} points'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      try {
                        final review = await QuizRepository(
                          session,
                        ).rpc('get_match_review', {'match_id': m['id']});
                        if (context.mounted) {
                          if (review['players'] is List) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => BattleResultScreen(
                                  matchId: m['id'],
                                  initialState: {
                                    ...review,
                                    'status': 'completed',
                                  },
                                  viewerId: session.profile!.id,
                                  reportLoader: () async => review,
                                ),
                              ),
                            );
                          } else {
                            context.push(
                              '/review',
                              extra: (review['questions'] as List)
                                  .map((q) => Map<String, dynamic>.from(q))
                                  .toList(),
                            );
                          }
                        }
                      } catch (_) {
                        if (context.mounted) {
                          showMessage(
                            context,
                            'Couldn’t load this review. Please retry.',
                          );
                        }
                      }
                    },
                  ),
                ),
                if (cached.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Saved reviews', style: context.type.titleLarge),
                  const SizedBox(height: 12),
                ],
                ...cached.map(
                  (r) => ListTile(
                    leading: const Icon(Icons.fact_check_rounded),
                    title: Text(
                      '${r['mode'] == 'daily' ? 'Daily Challenge' : 'Practice'} · ${r['score']} points',
                    ),
                    subtitle: Text(
                      '${r['correct']}/${r['count']} correct${r['preview'] == true ? ' · local preview' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(
                      '/review',
                      extra: (r['questions'] as List)
                          .map((q) => Map<String, dynamic>.from(q))
                          .toList(),
                    ),
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
