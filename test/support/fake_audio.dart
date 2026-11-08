import 'dart:async';
import 'package:quiz_arena/core/audio/audio_controller.dart';

class FakeAudioBackend implements AudioBackend {
  final calls = <String>[];
  bool failPlayback = false;
  bool autoCompleteCues = true;
  int activeCues = 0;
  final _activity = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> get cueActivity => _activity.stream;
  @override
  Future<void> playCue(String asset, double volume) async {
    if (failPlayback) throw StateError('Audio unavailable');
    calls.add('cue:$asset');
    _activity.add(++activeCues);
    if (autoCompleteCues) finishCue();
  }

  void finishCue() => _activity.add(--activeCues);

  @override
  Future<void> startMusic(double volume) async => calls.add('music:start');
  @override
  Future<void> resumeMusic(double volume) async => calls.add('music:resume');
  @override
  Future<void> pauseMusic() async => calls.add('music:pause');
  @override
  Future<void> stopMusic() async => calls.add('music:stop');
  @override
  Future<void> musicVolume(double volume) async => calls.add('volume:$volume');
  @override
  Future<void> stopCues() async {
    calls.add('cues:stop');
    activeCues = 0;
    _activity.add(0);
  }

  @override
  Future<void> close() async {
    calls.add('close');
    await _activity.close();
  }
}
