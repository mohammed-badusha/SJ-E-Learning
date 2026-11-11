import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../practice/data/quiz_repository.dart';

const questionImportExample = {
  'questions': [
    {
      'question': 'What is 15% of 200?',
      'option_a': '25',
      'option_b': '30',
      'option_c': '35',
      'option_d': '40',
      'correct_answer': 'B',
      'subject': 'Quantitative Aptitude',
      'topic': 'Percentage',
      'difficulty': 'Easy',
      'explanation': '15% of 200 = (15/100) × 200 = 30',
    },
    {
      'question': 'Choose the synonym of BENEVOLENT',
      'option_a': 'Cruel',
      'option_b': 'Kind',
      'option_c': 'Angry',
      'option_d': 'Sad',
      'correct_answer': 'B',
      'subject': 'English',
      'topic': 'Synonyms & Antonyms',
      'difficulty': 'Medium',
      'explanation': 'Benevolent means well-meaning and kindly',
    },
  ],
};

class QuestionImportScreen extends StatefulWidget {
  const QuestionImportScreen({super.key, required this.repo});
  final QuizRepository repo;
  @override
  State<QuestionImportScreen> createState() => _QuestionImportState();
}

class _QuestionImportState extends State<QuestionImportScreen> {
  final source = TextEditingController();
  String? error;
  bool busy = false;
  Map<String, dynamic>? batch;
  final example = const JsonEncoder.withIndent(
    '  ',
  ).convert(questionImportExample);
  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  Future<void> chooseFile() async {
    try {
      final pick = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!mounted || pick == null) return;
      final bytes = pick.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('The file could not be read.');
      }
      source.text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      validate();
    } catch (e) {
      if (mounted) setState(() => error = 'Could not read the JSON file. $e');
    }
  }

  void validate() {
    try {
      final document = jsonDecode(source.text);
      if (document is! Map<String, dynamic> || document['questions'] is! List) {
        throw const FormatException(
          'Use an object containing a questions array.',
        );
      }
      final rows = document['questions'] as List;
      if (rows.isEmpty || rows.length > 500) {
        throw const FormatException('Include 1–500 questions.');
      }
      for (final entry in rows.indexed) {
        final row = entry.$2;
        final number = entry.$1 + 1;
        if (row is! Map) {
          throw FormatException('Question $number must be an object.');
        }
        for (final field in [
          'question',
          'option_a',
          'option_b',
          'option_c',
          'option_d',
          'correct_answer',
          'subject',
          'topic',
          'difficulty',
        ]) {
          if (row[field] is! String || (row[field] as String).trim().isEmpty) {
            throw FormatException('Question $number is missing $field.');
          }
        }
        if (![
          'A',
          'B',
          'C',
          'D',
        ].contains(row['correct_answer'].trim().toUpperCase())) {
          throw FormatException(
            'Question $number needs a correct_answer from A to D.',
          );
        }
      }
      setState(() {
        error = null;
        batch = document;
      });
    } on FormatException catch (e) {
      setState(() {
        error = e.message;
        batch = null;
      });
    }
  }

  Future<void> save() async {
    if (busy || batch == null) return;
    setState(() => busy = true);
    try {
      final result = await widget.repo.rpc('admin_import_questions', {
        'payload': batch,
      });
      if (mounted) {
        Navigator.pop(
          context,
          result['already_imported'] == true
              ? 'This batch has already been imported.'
              : 'Imported ${result['imported']} playable questions.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is PostgrestException
              ? e.message
              : 'Import could not be confirmed. You can safely retry this batch.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ArenaBar(title: const Text('Bulk import')),
    body: PageBody(
      maxWidth: 820,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Import questions', style: context.type.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Choose a JSON file or paste its contents. Subject and topic names are matched to the approved list, including small spelling differences. Unknown names are rejected. Valid questions become playable immediately.',
          ),
          const SizedBox(height: 16),
          ArenaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Example JSON', style: context.type.titleMedium),
                ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Two sample questions'),
                  children: [
                    SizedBox(
                      height: 180,
                      child: SingleChildScrollView(
                        child: SelectableText(
                          example,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: example)),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy example'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy ? null : chooseFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Choose JSON file'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: source,
            enabled: !busy,
            minLines: 4,
            maxLines: 8,
            onChanged: (_) => setState(() {
              batch = null;
              error = null;
            }),
            decoration: const InputDecoration(labelText: 'Paste JSON'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (batch != null) ...[
            const SizedBox(height: 14),
            Text(
              '${(batch!['questions'] as List).length} questions ready to import',
              style: context.type.titleMedium,
            ),
            for (final item in (batch!['questions'] as List).take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item['question']),
                subtitle: Text('${item['subject']} · ${item['topic']}'),
              ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            label: batch == null ? 'Preview import' : 'Import questions',
            busy: busy,
            onPressed: batch == null ? validate : save,
          ),
        ],
      ),
    ),
  );
}
