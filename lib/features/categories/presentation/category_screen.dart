import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
import '../../../shared/arena_panel.dart';
import '../../auth/data/session.dart';
import '../../practice/data/quiz_repository.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, this.mode = 'practice'});
  final String mode;
  @override
  ConsumerState<CategoryScreen> createState() => _CategoryState();
}

class _CategoryState extends ConsumerState<CategoryScreen> {
  late Future<List<QuizCategory>> future;
  Future<List<Map<String, dynamic>>>? topics;
  String selected = 'mixed';
  String? topic;
  bool timed = true;
  QuizRepository get repo => QuizRepository(ref.read(sessionProvider));
  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen('preferences')) {
      selected = Hive.box('preferences').get('category', defaultValue: 'mixed');
    }
    load();
  }

  void load() => future = repo.categories();
  void choose(String id) {
    setState(() {
      selected = id;
      topic = null;
      topics = id == 'mixed' ? null : repo.subtopics(id);
    });
    if (Hive.isBoxOpen('preferences')) {
      Hive.box('preferences').put('category', id);
    }
  }

  void start() => context.push(
    Uri(
      path: widget.mode == 'battle' ? '/matchmaking' : '/quiz',
      queryParameters: {
        'category': selected,
        'mode': 'practice',
        'timed': '$timed',
        if (topic != null) 'subtopic': topic!,
      },
    ).toString(),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ArenaBar(
      title: Text(
        widget.mode == 'battle' ? 'Build your battle' : 'Find your focus',
      ),
    ),
    body: PageBody(
      maxWidth: 800,
      child: FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              title: 'Subjects couldn’t load',
              message: 'Reconnect and try again.',
              action: OutlinedButton(
                onPressed: () => setState(load),
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) return const SkeletonList();
          final categories = [mixedCategory, ...snapshot.data!];
          if (!categories.any((c) => c.id == selected)) {
            selected = 'mixed';
            topic = null;
            topics = null;
          }
          if (selected != 'mixed') topics ??= repo.subtopics(selected);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (widget.mode == 'battle') ...[
                      ArenaPanel(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '1v1 match',
                                    style: context.type.bodyMedium?.copyWith(
                                      color: arenaMint,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    categories
                                        .firstWhere((c) => c.id == selected)
                                        .name,
                                    style: context.type.headlineSmall?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Timed questions · Speed bonus',
                                    style: TextStyle(color: Color(0xffdce2fb)),
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/arena/duel.webp',
                              width: 76,
                              height: 76,
                              excludeFromSemantics: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    Text('Choose a subject', style: context.type.titleLarge),
                    const SizedBox(height: 12),
                    ArenaCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final category in categories) ...[
                            if (category != categories.first)
                              const Divider(indent: 68),
                            _SubjectChoice(
                              category: category,
                              selected: selected == category.id,
                              onTap: () => choose(category.id),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (topics != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Narrow your focus',
                        style: context.type.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      FutureBuilder(
                        future: topics,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return TextButton(
                              onPressed: () => setState(
                                () => topics = repo.subtopics(selected),
                              ),
                              child: const Text('Retry loading topics'),
                            );
                          }
                          return Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('All topics'),
                                selected: topic == null,
                                onSelected: (_) => setState(() => topic = null),
                              ),
                              ...?snapshot.data?.map(
                                (t) => ChoiceChip(
                                  label: Text(t['name']),
                                  selected: topic == t['id'],
                                  onSelected: (_) =>
                                      setState(() => topic = t['id']),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                    if (widget.mode == 'practice') ...[
                      const SizedBox(height: 24),
                      ArenaCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Practise with a timer'),
                          subtitle: const Text(
                            'Turn off for a more relaxed session',
                          ),
                          value: timed,
                          onChanged: (value) => setState(() => timed = value),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                decoration: BoxDecoration(
                  color: context.tokens.card,
                  border: Border(top: BorderSide(color: context.tokens.line)),
                ),
                child: PrimaryButton(
                  label: widget.mode == 'battle'
                      ? 'Find my opponent'
                      : 'Start practice',
                  icon: widget.mode == 'battle'
                      ? Icons.bolt_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: start,
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _SubjectChoice extends StatelessWidget {
  const _SubjectChoice({
    required this.category,
    required this.selected,
    required this.onTap,
  });
  final QuizCategory category;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      selected: selected,
      child: ListTile(
        onTap: onTap,
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: category.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(
              category.icon,
              size: 22,
              color: Theme.of(context).brightness == Brightness.dark
                  ? context.tokens.ink
                  : category.color,
            ),
          ),
        ),
        title: Text(
          category.id == 'mixed' ? 'All subjects' : category.name,
          style: context.type.titleSmall,
        ),
        trailing: Icon(
          selected
              ? Icons.check_circle_rounded
              : Icons.radio_button_off_rounded,
          size: 22,
          color: selected ? primary : context.tokens.muted,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
      ),
    );
  }
}
