import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class DailyScreen extends ConsumerStatefulWidget {
  const DailyScreen({super.key});
  @override
  ConsumerState<DailyScreen> createState() => _DailyState();
}

class _DailyState extends ConsumerState<DailyScreen> {
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
            'title': 'Daily challenge',
            'question_count': 5,
            'completed': false,
            'started': false,
          })
        : QuizRepository(session).rpc('get_today_challenge');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ArenaBar(title: const Text('Daily Challenge')),
    body: PageBody(
      maxWidth: 600,
      child: FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              title: 'Today’s challenge couldn’t load',
              message: 'Check your connection and try again.',
              action: OutlinedButton(
                onPressed: () => setState(load),
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const SkeletonList(layout: SkeletonLayout.quiz);
          }
          final d = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: ArenaTokens.navy,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.today_rounded,
                      color: ArenaTokens.gold,
                      size: 40,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      d['title'],
                      style: context.type.headlineSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Everyone gets the same questions. Each answer takes you straight to the next one.',
                      style: TextStyle(
                        color: Color(0xFFD7E2FF),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ArenaCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.quiz_rounded),
                      title: Text('${d['question_count']} questions'),
                      subtitle: const Text('Across all four categories'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.schedule_rounded),
                      title: Text('One attempt each day'),
                      subtitle: Text('Resets at midnight IST'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              PrimaryButton(
                label: d['completed'] == true
                    ? 'Challenge complete · ${d['score']} points'
                    : d['started'] == true
                    ? 'Resume my challenge'
                    : 'Start challenge',
                onPressed: d['completed'] == true
                    ? null
                    : () => context.push('/quiz?mode=daily'),
              ),
              const SizedBox(height: 16),
              Text(
                'Once started, timers keep running even if you close the app.',
                style: TextStyle(color: context.tokens.muted, fontSize: 12),
                textAlign: TextAlign.start,
              ),
            ],
          );
        },
      ),
    ),
  );
}
