# Game audio

The app plays bundled MP3 assets offline. It never calls ElevenLabs at runtime and never needs an ElevenLabs key on a phone or in a web bundle.

Twelve short original cues and one 30-second instrumental track were generated with the owner's authorised ElevenLabs account. Prompts are recorded in `prompts.json`; provider/model, duration and SHA-256 provenance are in `assets/audio/audio_manifest.json`. The track uses a quiet marimba/electric piano arrangement. Local mastering normalises effects to -19 LUFS and music to -27 LUFS, with brief fades at the loop boundary.

Effects cover selection, correct/wrong answers, the last three seconds, match found, question start, final round, win/loss/draw, tier promotion and timeout. Live correctness cues run only after the server reveals the answer. Stable event IDs prevent repeated polling or broadcasts from replaying a cue.

Music starts only in matchmaking and quiz routes, continues across the matchmaking-to-battle handover, ducks for cues, pauses when the app is inactive, and stops when gameplay ends. Effects and music have independent switches and volume sliders in Settings and the speaker button during gameplay. Preferences persist locally. iOS uses the ambient audio category, respecting silent mode.

## Authoring

Keep `ELEVENLABS_API_KEY` in the ignored root `.env`, never in Flutter configuration. The script generates at most 12 cues and one music track, skips existing files, uses two concurrent requests, and does not retry failed requests automatically.

```sh
python3 tools/audio/generate.py --dry-run
python3 tools/audio/generate.py
```

The raw originals are retained under `assets/audio/raw/` for editing. Flutter's asset declaration bundles only the top-level playable files and manifest. Verify asset inclusion and absence of authoring credentials when preparing a release.

Controller tests cover route ownership, background/resume, independent muting, event deduplication and recovery from a playback failure. Real device listening remains the final check for volume balance and personal preference.
