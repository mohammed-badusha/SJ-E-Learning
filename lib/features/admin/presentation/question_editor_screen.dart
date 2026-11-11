import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class QuestionEditorScreen extends ConsumerStatefulWidget {
  const QuestionEditorScreen({super.key, this.question});
  final Map<String, dynamic>? question;
  @override
  ConsumerState<QuestionEditorScreen> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends ConsumerState<QuestionEditorScreen> {
  final text = TextEditingController(), explanation = TextEditingController();
  final options = <TextEditingController>[];
  int correct = 0;
  String? category, topic;
  String difficulty = 'medium';
  bool saving = false;
  String? error;
  late Future<List<QuizCategory>> categories;
  Future<List<Map<String, dynamic>>>? topics;
  @override
  void initState() {
    super.initState();
    categories = QuizRepository(ref.read(sessionProvider)).categories();
    final q = widget.question;
    if (q != null) {
      text.text = q['question_text'];
      explanation.text = q['explanation'];
      category = q['category_id'];
      topic = q['subtopic_id'];
      topics = QuizRepository(ref.read(sessionProvider)).subtopics(category!);
      difficulty = q['difficulty'];
      for (final o in q['options'] as List) {
        options.add(TextEditingController(text: o['option_text']));
        if (o['is_correct'] == true) correct = options.length - 1;
      }
    } else {
      for (var i = 0; i < 4; i++) {
        options.add(TextEditingController());
      }
    }
    text.addListener(update);
  }

  void update() => setState(() {});
  @override
  void dispose() {
    text.dispose();
    explanation.dispose();
    for (final o in options) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> save({bool duplicate = false}) async {
    final values = options.map((o) => o.text.trim()).toList();
    if (category == null ||
        topic == null ||
        values.length != 4 ||
        text.text.trim().length < 4 ||
        values.any((o) => o.isEmpty) ||
        values.map((o) => o.toLowerCase()).toSet().length != values.length) {
      setState(
        () => error =
            'Choose a subject and topic, then enter a question and four different options.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(sessionProvider)
          .client!
          .rpc(
            'admin_save_question',
            params: {
              'payload': {
                if (widget.question != null && !duplicate)
                  'id': widget.question!['id'],
                'category_id': category,
                'subtopic_id': topic,
                if (widget.question?['image_url'] != null)
                  'image_url': widget.question?['image_url'],
                'question_text': text.text.trim(),
                'explanation': explanation.text.trim(),
                'difficulty': difficulty,
                'options': [
                  for (var i = 0; i < options.length; i++)
                    {'option_text': values[i], 'is_correct': i == correct},
                ],
              },
            },
          );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().contains('QUESTION_ALREADY_USED')
              ? 'This question has been used. Save a new copy to preserve match history.'
              : 'Couldn’t save. Check the subject, topic, options and connection.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(sessionProvider).role.canEdit;
    final form = ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          widget.question == null ? 'Add Question Manually' : 'Edit Question',
          style: context.type.headlineMedium,
        ),
        const SizedBox(height: 24),
        FutureBuilder(
          future: categories,
          builder: (context, snapshot) => DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: [
              for (final c in snapshot.data ?? <QuizCategory>[])
                DropdownMenuItem(value: c.id, child: Text(c.name)),
              if (category != null &&
                  !(snapshot.data ?? <QuizCategory>[]).any(
                    (c) => c.id == category,
                  ))
                DropdownMenuItem(
                  value: category,
                  child: Text(
                    widget.question?['category_name'] ?? 'Current category',
                  ),
                ),
            ],
            onChanged: canEdit
                ? (v) => setState(() {
                    category = v;
                    topic = null;
                    topics = v == null
                        ? null
                        : QuizRepository(
                            ref.read(sessionProvider),
                          ).subtopics(v);
                  })
                : null,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: difficulty,
          decoration: const InputDecoration(labelText: 'Difficulty'),
          items: [
            'easy',
            'medium',
            'hard',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: canEdit ? (v) => setState(() => difficulty = v!) : null,
        ),
        const SizedBox(height: 16),
        FutureBuilder(
          future: topics,
          builder: (context, snapshot) {
            final items = snapshot.data ?? <Map<String, dynamic>>[];
            return DropdownButtonFormField<String>(
              key: ValueKey('$category:${items.length}'),
              initialValue: items.any((item) => item['id'] == topic)
                  ? topic
                  : null,
              decoration: InputDecoration(
                labelText: 'Topic',
                helperText: category == null
                    ? 'Select a subject first'
                    : snapshot.hasError
                    ? 'Could not load topics'
                    : null,
              ),
              items: [
                for (final item in items)
                  DropdownMenuItem(
                    value: item['id'] as String,
                    child: Text(item['name'] as String),
                  ),
              ],
              onChanged: canEdit && snapshot.hasData
                  ? (v) => setState(() => topic = v)
                  : null,
            );
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: text,
          enabled: canEdit,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(labelText: 'Question Statement *'),
        ),
        const SizedBox(height: 20),
        Text('Options & Correct Answer', style: context.type.titleMedium),
        const SizedBox(height: 12),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: canEdit ? () => setState(() => correct = i) : null,
                  icon: Icon(
                    correct == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  tooltip: 'Mark option ${String.fromCharCode(65 + i)} correct',
                ),
                Expanded(
                  child: TextField(
                    controller: options[i],
                    enabled: canEdit,
                    decoration: InputDecoration(
                      labelText: 'Option ${String.fromCharCode(65 + i)}',
                    ),
                  ),
                ),
                if (canEdit && options.length > 4)
                  IconButton(
                    onPressed: () => setState(() {
                      options.removeAt(i).dispose();
                      if (correct >= options.length) {
                        correct = options.length - 1;
                      }
                    }),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    tooltip: 'Remove option',
                  ),
              ],
            ),
          ),
        if (canEdit && options.length < 4)
          TextButton.icon(
            onPressed: () =>
                setState(() => options.add(TextEditingController())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add option'),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: explanation,
          enabled: canEdit,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Solution / Explanation (Optional)',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        if (canEdit) ...[
          PrimaryButton(
            label: 'Save Question',
            busy: saving,
            onPressed: () => save(),
          ),
          if (widget.question != null)
            TextButton(
              onPressed: saving ? null : () => save(duplicate: true),
              child: const Text('Save as a new copy'),
            ),
        ],
      ],
    );
    return Scaffold(
      appBar: ArenaBar(
        title: Text(canEdit ? 'Add Question Manually' : 'Question details'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= 1024
            ? Row(
                children: [
                  Expanded(child: form),
                  SizedBox(
                    width: 380,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ArenaCard(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            Text(
                              'Student preview',
                              style: context.type.titleMedium,
                            ),
                            const SizedBox(height: 24),
                            Text(text.text, style: context.type.titleLarge),
                            const SizedBox(height: 20),
                            for (var i = 0; i < options.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: OptionTile(
                                  label: String.fromCharCode(65 + i),
                                  text: options[i].text,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : PageBody(maxWidth: 700, child: form),
      ),
    );
  }
}
