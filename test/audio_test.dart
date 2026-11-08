import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/core/audio/audio_controller.dart';
import 'support/fake_audio.dart';

void main() {
  test(
    'Music stays ducked until every overlapping cue really finishes',
    () async {
      final backend = FakeAudioBackend()..autoCompleteCues = false;
      final audio = AudioController(backend: backend, observeLifecycle: false);
      addTearDown(audio.dispose);
      audio.enterGame('battle');
      await audio.idle;
      audio.play(GameCue.finalRound);
      audio.play(GameCue.select);
      await audio.idle;
      backend.finishCue();
      await audio.idle;
      expect(backend.calls.last, 'volume:${audio.musicLevel * .28}');
      audio.setMusicVolume(.4);
      await audio.idle;
      expect(backend.calls.last, 'volume:${.4 * .28}');
      backend.finishCue();
      await audio.idle;
      expect(backend.calls.last, 'volume:0.4');
    },
  );
  test(
    'Music survives route handover, pauses in background, stops on exit',
    () async {
      final backend = FakeAudioBackend();
      final audio = AudioController(backend: backend, observeLifecycle: false);
      addTearDown(audio.dispose);
      final search = Object(), battle = Object();
      audio.enterGame(search);
      await audio.idle;
      audio.enterGame(battle);
      audio.leaveGame(search);
      await audio.idle;
      expect(backend.calls.where((c) => c == 'music:start').length, 1);
      expect(backend.calls, isNot(contains('music:stop')));
      audio.didChangeAppLifecycleState(AppLifecycleState.paused);
      await audio.idle;
      expect(backend.calls, containsAll(['cues:stop', 'music:pause']));
      audio.play(GameCue.correct);
      await audio.idle;
      expect(backend.calls.where((c) => c.startsWith('cue:')), isEmpty);
      audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await audio.idle;
      expect(backend.calls.last, 'music:resume');
      audio.leaveGame(battle);
      await audio.idle;
      expect(backend.calls.last, 'music:stop');
    },
  );

  test(
    'Reveal events are deduplicated and effects/music mute independently',
    () async {
      final backend = FakeAudioBackend();
      final audio = AudioController(backend: backend, observeLifecycle: false);
      addTearDown(audio.dispose);
      audio.enterGame('quiz');
      await audio.idle;
      audio.play(GameCue.correct, eventId: 'round:1');
      audio.play(GameCue.correct, eventId: 'round:1');
      await audio.idle;
      expect(
        backend.calls.where((c) => c == 'cue:audio/correct.mp3').length,
        1,
      );
      audio.setEffects(false);
      await audio.idle;
      audio.play(GameCue.wrong);
      await audio.idle;
      expect(backend.calls, isNot(contains('cue:audio/wrong.mp3')));
      expect(backend.calls, contains('cues:stop'));
      expect(backend.calls.last, 'volume:${audio.musicLevel}');
      audio.setMusic(false);
      await audio.idle;
      expect(backend.calls.last, 'music:stop');
      audio.setEffects(true);
      audio.play(GameCue.select);
      await audio.idle;
      expect(backend.calls.last, 'cue:audio/select.mp3');
    },
  );

  test('Playback failure is recoverable and never breaks the quiz', () async {
    final backend = FakeAudioBackend()..failPlayback = true;
    final audio = AudioController(backend: backend, observeLifecycle: false);
    addTearDown(audio.dispose);
    audio.play(GameCue.correct);
    await audio.idle;
    expect(audio.unavailable, isTrue);
    backend.failPlayback = false;
    audio.play(GameCue.correct);
    await audio.idle;
    expect(audio.unavailable, isFalse);
    expect(backend.calls.last, 'cue:audio/correct.mp3');
  });
}
