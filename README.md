# 卓声 ZENITH AUDIO

A cross-platform audio editor and DAW-style music production tool built with Flutter.

## Features

- Multi-track audio editing with waveform view
- Piano roll editor for MIDI/instrument tracks
- Built-in synthesizer with multiple instrument presets
- Real-time audio effects (gain, fade, reverb, delay, EQ, pitch shift, etc.)
- Mixer panel with per-track volume, pan, mute, solo
- Project save/load (.zap format with embedded audio)
- Auto-save and recovery
- Cross-platform: Windows, macOS, Linux, Android, iOS, Web

## Tech Stack

- Flutter 3.x
- Riverpod for state management
- media_kit for audio playback
- Custom WAV synthesis engine
- FFT-based frequency splitting and spectrum filtering

## Building

```bash
flutter pub get
flutter run
```

For release builds, see `.github/workflows/build.yml` for platform-specific steps.

## Project Structure

```
lib/
  models/        - Project, Track, Note, Instrument
  providers/     - Riverpod state management
  screens/       - Top-level screens
  services/      - Audio engine, synthesis, serialization, effects
  widgets/       - Editor UI, mixer, browser, toolbar
```

## License

MIT
