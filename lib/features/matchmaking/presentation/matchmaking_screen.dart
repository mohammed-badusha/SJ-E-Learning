import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../../../core/audio/audio_controller.dart';
import '../../../shared/widgets.dart';
import '../../../shared/audio_controls.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key, this.category = 'mixed', this.subtopic});
  final String category;
  final String? subtopic;
  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingState();
}

class _MatchmakingState extends ConsumerState<MatchmakingScreen> {
  Timer? timer;
  RealtimeChannel? channel;
  int remaining = 20;
  String? error;
  bool cancelled = false, busy = false, navigated = false;
  late QuizRepository repo;
  late AudioController audio;
  @override
  void initState() {
    super.initState();
    repo = QuizRepository(ref.read(sessionProvider));
    audio = ref.read(audioProvider)..enterGame(this);
    if (!repo.session.preview) start();
  }

  void openMatch(String id) {
    if (!mounted || cancelled || navigated) return;
    navigated = true;
    audio.play(GameCue.matchFound, eventId: 'battle:$id:found');
    timer?.cancel();
    context.replace('/battle/$id');
  }

  Future<void> start() async {
    setState(() => error = null);
    try {
      channel = repo.session.client!.channel(
        'user:${repo.session.profile!.id}',
        opts: const RealtimeChannelConfig(private: true),
      );
      channel!
          .onBroadcast(
            event: 'match_found',
            callback: (payload) {
              final id = payload['match_id'];
              if (id is String) openMatch(id);
            },
          )
          .subscribe();
      await poll();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'We couldn’t join the queue. Check your connection and retry.',
        );
      }
    }
  }

  Future<void> poll() async {
    if (busy || cancelled || navigated) return;
    busy = true;
    try {
      final result = await repo.rpc('join_matchmaking', {
        'category_id': widget.category == 'mixed' ? null : widget.category,
        'subtopic_id': widget.subtopic,
      });
      if (result['match_id'] != null) {
        openMatch(result['match_id']);
        return;
      }
      final elapsed = DateTime.parse(
        result['server_now'],
      ).difference(DateTime.parse(result['joined_at'])).inSeconds;
      final timeout = result['search_timeout_seconds'] as int;
      if (mounted) {
        setState(() => remaining = (timeout - elapsed).clamp(0, timeout));
      }
      if (remaining <= 0) {
        final bot = await repo.rpc('start_bot_match');
        if (bot['match_id'] != null) openMatch(bot['match_id']);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().contains('NOT_ENOUGH_QUESTIONS')
              ? 'There aren’t enough published questions in this topic yet. Try another category.'
              : 'Connection interrupted. Reconnecting to your queue…',
        );
      }
    } finally {
      busy = false;
    }
  }

  Future<void> cancel() async {
    cancelled = true;
    timer?.cancel();
    if (!repo.session.preview) {
      try {
        await repo.session.client!.rpc('leave_matchmaking');
      } catch (_) {}
    }
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    audio.leaveGame(this);
    timer?.cancel();
    if (channel != null) repo.session.client!.removeChannel(channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Finding your match'),
        actions: const [GameAudioButton()],
        leading: IconButton(
          onPressed: cancel,
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel matchmaking',
        ),
      ),
      body: PageBody(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 48),
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ArenaTokens.violet.withValues(alpha: .15),
                    width: 20,
                  ),
                ),
                child: Center(
                  child: AvatarBadge(
                    name: repo.session.profile!.fullName,
                    size: 100,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              repo.session.preview
                  ? 'Find your opponent'
                  : 'Searching for an opponent',
              textAlign: TextAlign.center,
              style: context.type.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              repo.session.preview
                  ? 'Live matchmaking needs the Supabase schema and Google sign-in. Try a local practice round to explore the question experience.'
                  : 'Searching for a learner at your level. If no one joins, a labelled practice opponent will take the challenge.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tokens.muted),
            ),
            const SizedBox(height: 32),
            if (!repo.session.preview)
              Center(
                child: TimerRing(remaining: remaining.toDouble(), total: 20),
              ),
            if (error != null) ...[
              const SizedBox(height: 20),
              Text(error!, textAlign: TextAlign.center),
              TextButton(
                onPressed: poll,
                child: const Text('Retry connection'),
              ),
            ],
            const SizedBox(height: 32),
            if (repo.session.preview)
              PrimaryButton(
                label: 'Try a preview round',
                onPressed: () => context.replace('/quiz?mode=practice'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: cancel,
              child: const Text('Cancel search'),
            ),
            const SizedBox(height: 24),
            Text(
              'Correct answers earn points; faster answers earn a bonus',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.tokens.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}
