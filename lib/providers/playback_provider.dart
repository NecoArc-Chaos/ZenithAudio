import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/audio_service.dart';
import 'project_provider.dart';
import 'settings_provider.dart';

enum PlaybackState { stopped, playing, paused }

final playbackProvider = NotifierProvider<PlaybackNotifier, PlaybackState>(
  PlaybackNotifier.new,
);

final playheadPositionProvider = StateProvider<double>((ref) => 0);

final currentStepProvider = StateProvider<int>((ref) => -1);

final masterVolumeProvider = StateProvider<double>((ref) => 0.8);

final pixelsPerSecondProvider = StateProvider<double>((ref) => 50.0);

/// WAV generation progress (0.0 – 1.0). Resets to 0 on each play().
final wavGenerationProgressProvider = StateProvider<double>((ref) => 0.0);

class PlaybackNotifier extends Notifier<PlaybackState> {
  @override
  PlaybackState build() {
    final audio = ref.read(audioServiceProvider);
    audio.onPositionChanged = (pos) {
      ref.read(playheadPositionProvider.notifier).state = pos;
      final project = ref.read(projectProvider);
      final bpm = project.bpm;
      final stepsPerBeat = AppConstants.stepsPerBeat;
      final secondsPerStep = 60.0 / bpm / stepsPerBeat;
      final step = (pos / secondsPerStep).floor() % 16;
      ref.read(currentStepProvider.notifier).state = step;
    };
    audio.onCompleted = () {
      final settings = ref.read(settingsProvider);
      if (settings.autoLoop) {
        _restart();
      } else {
        state = PlaybackState.stopped;
        ref.read(playheadPositionProvider.notifier).state = 0;
      }
    };
    return PlaybackState.stopped;
  }

  Future<void> _restart() async {
    await ref.read(audioServiceProvider).seekTo(0);
    ref.read(playheadPositionProvider.notifier).state = 0;
    await ref.read(audioServiceProvider).play();
    state = PlaybackState.playing;
  }

  /// Start playback of all tracks.
  ///
  /// Only loads tracks that should actually play under current solo/mute
  /// state. Inactive tracks stay unloaded to save memory.
  Future<void> play({String? editingTrackId}) async {
    final audio = ref.read(audioServiceProvider);
    final project = ref.read(projectProvider);

    ref.read(wavGenerationProgressProvider.notifier).state = 0.0;

    // Unload tracks that no longer exist in the project.
    final activeIds = project.tracks.map((t) => t.id).toSet();
    for (final id in List.from(audio.cachedTrackIds)) {
      if (!activeIds.contains(id)) {
        await audio.unloadTrack(id);
      }
    }

    // Determine which tracks should play (solo/mute aware).
    final hasSolo = project.hasSoloTrack;
    final tracksToPlay = project.tracks.where((t) {
      if (hasSolo) return t.isSolo;
      return !t.isMuted;
    }).toList();

    // Load only tracks that need to play.
    final needsLoad = <Track>[];
    for (final track in tracksToPlay) {
      if (!audio.isTrackLoaded(track.id)) {
        needsLoad.add(track);
      }
    }

    // 1. Load missing audio tracks immediately (no WAV gen needed)
    for (final track in needsLoad) {
      if (track.type == TrackType.audio) {
        if (track.audioFilePath != null && File(track.audioFilePath!).existsSync()) {
          await audio.loadTrackFromPath(
            track.id,
            track.audioFilePath!,
            volume: track.volume,
          );
        }
      }
    }

    // 2. Prepare instrument tracks that need loading
    final instTracks = needsLoad
        .where((t) => t.type == TrackType.instrument &&
            t.instrumentName != null && t.notes.isNotEmpty)
        .toList();

    // Separate editing track from others
    final editingTrack = editingTrackId != null
        ? instTracks.where((t) => t.id == editingTrackId).firstOrNull
        : null;
    final otherTracks = instTracks.where((t) => t.id != editingTrackId).toList();

    // Prepare editing track WAV on background isolate (non-blocking)
    final Future<String?> editingFuture;
    if (editingTrack != null) {
      editingFuture = audio.prepareInstrumentTrack(editingTrack, useIsolate: true);
    } else {
      editingFuture = Future.value(null);
    }

    // Prepare other tracks with progress
    int done = 0;
    final total = otherTracks.length;
    for (final track in otherTracks) {
      final path = await audio.prepareInstrumentTrack(track);
      if (path != null) {
        await audio.loadTrackFromPath(
          track.id,
          path,
          volume: track.volume,
        );
      }
      done++;
      ref.read(wavGenerationProgressProvider.notifier).state =
          total > 0 ? done / total : 1.0;
    }

    // Wait for editing track's WAV
    final editingPath = await editingFuture;
    if (editingPath != null && editingTrack != null) {
      await audio.loadTrackFromPath(
        editingTrack.id,
        editingPath,
        volume: editingTrack.volume,
      );
    }

    // 3. Apply solo/mute state to all loaded tracks
    for (final t in tracksToPlay) {
      audio.updateTrackVolume(t.id, t.volume);
      audio.setTrackMute(t.id, t.isMuted);
      audio.setTrackSolo(t.id, t.isSolo);
    }

    ref.read(wavGenerationProgressProvider.notifier).state = 1.0;
    audio.setPlaybackSpeed(project.playbackSpeed);
    await audio.play();
    state = PlaybackState.playing;
  }

  Future<void> pause() async {
    await ref.read(audioServiceProvider).pause();
    state = PlaybackState.paused;
  }

  Future<void> stop() async {
    await ref.read(audioServiceProvider).stop();
    ref.read(playheadPositionProvider.notifier).state = 0;
    state = PlaybackState.stopped;
  }

  /// Prefetch tracks that are likely to be played soon (e.g., after
  /// a solo/mute toggle). Does not block playback.
  Future<void> prefetchTracks(List<Track> tracks) async {
    final audio = ref.read(audioServiceProvider);
    final toLoad = tracks.where((t) => !audio.isTrackLoaded(t.id)).toList();
    if (toLoad.isEmpty) return;

    for (final track in toLoad) {
      if (track.type == TrackType.audio) {
        if (track.audioFilePath != null && File(track.audioFilePath!).existsSync()) {
          await audio.loadTrackFromPath(
            track.id,
            track.audioFilePath!,
            volume: track.volume,
          );
        }
      }
    }

    final instTracks = toLoad
        .where((t) => t.type == TrackType.instrument &&
            t.instrumentName != null && t.notes.isNotEmpty)
        .toList();
    for (final track in instTracks) {
      final path = await audio.prepareInstrumentTrack(track);
      if (path != null) {
        await audio.loadTrackFromPath(track.id, path, volume: track.volume);
      }
    }
  }

  /// Release tracks that are not currently playing and have been inactive
  /// the longest. Called when playback stops to free memory.
  Future<void> releaseInactiveTracks({int keepCount = 8}) async {
    final audio = ref.read(audioServiceProvider);
    final loadedIds = audio.cachedTrackIds.toList();
    if (loadedIds.length <= keepCount) return;

    // Keep the most recently used tracks.
    final entries = loadedIds.map((id) {
      final usage = audio.getTrackLastUsed(id);
      return MapEntry(id, usage);
    }).toList();
    entries.sort((a, b) => a.value.compareTo(b.value));

    final toRelease = entries.take(entries.length - keepCount).map((e) => e.key).toList();
    for (final id in toRelease) {
      await audio.unloadTrack(id);
    }
  }

  Future<void> toggle({String? editingTrackId}) async {
    if (state == PlaybackState.playing) {
      await pause();
    } else {
      await play(editingTrackId: editingTrackId);
    }
  }

  Future<void> seekTo(double seconds) async {
    await ref.read(audioServiceProvider).seekTo(seconds);
    ref.read(playheadPositionProvider.notifier).state = seconds;
  }
}
