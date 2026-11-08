import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/core/audio/cue_mixer.dart';

class _Voice implements CueVoice {
  final events = StreamController<void>.broadcast(sync: true);
  bool stopped = false, disposed = false;
  String? asset;
  @override
  Stream<void> get completed => events.stream;
  @override
  Future<void> play(String source, double volume) async => asset = source;
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async {
    disposed = true;
    await events.close();
  }
}

void main() {
  test(
    'A third cue cannot stop either earlier cue; completion releases its own voice',
    () async {
      final voices = <_Voice>[];
      final mixer = CueMixer(
        createVoice: () {
          final voice = _Voice();
          voices.add(voice);
          return voice;
        },
      );
      final activity = <int>[];
      final subscription = mixer.activity.listen(activity.add);
      await mixer.play('final_round', .7);
      await mixer.play('select', .7);
      await mixer.play('correct', .7);
      expect(voices.length, 3);
      expect(voices.every((v) => !v.stopped && !v.disposed), isTrue);
      voices[1].events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(voices[1].disposed, isTrue);
      expect(voices[0].disposed, isFalse);
      expect(voices[2].disposed, isFalse);
      expect(activity, [1, 2, 3, 2]);
      await mixer.close();
      expect(voices[0].stopped, isTrue);
      expect(voices[2].stopped, isTrue);
      expect(voices.every((v) => v.disposed), isTrue);
      await subscription.cancel();
    },
  );

  test(
    'Overload drops a new cue instead of interrupting active audio',
    () async {
      final voices = <_Voice>[];
      final mixer = CueMixer(
        maxVoices: 2,
        createVoice: () {
          final voice = _Voice();
          voices.add(voice);
          return voice;
        },
      );
      await mixer.play('win', .7);
      await mixer.play('correct', .7);
      await mixer.play('tick', .7);
      expect(voices.length, 2);
      expect(voices.every((v) => !v.stopped), isTrue);
      await mixer.close();
    },
  );
}
