import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/features/battle/domain/match_heartbeat.dart';

void main() {
  final state = <String, dynamic>{
    'status': 'in_progress',
    'phase': 'question',
    'question_index': 1,
    'answered': ['me'],
    'players': [
      {'id': 'me', 'connected': true},
      {'id': 'rival', 'connected': true},
    ],
  };
  final heartbeat = <String, dynamic>{
    'status': 'in_progress',
    'phase': 'question',
    'question_index': 1,
    'answered_count': 1,
    'opponent_connected': true,
  };

  test('Quiet heartbeat avoids a full match-state download', () {
    expect(matchHeartbeatNeedsRefresh(heartbeat, state, 'me'), isFalse);
  });

  test(
    'Fallback catches missed round, answer, disconnect and finish events',
    () {
      expect(matchHeartbeatNeedsRefresh(heartbeat, null, 'me'), isTrue);
      for (final changed in [
        {...heartbeat, 'phase': 'result'},
        {...heartbeat, 'question_index': 2},
        {...heartbeat, 'answered_count': 2},
        {...heartbeat, 'opponent_connected': false},
        {...heartbeat, 'status': 'completed'},
      ]) {
        expect(matchHeartbeatNeedsRefresh(changed, state, 'me'), isTrue);
      }
    },
  );
}
