import 'dart:async';

/// A voice belongs to one cue until the decoder reports completion.
abstract class CueVoice {
  Stream<void> get completed;
  Future<void> play(String asset, double volume);
  Future<void> stop();
  Future<void> dispose();
}

class CueMixer {
  CueMixer({required this.createVoice, this.maxVoices = 8});
  final CueVoice Function() createVoice;
  final int maxVoices;
  final _voices = <CueVoice, StreamSubscription<void>>{};
  final _activity = StreamController<int>.broadcast(sync: true);
  final _cleaning = <Future<void>>{};
  bool _closed = false;
  Stream<int> get activity => _activity.stream;

  Future<void> play(String asset, double volume) async {
    // Under overload, skip a new cue rather than cut an audible one short.
    if (_closed || _voices.length >= maxVoices) return;
    final voice = createVoice();
    _voices[voice] = voice.completed.listen(
      (_) => _release(voice),
      onError: (Object _, StackTrace __) => _release(voice, stop: true),
    );
    _activity.add(_voices.length);
    try {
      await voice.play(asset, volume);
    } catch (_) {
      await _release(voice);
      rethrow;
    }
  }

  Future<void> _release(CueVoice voice, {bool stop = false}) {
    final subscription = _voices.remove(voice);
    if (subscription == null) return Future.value();
    _activity.add(_voices.length);
    final cleanup = () async {
      await subscription.cancel();
      try {
        if (stop) await voice.stop();
      } finally {
        await voice.dispose();
      }
    }();
    _cleaning.add(cleanup);
    // Cleanup errors must not become unhandled stream-callback exceptions.
    unawaited(
      cleanup.then(
        (_) => _cleaning.remove(cleanup),
        onError: (Object _, StackTrace __) => _cleaning.remove(cleanup),
      ),
    );
    return cleanup;
  }

  Future<void> stop() async {
    await Future.wait(
      _voices.keys.toList().map((v) => _release(v, stop: true)),
    );
    await Future.wait(_cleaning.toList());
  }

  Future<void> close() async {
    _closed = true;
    await stop();
    await _activity.close();
  }
}
