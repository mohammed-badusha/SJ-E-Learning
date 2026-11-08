import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets.dart';
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
  String selected = 'mixed';
  String? topic;
  bool timed = true;
  @override
  void initState() {
    super.initState();
    load();
    if (Hive.isBoxOpen('preferences')) {
      selected = Hive.box('preferences').get('category', defaultValue: 'mixed');
    }
  }

  void load() =>
      future = QuizRepository(ref.read(sessionProvider)).categories();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.mode == 'battle' ? 'Choose a category' : 'Practice by subject',
      ),
    ),
    body: PageBody(
      maxWidth: 800,
      child: FutureBuilder(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              title: 'Categories couldn’t load',
              message: 'Check your connection and try again.',
              action: OutlinedButton(
                onPressed: () => setState(load),
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) return const SkeletonList();
          final categories = [...snapshot.data!, mixedCategory];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Choose a subject', style: context.type.headlineMedium),
              const SizedBox(height: 8),
              Text(
                widget.mode == 'battle'
                    ? 'Select a category for your next battle'
                    : 'Practise with explanations at your own pace',
                style: TextStyle(color: context.tokens.muted),
              ),
              const SizedBox(height: 24),
              ...categories.map(
                (category) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    selected: selected == category.id,
                    child: Material(
                      color: selected == category.id
                          ? context.tokens.raised
                          : context.tokens.card,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            selected = category.id;
                            topic = null;
                          });
                          if (Hive.isBoxOpen('preferences')) {
                            Hive.box('preferences').put('category', selected);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected == category.id
                                  ? Theme.of(context).colorScheme.primary
                                  : context.tokens.line,
                              width: selected == category.id ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 24,
                                child: Icon(
                                  category.icon,
                                  color: context.tokens.secondary,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: category.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  category.name,
                                  style: context.type.titleMedium,
                                ),
                              ),
                              Icon(
                                selected == category.id
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected == category.id
                                    ? Theme.of(context).colorScheme.primary
                                    : context.tokens.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (selected != 'mixed')
                FutureBuilder(
                  future: QuizRepository(
                    ref.read(sessionProvider),
                  ).subtopics(selected),
                  builder: (context, snapshot) => Wrap(
                    spacing: 8,
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
                          onSelected: (_) => setState(() => topic = t['id']),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.mode == 'practice')
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Question timer'),
                  subtitle: const Text(
                    'Turn off the timer for untimed practice',
                  ),
                  value: timed,
                  onChanged: (v) => setState(() => timed = v),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: widget.mode == 'battle'
                    ? 'Find opponent'
                    : 'Start practice',
                icon: widget.mode == 'battle'
                    ? Icons.bolt_rounded
                    : Icons.play_arrow_rounded,
                onPressed: () => context.push(
                  Uri(
                    path: widget.mode == 'battle' ? '/matchmaking' : '/quiz',
                    queryParameters: {
                      'category': selected,
                      'mode': 'practice',
                      'timed': '$timed',
                      if (topic != null) 'subtopic': topic!,
                    },
                  ).toString(),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    ),
  );
}
