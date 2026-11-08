import 'dart:async';
import 'search_clock.dart';
import '../../../shared/arena_panel.dart';
import 'search_pulse.dart';
import '../../../shared/player_avatar.dart';
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
  final clock = SearchClock();
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
    clock.stop();
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
      if (!mounted || cancelled || navigated) return;
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
      if (!mounted || cancelled || navigated) return;
      if (error != null) setState(() => error = null);
      final joined = DateTime.parse(result['joined_at']);
      final server = DateTime.parse(result['server_now']);
      final timeout = result['search_timeout_seconds'] as int;
      clock.sync(joined: joined, server: server, timeout: timeout);
      if (!server.isBefore(joined.add(Duration(seconds: timeout)))) {
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
    if (cancelled || navigated) return;
    cancelled = true;
    clock.stop();
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
    clock.dispose();
    audio.leaveGame(this);
    timer?.cancel();
    if (channel != null) repo.session.client!.removeChannel(channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (popped, _) {
      if (!popped) cancel();
    },
    child: Scaffold(
      appBar: ArenaBar(
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
            ArenaPanel(
              child: Column(
                children: [
                  Text(
                    'Matchmaking',
                    style: context.type.bodySmall?.copyWith(color: arenaMint),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Finding your opponent',
                    textAlign: TextAlign.center,
                    style: context.type.headlineSmall?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            ArenaPortrait(
                              accent: arenaLilac,
                              child: PlayerAvatar(
                                reference: repo.session.profile!.avatarUrl,
                                name: repo.session.profile!.fullName,
                                size: 62,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              repo.session.profile!.firstName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${repo.session.profile!.tier} · You',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: arenaLilac),
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 22),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w800,
                            color: ArenaTokens.gold,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Column(
                          children: [
                            SearchPulse(color: arenaMint),
                            SizedBox(height: 10),
                            Text(
                              'Opponent',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Searching…',
                              style: TextStyle(color: arenaMint),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ArenaCard(
              child: ValueListenableBuilder<int?>(
                valueListenable: clock,
                builder: (context, value, _) {
                  final status = repo.session.preview
                      ? 'Practice preview'
                      : value == null
                      ? 'Joining the queue…'
                      : value == 0
                      ? 'Preparing your opponent…'
                      : 'Searching for a live player';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              status,
                              style: context.type.titleMedium,
                            ),
                          ),
                          if (value != null && value > 0)
                            Text('${value}s', style: context.type.titleLarge),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: value == null ? 0 : 1 - value / clock.total,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        repo.session.preview
                            ? 'Try a sample round to practise answering.'
                            : 'If no learner joins in time, you’ll play a practice opponent.',
                        style: context.type.bodySmall,
                      ),
                    ],
                  );
                },
              ),
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
          ],
        ),
      ),
    ),
  );
}
