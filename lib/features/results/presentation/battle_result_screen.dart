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
      appBar: AppBar(
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
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: context.tokens.warning.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        mine.result == 'win'
                            ? Icons.emoji_events_rounded
                            : mine.result == 'draw'
                            ? Icons.handshake_outlined
                            : Icons.sports_score_rounded,
                        size: 36,
                        color: context.tokens.warning,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            abandoned
                                ? 'Match ended'
                                : mine.result == 'win'
                                ? 'You won'
                                : mine.result == 'draw'
                                ? 'A well-matched draw'
                                : 'Battle complete',
                            style: context.type.headlineMedium,
                          ),
                          Text(
                            abandoned
                                ? 'No rating change'
                                : mine.result == 'loss'
                                ? 'A loss, with progress to keep'
                                : 'Review the round and build on it',
                            style: TextStyle(
                              color: context.tokens.secondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ArenaCard(
                  child: Row(
                    children: [
                      Expanded(child: _PlayerScore(player: mine, you: true)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('vs', style: context.type.bodySmall),
                      ),
                      Expanded(child: _PlayerScore(player: rival, you: false)),
                    ],
                  ),
                ),
                if (report?.isBot == true && report?.labelBot == true) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Practice opponent · Bot matches use reduced rating changes',
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Rating change',
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
                const SizedBox(height: 24),
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
                ArenaCard(
                  child: TierProgress(
                    rating: mine.ratingAfter ?? mine.ratingBefore,
                  ),
                ),
                if (!snapshot.hasData && !snapshot.hasError) ...[
                  const SizedBox(height: 24),
                  const ArenaCard(
                    child: Text('Preparing your match breakdown…'),
                  ),
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
                  const SizedBox(height: 32),
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
                    const SizedBox(height: 24),
                    _CategoryBreakdown(questions: report.questions),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '${report.roundsPlayed} of ${report.questionCount} questions played · ${answerTime(report.durationMs)} match time',
                    style: context.type.bodySmall,
                  ),
                ],
                if (report != null && !report.advanced) ...[
                  const SizedBox(height: 20),
                  const ArenaCard(
                    child: Text(
                      'Answer review is available. Timing and opponent statistics are unavailable for this report.',
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                PrimaryButton(
                  label: 'Review every answer',
                  icon: Icons.fact_check_outlined,
                  onPressed: report == null || report.questions.isEmpty
                      ? null
                      : () => context.push('/review', extra: report.questions),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.replace('/categories?mode=battle'),
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
  const _PlayerScore({required this.player, required this.you});
  final BattlePlayerStats player;
  final bool you;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TierBadge(rating: player.ratingAfter ?? player.ratingBefore, size: 44),
      const SizedBox(height: 12),
      SizedBox(
        height: MediaQuery.textScalerOf(context).scale(14) * 3,
        child: Center(
          child: Text(
            you ? 'You' : player.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.type.titleSmall,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text('${player.score}', style: context.type.headlineLarge),
      Text('points', style: context.type.bodySmall),
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
