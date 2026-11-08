import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/audio/audio_controller.dart';
import '../core/theme.dart';

class GameAudioButton extends ConsumerWidget {
  const GameAudioButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioProvider);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) => IconButton(
        tooltip: audio.effectsEnabled || audio.musicEnabled
            ? 'Audio settings'
            : 'Audio muted',
        icon: Icon(
          audio.effectsEnabled || audio.musicEnabled
              ? Icons.volume_up_outlined
              : Icons.volume_off_outlined,
        ),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => const SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24),
              child: AudioSettings(),
            ),
          ),
        ),
      ),
    );
  }
}

class AudioSettings extends ConsumerWidget {
  const AudioSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioProvider);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Game audio', style: context.type.titleLarge),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sound effects'),
            subtitle: const Text('Answers, countdowns and results'),
            value: audio.effectsEnabled,
            onChanged: audio.setEffects,
          ),
          Row(
            children: [
              const Icon(Icons.volume_down_outlined, size: 20),
              Expanded(
                child: Slider(
                  label: '${(audio.effectVolume * 100).round()}%',
                  value: audio.effectVolume,
                  onChanged: audio.effectsEnabled
                      ? audio.setEffectVolume
                      : null,
                ),
              ),
              Text(
                '${(audio.effectVolume * 100).round()}%',
                style: context.type.bodySmall,
              ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Background music'),
            subtitle: const Text('Plays during a quiz; pauses outside the app'),
            value: audio.musicEnabled,
            onChanged: audio.setMusic,
          ),
          Row(
            children: [
              const Icon(Icons.music_note_outlined, size: 20),
              Expanded(
                child: Slider(
                  label: '${(audio.musicLevel * 100).round()}%',
                  value: audio.musicLevel,
                  onChanged: audio.musicEnabled ? audio.setMusicVolume : null,
                ),
              ),
              Text(
                '${(audio.musicLevel * 100).round()}%',
                style: context.type.bodySmall,
              ),
            ],
          ),
          TextButton.icon(
            onPressed: audio.effectsEnabled
                ? () => audio.play(GameCue.correct)
                : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Preview answer sound'),
          ),
          if (audio.unavailable)
            Text(
              'Audio could not play. Check your media volume and try the preview again.',
              style: TextStyle(color: context.tokens.secondary, fontSize: 13),
            ),
        ],
      ),
    );
  }
}
