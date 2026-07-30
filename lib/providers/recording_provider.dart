import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import '../core/utils/logger.dart';
import '../services/platform_dir.dart';

enum RecordingState { idle, recording, permissionDenied }

final recordingProvider =
    NotifierProvider<RecordingNotifier, RecordingState>(RecordingNotifier.new);

final recordingElapsedProvider = StateProvider<double>((ref) => 0);

class RecordingNotifier extends Notifier<RecordingState> {
  AudioRecorder? _recorder;
  String? _outputPath;
  Timer? _timer;
  DateTime? _startTime;

  @override
  RecordingState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _recorder?.dispose();
    });
    return RecordingState.idle;
  }

  String? get outputPath => _outputPath;

  Future<bool> requestPermission() async {
    final recorder = AudioRecorder();
    final hasPermission = await recorder.hasPermission();
    if (!hasPermission) {
      AppLogger.w('麦克风权限被拒绝');
      state = RecordingState.permissionDenied;
      return false;
    }
    return true;
  }

  Future<String?> startRecording() async {
    if (state == RecordingState.recording) return null;

    final hasPerm = await requestPermission();
    if (!hasPerm) return null;

    _recorder = AudioRecorder();
    final dir = await PlatformDir.getDocumentsPath('ZenithAudio');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _outputPath = '$dir/recording_$timestamp.wav';

    await _recorder!.start(
      RecordConfig(encoder: AudioEncoder.wav),
      path: _outputPath!,
    );

    _startTime = DateTime.now();
    state = RecordingState.recording;
    ref.read(recordingElapsedProvider.notifier).state = 0;

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_startTime != null) {
        final elapsed =
            DateTime.now().difference(_startTime!).inMilliseconds / 1000.0;
        ref.read(recordingElapsedProvider.notifier).state = elapsed;
      }
    });

    AppLogger.i('录音开始: $_outputPath');
    return _outputPath;
  }

  Future<String?> stopRecording() async {
    if (state != RecordingState.recording || _recorder == null) return null;

    _timer?.cancel();
    _timer = null;

    final path = await _recorder!.stop();
    _recorder?.dispose();
    _recorder = null;
    _startTime = null;

    ref.read(recordingElapsedProvider.notifier).state = 0;
    state = RecordingState.idle;

    AppLogger.i('录音结束: $path');
    return path ?? _outputPath;
  }
}
