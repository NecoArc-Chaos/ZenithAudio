// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../core/utils/logger.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

class AudioService {
  final Map<String, _TrackPlayer> _players = {};
  final Map<String, String> _cachedPaths = {};
  final Set<String> _blobUrls = {};
  bool _isPlaying = false;
  double _masterVolume = 1.0;

  void Function(double position)? onPositionChanged;
  void Function()? onCompleted;

  bool get isPlaying => _isPlaying;

  double get masterVolume => _masterVolume;

  set masterVolume(double v) {
    _masterVolume = v.clamp(0.0, 1.0);
    for (final p in _players.values) {
      p.element.volume = (_masterVolume * p.volume).toDouble();
    }
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

      tp.positionSub = element.onTimeUpdate.listen((_) {
        onPositionChanged?.call(element.currentTime.toDouble());
      });

      tp.endedSub = element.onEnded.listen((_) {
        final allEnded =
            _players.values.every((p) => p.element.ended || p.element.paused);
        if (allEnded) {
          _isPlaying = false;
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
        ..volume = muted ? 0 : (volume * _masterVolume).toDouble();

      await element.onCanPlayThrough.first;
      final tp = _TrackPlayer(element: element, volume: volume);

      tp.positionSub = element.onTimeUpdate.listen((_) {
        onPositionChanged?.call(element.currentTime.toDouble());
      });
      tp.endedSub = element.onEnded.listen((_) {
        _players.remove(trackId);
        if (_players.isEmpty) {
          _isPlaying = false;
          onCompleted?.call();
        }
      });

      _players[trackId] = tp;
      if (path.startsWith('blob:')) {
        _blobUrls.add(path);
      }
    } catch (e) {
      AppLogger.e('loadTrackFromPath failed: $e');
    }
  }

  Future<String?> prepareInstrumentTrack(Track track,
      {bool useIsolate = false}) async {
    if (track.type == TrackType.audio) return track.audioFilePath;
    if (track.instrumentName == null || track.notes.isEmpty) return null;
    return _cachedPaths[track.id]; // Web: no offline WAV gen
  }

  Stream<double> prepareTracks(List<Track> tracks,
      {String? skipTrackId, bool useIsolate = false}) async* {
    yield 1.0;
  }

  void setMute(String trackId, bool muted) {
    final tp = _players[trackId];
    if (tp != null) {
      tp.element.volume = muted ? 0 : (tp.volume * _masterVolume).toDouble();
    }
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
      tp.element.volume = (volume * _masterVolume).toDouble();
    }
  }

  void updateMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    for (final p in _players.values) {
      p.element.volume = (p.volume * _masterVolume).toDouble();
    }
  }

  Future<void> play() async {
    if (_players.isEmpty) return;
    _isPlaying = true;
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
    _isPlaying = false;
    for (final p in _players.values) {
      p.element.pause();
    }
  }

  Future<void> stop() async {
    _isPlaying = false;
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
      _revokeBlobUrl(tp.element.src);
      tp.element.removeAttribute('src');
      tp.element.load();
    }
  }

  Future<void> unloadAll() async {
    for (final p in _players.values) {
      p.positionSub?.cancel();
      p.endedSub?.cancel();
      p.element.pause();
      _revokeBlobUrl(p.element.src);
      p.element.removeAttribute('src');
      p.element.load();
    }
    _players.clear();
    _isPlaying = false;
  }

  void _revokeBlobUrl(String? url) {
    if (url != null && url.startsWith('blob:')) {
      try {
        html.Url.revokeObjectUrl(url);
        _blobUrls.remove(url);
      } catch (_) {}
    }
  }

  void dispose() {
    unloadAll();
    // Revoke any remaining tracked blob URLs.
    for (final url in _blobUrls) {
      try {
        html.Url.revokeObjectUrl(url);
      } catch (_) {}
    }
    _blobUrls.clear();
  }

  String? getCachedTrackPath(String trackId) => _cachedPaths[trackId];

  bool isTrackCached(Track track) {
    if (track.type == TrackType.audio) return track.audioFilePath != null;
    return _cachedPaths.containsKey(track.id);
  }
}

class _TrackPlayer {
  final html.AudioElement element;
  double volume;
  StreamSubscription<html.Event>? positionSub;
  StreamSubscription<html.Event>? endedSub;

  _TrackPlayer({required this.element, required this.volume});
}
