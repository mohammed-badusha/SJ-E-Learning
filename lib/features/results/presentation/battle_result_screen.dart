import '../../../shared/arena_motion.dart';
import '../../../shared/trophy.dart';
import '../../../shared/arena_panel.dart';
import '../../../shared/player_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/rewards.dart';
import '../../auth/data/session.dart';
import '../../battle/domain/battle_report.dart';
import '../../practice/data/quiz_repository.dart';
import '../../profile/domain/rank_tier.dart';
import 'score_chart.dart';

class BattleResultScreen extends ConsumerStatefulWidget {
  const BattleResultScreen({
    super.key,
    required this.matchId,
    required this.initialState,
    required this.viewerId,
    this.reportLoader,
  });
  final String matchId, viewerId;
  final Map<String, dynamic> initialState;
  final Future<Map<String, dynamic>> Function()? reportLoader;
  @override
  ConsumerState<BattleResultScreen> createState() => _BattleResultState();
}

class _BattleResultState extends ConsumerState<BattleResultScreen> {
  late Future<BattleReport> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future =
        (widget.reportLoader?.call() ??
                QuizRepository(
                  ref.read(sessionProvider),
                ).rpc('get_match_review', {'match_id': widget.matchId}))
            .then(
              (json) => BattleReport.fromJson(
                json,
                initialState: widget.initialState,
              ),
            );
  }

  @override
  Widget build(BuildContext context) {
    final initial = (widget.initialState['players'] as List)
        .map((p) => BattlePlayerStats.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    final me = initial.firstWhere((p) => p.id == widget.viewerId);
    final other = initial.firstWhere((p) => p.id != widget.viewerId);
    final abandoned = widget.initialState['status'] == 'abandoned';
    return Scaffold(
      appBar: ArenaBar(
        title: const Text('Battle report'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Home',
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 820,
        child: FutureBuilder(
          future: future,
          builder: (context, snapshot) {
            final report = snapshot.data;
            final mine = report?.player(widget.viewerId) ?? me;
            final rival = report?.opponent(widget.viewerId) ?? other;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ArenaPanel(
                  child: Column(
                    children: [
                      if (mine.result == 'win') const Trophy(size: 36),
                      Text(
                        abandoned
                            ? 'Match ended'
                            : switch (mine.result) {
                                'win' => 'You won',
                                'draw' => 'Draw',
                                'loss' => 'Defeat',
                                _ => 'Battle complete',
                              },
                        textAlign: TextAlign.center,
                        style: context.type.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _PlayerScore(
                              player: mine,
                              reference:
                                  mine.avatarUrl ??
                                  me.avatarUrl ??
                                  ref.read(sessionProvider).profile?.avatarUrl,
                              you: true,
                              matchId: widget.matchId,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 20),
                            child: Text(
                              'VS',
                              style: TextStyle(
                                color: ArenaTokens.gold,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: _PlayerScore(
                              player: rival,
                              reference:
                                  rival.avatarUrl ??
                                  other.avatarUrl ??
                                  ((report?.isBot ??
                                          (widget.initialState['mode'] ==
                                              'bot'))
                                      ? 'preset:explorer'
                                      : null),
                              you: false,
                              matchId: widget.matchId,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (report?.isBot == true && report?.labelBot == true) ...[
                  const SizedBox(height: 12),
                  const Text('Practice opponent'),
                ],
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'Review every answer',
                  icon: Icons.fact_check_outlined,
                  onPressed: report == null || report.questions.isEmpty
                      ? null
                      : () => context.push('/review', extra: report.questions),
                ),
                const SizedBox(height: 20),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _Stat(
                          label: 'Trophy change',
                          value:
                              '${mine.ratingChange >= 0 ? '+' : ''}${mine.ratingChange}',
                          icon: Icons.trending_up_rounded,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Stat(
                          label: 'XP earned',
                          value: '+${mine.xp}',
                          icon: Icons.workspace_premium_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!snapshot.hasData && !snapshot.hasError) ...[
                  const SizedBox(height: 24),
                  const ArenaSkeleton(layout: SkeletonLayout.report),
                ],
                if (snapshot.hasError && !abandoned) ...[
                  const SizedBox(height: 24),
                  EmptyState(
                    title: 'Detailed report couldn’t load',
                    message:
                        'Your final score is saved. Reconnect and retry the breakdown.',
                    action: OutlinedButton(
                      onPressed: () => setState(load),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
                if (report != null && report.advanced) ...[
                  if (report.questions.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    ArenaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'How the battle unfolded',
                            style: context.type.titleMedium,
                          ),
                          const SizedBox(height: 20),
                          ScoreChart(
                            yours: report.cumulativeScores(),
                            opponent: report.cumulativeScores(opponent: true),
                            opponentName: rival.name,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'Your round at a glance',
                    style: context.type.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: width,
                            child: _Stat(
                              label: 'Accuracy',
                              value: answerAccuracy(mine.accuracy),
                              icon: Icons.track_changes_rounded,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _Stat(
                              label: 'Average answer',
                              value: answerTime(mine.avgResponseMs),
                              icon: Icons.timer_outlined,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _Stat(
                              label: 'Correct answers',
                              value: '${mine.correct}/${report.roundsPlayed}',
                              icon: Icons.check_circle_outline_rounded,
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: _Stat(
                              label: 'Speed bonus',
                              value: '+${mine.speedBonus}',
                              icon: Icons.bolt_outlined,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Accuracy includes unanswered questions. Average time uses submitted answers.',
                    style: context.type.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  ArenaCard(
                    child: Column(
                      children: [
                        _CompareRow(
                          label: 'Round comparison',
                          you: 'You',
                          other: 'Opponent',
                          heading: true,
                        ),
                        const Divider(height: 24),
                        _CompareRow(
                          label: 'Correct',
                          you: '${mine.correct}',
                          other: '${rival.correct}',
                        ),
                        _CompareRow(
                          label: 'Wrong',
                          you: '${mine.wrong}',
                          other: '${rival.wrong}',
                        ),
                        _CompareRow(
                          label: 'Unanswered',
                          you: '${mine.unanswered}',
                          other: '${rival.unanswered}',
                        ),
                        _CompareRow(
                          label: 'Average time',
                          you: answerTime(mine.avgResponseMs),
                          other: answerTime(rival.avgResponseMs),
                        ),
                        _CompareRow(
                          label: 'Fastest correct',
                          you: answerTime(mine.fastestCorrectMs),
                          other: answerTime(rival.fastestCorrectMs),
                        ),
                        _CompareRow(
                          label: 'Base points',
                          you: '${mine.basePoints}',
                          other: '${rival.basePoints}',
                        ),
                        _CompareRow(
                          label: 'Speed bonus',
                          you: '+${mine.speedBonus}',
                          other: '+${rival.speedBonus}',
                        ),
                      ],
                    ),
                  ),
                  if (report.questions.isNotEmpty) ...[
                    _CategoryBreakdown(questions: report.questions),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '${report.roundsPlayed} of ${report.questionCount} questions played · ${answerTime(report.durationMs)} match time',
                    style: context.type.bodySmall,
                  ),
                ],
                if (RankTier.forRating(
                      mine.ratingAfter ?? mine.ratingBefore,
                    ).index >
                    RankTier.forRating(mine.ratingBefore).index) ...[
                  Text(
                    'Promoted to ${RankTier.forRating(mine.ratingAfter!).label}',
                    style: context.type.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                if (RankTier.forRating(
                      mine.ratingAfter ?? mine.ratingBefore,
                    ).index <
                    RankTier.forRating(mine.ratingBefore).index) ...[
                  Text(
                    'Now in ${RankTier.forRating(mine.ratingAfter!).label} tier',
                    style: context.type.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                ArenaCard(
                  child: TierProgress(
                    rating: mine.ratingAfter ?? mine.ratingBefore,
                  ),
                ),
                if (report != null && !report.advanced) ...[
                  const SizedBox(height: 20),
                  const ArenaCard(
                    child: Text(
                      'Answer review is available. Timing and opponent statistics are unavailable for this report.',
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.replace('/matchmaking'),
                  child: const Text('Play again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ref.read(sessionProvider).refresh();
                    context.go('/');
                  },
                  child: const Text('Back to home'),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerScore extends StatelessWidget {
  const _PlayerScore({
    required this.player,
    required this.reference,
    required this.you,
    required this.matchId,
  });
  final BattlePlayerStats player;
  final String? reference;
  final String matchId;
  final bool you;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ArenaPortrait(
        accent: you ? arenaLilac : arenaMint,
        child: PlayerAvatar(
          name: player.name,
          reference: reference,
          matchId: you ? null : matchId,
          size: 56,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        you ? 'You' : 'Opponent',
        style: TextStyle(fontSize: 12, color: you ? arenaLilac : arenaMint),
      ),
      SizedBox(
        height: MediaQuery.textScalerOf(context).scale(14) * 2.9,
        child: Center(
          child: Text(
            player.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.type.titleSmall?.copyWith(color: Colors.white),
          ),
        ),
      ),
      CountMetric(
        player.score,
        style: context.type.headlineLarge?.copyWith(color: Colors.white),
      ),
      const Text(
        'points',
        style: TextStyle(color: Colors.white70, fontSize: 12),
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ArenaCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: context.tokens.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: context.type.bodySmall)),
          ],
        ),
        const SizedBox(height: 12),
        if (int.tryParse(value) case final int n)
          CountMetric(
            n,
            format: (v) => value.startsWith('+') ? '+$v' : '$v',
            style: context.type.headlineSmall,
          )
        else
          Text(value, style: context.type.headlineSmall),
      ],
    ),
  );
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.label,
    required this.you,
    required this.other,
    this.heading = false,
  });
  final String label, you, other;
  final bool heading;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: heading
                ? context.type.titleSmall
                : TextStyle(color: context.tokens.secondary, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            you,
            textAlign: TextAlign.end,
            style: context.type.titleSmall,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            other,
            textAlign: TextAlign.end,
            style: context.type.titleSmall,
          ),
        ),
      ],
    ),
  );
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.questions});
  final List<Map<String, dynamic>> questions;
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final question in questions) {
      groups
          .putIfAbsent(
            question['category_name'] as String? ?? 'Quiz questions',
            () => [],
          )
          .add(question);
    }
    return ArenaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Accuracy by subject', style: context.type.titleMedium),
          const SizedBox(height: 16),
          for (final entry in groups.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(entry.key, style: context.type.titleSmall),
                      ),
                      Text(
                        '${entry.value.where((q) => q['is_correct'] == true).length}/${entry.value.length}',
                        style: context.type.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value:
                        entry.value
                            .where((q) => q['is_correct'] == true)
                            .length /
                        entry.value.length,
                    minHeight: 5,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
