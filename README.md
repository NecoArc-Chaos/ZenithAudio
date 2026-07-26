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

### Android Release Signing

Copy `android/key.properties.example` to `android/key.properties` and fill in your keystore details:

```properties
storeFile=/path/to/your/upload-keystore.jks
storePassword=your-keystore-password
keyAlias=your-key-alias
keyPassword=your-key-password
```

Then build a release APK:

```bash
flutter build apk --release
```

For more release build options, see `.github/workflows/build.yml`.

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
