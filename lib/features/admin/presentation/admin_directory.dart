import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/player_avatar.dart';
import '../../auth/domain/models.dart';
import '../../practice/data/quiz_repository.dart';
import 'question_import_screen.dart';

const userColumns = <String, String>{
  'full_name': 'Full name',
  'email': 'Email',
  'phone': 'Phone',
  'role': 'Role',
  'target_exam': 'Target exam',
  'username': 'Username',
  'level': 'Level',
  'rating': 'Rating',
  'xp': 'XP',
  'current_streak': 'Current streak',
  'best_streak': 'Best streak',
  'last_daily_date': 'Last daily challenge',
  'profile_completed': 'Profile complete',
  'is_banned': 'Banned',
  'created_at': 'Joined',
  'updated_at': 'Updated',
  'id': 'User ID',
};

class AdminDirectory extends StatefulWidget {
  const AdminDirectory({
    super.key,
    required this.repo,
    this.categoryId,
    required this.title,
    this.initialSearch = '',
    this.userDirectory = false,
  });
  final QuizRepository repo;
  final String title, initialSearch;
  final String? categoryId;
  final bool userDirectory;
  @override
  State<AdminDirectory> createState() => _AdminDirectoryState();
}

class _AdminDirectoryState extends State<AdminDirectory> {
  late final search = TextEditingController(text: widget.initialSearch);
  late String query = widget.initialSearch;
  final rows = <Map<String, dynamic>>[];
  bool loading = false, more = true, exporting = false;
  int generation = 0;
  String? error;
  int total = 0;
  String? selectedCategoryId;
  late final Future<List<QuizCategory>> categories;
  final expandedIds = <String>{};
  final details = <String, Future<Map<String, dynamic>>>{};
  bool get users => widget.userDirectory;
  @override
  void initState() {
    super.initState();
    selectedCategoryId = widget.categoryId;
    if (!users) categories = widget.repo.categories();
    widget.repo.session.dataChanges.addListener(onDataChanged);
    load(reset: true);
  }

  void onDataChanged() {
    if (mounted) load(reset: true);
  }

  @override
  void dispose() {
    widget.repo.session.dataChanges.removeListener(onDataChanged);
    search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> page(String? cursor, String filter) async {
    final result = await widget.repo
        .rpc(users ? 'admin_user_page' : 'admin_question_summary_page', {
          if (!users) 'subject_id': selectedCategoryId,
          'search': filter,
          'after_id': cursor,
        });
    if (!users && cursor == null) total = (result['total'] as num).toInt();
    return (result['rows'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> load({bool reset = false}) async {
    if (!reset && (loading || !more)) return;
    if (reset) generation++;
    final request = generation;
    setState(() {
      if (reset) {
        rows.clear();
        more = true;
        expandedIds.clear();
        details.clear();
      }
      loading = true;
      error = null;
    });
    try {
      final part = await page(rows.lastOrNull?['id'] as String?, query);
      if (mounted && generation == request) {
        setState(() {
          rows.addAll(part);
          more = part.length == (users ? 100 : 50);
        });
      }
    } catch (_) {
      if (mounted && generation == request) {
        setState(() => error = 'Couldn’t load this page.');
      }
    } finally {
      if (mounted && generation == request) setState(() => loading = false);
    }
  }

  Future<void> exportUsers() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final output = <List<dynamic>>[userColumns.values.toList()];
      String? cursor;
      while (mounted) {
        final batch = await page(cursor, '');
        for (final user in batch) {
          output.add([for (final key in userColumns.keys) csvCell(user[key])]);
        }
        if (batch.length < 100) break;
        cursor = batch.last['id'];
      }
      if (!mounted) return;
      final bytes = Uint8List.fromList(
        utf8.encode('\uFEFF${const ListToCsvConverter().convert(output)}'),
      );
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Export all learners',
        fileName: 'sj-learners.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );
      if (mounted && (kIsWeb || destination != null)) {
        showMessage(context, 'Exported ${output.length - 1} learners.');
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Couldn’t export the directory. Check your connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> open(Map<String, dynamic> row) async {
    final toggle = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .82,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('Learner profile', style: context.type.headlineSmall),
              const SizedBox(height: 12),
              PlayerAvatar(
                name: row['full_name'] as String? ?? 'Learner',
                reference: row['avatar_url'] as String?,
                size: 72,
              ),
              const SizedBox(height: 12),
              for (final field in userColumns.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(field.value, style: context.type.bodySmall),
                  subtitle: SelectableText('${row[field.key] ?? '—'}'),
                ),
              if (widget.repo.session.role == AdminRole.superAdmin)
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    row['is_banned'] == true
                        ? 'Restore account access'
                        : 'Suspend account',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (toggle != true || !mounted) return;
    try {
      await widget.repo.session.client!.rpc(
        'admin_set_user',
        params: {'user_id': row['id'], 'is_banned': row['is_banned'] != true},
      );
      if (mounted) await load(reset: true);
    } catch (_) {
      if (mounted) showMessage(context, 'Couldn’t update account access.');
    }
  }

  Future<Map<String, dynamic>> detail(String id) => details.putIfAbsent(
    id,
    () => widget.repo.rpc('admin_question_detail', {'question_id': id}),
  );

  void toggleQuestion(String id) {
    setState(() {
      if (!expandedIds.remove(id)) {
        expandedIds.add(id);
        detail(id);
      }
    });
  }

  Future<void> editQuestion(String id) async {
    try {
      final question = await detail(id);
      if (!mounted) return;
      await context.push('/admin/question', extra: question);
      if (mounted) await load(reset: true);
    } catch (_) {
      details.remove(id);
      if (mounted) {
        showMessage(context, 'Couldn’t open this question. Try again.');
      }
    }
  }

  Future<void> deleteQuestion(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete question?'),
        content: const Text(
          'This question will be removed from future quizzes. Past matches and Daily Challenges will keep their saved copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.repo.rpc('admin_archive_question', {'question_id': id});
      if (!mounted) return;
      setState(() {
        rows.removeWhere((row) => row['id'] == id);
        expandedIds.remove(id);
        details.remove(id);
        total = (total - 1).clamp(0, 1 << 31);
      });
      showMessage(context, 'Question deleted from future quizzes.');
      await load(reset: true);
    } catch (_) {
      if (mounted) {
        showMessage(context, 'Couldn’t delete this question. Please retry.');
      }
    }
  }

  Widget badge(String label, Color foreground, Color background) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
    ),
  );

  Widget questionCard(Map<String, dynamic> row) {
    final id = row['id'] as String;
    final expanded = expandedIds.contains(id);
    final difficulty = (row['difficulty'] as String? ?? 'medium').toLowerCase();
    final difficultyColor = switch (difficulty) {
      'easy' => const Color(0xFF168438),
      'hard' => const Color(0xFFC62828),
      _ => const Color(0xFFA96800),
    };
    final difficultyLabel = switch (difficulty) {
      'easy' => 'Easy',
      'hard' => 'Hard',
      _ => 'Moderate',
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => toggleQuestion(id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row['question_text'] as String? ?? '',
                      maxLines: expanded ? null : 2,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: context.type.titleMedium,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  badge(
                    row['category_name'] as String? ?? 'Subject',
                    const Color(0xFF1648A8),
                    const Color(0xFFDCEAFF),
                  ),
                  if (row['topic_name'] is String)
                    badge(
                      row['topic_name'] as String,
                      const Color(0xFF1648A8),
                      const Color(0xFFD4EDFF),
                    ),
                  badge(
                    difficultyLabel,
                    difficultyColor,
                    difficultyColor.withValues(alpha: 0.16),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: expanded
                    ? FutureBuilder<Map<String, dynamic>>(
                        future: detail(id),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: TextButton(
                                onPressed: () => setState(() {
                                  details.remove(id);
                                  detail(id);
                                }),
                                child: const Text(
                                  'Couldn’t load details. Retry',
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: LinearProgressIndicator(),
                            );
                          }
                          final question = snapshot.data!;
                          final options = (question['options'] as List?) ?? [];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(height: 24),
                              for (var i = 0; i < options.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: options[i]['is_correct'] == true
                                          ? const Color(
                                              0xFF22C55E,
                                            ).withValues(alpha: 0.14)
                                          : null,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor:
                                              options[i]['is_correct'] == true
                                              ? const Color(0xFF168438)
                                              : context.tokens.line,
                                          child: Text(
                                            String.fromCharCode(65 + i),
                                            style: TextStyle(
                                              color:
                                                  options[i]['is_correct'] ==
                                                      true
                                                  ? Colors.white
                                                  : context.tokens.ink,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            options[i]['option_text']
                                                    as String? ??
                                                '',
                                            style: TextStyle(
                                              color:
                                                  options[i]['is_correct'] ==
                                                      true
                                                  ? const Color(0xFF168438)
                                                  : null,
                                              fontWeight:
                                                  options[i]['is_correct'] ==
                                                      true
                                                  ? FontWeight.w700
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (options[i]['is_correct'] == true)
                                          const Icon(
                                            Icons.check_rounded,
                                            color: Color(0xFF168438),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              if ((question['explanation'] as String? ?? '')
                                  .trim()
                                  .isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFFFFE79A,
                                    ).withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'Explanation: ${question['explanation']}',
                                  ),
                                ),
                              if (widget.repo.session.role.canEdit)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () => editQuestion(id),
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Edit'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => deleteQuestion(id),
                                        icon: const Icon(Icons.delete_outline),
                                        label: const Text('Delete'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ArenaBar(title: Text(users ? widget.title : 'Question Bank')),
    body: PageBody(
      maxWidth: 850,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!users && widget.repo.session.role.canEdit) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await context.push('/admin/question');
                          if (mounted) await load(reset: true);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Manually'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final message = await Navigator.push<String>(
                            context,
                            MaterialPageRoute<String>(
                              builder: (_) =>
                                  QuestionImportScreen(repo: widget.repo),
                            ),
                          );
                          if (context.mounted && message != null) {
                            showMessage(context, message);
                          }
                          if (mounted) await load(reset: true);
                        },
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Bulk Upload'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: users
                        ? 'Search name, email or phone'
                        : 'Search questions or topics',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onSubmitted: (v) {
                    query = v.trim();
                    load(reset: true);
                  },
                ),
                if (!users) ...[
                  const SizedBox(height: 12),
                  FutureBuilder<List<QuizCategory>>(
                    future: categories,
                    builder: (context, snapshot) =>
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                            '$selectedCategoryId:${snapshot.hasData}',
                          ),
                          initialValue:
                              (snapshot.data ?? <QuizCategory>[]).any(
                                (category) => category.id == selectedCategoryId,
                              )
                              ? selectedCategoryId
                              : '',
                          decoration: const InputDecoration(
                            labelText: 'Filter by Subject',
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('All Subjects'),
                            ),
                            for (final category
                                in snapshot.data ?? <QuizCategory>[])
                              DropdownMenuItem(
                                value: category.id,
                                child: Text(category.name),
                              ),
                          ],
                          onChanged: snapshot.hasData
                              ? (value) {
                                  selectedCategoryId = value == ''
                                      ? null
                                      : value;
                                  load(reset: true);
                                }
                              : null,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$total questions found',
                    style: context.type.titleMedium,
                  ),
                ],
                if (users)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: exporting ? null : exportUsers,
                      icon: const Icon(Icons.download_outlined),
                      label: Text(
                        exporting ? 'Exporting…' : 'Export all learners (CSV)',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: loading && rows.isEmpty
                ? const SkeletonList()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: rows.length + 1,
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        if (error != null) {
                          return TextButton(
                            onPressed: load,
                            child: Text('$error Retry'),
                          );
                        }
                        if (rows.isEmpty) {
                          return const EmptyState(
                            title: 'No results',
                            message: 'Try another search.',
                          );
                        }
                        if (more) {
                          return TextButton(
                            onPressed: loading ? null : load,
                            child: Text(loading ? 'Loading…' : 'Load more'),
                          );
                        }
                        return const SizedBox(height: 20);
                      }
                      final row = rows[index];
                      if (!users) return questionCard(row);
                      return Card(
                        child: ListTile(
                          onTap: () => open(row),
                          leading: PlayerAvatar(
                            name: row['full_name'] as String? ?? 'Learner',
                            reference: row['avatar_url'] as String?,
                            size: 38,
                          ),
                          title: Text(
                            row['full_name'].toString().isEmpty
                                ? 'Unnamed learner'
                                : row['full_name'],
                          ),
                          subtitle: Text(
                            '${row['email'] ?? '—'} · Level ${row['level']}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

String csvCell(dynamic value) {
  final text = value?.toString() ?? '';
  return value is String && RegExp(r'^[\s]*[=+@-]').hasMatch(text)
      ? "'$text"
      : text;
}
