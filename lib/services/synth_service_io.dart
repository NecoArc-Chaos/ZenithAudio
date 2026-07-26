import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/instrument.dart';
import '../core/utils/logger.dart';
import 'wav_encoder.dart';

class SynthService {
  static const _sampleRate = 44100;
  static const _uuid = Uuid();

  Future<({String path, double duration})> renderToFile({
    required List<Note> notes,
    required String instrumentName,
  }) async {
    if (notes.isEmpty) {
      AppLogger.w('SynthService: no notes to render');
      return (path: '', duration: 0.0);
    }

    final instrument = InstrumentPreset.fromId(instrumentName);
    final tempDir = await getTemporaryDirectory();
    final totalDuration = _computeDuration(notes);
    final numSamples = (_sampleRate * totalDuration).ceil();

    final buffer = Float64List(numSamples);
    _renderNotes(notes, instrument, buffer, numSamples);
    _normalize(buffer);

    final wavBytes = _encodeWav(buffer, numSamples);
    final filePath = '${tempDir.path}/synth_${_uuid.v4()}.wav';
    await File(filePath).writeAsBytes(wavBytes);

    AppLogger.d('SynthService: rendered ${notes.length} notes to $filePath (${totalDuration.toStringAsFixed(2)}s)');
    return (path: filePath, duration: totalDuration);
  }

  double _computeDuration(List<Note> notes) {
    double end = 0;
    for (final n in notes) {
      final e = n.startTime + n.duration;
      if (e > end) end = e;
    }
    return end + 0.5;
  }

  void _renderNotes(List<Note> notes, InstrumentPreset inst, Float64List buffer, int numSamples) {
    for (final note in notes) {
      final startSample = (note.startTime * _sampleRate).round();
      final durSamples = (note.duration * _sampleRate).round();
      if (startSample >= numSamples) break;

      final endSample = (startSample + durSamples).clamp(0, numSamples);
      final freq = _midiToFreq(note.pitch);

      for (int i = startSample; i < endSample; i++) {
        final t = (i - startSample) / _sampleRate;
        final envelope = inst.getEnvelope(t, note.duration, note.velocity);
        final sample = inst.synthSample(t, freq, note.velocity) * envelope;
        buffer[i] += sample;
      }
    }
  }

  double _midiToFreq(int pitch) => 440 * pow(2, (pitch - 69) / 12).toDouble();

  void _normalize(Float64List buffer) {
    double maxAmp = 0;
    for (final s in buffer) {
      final abs = s.abs();
      if (abs > maxAmp) maxAmp = abs;
    }
    if (maxAmp > 0 && maxAmp > 0.95) {
      final scale = 0.95 / maxAmp;
      for (int i = 0; i < buffer.length; i++) {
        buffer[i] *= scale;
      }
    }
  }

  Uint8List _encodeWav(Float64List buffer, int numSamples) {
    return WavEncoder.encode(buffer, numSamples, _sampleRate);
  }

  /// Render a short preview buffer for a single note at middle C.
  Float64List renderPreview(InstrumentPreset inst, {int pitch = 60, double duration = 1.0, int velocity = 100}) {
    final numSamples = (_sampleRate * duration).ceil();
    final buffer = Float64List(numSamples);
    final freq = _midiToFreq(pitch);

    for (int i = 0; i < numSamples; i++) {
      final t = i / _sampleRate;
      final envelope = inst.getEnvelope(t, duration, velocity);
      final sample = inst.synthSample(t, freq, velocity) * envelope;
      buffer[i] = sample;
    }

    _normalize(buffer);
    return buffer;
  }

  /// Returns WAV bytes for a preview note.
  Uint8List renderPreviewWav(InstrumentPreset inst, {int pitch = 60, double duration = 1.0, int velocity = 100}) {
    final buffer = renderPreview(inst, pitch: pitch, duration: duration, velocity: velocity);
    return _encodeWav(buffer, buffer.length);
  }
}
