import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import '../models/instrument.dart';
import '../core/utils/logger.dart';
import 'wav_encoder.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

class _TrackPlayer {
  final Player player;
  StreamSubscription? completedSub;
  StreamSubscription? positionSub;
  StreamSubscription? durationSub;
  bool _disposed = false;
  double trackVolume = 1.0;

  _TrackPlayer(this.player);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    completedSub?.cancel();
    positionSub?.cancel();
    durationSub?.cancel();
    completedSub = null;
    positionSub = null;
    durationSub = null;
    player.stop();
    player.dispose();
  }
}

/// Tracks which instrument WAVs are cached and their note hash.
class _WavCache {
  final String path;
  final int noteHash;
  _WavCache(this.path, this.noteHash);
}

class AudioService {
  final Map<String, _TrackPlayer> _players = {};
  final Map<String, _WavCache> _wavCache = {};
  bool _isPlaying = false;
  double _masterVolume = 1.0;
  double _playbackSpeed = 1.0;
  int _completedTracks = 0;
  int _totalTracks = 0;

  /// Track state for solo/mute logic. These are keyed by trackId and
  /// applied uniformly via [_applyEffectiveVolumes].
  final Map<String, bool> _trackMutes = {};
  final Map<String, bool> _trackSolos = {};

  void Function(double position)? onPositionChanged;
  void Function()? onCompleted;

  bool get isPlaying => _isPlaying;
  double get masterVolume => _masterVolume;

  set masterVolume(double v) {
    _masterVolume = v.clamp(0.0, 1.0);
    _applyEffectiveVolumes();
  }

  DateTime _lastPositionUpdate = DateTime.now();
  static const Duration _positionThrottle = Duration(milliseconds: AppConstants.positionUpdateThrottleMs);

  Future<double> loadTrack(Track track) async {
    if (track.audioFilePath == null) return 0;

    final player = Player();
    final tp = _TrackPlayer(player);
    try {
      final uri = Uri.file(track.audioFilePath!);
      await player.open(Media(uri.toString()), play: false);

      final vol = (track.volume * _masterVolume * 100).roundToDouble();
      await player.setVolume(vol);
      await player.setRate(_playbackSpeed);

      _players[track.id] = tp;
      tp.trackVolume = track.volume;
      _trackMutes[track.id] = track.isMuted;
      _trackSolos[track.id] = track.isSolo;

      tp.completedSub = player.stream.completed.listen((completed) {
        if (tp._disposed) return;
        if (completed) {
          _completedTracks++;
          if (_completedTracks >= _totalTracks) {
            _isPlaying = false;
            onCompleted?.call();
          }
        }
      });

      tp.positionSub = player.stream.position.listen((position) {
        if (tp._disposed) return;
        final now = DateTime.now();
        if (now.difference(_lastPositionUpdate) < _positionThrottle) return;
        _lastPositionUpdate = now;
        onPositionChanged?.call(position.inMilliseconds / 1000.0);
      });

      _totalTracks++;
      double dur = player.state.duration.inMilliseconds / 1000.0;
      if (dur <= 0) {
        try {
          dur = await player.stream.duration
              .firstWhere((d) => d > Duration.zero,
                  orElse: () => Duration.zero)
              .timeout(const Duration(seconds: 5),
                  onTimeout: () => Duration.zero)
              .then((d) => d.inMilliseconds / 1000.0);
        } catch (_) {
          dur = 0;
        }
      }
      AppLogger.d('loadTrack: ${dur.toStringAsFixed(2)}s');
      return dur;
    } catch (e) {
      tp.dispose();
      _players.remove(track.id);
      return 0;
    }
  }

  /// Get or generate a WAV for an instrument track. Returns the file path.
  /// Returns null if track has no instrument or no notes.
  /// If [useIsolate] is true, synthesis runs on a background isolate.
  Future<String?> prepareInstrumentTrack(Track track,
      {bool useIsolate = false}) async {
    if (track.type == TrackType.audio) return track.audioFilePath;
    if (track.instrumentName == null || track.notes.isEmpty) return null;

    final noteHash = Object.hash(track.instrumentName, Object.hashAll(track.notes));
    final cached = _wavCache[track.id];
    if (cached != null && cached.noteHash == noteHash) {
      return cached.path;
    }

    const maxDur = AppConstants.maxInstrumentRenderSeconds.toDouble();
    final dur = track.computedDuration > 0
        ? (track.computedDuration + 0.5).clamp(0, maxDur)
        : 2.0;
    final sampleRate = 44100;

    final Uint8List wav;
    if (useIsolate) {
      final params = <String, dynamic>{
        'notes': track.notes.map((n) => {
          'startTime': n.startTime,
          'duration': n.duration,
          'pitch': n.pitch,
          'velocity': n.velocity,
        }).toList(),
        'instrumentName': track.instrumentName,
        'duration': dur,
        'sampleRate': sampleRate,
      };
      wav = await Isolate.run(() => _synthAndEncodeWav(params));
    } else {
      wav = _synthAndEncodeWav(<String, dynamic>{
        'notes': track.notes.map((n) => {
          'startTime': n.startTime,
          'duration': n.duration,
          'pitch': n.pitch,
          'velocity': n.velocity,
        }).toList(),
        'instrumentName': track.instrumentName,
        'duration': dur,
        'sampleRate': sampleRate,
      });
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/synth_${track.id}.wav';
    await File(filePath).writeAsBytes(wav);

    _wavCache[track.id] = _WavCache(filePath, noteHash);
    return filePath;
  }

  /// Prepare all given tracks (generate WAVs for instrument tracks if needed).
  /// Returns a stream of progress (0.0 – 1.0).
  Stream<double> prepareTracks(List<Track> tracks,
      {String? skipTrackId, bool useIsolate = false}) async* {
    final targets = tracks.where((t) =>
        t.type == TrackType.instrument &&
        t.id != skipTrackId &&
        t.instrumentName != null &&
        t.notes.isNotEmpty);

    int done = 0;
    final total = targets.length;
    if (total == 0) {
      yield 1.0;
      return;
    }

    for (final track in targets) {
      await prepareInstrumentTrack(track, useIsolate: useIsolate);
      done++;
      yield done / total;
    }
  }

  /// Load all given tracks into players and volume them according to
  /// their settings and master volume.
  Future<void> loadTracks(List<Track> tracks, {String? skipTrackId}) async {
    await unloadAll();
    for (final track in tracks) {
      if (track.id == skipTrackId) continue;
      final path = track.type == TrackType.audio
          ? track.audioFilePath
          : _wavCache[track.id]?.path;
      if (path == null || path.isEmpty) continue;
      if (!File(path).existsSync()) continue;

      final player = Player();
      final tp = _TrackPlayer(player);
      try {
        await player.open(Media(Uri.file(path).toString()), play: false);
        final vol = (track.volume * _masterVolume * 100).roundToDouble();
        await player.setVolume(track.isMuted ? 0 : vol);
        await player.setRate(_playbackSpeed);
        _players[track.id] = tp;
        tp.trackVolume = track.volume;
        _trackMutes[track.id] = track.isMuted;
        _trackSolos[track.id] = track.isSolo;
      } catch (e) {
        tp.dispose();
      }
    }
  }

  /// Load a single track from a file path with given raw volume and mute state.
  Future<void> loadTrackFromPath(String trackId, String path,
      {double volume = 1.0, bool muted = false}) async {
    await unloadTrack(trackId);
    final player = Player();
    final tp = _TrackPlayer(player);
    try {
      await player.open(Media(Uri.file(path).toString()), play: false);
      await player.setVolume((volume * _masterVolume * 100).roundToDouble());
      await player.setRate(_playbackSpeed);
      _players[trackId] = tp;
      tp.trackVolume = volume;
      _trackMutes[trackId] = muted;
      _trackSolos[trackId] = false;

      tp.completedSub = player.stream.completed.listen((completed) {
        if (tp._disposed) return;
        if (completed) {
          _completedTracks++;
          if (_completedTracks >= _totalTracks) {
            _isPlaying = false;
            onCompleted?.call();
          }
        }
      });

      tp.positionSub = player.stream.position.listen((position) {
        if (tp._disposed) return;
        final now = DateTime.now();
        if (now.difference(_lastPositionUpdate) < _positionThrottle) return;
        _lastPositionUpdate = now;
        onPositionChanged?.call(position.inMilliseconds / 1000.0);
      });
      _totalTracks++;
    } catch (e) {
      tp.dispose();
    }
  }

  /// Returns the cached WAV path for a track, or null if not cached.
  Set<String> get cachedTrackIds => Set.from(_wavCache.keys);
  String? getCachedTrackPath(String trackId) => _wavCache[trackId]?.path;

  /// Check if track WAV is cached with current notes.
  bool isTrackCached(Track track) {
    if (track.type == TrackType.audio) return track.audioFilePath != null;
    final cached = _wavCache[track.id];
    if (cached == null) return false;
    final noteHash = Object.hash(track.instrumentName, Object.hashAll(track.notes));
    return cached.noteHash == noteHash;
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed;
    for (final tp in _players.values) {
      tp.player.setRate(speed);
    }
  }

  void updateMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    _applyEffectiveVolumes();
  }

  void updateTrackVolume(String trackId, double volume) {
    final tp = _players[trackId];
    if (tp != null) {
      tp.trackVolume = volume;
    }
    _applyEffectiveVolumes();
  }

  void setTrackMute(String trackId, bool muted) {
    _trackMutes[trackId] = muted;
    _applyEffectiveVolumes();
  }

  void setTrackSolo(String trackId, bool solo) {
    _trackSolos[trackId] = solo;
    _applyEffectiveVolumes();
  }

  void _applyEffectiveVolumes() {
    final hasSolo = _trackSolos.values.any((s) => s);
    for (final entry in _players.entries) {
      final trackId = entry.key;
      final tp = entry.value;
      if (tp._disposed) continue;

      final rawVol = tp.trackVolume;
      final isMuted = _trackMutes[trackId] ?? false;
      final isSolo = _trackSolos[trackId] ?? false;

      double effectiveVol;
      if (hasSolo) {
        effectiveVol = isSolo ? rawVol : 0.0;
      } else {
        effectiveVol = isMuted ? 0.0 : rawVol;
      }

      tp.player.setVolume((effectiveVol * _masterVolume * 100).roundToDouble());
    }
  }

  Future<void> play() async {
    if (_players.isEmpty) return;
    _isPlaying = true;
    _completedTracks = 0;
    _totalTracks = _players.length;
    _applyEffectiveVolumes();
    await Future.wait(_players.values.map((tp) {
      if (tp._disposed) return Future.value();
      return tp.player.play();
    }));
  }

  /// Play a single track without affecting other tracks' state.
  Future<void> playSingleTrack(String trackId) async {
    final tp = _players[trackId];
    if (tp != null && !tp._disposed) {
      tp.player.play();
    }
  }

  /// Stop and unload a single track.
  Future<void> stopAndUnloadTrack(String trackId) async {
    final tp = _players[trackId];
    if (tp != null && !tp._disposed) {
      tp.player.stop();
    }
    await unloadTrack(trackId);
  }

  Future<void> pause() async {
    _isPlaying = false;
    for (final tp in _players.values) {
      if (!tp._disposed) tp.player.pause();
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
    for (final tp in _players.values) {
      if (!tp._disposed) tp.player.stop();
    }
  }

  Future<void> seekTo(double seconds) async {
    final duration = Duration(milliseconds: (seconds * 1000).round());
    await Future.wait(_players.values.map((tp) {
      if (tp._disposed) return Future.value();
      return tp.player.seek(duration);
    }));
  }

  Future<void> unloadTrack(String trackId) async {
    final tp = _players.remove(trackId);
    tp?.dispose();
    _trackMutes.remove(trackId);
    _trackSolos.remove(trackId);
  }

  Future<void> unloadAll() async {
    for (final tp in _players.values) {
      tp.dispose();
    }
    _players.clear();
    _trackMutes.clear();
    _trackSolos.clear();
    _isPlaying = false;
    _completedTracks = 0;
    _totalTracks = 0;
  }

  Future<void> dispose() async {
    await unloadAll();
    _wavCache.clear();
  }
}

// ── Top-level WAV synthesis (usable with Flutter.compute) ──

/// Top-level synth + encode function for use with [compute].
/// [params] must contain 'notes', 'instrumentName', 'duration', 'sampleRate'.
Uint8List _synthAndEncodeWav(Map<String, dynamic> params) {
  final notesData = params['notes'] as List<dynamic>;
  final instrumentName = params['instrumentName'] as String;
  final duration = (params['duration'] as num).toDouble();
  final sampleRate = params['sampleRate'] as int;

  final inst = InstrumentPreset.fromId(instrumentName);
  final numSamples = (sampleRate * duration).ceil();
  final buffer = Float64List(numSamples);

  for (final nd in notesData) {
    final noteMap = nd as Map<String, dynamic>;
    final startTime = (noteMap['startTime'] as num).toDouble();
    final noteDuration = (noteMap['duration'] as num).toDouble();
    final pitch = noteMap['pitch'] as int;
    final velocity = noteMap['velocity'] as int;

    final startSample = (startTime * sampleRate).round();
    final durSamples = (noteDuration * sampleRate).round();
    final endSample = (startSample + durSamples).clamp(0, numSamples);
    final freq = 440 * pow(2, (pitch - 69) / 12).toDouble();
    for (int i = startSample; i < endSample; i++) {
      final t = (i - startSample) / sampleRate;
      final env = inst.getEnvelope(t, noteDuration, velocity);
      buffer[i] += inst.synthSample(t, freq, velocity) * env;
    }
  }

  double maxAmp = 0;
  for (final s in buffer) {
    final a = s.abs();
    if (a > maxAmp) maxAmp = a;
  }
  if (maxAmp > 0 && maxAmp > 0.95) {
    final scale = 0.95 / maxAmp;
    for (int i = 0; i < buffer.length; i++) buffer[i] *= scale;
  }

  return WavEncoder.encode(buffer, numSamples, sampleRate);
}
