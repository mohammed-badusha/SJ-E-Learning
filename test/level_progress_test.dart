import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/features/profile/domain/level_progress.dart';

void main() {
  test('Balanced levels use cumulative 100, 250, 450, 700 XP thresholds', () {
    for (final (xp, level, progress, required) in [
      (0, 1, 0, 100),
      (99, 1, 99, 100),
      (100, 2, 0, 150),
      (249, 2, 149, 150),
      (250, 3, 0, 200),
      (449, 3, 199, 200),
      (450, 4, 0, 250),
      (700, 5, 0, 300),
    ]) {
      final value = LevelProgress.fromTotalXp(xp);
      expect(value.level, level);
      expect(value.earnedInLevel, progress);
      expect(value.requiredForNext, required);
      expect(value.fraction, progress / required);
    }
  });
}
