import 'dart:async';
import 'duel_intro.dart';
import '../../../shared/arena_motion.dart';
import '../../../shared/player_avatar.dart';
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
  bool refreshPending = false;
  String? selected, error;
  int previousIndex = -1;
  final roundsScroll = ScrollController();
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
    ticker = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (active &&
          mounted &&
          data?['phase'] == 'question' &&
          data?['question'] != null) {
        final deadline = data!['question']['deadline_at'];
        if (deadline != null) {
          final next =
              (DateTime.parse(
                        deadline,
                      ).difference(DateTime.now().add(offset)).inMilliseconds /
                      1000)
                  .clamp(0, 120)
                  .ceilToDouble();
          if (next != remaining) setState(() => remaining = next);
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
    if (!mounted) return;
    if (busy) {
      refreshPending = true;
      return;
    }
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
        if (roundsScroll.hasClients) roundsScroll.jumpTo(0);
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
        final deadline = next['question']?['deadline_at'];
        if (deadline != null) {
          remaining =
              (DateTime.parse(
                        deadline,
                      ).difference(DateTime.now().add(offset)).inMilliseconds /
                      1000)
                  .clamp(0, 120)
                  .ceilToDouble();
        }
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
      if (refreshPending) {
        refreshPending = false;
        if (mounted &&
            active &&
            !['completed', 'abandoned'].contains(data?['status'])) {
          unawaited(refresh());
        }
      }
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
    roundsScroll.dispose();
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
      if (error == null) {
        final profile = repo.session.profile!;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (popped, _) {
            if (!popped) leave();
          },
          child: DuelIntro(
            name: profile.fullName,
            rival: '',
            ownPortrait: profile.avatarUrl,
            rivalPortrait: null,
            matchId: widget.matchId,
            ownRank: profile.tier,
            rivalRank: '',
            bot: false,
            onLeave: leave,
          ),
        );
      }
      return Scaffold(
        appBar: ArenaBar(title: const Text('Your battle')),
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
      child: question == null && error == null
          ? DuelIntro(
              matchId: widget.matchId,
              name: me['full_name'],
              rival: opponent['full_name'],
              ownRank:
                  '${RankTier.forRating(me['rating']).label} · Level ${me['level'] ?? 1}',
              rivalRank:
                  '${RankTier.forRating(opponent['rating']).label} · Level ${opponent['level'] ?? 1}',
              ownPortrait: repo.session.profile!.avatarUrl,
              rivalPortrait:
                  opponent['avatar_url'] ??
                  (data!['mode'] == 'bot' ? 'preset:explorer' : null),
              bot: data!['mode'] == 'bot' && data!['label_bots'] == true,
              onLeave: leave,
            )
          : Scaffold(
              appBar: ArenaBar(
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
                  controller: roundsScroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (error != null)
                      MaterialBanner(
                        content: Text(error!),
                        actions: [
                          TextButton(
                            onPressed: refresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    _FaceOff(
                      me: me,
                      opponent: opponent,
                      matchId: widget.matchId,
                      ownPortrait: repo.session.profile!.avatarUrl,
                      countdown: question == null,
                      bot: data!['mode'] == 'bot',
                    ),
                    if (opponent['connected'] == false) ...[
                      const SizedBox(height: 12),
                      const Text('Opponent reconnecting…'),
                    ],
                    if (data!['mode'] == 'bot' && data!['label_bots'] == true)
                      const Center(
                        child: Chip(label: Text('Practice opponent')),
                      ),
                    const SizedBox(height: 16),
                    if (question == null) ...[
                      Text(
                        'Match found',
                        textAlign: TextAlign.center,
                        style: context.type.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Get ready for the first question.',
                        textAlign: TextAlign.center,
                        style: context.type.bodyLarge,
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
                            total: (question['time_limit_seconds'] as num)
                                .toDouble(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value:
                              ((data!['question_index'] as num) + 1) /
                              (data!['question_count'] as num),
                          minHeight: 5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (data!['question_index'] ==
                          (data!['question_count'] as int) - 1) ...[
                        Text(
                          'Final round · English',
                          style: TextStyle(
                            color: context.tokens.warning,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ArenaCard(
                        child: Text(
                          question['question_text'],
                          style: context.type.titleLarge?.copyWith(height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (result == null)
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              submitting
                                  ? 'Sending your answer…'
                                  : selected != null ||
                                        (data!['answered'] as List).contains(
                                          uid,
                                        )
                                  ? 'Answer locked · Waiting for the reveal'
                                  : (data!['answered'] as List).contains(
                                      opponent['id'],
                                    )
                                  ? 'Opponent has answered'
                                  : 'Choose an answer',
                              style: context.type.titleSmall,
                            ),
                          ),
                        ),
                      ...(question['options'] as List).asMap().entries.map((
                        entry,
                      ) {
                        final opt = entry.value as Map;
                        final id = opt['id'] as String;
                        final answered = (data!['answered'] as List).contains(
                          uid,
                        );
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
                      if (result != null) ...[
                        const SizedBox(height: 16),
                        Arrive(
                          key: ValueKey(previousIndex),
                          child: ArenaCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selected == null
                                      ? 'Time’s up'
                                      : selected == result['correct_option_id']
                                      ? 'Correct answer'
                                      : 'Incorrect answer',
                                  style: context.type.titleMedium,
                                ),
                                if ((result['explanation'] ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(result['explanation']),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _FaceOff extends StatelessWidget {
  const _FaceOff({
    required this.me,
    required this.opponent,
    required this.matchId,
    required this.ownPortrait,
    required this.countdown,
    required this.bot,
  });
  final Map<String, dynamic> me, opponent;
  final String matchId;
  final String? ownPortrait;
  final bool countdown, bot;
  @override
  Widget build(BuildContext context) {
    Widget player(Map<String, dynamic> data, bool mine) {
      final name = data['full_name'] as String;
      return Expanded(
        child: Arrive(
          from: Offset(mine ? -32 : 32, 0),
          duration: 360,
          child: Column(
            children: [
              PlayerAvatar(
                name: name,
                reference: mine
                    ? ownPortrait
                    : (data['avatar_url'] as String? ??
                          (bot ? 'preset:explorer' : null)),
                matchId: mine ? null : matchId,
                size: countdown ? 72 : 42,
              ),
              const SizedBox(height: 7),
              Text(
                mine ? 'You · $name' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.type.titleSmall?.copyWith(color: Colors.white),
              ),
              if (countdown)
                Text(
                  RankTier.forRating(data['rating'] as int).label,
                  style: const TextStyle(color: Color(0xffdddaf8)),
                )
              else
                CountMetric(
                  data['score'] as num,
                  format: (n) => '$n pts',
                  style: context.type.titleMedium?.copyWith(
                    color: ArenaTokens.gold,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [ArenaTokens.navy, Color(0xff443887)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          children: [
            player(me, true),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: const BoxDecoration(
                color: ArenaTokens.gold,
                shape: BoxShape.circle,
              ),
              child: const Text(
                'VS',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ArenaTokens.navy,
                  fontSize: 12,
                ),
              ),
            ),
            player(opponent, false),
          ],
        ),
      ),
    );
  }
}
