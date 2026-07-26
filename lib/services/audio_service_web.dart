import 'dart:async';
import 'dart:html' as html;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../models/instrument.dart';
import '../core/utils/logger.dart';
import 'synth_service.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

class AudioService {
  final Map<String, _TrackPlayer> _players = {};
  final Map<String, String> _cachedPaths = {};
  double _masterVolume = 1.0;

  final Map<String, bool> _trackMutes = {};
  final Map<String, bool> _trackSolos = {};

  void Function(double position)? onPositionChanged;
  void Function()? onCompleted;


  double get masterVolume => _masterVolume;

  set masterVolume(double v) {
    _masterVolume = v.clamp(0.0, 1.0);
    _applyEffectiveVolumes();
  }

  Future<double> loadTrack(Track track) async {
    final audioPath = track.audioFilePath;
    if (audioPath == null) return 0;

    try {
      final element = html.AudioElement()
        ..src = audioPath
        ..preload = 'auto'
        ..volume = (track.volume * _masterVolume).toDouble();

      await element.onCanPlayThrough.first;
      final dur = element.duration.toDouble();

      final tp = _TrackPlayer(element: element, volume: track.volume);
      _trackMutes[track.id] = track.isMuted;
      _trackSolos[track.id] = track.isSolo;

      tp.positionSub = element.onTimeUpdate.listen((_) {
        onPositionChanged?.call(element.currentTime.toDouble());
      });

      tp.endedSub = element.onEnded.listen((_) {
        final allEnded =
            _players.values.every((p) => p.element.ended || p.element.paused);
        if (allEnded) {
          onCompleted?.call();
        }
      });

      _players[track.id] = tp;
      AppLogger.d('loadTrack 时长: ${dur.toStringAsFixed(2)}s');
      return dur;
    } catch (e) {
      AppLogger.e('加载音频失败', e);
      return 0;
    }
  }

  Future<void> loadTrackFromPath(String trackId, String path,
      {double volume = 1.0, bool muted = false}) async {
    unloadTrack(trackId);
    try {
      final element = html.AudioElement()
        ..src = path
        ..preload = 'auto'
        ..volume = (volume * _masterVolume).toDouble();

      await element.onCanPlayThrough.first;
      final tp = _TrackPlayer(element: element, volume: volume);
      _trackMutes[trackId] = muted;
      _trackSolos[trackId] = false;

      tp.positionSub = element.onTimeUpdate.listen((_) {
        onPositionChanged?.call(element.currentTime.toDouble());
      });
      tp.endedSub = element.onEnded.listen((_) {
        _players.remove(trackId);
        if (_players.isEmpty) {
          onCompleted?.call();
        }
      });

      _players[trackId] = tp;
    } catch (e) {
      AppLogger.e('loadTrackFromPath failed: $e');
    }
  }

  Future<String?> prepareInstrumentTrack(Track track,
      {bool useIsolate = false}) async {
    if (track.type == TrackType.audio) return track.audioFilePath;
    if (track.instrumentName == null || track.notes.isEmpty) return null;

    final cached = _cachedPaths[track.id];
    if (cached != null) return cached;

    final synth = SynthService();
    final result = await synth.renderToFile(
      notes: track.notes,
      instrumentName: track.instrumentName!,
    );
    if (result.path.isNotEmpty) {
      _cachedPaths[track.id] = result.path;
    }
    return result.path.isEmpty ? null : result.path;
  }

  Future<_TrackPlayer?> prepareTrack(String trackId, String path) async {
    try {
      final element = html.AudioElement()
        ..src = path
        ..preload = 'auto'
        ..volume = _masterVolume;

      final tp = _TrackPlayer(element: element, volume: 1.0);
      _players[trackId] = tp;
      _trackMutes[trackId] = false;
      _trackSolos[trackId] = false;

      tp.positionSub = element.onTimeUpdate.listen((_) {
        onPositionChanged?.call(element.currentTime.toDouble());
      });
      tp.endedSub = element.onEnded.listen((_) {
        _players.remove(trackId);
        if (_players.isEmpty) {
          onCompleted?.call();
        }
      });

      return tp;
    } catch (e) {
      AppLogger.e('Failed to prepare track $trackId: $path', e);
      return null;
    }
  }

  Stream<double> prepareTracks(List<Track> tracks,
      {String? skipTrackId, bool useIsolate = false}) async* {
    yield 1.0;
  }

  void setPlaybackSpeed(double speed) {
    for (final p in _players.values) {
      p.element.playbackRate = speed;
    }
  }

  void updateTrackVolume(String trackId, double volume) {
    final tp = _players[trackId];
    if (tp != null) {
      tp.volume = volume;
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
      final rawVol = tp.volume;
      final isMuted = _trackMutes[trackId] ?? false;
      final isSolo = _trackSolos[trackId] ?? false;

      double effectiveVol;
      if (hasSolo) {
        effectiveVol = isSolo ? rawVol : 0.0;
      } else {
        effectiveVol = isMuted ? 0.0 : rawVol;
      }

      tp.element.volume = (effectiveVol * _masterVolume).toDouble();
    }
  }

  void updateMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    _applyEffectiveVolumes();
  }

  Future<void> play() async {
    if (_players.isEmpty) return;
    _applyEffectiveVolumes();
    for (final p in _players.values) {
      await p.element.play();
    }
  }

  Future<void> playSingleTrack(String trackId) async {
    final p = _players[trackId];
    if (p != null) {
      await p.element.play();
    }
  }

  Future<void> stopAndUnloadTrack(String trackId) async {
    final p = _players[trackId];
    if (p != null) {
      p.element.pause();
      p.element.currentTime = 0;
    }
    await unloadTrack(trackId);
  }

  Future<void> pause() async {
    for (final p in _players.values) {
      p.element.pause();
    }
  }

  Future<void> stop() async {
    for (final p in _players.values) {
      p.element.pause();
      p.element.currentTime = 0;
    }
  }

  Future<void> seekTo(double seconds) async {
    for (final p in _players.values) {
      p.element.currentTime = seconds;
    }
  }

  Future<void> unloadTrack(String trackId) async {
    final tp = _players.remove(trackId);
    if (tp != null) {
      tp.positionSub?.cancel();
      tp.endedSub?.cancel();
      tp.element.pause();
      tp.element.removeAttribute('src');
      tp.element.load();
    }
    _trackMutes.remove(trackId);
    _trackSolos.remove(trackId);
  }

  Future<void> unloadAll() async {
    for (final p in _players.values) {
      p.positionSub?.cancel();
      p.endedSub?.cancel();
      p.element.pause();
      p.element.removeAttribute('src');
      p.element.load();
    }
    _players.clear();
    _trackMutes.clear();
    _trackSolos.clear();
  }

  String? getCachedTrackPath(String trackId) => _cachedPaths[trackId];

  bool isTrackCached(Track track) {
    if (track.type == TrackType.audio) return track.audioFilePath != null;
    return _cachedPaths.containsKey(track.id);
  }

  void dispose() {
    unloadAll();
  }
}

class _TrackPlayer {
  final html.AudioElement element;
  double volume;
  StreamSubscription<html.Event>? positionSub;
  StreamSubscription<html.Event>? endedSub;

  _TrackPlayer({required this.element, required this.volume});
}
