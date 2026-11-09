import 'package:flutter/material.dart';
import '../../auth/data/session.dart';

class QuizCategory {
  const QuizCategory(this.id, this.name, this.slug, this.color, this.icon);
  final String id, name, slug;
  final Color color;
  final IconData icon;
  factory QuizCategory.fromJson(Map<String, dynamic> json) => QuizCategory(
    json['id'],
    json['name'],
    json['slug'],
    Color(
      int.parse(
        'FF${(json['color_hex'] as String).replaceAll('#', '')}',
        radix: 16,
      ),
    ),
    categoryIcon(json['icon'] as String? ?? json['slug']),
  );
}

IconData categoryIcon(String value) => switch (value) {
  'quant' || 'calculate' => Icons.calculate_outlined,
  'english' || 'translate' => Icons.translate_rounded,
  'reasoning' || 'psychology' => Icons.psychology_outlined,
  'general-awareness' || 'public' => Icons.public_outlined,
  _ => Icons.shuffle_rounded,
};
const previewCategories = [
  QuizCategory(
    'quant',
    'Quantitative Aptitude',
    'quant',
    Color(0xFF376BD6),
    Icons.calculate_outlined,
  ),
  QuizCategory(
    'english',
    'English',
    'english',
    Color(0xFF087E83),
    Icons.translate_rounded,
  ),
  QuizCategory(
    'reasoning',
    'Reasoning',
    'reasoning',
    Color(0xFF8051C5),
    Icons.psychology_outlined,
  ),
  QuizCategory(
    'awareness',
    'General Awareness',
    'general-awareness',
    Color(0xFFB66A13),
    Icons.public_outlined,
  ),
];
const mixedCategory = QuizCategory(
  'mixed',
  'Mixed',
  'mixed',
  Color(0xFF5B4CFF),
  Icons.shuffle_rounded,
);

class QuizRepository {
  QuizRepository(this.session);
  final SessionController session;
  Future<List<QuizCategory>> categories() async {
    if (session.preview) return previewCategories;
    final rows = await session.client!
        .from('categories')
        .select('id,name,slug,color_hex,icon')
        .eq('is_active', true)
        .order('sort_order');
    return rows.map(QuizCategory.fromJson).toList();
  }

  Future<List<Map<String, dynamic>>> subtopics(String id) async {
    if (session.preview) {
      return [
        {'id': 'sample', 'name': 'All exam topics'},
      ];
    }
    return session.client!
        .from('subtopics')
        .select('id,name,topic_group')
        .eq('category_id', id)
        .eq('is_active', true)
        .order('sort_order');
  }

  Future<Map<String, dynamic>> rpc(
    String name, [
    Map<String, dynamic>? params,
  ]) async => Map<String, dynamic>.from(
    await session.client!.rpc(name, params: params),
  );
}

// These answers ship ONLY for the explicitly labelled, unrated local preview.
// Production questions and answer keys are fetched separately through guarded RPCs.
const previewQuestions = [
  {
    'question_text':
        'A number is increased by 20% and then decreased by 20%. What is the net change?',
    'options': [
      {'id': 'a', 'option_text': 'No change'},
      {'id': 'b', 'option_text': '4% decrease'},
      {'id': 'c', 'option_text': '4% increase'},
      {'id': 'd', 'option_text': '2% decrease'},
    ],
    'correct_option_id': 'b',
    'explanation':
        'Start with 100. After a 20% increase it becomes 120. A 20% decrease gives 96: a net decrease of 4%.',
    'time_limit_seconds': 15,
  },
  {
    'question_text': 'Choose the word closest in meaning to “resilient”.',
    'options': [
      {'id': 'a', 'option_text': 'Adaptable'},
      {'id': 'b', 'option_text': 'Fragile'},
      {'id': 'c', 'option_text': 'Indifferent'},
      {'id': 'd', 'option_text': 'Reluctant'},
    ],
    'correct_option_id': 'a',
    'explanation':
        'Resilient means able to recover from difficulties. “Adaptable” is the closest of these choices.',
    'time_limit_seconds': 15,
  },
  {
    'question_text':
        'Find the next number in the sequence: 2, 6, 12, 20, 30, …',
    'options': [
      {'id': 'a', 'option_text': '36'},
      {'id': 'b', 'option_text': '40'},
      {'id': 'c', 'option_text': '42'},
      {'id': 'd', 'option_text': '44'},
    ],
    'correct_option_id': 'c',
    'explanation':
        'The differences are 4, 6, 8, 10. The next difference is 12, so 30 + 12 = 42.',
    'time_limit_seconds': 15,
  },
  {
    'question_text':
        'Which part of the Indian Constitution contains the Fundamental Rights?',
    'options': [
      {'id': 'a', 'option_text': 'Part I'},
      {'id': 'b', 'option_text': 'Part II'},
      {'id': 'c', 'option_text': 'Part III'},
      {'id': 'd', 'option_text': 'Part IV'},
    ],
    'correct_option_id': 'c',
    'explanation':
        'Fundamental Rights are described in Part III (Articles 12–35) of the Indian Constitution.',
    'time_limit_seconds': 15,
  },
  {
    'question_text':
        'If 6 people finish a task in 12 days, how long would 9 people take at the same rate?',
    'options': [
      {'id': 'a', 'option_text': '6 days'},
      {'id': 'b', 'option_text': '8 days'},
      {'id': 'c', 'option_text': '9 days'},
      {'id': 'd', 'option_text': '18 days'},
    ],
    'correct_option_id': 'b',
    'explanation':
        'Total work = 6 × 12 = 72 person-days. With 9 people, the work takes 72 ÷ 9 = 8 days.',
    'time_limit_seconds': 15,
  },
];

int previewScore({
  required bool correct,
  required int remainingMs,
  required int durationMs,
  bool finalRound = false,
}) => correct
    ? (10 + (10 * (remainingMs / durationMs).clamp(0, 1)).floor()) *
          (finalRound ? 2 : 1)
    : 0;
