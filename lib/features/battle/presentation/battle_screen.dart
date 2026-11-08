import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../../../core/audio/audio_controller.dart';
import '../../../shared/audio_controls.dart';
import '../../results/presentation/battle_result_screen.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';
import '../../profile/domain/rank_tier.dart';

class BattleScreen extends ConsumerStatefulWidget {
  const BattleScreen({super.key, required this.matchId});
  final String matchId;
  @override
  ConsumerState<BattleScreen> createState() => _BattleState();
}

class _BattleState extends ConsumerState<BattleScreen>
    with WidgetsBindingObserver {
  late QuizRepository repo;
  late AudioController audio;
  Map<String, dynamic>? data;
  Timer? polling, ticker;
  RealtimeChannel? channel;
  bool busy = false, submitting = false, active = true;
  String? selected, error;
  int previousIndex = -1;
  double remaining = 0;
  Duration offset = Duration.zero;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    repo = QuizRepository(ref.read(sessionProvider));
    audio = ref.read(audioProvider)..enterGame(this);
    channel = repo.session.client!.channel(
      'match:${widget.matchId}',
      opts: const RealtimeChannelConfig(private: true),
    );
    for (final event in [
      'question_start',
      'question_result',
      'opponent_answered',
      'match_end',
    ]) {
      channel!.onBroadcast(event: event, callback: (_) => refresh());
    }
    channel!.subscribe();
    refresh();
    polling = Timer.periodic(const Duration(seconds: 2), (_) {
      if (active) refresh();
    });
    ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && data?['question'] != null) {
        final deadline = data!['question']['deadline_at'];
        if (deadline != null) {
          setState(
            () => remaining =
                (DateTime.parse(deadline)
                            .difference(DateTime.now().add(offset))
                            .inMilliseconds /
                        1000)
                    .clamp(0, 120),
          );
          final seconds = remaining.ceil();
          if (seconds > 0 &&
              seconds <= 3 &&
              data!['phase'] == 'question' &&
              selected == null) {
            audio.play(
              GameCue.tick,
              eventId: 'battle:${widget.matchId}:$previousIndex:tick:$seconds',
            );
          }
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    busy = true;
    final sent = DateTime.now();
    try {
      final next = await repo.rpc('get_match_state', {
        'match_id': widget.matchId,
      });
      if (!mounted) return;
      offset = DateTime.parse(next['server_now']).difference(
        sent.add(
          Duration(
            milliseconds: DateTime.now().difference(sent).inMilliseconds ~/ 2,
          ),
        ),
      );
      final nextIndex = next['question_index'] as int;
      final cuePrefix = 'battle:${widget.matchId}:$nextIndex';
      if (next['phase'] == 'countdown') {
        audio.play(
          GameCue.matchFound,
          eventId: 'battle:${widget.matchId}:found',
        );
      }
      if (next['phase'] == 'question') {
        audio.play(
          nextIndex == (next['question_count'] as int) - 1
              ? GameCue.finalRound
              : GameCue.questionStart,
          eventId: '$cuePrefix:start',
        );
      }
      if (next['phase'] == 'result' && next['status'] == 'in_progress') {
        final round = next['result'] as Map?;
        final answers = (round?['answers'] as List? ?? []).cast<Map>();
        final yours = answers
            .where((a) => a['user_id'] == repo.session.profile!.id)
            .firstOrNull;
        final option = yours?['option_id'];
        audio.play(
          option == null
              ? GameCue.timeout
              : option == round?['correct_option_id']
              ? GameCue.correct
              : GameCue.wrong,
          eventId: '$cuePrefix:result',
        );
      }
      if (['completed', 'abandoned'].contains(next['status'])) {
        polling?.cancel();
        ticker?.cancel();
        audio.leaveGame(this);
        if (next['status'] == 'completed') {
          final me = (next['players'] as List).cast<Map>().firstWhere(
            (p) => p['id'] == repo.session.profile!.id,
          );
          audio.play(
            RankTier.forRating(
                      (me['rating_after'] ?? me['rating']) as int,
                    ).index >
                    RankTier.forRating(me['rating'] as int).index
                ? GameCue.levelUp
                : me['result'] == 'win'
                ? GameCue.win
                : me['result'] == 'draw'
                ? GameCue.draw
                : GameCue.loss,
            eventId: 'battle:${widget.matchId}:end',
          );
        }
      }
      if (next['question_index'] != previousIndex) {
        selected = null;
        submitting = false;
        previousIndex = next['question_index'];
      }
      if (next['result'] != null) {
        final yours = ((next['result']['answers'] as List?) ?? [])
            .cast<Map>()
            .where((a) => a['user_id'] == repo.session.profile!.id)
            .firstOrNull;
        if (yours?['option_id'] is String) selected = yours!['option_id'];
      }
      setState(() {
        data = next;
        error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Connection lost. The round keeps running on the server. Reconnecting…',
        );
      }
    } finally {
      busy = false;
    }
  }

  Future<void> answer(String id) async {
    if (selected != null || submitting) return;
    setState(() {
      selected = id;
      submitting = true;
    });
    if (repo.session.haptics) unawaited(HapticFeedback.selectionClick());
    audio.play(GameCue.select);
    try {
      await repo.rpc('submit_answer', {
        'match_id': widget.matchId,
        'question_index': data!['question_index'],
        'option_id': id,
      });
      await refresh();
    } catch (e) {
      if (mounted) {
        setState(() => selected = null);
        showMessage(
          context,
          e.toString().contains('TIME_UP')
              ? 'Time’s up.'
              : 'Answer not confirmed. Tap again to retry safely.',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> leave() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this match?'),
        content: const Text(
          'Leaving counts as a loss. You can keep playing if you stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep playing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave match'),
          ),
        ],
      ),
    );
    if (yes == true) {
      try {
        await repo.session.client!.rpc(
          'forfeit_match',
          params: {'match_id': widget.matchId},
        );
        if (mounted) context.go('/');
      } catch (_) {
        if (mounted) {
          showMessage(context, 'Couldn’t confirm leaving. Please retry.');
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    audio.leaveGame(this);
    polling?.cancel();
    ticker?.cancel();
    if (channel != null) repo.session.client!.removeChannel(channel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your battle')),
        body: error == null
            ? const SkeletonList()
            : EmptyState(
                title: 'Let’s reconnect',
                message: error!,
                action: OutlinedButton(
                  onPressed: refresh,
                  child: const Text('Retry'),
                ),
              ),
      );
    }
    final uid = repo.session.profile!.id;
    final players = (data!['players'] as List).cast<Map<String, dynamic>>();
    final me = players.firstWhere((p) => p['id'] == uid);
    final opponent = players.firstWhere((p) => p['id'] != uid);
    final finished = ['completed', 'abandoned'].contains(data!['status']);
    final question = data!['question'] as Map?;
    final result = data!['result'] as Map?;
    if (finished) {
      return BattleResultScreen(
        matchId: widget.matchId,
        initialState: data!,
        viewerId: uid,
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Live battle'),
          actions: const [GameAudioButton()],
          leading: IconButton(
            onPressed: leave,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Leave match',
          ),
        ),
        body: PageBody(
          maxWidth: 700,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (error != null)
                MaterialBanner(
                  content: Text(error!),
                  actions: [
                    TextButton(onPressed: refresh, child: const Text('Retry')),
                  ],
                ),
              Row(
                children: [
                  AvatarBadge(name: me['full_name']),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You\n${me['score']} pts',
                      style: context.type.titleMedium,
                    ),
                  ),
                  Text(
                    'VS',
                    style: TextStyle(
                      color: context.tokens.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Text(
                      '${opponent['full_name']}\n${opponent['score']} pts',
                      textAlign: TextAlign.end,
                      style: context.type.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 12),
                  AvatarBadge(
                    name: opponent['full_name'],
                    color: context.tokens.warning,
                  ),
                ],
              ),
              if (opponent['connected'] == false) ...[
                const SizedBox(height: 12),
                const Text('Opponent reconnecting…'),
              ],
              if (data!['mode'] == 'bot' && data!['label_bots'] == true)
                const Center(child: Chip(label: Text('Practice opponent'))),
              const SizedBox(height: 32),
              if (question == null) ...[
                const SizedBox(height: 40),
                Text(
                  'Match found\nGet ready',
                  textAlign: TextAlign.center,
                  style: context.type.headlineLarge,
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 88,
                    color: ArenaTokens.violet,
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Question ${(data!['question_index'] as int) + 1} of ${data!['question_count']}',
                        style: context.type.titleMedium,
                      ),
                    ),
                    TimerRing(
                      remaining: remaining,
                      total: (question['time_limit_seconds'] as num).toDouble(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (data!['question_index'] ==
                    (data!['question_count'] as int) - 1) ...[
                  Text(
                    'Final round · Double points',
                    style: TextStyle(
                      color: context.tokens.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  question['question_text'],
                  style: context.type.titleLarge?.copyWith(height: 1.5),
                ),
                const SizedBox(height: 28),
                ...(question['options'] as List).asMap().entries.map((entry) {
                  final opt = entry.value as Map;
                  final id = opt['id'] as String;
                  final answered = (data!['answered'] as List).contains(uid);
                  final state = result != null
                      ? (id == result['correct_option_id']
                            ? OptionState.correct
                            : id == selected
                            ? OptionState.wrong
                            : OptionState.disabled)
                      : id == selected
                      ? OptionState.selected
                      : answered || selected != null || remaining <= 0
                      ? OptionState.disabled
                      : OptionState.idle;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OptionTile(
                      label: String.fromCharCode(65 + entry.key),
                      text: opt['option_text'],
                      state: state,
                      onTap: () => answer(id),
                    ),
                  );
                }),
                if ((data!['answered'] as List).contains(opponent['id']))
                  const Center(
                    child: Chip(
                      avatar: Icon(Icons.check_rounded, size: 18),
                      label: Text('Opponent answered'),
                    ),
                  ),
                if (result != null) ...[
                  const SizedBox(height: 16),
                  ArenaCard(child: Text(result['explanation'] ?? '')),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
