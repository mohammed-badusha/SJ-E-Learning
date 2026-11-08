import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../auth/data/session.dart';
import '../../auth/domain/models.dart';
import '../../practice/data/quiz_repository.dart';

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});
  @override
  ConsumerState<AdminScreen> createState() => _AdminState();
}

class _AdminState extends ConsumerState<AdminScreen> {
  int section = 0;
  late Future<Map<String, dynamic>> future;
  String query = '';
  final labels = [
    'Overview',
    'Questions',
    'Categories',
    'Users & roles',
    'Reports',
    'Settings',
    'Daily schedule',
    'Analytics',
  ];
  final icons = [
    Icons.grid_view_rounded,
    Icons.quiz_rounded,
    Icons.category_rounded,
    Icons.people_rounded,
    Icons.flag_rounded,
    Icons.tune_rounded,
    Icons.calendar_month_rounded,
    Icons.insights_rounded,
  ];
  QuizRepository get repo => QuizRepository(ref.read(sessionProvider));
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = switch (section) {
      0 => repo.rpc('admin_dashboard'),
      1 => repo.rpc('admin_questions', {'search': query}),
      2 => repo.categories().then((c) => {'categories': c}),
      3 => repo.rpc('admin_list_users', {'search': query}),
      4 => repo.rpc('admin_reports'),
      6 => repo.rpc('admin_daily_calendar'),
      7 => repo.rpc('admin_analytics'),
      _ => repo.rpc('get_app_settings'),
    };
  }

  void select(int i) => setState(() {
    section = i;
    query = '';
    load();
  });
  Future<void> openEditor([Map<String, dynamic>? question]) async {
    await context.push('/admin/question', extra: question);
    if (mounted) setState(load);
  }

  Future<void> roleDialog() async {
    final email = TextEditingController();
    String role = 'editor';
    bool active = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add or update an admin'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Google email address',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                    DropdownMenuItem(value: 'editor', child: Text('Editor')),
                    DropdownMenuItem(
                      value: 'super_admin',
                      child: Text('Super Admin'),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => role = v!),
                ),
                SwitchListTile.adaptive(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                ),
                const Text(
                  'You can also manage these rows in Supabase → Table Editor → admin_users.',
                  style: TextStyle(fontSize: 12),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await repo.session.client!.rpc(
          'admin_set_role',
          params: {
            'email': email.text.trim(),
            'role': role,
            'is_active': active,
          },
        );
        if (mounted) setState(load);
      } catch (_) {
        if (mounted) {
          showMessage(
            context,
            'Couldn’t update this role. Check the email and your permissions.',
          );
        }
      }
    }
    email.dispose();
  }

  Future<void> categoryDialog([QuizCategory? category]) async {
    final name = TextEditingController(text: category?.name);
    final slug = TextEditingController(text: category?.slug);
    final color = TextEditingController(
      text: category == null
          ? '#5B4CFF'
          : '#${category.color.toARGB32().toRadixString(16).substring(2)}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category == null ? 'Add a category' : 'Edit category'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: slug,
                decoration: const InputDecoration(labelText: 'Slug'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: color,
                decoration: const InputDecoration(
                  labelText: 'Colour (#RRGGBB)',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        await repo.session.client!.rpc(
          'admin_save_category',
          params: {
            'payload': {
              if (category != null) 'id': category.id,
              'name': name.text.trim(),
              'slug': slug.text.trim(),
              'color_hex': color.text,
              'icon': category?.slug ?? 'public',
            },
          },
        );
        if (mounted) setState(load);
      } catch (_) {
        if (mounted) {
          showMessage(
            context,
            'Couldn’t save the category. Use a unique slug and valid hex colour.',
          );
        }
      }
    }
    name.dispose();
    slug.dispose();
    color.dispose();
  }

  Future<void> importCsv() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null) throw StateError('No bytes');
      final List<List<dynamic>> rows;
      if (picked.files.single.extension == 'xlsx') {
        final workbook = Excel.decodeBytes(bytes);
        rows = workbook.tables.values.first.rows
            .map(
              (row) =>
                  row.map((cell) => cell?.value?.toString() ?? '').toList(),
            )
            .toList();
      } else {
        final source = utf8.decode(bytes).replaceFirst('\uFEFF', '');
        rows = const CsvToListConverter(
          shouldParseNumbers: false,
          eol: '\n',
        ).convert(source.replaceAll('\r\n', '\n'));
      }
      if (rows.length < 2 || rows.length > 501) {
        throw StateError('Use 1–500 rows');
      }
      final header = rows.first.map((v) => v.toString().trim()).toList();
      final categories = await repo.categories();
      final valid = <Map<String, dynamic>>[];
      final errors = <String>[];
      for (var i = 1; i < rows.length; i++) {
        final row = {
          for (var j = 0; j < header.length; j++)
            header[j]: j < rows[i].length ? rows[i][j].toString().trim() : '',
        };
        final matches = categories
            .where(
              (c) =>
                  c.name.toLowerCase() ==
                      (row['category'] ?? '').toLowerCase() ||
                  c.slug == row['category'],
            )
            .toList();
        final options = [
          for (final letter in ['a', 'b', 'c', 'd', 'e', 'f'])
            if ((row['option_$letter'] ?? '').isNotEmpty)
              {
                'option_text': row['option_$letter'],
                'is_correct': row['correct_option']?.toLowerCase() == letter,
              },
        ];
        final seconds = int.tryParse(row['time_limit_seconds'] ?? '') ?? 15;
        if (matches.isEmpty ||
            (row['question'] ?? '').length < 4 ||
            options.length < 2 ||
            options.where((o) => o['is_correct'] == true).length != 1 ||
            options
                    .map((o) => o['option_text'].toString().toLowerCase())
                    .toSet()
                    .length !=
                options.length ||
            seconds < 5 ||
            seconds > 120 ||
            !['easy', 'medium', 'hard'].contains(row['difficulty'])) {
          errors.add(
            'Row ${i + 1}: check category, question, unique options, answer, difficulty and timer.',
          );
          continue;
        }
        valid.add({
          'category_id': matches.first.id,
          'question_text': row['question'],
          'options': options,
          'time_limit_seconds': seconds,
          'difficulty': row['difficulty'],
          'explanation': row['explanation'] ?? '',
          'status': 'draft',
        });
      }
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '${valid.length} valid · ${errors.length} need attention',
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Valid rows will be imported as drafts for review.',
                  ),
                  const SizedBox(height: 16),
                  ...valid.take(5).map((r) => Text('• ${r['question_text']}')),
                  ...errors
                      .take(20)
                      .map(
                        (e) => Text(
                          e,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: valid.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Import valid rows'),
            ),
          ],
        ),
      );
      if (approved == true) {
        var imported = 0;
        for (final payload in valid) {
          try {
            await repo.session.client!.rpc(
              'admin_save_question',
              params: {'payload': payload},
            );
            imported++;
          } catch (_) {}
        }
        if (mounted) {
          showMessage(
            context,
            '$imported of ${valid.length} rows imported as drafts.',
          );
          setState(load);
        }
      }
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Couldn’t read that CSV. Use the template in docs/import-template.csv, with at most 500 rows.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(sessionProvider).role;
    final content = FutureBuilder(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return EmptyState(
            title: 'This page couldn’t load',
            message: 'Check your connection and current permissions.',
            action: OutlinedButton(
              onPressed: () => setState(load),
              child: const Text('Retry'),
            ),
          );
        }
        if (!snapshot.hasData) return const SkeletonList();
        final d = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    labels[section],
                    style: context.type.headlineMedium,
                  ),
                ),
                if (section == 1 && role.canEdit) ...[
                  IconButton(
                    onPressed: importCsv,
                    icon: const Icon(Icons.upload_file_rounded),
                    tooltip: 'Import CSV',
                  ),
                  FilledButton.icon(
                    onPressed: () => openEditor(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ],
                if (section == 2 && role.canEdit)
                  IconButton(
                    onPressed: () => categoryDialog(),
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Add category',
                  ),
                if (section == 3 && role == AdminRole.superAdmin)
                  IconButton(
                    onPressed: roleDialog,
                    icon: const Icon(Icons.person_add_rounded),
                    tooltip: 'Add or update admin',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (section == 0) ...[
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final item in [
                    ('Students', d['students']),
                    ('Published questions', d['questions']),
                    ('Today’s matches', d['matches']),
                    ('Open reports', d['reports']),
                  ])
                    SizedBox(
                      width: 200,
                      child: ArenaCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.$2}',
                              style: context.type.headlineLarge,
                            ),
                            Text(item.$1),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Content readiness', style: context.type.titleLarge),
              const SizedBox(height: 12),
              if ((d['short_categories'] as List).isEmpty)
                const ArenaCard(
                  child: Text(
                    'Every active category has enough published questions for a default match.',
                  ),
                )
              else
                ...(d['short_categories'] as List).map(
                  (c) => ListTile(
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text(c['name']),
                    subtitle: Text(
                      '${c['count']} published questions · add more before matchmaking.',
                    ),
                  ),
                ),
            ],
            if (section == 1 || section == 3) ...[
              TextField(
                decoration: InputDecoration(
                  labelText: section == 1
                      ? 'Search question text'
                      : 'Search name or email',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
                onSubmitted: (v) => setState(() {
                  query = v;
                  load();
                }),
              ),
              const SizedBox(height: 16),
            ],
            if (section == 1) ...[
              if ((d['questions'] as List).isEmpty)
                const EmptyState(
                  title: 'Your question bank starts here',
                  message: 'Create a question or import a CSV.',
                ),
              ...(d['questions'] as List).map(
                (q) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  title: Text(q['question_text']),
                  subtitle: Text(
                    '${q['category_name']} · ${q['difficulty']} · ${q['time_limit_seconds']}s · ${q['status']}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openEditor(Map<String, dynamic>.from(q)),
                ),
              ),
            ],
            if (section == 2)
              ...(d['categories'] as List<QuizCategory>).map(
                (c) => ListTile(
                  leading: Icon(c.icon, color: c.color),
                  title: Text(c.name),
                  subtitle: Text(c.slug),
                  trailing: role.canEdit
                      ? const Icon(Icons.edit_outlined)
                      : null,
                  onTap: role.canEdit ? () => categoryDialog(c) : null,
                ),
              ),
            if (section == 3) ...[
              if (role == AdminRole.superAdmin) ...[
                Text('Academy staff', style: context.type.titleLarge),
                const SizedBox(height: 12),
                ...(d['admins'] as List).map(
                  (a) => ListTile(
                    leading: const Icon(Icons.admin_panel_settings_rounded),
                    title: Text(a['email']),
                    subtitle: Text(
                      '${a['role']} · ${a['is_active'] == true ? 'active' : 'inactive'}',
                    ),
                  ),
                ),
                const Divider(height: 32),
              ],
              Text('Students', style: context.type.titleLarge),
              ...(d['users'] as List).map(
                (u) => ListTile(
                  leading: AvatarBadge(name: u['full_name']),
                  title: Text(u['full_name']),
                  subtitle: Text('${u['email']} · ${u['rating']} rating'),
                  trailing: role == AdminRole.superAdmin
                      ? TextButton(
                          onPressed: () async {
                            try {
                              await repo.session.client!.rpc(
                                'admin_set_user',
                                params: {
                                  'user_id': u['id'],
                                  'is_banned': u['is_banned'] != true,
                                },
                              );
                              if (mounted) setState(load);
                            } catch (_) {
                              if (context.mounted) {
                                showMessage(
                                  context,
                                  'Couldn’t update this user.',
                                );
                              }
                            }
                          },
                          child: Text(u['is_banned'] == true ? 'Unban' : 'Ban'),
                        )
                      : null,
                ),
              ),
            ],
            if (section == 4) ...[
              if ((d['reports'] as List).isEmpty)
                const EmptyState(
                  title: 'All clear',
                  message: 'Question reports from students will appear here.',
                  icon: Icons.fact_check_rounded,
                ),
              ...(d['reports'] as List).map(
                (r) => ArenaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['question_text'], style: context.type.titleMedium),
                      Text('${r['reason']} · ${r['status']}'),
                      if (r['note'] != null) Text(r['note']),
                      if (role.canEdit && r['status'] == 'open')
                        TextButton(
                          onPressed: () async {
                            try {
                              await repo.session.client!.rpc(
                                'admin_resolve_report',
                                params: {
                                  'report_id': r['id'],
                                  'status': 'resolved',
                                },
                              );
                              if (mounted) setState(load);
                            } catch (_) {
                              if (context.mounted) {
                                showMessage(
                                  context,
                                  'Couldn’t resolve this report.',
                                );
                              }
                            }
                          },
                          child: const Text('Mark resolved'),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (section == 6) ...[
              const Text(
                'A balanced question set for each day. Challenges lock when a student starts.',
              ),
              const SizedBox(height: 16),
              ...(d['days'] as List).map(
                (day) => ListTile(
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: Text(day['day'].toString().split('T').first),
                  subtitle: Text(day['title'] ?? 'No challenge scheduled'),
                  trailing: role.canEdit
                      ? TextButton(
                          onPressed: () async {
                            final title = TextEditingController(
                              text: day['title'] ?? 'Your daily ten',
                            );
                            final approved = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Schedule daily challenge'),
                                content: TextField(
                                  controller: title,
                                  decoration: const InputDecoration(
                                    labelText: 'Challenge title',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Auto-fill & schedule'),
                                  ),
                                ],
                              ),
                            );
                            if (approved == true) {
                              try {
                                await repo.session.client!.rpc(
                                  'admin_schedule_daily',
                                  params: {
                                    'day': day['day']
                                        .toString()
                                        .split('T')
                                        .first,
                                    'title': title.text,
                                  },
                                );
                                if (mounted) setState(load);
                              } catch (_) {
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    'Couldn’t schedule this day. It may already have participants.',
                                  );
                                }
                              }
                            }
                            title.dispose();
                          },
                          child: Text(
                            day['id'] == null ? 'Schedule' : 'Edit title',
                          ),
                        )
                      : null,
                ),
              ),
            ],
            if (section == 7) ...[
              Text('Category popularity', style: context.type.titleLarge),
              ...(d['categories'] as List).map(
                (c) => ListTile(
                  title: Text(c['name']),
                  trailing: Text('${c['matches']} matches'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Question performance', style: context.type.titleLarge),
              if ((d['questions'] as List).isEmpty)
                const EmptyState(
                  title: 'A clearer picture, with every round',
                  message:
                      'Accuracy and response-time insights appear after battles.',
                ),
              ...(d['questions'] as List).map(
                (q) => ListTile(
                  title: Text(q['question_text']),
                  subtitle: Text(
                    '${q['attempts']} answers · ${q['accuracy']}% accuracy · ${q['average_ms']} ms average',
                  ),
                  leading:
                      (q['accuracy'] as num) < 10 || (q['accuracy'] as num) > 95
                      ? const Icon(Icons.flag_outlined)
                      : const Icon(Icons.insights_rounded),
                ),
              ),
              const SizedBox(height: 24),
              Text('Playing hours · IST', style: context.type.titleLarge),
              ...(d['hours'] as List).map(
                (h) => ListTile(
                  title: Text('${h['hour']}:00'),
                  trailing: Text('${h['matches']} matches'),
                ),
              ),
            ],
            if (section == 5) ...[
              const Text('Only Super Admins can change app settings.'),
              const SizedBox(height: 16),
              for (final key in [
                'search_timeout_seconds',
                'questions_per_match',
                'label_bots',
                'maintenance_mode',
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(key.replaceAll('_', ' ')),
                  subtitle: Text('${d[key]}'),
                  trailing: role == AdminRole.superAdmin
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit ${key.replaceAll('_', ' ')}',
                          onPressed: () async {
                            final controller = TextEditingController(
                              text: '${d[key]}',
                            );
                            final value = await showDialog<String>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(key.replaceAll('_', ' ')),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Value (number or true/false)',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, controller.text),
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );
                            if (value != null) {
                              try {
                                await repo.session.client!.rpc(
                                  'admin_save_setting',
                                  params: {
                                    'key': key,
                                    'value': jsonDecode(value),
                                  },
                                );
                                if (mounted) setState(load);
                              } catch (_) {
                                if (context.mounted) {
                                  showMessage(
                                    context,
                                    'That value isn’t valid for this setting.',
                                  );
                                }
                              }
                            }
                            controller.dispose();
                          },
                        )
                      : null,
                ),
            ],
            const SizedBox(height: 32),
          ],
        );
      },
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Academy workspace')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1024) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: section,
                  onDestinationSelected: select,
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (var i = 0; i < labels.length; i++)
                      NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            );
          }
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(labels[i]),
                          selected: section == i,
                          onSelected: (_) => select(i),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}
