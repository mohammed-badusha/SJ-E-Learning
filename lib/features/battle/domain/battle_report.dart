class BattlePlayerStats {
  BattlePlayerStats.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['full_name'] as String? ?? 'Learner',
      score = (json['score'] as num?)?.toInt() ?? 0,
      ratingBefore = (json['rating_before'] ?? json['rating'] ?? 1000) as int,
      ratingAfter = (json['rating_after'] as num?)?.toInt(),
      xp = (json['xp_gained'] as num?)?.toInt() ?? 0,
      result = json['result'] as String?,
      correct = (json['correct'] as num?)?.toInt(),
      wrong = (json['wrong'] as num?)?.toInt(),
      unanswered = (json['unanswered'] as num?)?.toInt(),
      answered = (json['answered'] as num?)?.toInt(),
      accuracy = (json['accuracy'] as num?)?.toDouble(),
      avgResponseMs = (json['avg_response_ms'] as num?)?.toInt(),
      fastestCorrectMs = (json['fastest_correct_ms'] as num?)?.toInt(),
      basePoints = (json['base_points'] as num?)?.toInt(),
      speedBonus = (json['speed_bonus'] as num?)?.toInt();
  final String id, name;
  final int score, ratingBefore, xp;
  final int? ratingAfter,
      correct,
      wrong,
      unanswered,
      answered,
      avgResponseMs,
      fastestCorrectMs,
      basePoints,
      speedBonus;
  final double? accuracy;
  final String? result;
  int get ratingChange => (ratingAfter ?? ratingBefore) - ratingBefore;
}

class BattleReport {
  BattleReport.fromJson(
    Map<String, dynamic> json, {
    required Map<String, dynamic> initialState,
  }) : advanced = json['players'] is List && json['rounds_played'] != null,
       players = ((json['players'] ?? initialState['players']) as List)
           .map((p) => BattlePlayerStats.fromJson(Map<String, dynamic>.from(p)))
           .toList(),
       questions = (json['questions'] as List? ?? [])
           .map((q) => Map<String, dynamic>.from(q))
           .toList(),
       roundsPlayed = (json['rounds_played'] as num?)?.toInt(),
       questionCount =
           (json['question_count'] ?? initialState['question_count'] ?? 0)
               as int,
       durationMs = (json['duration_ms'] as num?)?.toInt(),
       isBot = (json['mode'] ?? initialState['mode']) == 'bot',
       labelBot = (json['label_bots'] ?? initialState['label_bots']) == true;
  final bool advanced, isBot, labelBot;
  final List<BattlePlayerStats> players;
  final List<Map<String, dynamic>> questions;
  final int? roundsPlayed, durationMs;
  final int questionCount;
  BattlePlayerStats player(String id) => players.firstWhere((p) => p.id == id);
  BattlePlayerStats opponent(String id) =>
      players.firstWhere((p) => p.id != id);
  List<int> cumulativeScores({bool opponent = false}) {
    var total = 0;
    return [
      0,
      ...questions.map((q) {
        total +=
            (q[opponent ? 'opponent_points' : 'points'] as num?)?.toInt() ?? 0;
        return total;
      }),
    ];
  }
}

String answerTime(num? milliseconds) =>
    milliseconds == null ? '—' : '${(milliseconds / 1000).toStringAsFixed(1)}s';
String answerAccuracy(num? value) => value == null
    ? '—'
    : '${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}%';
