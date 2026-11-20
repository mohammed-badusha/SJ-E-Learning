import 'dart:math' as math;

/// Display-only mirror of the server's cumulative XP thresholds.
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.earnedInLevel,
    required this.requiredForNext,
  });

  final int level;
  final int earnedInLevel;
  final int requiredForNext;

  double get fraction => earnedInLevel / requiredForNext;

  static int thresholdForLevel(int level) {
    final completed = math.max(level - 1, 0);
    return 25 * completed * (completed + 3);
  }

  factory LevelProgress.fromTotalXp(int totalXp) {
    final xp = math.max(totalXp, 0);
    var level = 1 + ((math.sqrt(9 + 4 * xp / 25) - 3) / 2).floor();
    // Keep boundary values exact after the floating-point estimate.
    while (thresholdForLevel(level + 1) <= xp) {
      level++;
    }
    while (thresholdForLevel(level) > xp) {
      level--;
    }
    return LevelProgress(
      level: level,
      earnedInLevel: xp - thresholdForLevel(level),
      requiredForNext: 100 + 50 * (level - 1),
    );
  }
}
