import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/widgets.dart';
import '../../../shared/player_avatar.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';
import '../../results/presentation/battle_result_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<HistoryScreen> {
  final rows = <Map<String, dynamic>>[];
  bool loading = false, more = true;
  int generation = 0;
  String? error;
  late final SessionController session;
  @override
  void initState() {
    super.initState();
    session = ref.read(sessionProvider);
    session.dataChanges.addListener(changed);
    load(reset: true);
  }

  void changed() {
    if (mounted) load(reset: true);
  }

  @override
  void dispose() {
    session.dataChanges.removeListener(changed);
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (!reset && (loading || !more)) return;
    final request = ++generation;
    final cursor = reset || rows.isEmpty ? null : rows.last;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = session.preview
          ? {'rows': []}
          : await QuizRepository(session).rpc('get_history_page', {
              'before_at': cursor?['played_at'],
              'before_id': cursor?['id'],
            });
      if (!mounted || request != generation) return;
      final page = (data['rows'] as List).cast<Map<String, dynamic>>();
      setState(() {
        if (reset) rows.clear();
        rows.addAll(page);
        more = page.length == 30;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = 'History couldn’t load. Reconnect and retry.');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> review(Map<String, dynamic> row) async {
    try {
      final battle = row['mode'] == 'battle';
      final data = await QuizRepository(session).rpc(
        battle
            ? 'get_match_review'
            : row['mode'] == 'daily'
            ? 'get_daily_review'
            : 'get_practice_review',
        {battle ? 'match_id' : 'attempt_id': row['id']},
      );
      if (!mounted) return;
      if (battle) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BattleResultScreen(
              matchId: row['id'],
              initialState: {...data, 'status': 'completed'},
              viewerId: session.profile!.id,
              reportLoader: () async => data,
            ),
          ),
        );
      } else {
        context.push(
          '/review',
          extra: (data['questions'] as List)
              .map((q) => Map<String, dynamic>.from(q))
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Couldn’t load this review. Please retry.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ArenaBar(title: const Text('History')),
    body: PageBody(
      maxWidth: 800,
      child: rows.isEmpty && loading
          ? const SkeletonList()
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (error != null) ...[
                  Text(error!),
                  TextButton(
                    onPressed: () => load(reset: true),
                    child: const Text('Retry'),
                  ),
                ],
                if (rows.isEmpty && !loading && error == null)
                  EmptyState(
                    title: 'Your story starts with a round',
                    message:
                        'Your battles, daily challenges and practice reviews will appear here.',
                    action: OutlinedButton(
                      onPressed: () =>
                          context.push('/categories?mode=practice'),
                      child: const Text('Try practice'),
                    ),
                  ),
                ...rows.map(
                  (row) => ListTile(
                    leading: row['mode'] == 'battle'
                        ? PlayerAvatar(
                            name: row['title'] as String? ?? 'Opponent',
                            reference: row['avatar_url'] as String?,
                            size: 40,
                          )
                        : const Icon(Icons.fact_check_outlined),
                    title: Text(
                      row['mode'] == 'battle'
                          ? 'You vs ${row['title']}'
                          : row['title'],
                    ),
                    subtitle: Text(
                      '${row['score']} marks · ${row['played_at'].toString().substring(0, 10)}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => review(row),
                  ),
                ),
                if (rows.isNotEmpty && more)
                  TextButton(
                    onPressed: loading ? null : () => load(),
                    child: Text(loading ? 'Loading…' : 'Load more'),
                  ),
              ],
            ),
    ),
  );
}
