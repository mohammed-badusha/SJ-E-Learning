import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../core/audio/audio_controller.dart';
import '../../../shared/audio_controls.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/session.dart';
import '../data/quiz_repository.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({
    super.key,
    this.category = 'mixed',
    this.subtopic,
    this.mode = 'practice',
    this.timed = true,
    this.exam,
    this.difficulty,
    this.questionCount = 10,
  });
  final String category, mode;
  final String? subtopic, exam, difficulty;
  final int questionCount;
  final bool timed;
  @override
  ConsumerState<QuizScreen> createState() => _QuizState();
}

class _QuizState extends ConsumerState<QuizScreen> {
  Map<String, dynamic>? question, result;
  String? attempt, selected, error;
  int index = 0, count = 5, score = 0, correct = 0;
  double remaining = 15;
  DateTime? deadline;
  Timer? timer, autoAdvance;
  bool advancing = false;
  final questionScroll = ScrollController();
  bool loading = true, submitting = false, finished = false;
  final List<Map<String, dynamic>> review = [];
  late QuizRepository repository;
  late AudioController audio;
  @override
  void initState() {
    super.initState();
    repository = QuizRepository(ref.read(sessionProvider));
    audio = ref.read(audioProvider)..enterGame(this);
    start();
  }

  Future<void> start() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (repository.session.preview) {
        count = previewQuestions.length;
        showQuestion(Map.of(previewQuestions[0]));
      } else {
        final data = await repository.rpc(
          widget.mode == 'daily' ? 'start_daily_attempt' : 'start_practice',
          widget.mode == 'daily'
              ? null
              : {
                  'category_id': widget.category == 'mixed'
                      ? null
                      : widget.category,
                  'subtopic_id': widget.subtopic,
                  'timed': widget.timed,
                  'exam_filter': widget.exam,
                  'difficulty_filter': widget.difficulty,
                  'question_count': widget.questionCount,
                },
        );
        attempt = data['attempt_id'];
        count = data['question_count'];
        index = data['question_index'] ?? 0;
        if (data['completed'] == true) {
          score = data['score'] ?? 0;
          correct = data['correct_count'] ?? 0;
          finished = true;
          audio.leaveGame(this);
        } else {
          if (!mounted) return;
          showQuestion(Map<String, dynamic>.from(data['question']));
        }
      }
    } catch (_) {
      error =
          'This round couldn’t start. Check your connection and that questions are published.';
    }
    if (mounted) setState(() => loading = false);
  }

  void showQuestion(Map<String, dynamic> value) {
    if (questionScroll.hasClients) questionScroll.jumpTo(0);
    question = value;
    audio.play(
      index == count - 1 ? GameCue.finalRound : GameCue.questionStart,
      eventId: 'quiz:${attempt ?? identityHashCode(this)}:$index:start',
    );
    selected = null;
    result = null;
    submitting = false;
    remaining = (value['time_limit_seconds'] as num).toDouble();
    deadline = value['deadline_at'] != null
        ? DateTime.parse(value['deadline_at'])
        : DateTime.now().add(Duration(seconds: remaining.toInt()));
    timer?.cancel();
    if (widget.timed || widget.mode == 'daily') {
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted ||
            (result != null && widget.mode != 'daily') ||
            submitting) {
          return;
        }
        final left =
            (deadline!.difference(DateTime.now()).inMilliseconds / 1000)
                .clamp(0, 120)
                .toDouble();
        final seconds = left.ceil();
        if (seconds != remaining.ceil()) {
          setState(() => remaining = left);
        } else {
          remaining = left;
        }
        if (result == null && seconds > 0 && seconds <= 3) {
          audio.play(
            GameCue.tick,
            eventId:
                'quiz:${attempt ?? identityHashCode(this)}:$index:tick:$seconds',
          );
        }
        if (remaining <= 0 && result == null && error == null) answer(null);
      });
    }
  }

  Future<void> answer(String? option) async {
    if (submitting || result != null) return;
    final capturedRemaining = remaining;
    setState(() {
      selected = option;
      submitting = true;
      error = null;
    });
    if (repository.session.haptics) unawaited(HapticFeedback.selectionClick());
    if (option != null) audio.play(GameCue.select);
    try {
      Map<String, dynamic> response;
      if (repository.session.preview) {
        final right = option == question!['correct_option_id'];
        response = {
          'correct_option_id': question!['correct_option_id'],
          'explanation': question!['explanation'],
          'is_correct': right,
          'points': previewScore(
            correct: right,
            remainingMs: widget.timed || widget.mode == 'daily'
                ? (capturedRemaining * 1000).round()
                : 0,
            durationMs: (question!['time_limit_seconds'] as int) * 1000,
            finalRound: index == count - 1,
          ),
        };
      } else {
        response = await repository.rpc(
          widget.mode == 'daily'
              ? 'submit_daily_answer'
              : 'submit_practice_answer',
          {'attempt_id': attempt, 'question_index': index, 'option_id': option},
        );
      }
      if (!mounted) return;
      timer?.cancel();
      result = response;
      audio.play(
        option == null
            ? GameCue.timeout
            : response['is_correct'] == true
            ? GameCue.correct
            : GameCue.wrong,
        eventId: 'quiz:${attempt ?? identityHashCode(this)}:$index:result',
      );
      score += (response['points'] as num?)?.toInt() ?? 0;
      if (response['is_correct'] == true) correct++;
      review.add({...question!, ...response, 'selected_option_id': option});
      setState(() => submitting = false);
      if (widget.mode == 'daily') {
        autoAdvance = Timer(const Duration(milliseconds: 350), next);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          submitting = false;
          selected = option;
          error =
              'Answer not confirmed. Retry to safely recover the first submission.';
        });
      }
    }
  }

  Future<void> next() async {
    if (!mounted || advancing) return;
    advancing = true;
    try {
      await advance();
    } finally {
      advancing = false;
    }
  }

  Future<void> advance() async {
    if (index == count - 1) {
      if (!repository.session.preview) {
        try {
          final data = await repository.rpc(
            widget.mode == 'daily' ? 'finish_daily_attempt' : 'finish_practice',
            {'attempt_id': attempt},
          );
          if (!mounted) return;
          score = data['score'];
          correct = data['correct_count'];
        } catch (_) {
          if (mounted) {
            setState(
              () => error = 'Couldn’t confirm your result. Please retry.',
            );
          }
          return;
        }
      }

      unawaited(repository.session.refresh());
      audio.leaveGame(this);
      audio.play(
        GameCue.win,
        eventId: 'quiz:${attempt ?? identityHashCode(this)}:end',
      );
      if (mounted) setState(() => finished = true);
      return;
    }
    setState(() {
      loading = widget.mode != 'daily';
      error = null;
    });
    try {
      final newIndex = index + 1;
      final data = repository.session.preview
          ? Map<String, dynamic>.of(previewQuestions[newIndex])
          : await repository.rpc(
              widget.mode == 'daily'
                  ? 'get_daily_question'
                  : 'get_practice_question',
              {'attempt_id': attempt, 'question_index': newIndex},
            );
      if (!mounted) return;
      index = newIndex;
      showQuestion(data);
    } catch (_) {
      error = 'The next question couldn’t load. Please retry.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    timer?.cancel();
    autoAdvance?.cancel();
    questionScroll.dispose();
    audio.leaveGame(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (finished) {
      return Scaffold(
        appBar: ArenaBar(
          title: Text(
            widget.mode == 'daily' ? 'Daily results' : 'Practice results',
          ),
        ),
        body: PageBody(
          maxWidth: 600,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.workspace_premium_rounded,
                color: context.tokens.warning,
                size: 96,
              ),
              const SizedBox(height: 24),
              Text(
                'Round complete',
                textAlign: TextAlign.center,
                style: context.type.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                repository.session.preview
                    ? 'Local preview complete · no rating or XP changes'
                    : 'Review your answers to prepare for the next round',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.tokens.muted),
              ),
              const SizedBox(height: 28),
              ArenaCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('$score', style: context.type.headlineLarge),
                        const Text('Points'),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '$correct/$count',
                          style: context.type.headlineLarge,
                        ),
                        const Text('Correct'),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '${(100 * correct / count).round()}%',
                          style: context.type.headlineMedium,
                        ),
                        const Text('Accuracy'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Review answers',
                icon: Icons.fact_check_rounded,
                onPressed: () => context.push('/review', extra: review),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to home'),
              ),
            ],
          ),
        ),
      );
    }
    return PopScope(
      canPop: widget.mode == 'practice',
      child: Scaffold(
        appBar: ArenaBar(
          title: Text(
            widget.mode == 'daily' ? 'Daily Challenge' : 'Practice round',
          ),
          actions: [
            const GameAudioButton(),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: () => context.go('/'),
              child: const Text('Leave'),
            ),
          ],
        ),
        body: loading
            ? const SkeletonList(layout: SkeletonLayout.quiz)
            : question == null
            ? EmptyState(
                title: 'Let’s try that again',
                message: error ?? 'Round unavailable',
                action: OutlinedButton(
                  onPressed: start,
                  child: const Text('Retry'),
                ),
              )
            : PageBody(
                maxWidth: 700,
                child: ListView(
                  controller: questionScroll,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Question ${index + 1} of $count',
                                style: context.type.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$score points',
                                style: TextStyle(color: context.tokens.muted),
                              ),
                            ],
                          ),
                        ),
                        if (widget.timed || widget.mode == 'daily')
                          TimerRing(
                            remaining: remaining,
                            total: (question!['time_limit_seconds'] as num)
                                .toDouble(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: (index + 1) / count,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (index == count - 1) ...[
                      Text(
                        'Final round · Double points',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: context.tokens.warning,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      question!['question_text'],
                      style: context.type.titleLarge?.copyWith(
                        fontSize: 21,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ...(question!['options'] as List).asMap().entries.map((
                      entry,
                    ) {
                      final option = entry.value as Map;
                      final id = option['id'] as String;
                      final state = result != null
                          ? (id == result!['correct_option_id']
                                ? OptionState.correct
                                : id == selected
                                ? OptionState.wrong
                                : OptionState.disabled)
                          : selected == id
                          ? OptionState.selected
                          : submitting || error != null
                          ? OptionState.disabled
                          : OptionState.idle;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OptionTile(
                          label: String.fromCharCode(65 + entry.key),
                          text: option['option_text'],
                          state: state,
                          onTap: () => answer(id),
                        ),
                      );
                    }),
                    if (error != null) ...[
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: result != null
                            ? next
                            : () => answer(selected),
                        child: const Text('Retry'),
                      ),
                    ],
                    if (result != null) ...[
                      const SizedBox(height: 12),
                      ArenaCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  result!['is_correct'] == true
                                      ? Icons.check_circle_rounded
                                      : Icons.lightbulb_rounded,
                                  color: context.tokens.success,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    result!['is_correct'] == true
                                        ? 'Correct · +${result!['points']}'
                                        : 'Answer explanation',
                                    style: context.type.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(result!['explanation'] ?? ''),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (widget.mode != 'daily')
                        PrimaryButton(
                          label: index == count - 1
                              ? 'See my results'
                              : 'Next question',
                          onPressed: next,
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
