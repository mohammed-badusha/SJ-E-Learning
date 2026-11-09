import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/domain/models.dart';
import '../../practice/data/quiz_repository.dart';

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
  });
  final QuizRepository repo;
  final String title, initialSearch;
  final String? categoryId;
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
  bool get users => widget.categoryId == null;
  @override
  void initState() {
    super.initState();
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
    final result = await widget.repo.rpc(
      users ? 'admin_user_page' : 'admin_question_page',
      {
        if (!users) 'subject_id': widget.categoryId,
        'search': filter,
        'after_id': cursor,
      },
    );
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
    if (!users) {
      await context.push(
        '/admin/question',
        extra: {...row, 'category_name': widget.title},
      );
      if (mounted) await load(reset: true);
      return;
    }
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ArenaBar(title: Text(widget.title)),
    body: PageBody(
      maxWidth: 850,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: users
                        ? 'Search name, email or phone'
                        : 'Search this category',
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onSubmitted: (v) {
                    query = v.trim();
                    load(reset: true);
                  },
                ),
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
                      return Card(
                        child: ListTile(
                          onTap: () => open(row),
                          leading: users
                              ? AvatarBadge(name: row['full_name'], size: 38)
                              : Icon(
                                  row['status'] == 'published'
                                      ? Icons.check_circle_outline
                                      : Icons.edit_note,
                                ),
                          title: Text(
                            users
                                ? (row['full_name'].toString().isEmpty
                                      ? 'Unnamed learner'
                                      : row['full_name'])
                                : row['question_text'],
                          ),
                          subtitle: Text(
                            users
                                ? '${row['email'] ?? '—'} · Level ${row['level']}'
                                : [
                                    row['topic_name'],
                                    row['difficulty'],
                                    row['status'],
                                  ].whereType<String>().join(' · '),
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
