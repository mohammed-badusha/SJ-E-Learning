import '../../../shared/arena_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/session.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../battle/domain/battle_report.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.questions});
  final List<Map<String, dynamic>> questions;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<ReviewScreen> {
  bool wrongOnly = false;
  Future<void> report(String id) async {
    final note = TextEditingController();
    var reason = 'Wrong answer';
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Report a question'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items:
                      ['Wrong answer', 'Unclear question', 'Outdated content']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                  onChanged: (v) => update(() => reason = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: note,
                  maxLength: 1000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Anything we should know? (optional)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send report'),
            ),
          ],
        ),
      ),
    );
    if (send == true) {
      try {
        await ref
            .read(sessionProvider)
            .client!
            .rpc(
              'report_question',
              params: {'question_id': id, 'reason': reason, 'note': note.text},
            );
        if (mounted) {
          showMessage(
            context,
            'Thanks. The academy will review this question.',
          );
        }
      } catch (_) {
        if (mounted) {
          showMessage(context, 'Report couldn’t be sent. Please retry.');
        }
      }
    }
    note.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.questions
        .where((q) => !wrongOnly || q['is_correct'] != true)
        .toList();
    return Scaffold(
      appBar: ArenaBar(title: const Text('Answer review')),
      body: PageBody(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show wrong answers only'),
              value: wrongOnly,
              onChanged: (v) => setState(() => wrongOnly = v),
            ),
            if (questions.isEmpty)
              const EmptyState(
                title: 'Nothing to revisit here',
                message: 'Keep practising to build your confidence.',
              ),
            ...questions.map(
              (q) => Arrive(
                key: ValueKey(
                  q['question_index'] ?? widget.questions.indexOf(q),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: ArenaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Question ${(q['question_index'] as int? ?? widget.questions.indexOf(q)) + 1}',
                                style: context.type.bodySmall,
                              ),
                            ),
                            if (q['multiplier'] == 2)
                              Text(
                                'Double points',
                                style: TextStyle(
                                  color: context.tokens.warning,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (q['category_name'] != null)
                          Text(
                            '${q['category_name']} · ${q['difficulty']} · ${q['time_limit_seconds']}s',
                            style: context.type.bodySmall,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          q['question_text'],
                          style: context.type.titleMedium,
                        ),
                        const SizedBox(height: 20),
                        ...(q['options'] as List).asMap().entries.map(
                          (e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OptionTile(
                              label: String.fromCharCode(65 + e.key),
                              text: e.value['option_text'],
                              state: e.value['id'] == q['correct_option_id']
                                  ? OptionState.correct
                                  : e.value['id'] == q['selected_option_id']
                                  ? OptionState.wrong
                                  : OptionState.disabled,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _AnswerSummary(
                          label: 'Your answer',
                          question: q,
                          optionId: q['selected_option_id'],
                          responseMs: q['response_ms'],
                          points: q['points'],
                        ),
                        if (q.containsKey('opponent_option_id')) ...[
                          const SizedBox(height: 12),
                          _AnswerSummary(
                            label: 'Opponent answer',
                            question: q,
                            optionId: q['opponent_option_id'],
                            responseMs: q['opponent_response_ms'],
                            points: q['opponent_points'],
                          ),
                        ],
                        const Divider(height: 32),
                        Text('Why this answer', style: context.type.titleSmall),
                        const SizedBox(height: 8),
                        SelectableText(q['explanation'] ?? ''),
                        if (q['id'] != null &&
                            !ref.read(sessionProvider).preview)
                          TextButton.icon(
                            onPressed: () => report(q['id']),
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('Report this question'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerSummary extends StatelessWidget {
  const _AnswerSummary({
    required this.label,
    required this.question,
    required this.optionId,
    required this.responseMs,
    required this.points,
  });
  final String label;
  final Map<String, dynamic> question;
  final Object? optionId;
  final num? responseMs, points;
  @override
  Widget build(BuildContext context) {
    final options = question['options'] as List;
    final idx = options.indexWhere((o) => o['id'] == optionId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.type.bodySmall),
        const SizedBox(height: 4),
        Text(
          idx < 0
              ? 'Unanswered'
              : '${String.fromCharCode(65 + idx)} · ${options[idx]['option_text']}',
          style: context.type.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${answerTime(responseMs)} · +${points ?? 0} points',
          style: context.type.bodySmall,
        ),
      ],
    );
  }
}
