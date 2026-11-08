import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

final audioBackendProvider = Provider<AudioBackend>(
  (ref) => DeviceAudioBackend(),
);
final audioProvider = Provider<AudioController>((ref) {
  final controller = AudioController(backend: ref.watch(audioBackendProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

enum GameCue {
  select('select', 500),
  correct('correct', 800),
  wrong('wrong', 650),
  tick('tick', 500),
  matchFound('match_found', 1200),
  questionStart('question_start', 500),
  finalRound('final_round', 1100),
  win('win', 2000),
  loss('loss', 1100),
  draw('draw', 1100),
  levelUp('level_up', 1400),
  timeout('timeout', 700);

  const GameCue(this.file, this.durationMs);
  final String file;
  final int durationMs;
  String get asset => 'audio/$file.mp3';
}

abstract class AudioBackend {
  Future<void> playCue(String asset, double volume);
  Future<void> startMusic(double volume);
  Future<void> resumeMusic(double volume);
  Future<void> pauseMusic();
  Future<void> stopMusic();
  Future<void> musicVolume(double volume);
  Future<void> stopCues();
  Future<void> close();
}

class DeviceAudioBackend implements AudioBackend {
  AudioPlayer? _music;
  final List<AudioPlayer> _cues = [];
  int _next = 0;
  Future<void>? _initializing;
  Future<void> _ready() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    final context = AudioContext(
      android: const AudioContextAndroid(
        usageType: AndroidUsageType.game,
        contentType: AndroidContentType.music,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
      iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
    );
    _music = AudioPlayer();
    await _music!.setAudioContext(context);
    await _music!.setReleaseMode(ReleaseMode.loop);
    for (var i = 0; i < 2; i++) {
      final player = AudioPlayer();
      _cues.add(player);
      await player.setAudioContext(context);
      await player.setReleaseMode(ReleaseMode.stop);
    }
  }

  @override
  Future<void> playCue(String asset, double volume) async {
    await _ready();
    final player = _cues[_next++ % _cues.length];
    await player.stop();
    await player.play(AssetSource(asset), volume: volume);
  }

  @override
  Future<void> startMusic(double volume) async {
    await _ready();
    await _music!.play(AssetSource('audio/music.mp3'), volume: volume);
  }

  @override
  Future<void> resumeMusic(double volume) async {
    await _ready();
    await _music!.setVolume(volume);
    await _music!.resume();
  }

  @override
  Future<void> pauseMusic() async {
    await _music?.pause();
  }

  @override
  Future<void> stopMusic() async {
    await _music?.stop();
  }

  @override
  Future<void> musicVolume(double volume) async {
    await _music?.setVolume(volume);
  }

  @override
  Future<void> stopCues() async {
    for (final player in _cues) {
      await player.stop();
    }
  }

  @override
  Future<void> close() async {
    if (_initializing != null) {
      try {
        await _initializing;
      } catch (_) {}
    }
    for (final player in _cues) {
      await player.dispose();
    }
    await _music?.dispose();
  }
}

/// Audio is presentation only. Correct/wrong cues are triggered after server reveal.
class AudioController extends ChangeNotifier with WidgetsBindingObserver {
  AudioController({required this.backend, this.observeLifecycle = true}) {
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    if (Hive.isBoxOpen('preferences')) {
      final prefs = Hive.box<dynamic>('preferences');
      effectsEnabled = prefs.get('sound_effects', defaultValue: true) as bool;
      musicEnabled = prefs.get('music_enabled', defaultValue: true) as bool;
      effectVolume = (prefs.get('effects_volume', defaultValue: .7) as num)
          .toDouble()
          .clamp(0, 1);
      musicLevel = (prefs.get('music_volume', defaultValue: .22) as num)
          .toDouble()
          .clamp(0, 1);
    }
  }
  final AudioBackend backend;
  final bool observeLifecycle;
  bool effectsEnabled = true, musicEnabled = true, unavailable = false;
  double effectVolume = .7, musicLevel = .22;
  final Set<Object> _owners = {};
  final Set<String> _seen = {};
  bool _foreground = true,
      _closed = false,
      _musicStarted = false,
      _musicPlaying = false;
  Timer? _duckTimer;
  Future<void> _pending = Future.value();
  Future<void> get idle => _pending;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void _save(String key, Object value) {
    if (Hive.isBoxOpen('preferences')) {
      unawaited(Hive.box<dynamic>('preferences').put(key, value));
    }
  }

  void _run(Future<void> Function() operation) {
    if (_closed) return;
    _pending = _pending.then((_) async {
      if (_closed) return;
      try {
        await operation();
        if (unavailable) {
          unavailable = false;
          _notify();
        }
      } catch (_) {
        if (!unavailable) {
          unavailable = true;
          _notify();
        }
        if (kDebugMode) debugPrint('SJ_AUDIO_UNAVAILABLE');
      }
    });
  }

  void enterGame(Object owner) {
    if (_closed) return;
    _owners.add(owner);
    _reconcile();
  }

  void leaveGame(Object owner) {
    _owners.remove(owner);
    _reconcile();
  }

  void _reconcile() {
    _run(() async {
      if (_owners.isEmpty || !musicEnabled) {
        await backend.stopMusic();
        _musicStarted = false;
        _musicPlaying = false;
        return;
      }
      if (!_foreground) {
        await backend.pauseMusic();
        _musicPlaying = false;
        return;
      }
      if (!_musicStarted) {
        await backend.startMusic(musicLevel);
        _musicStarted = true;
        _musicPlaying = true;
      } else if (!_musicPlaying) {
        await backend.resumeMusic(musicLevel);
        _musicPlaying = true;
      }
    });
  }

  void setEffects(bool enabled) {
    effectsEnabled = enabled;
    _save('sound_effects', enabled);
    if (!enabled) _run(backend.stopCues);
    _notify();
  }

  void setMusic(bool enabled) {
    musicEnabled = enabled;
    _save('music_enabled', enabled);
    _reconcile();
    _notify();
  }

  void setEffectVolume(double value) {
    effectVolume = value.clamp(0, 1);
    _save('effects_volume', effectVolume);
    _notify();
  }

  void setMusicVolume(double value) {
    musicLevel = value.clamp(0, 1);
    _save('music_volume', musicLevel);
    if (_musicPlaying) _run(() => backend.musicVolume(musicLevel));
    _notify();
  }

  void play(GameCue cue, {String? eventId}) {
    if (_closed || !_foreground || !effectsEnabled || effectVolume == 0) return;
    if (eventId != null && !_seen.add(eventId)) return;
    if (_seen.length > 256) _seen.remove(_seen.first);
    _run(() async {
      if (!effectsEnabled || !_foreground) return;
      if (_musicPlaying) await backend.musicVolume(musicLevel * .28);
      await backend.playCue(cue.asset, effectVolume);
      _duckTimer?.cancel();
      _duckTimer = Timer(Duration(milliseconds: cue.durationMs + 120), () {
        if (_musicPlaying && musicEnabled && _foreground) {
          _run(() => backend.musicVolume(musicLevel));
        }
      });
    });
  }

  void foreground(bool value) {
    _foreground = value;
    if (!value) {
      _duckTimer?.cancel();
      _run(backend.stopCues);
    }
    _reconcile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      foreground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _duckTimer?.cancel();
    _owners.clear();
    if (observeLifecycle) WidgetsBinding.instance.removeObserver(this);
    unawaited(_pending.then((_) => backend.close()));
    super.dispose();
  }
}
