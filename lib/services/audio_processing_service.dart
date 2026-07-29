import 'dart:math';
import 'dart:typed_data';
import 'fft_service.dart';

class AudioProcessingService {
  /// Apply gain in dB (positive = amplify, negative = attenuate).
  static Float64List applyGain(Float64List samples, double gainDB) {
    final factor = pow(10, gainDB / 20).toDouble();
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] * factor;
    }
    return result;
  }

  /// Normalize peak amplitude to [target] (0–1).
  static Float64List normalizePeak(Float64List samples, {double target = 0.95}) {
    double maxAmp = 0;
    for (final s in samples) {
      final a = s.abs();
      if (a > maxAmp) maxAmp = a;
    }
    if (maxAmp <= 0) return Float64List.fromList(samples);
    final scale = target / maxAmp;
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] * scale;
    }
    return result;
  }

  /// Reverse the audio.
  static Float64List reverse(Float64List samples) {
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[samples.length - 1 - i];
    }
    return result;
  }

  /// Linear fade-in over [duration] seconds.
  static Float64List fadeIn(Float64List samples, double duration, int sampleRate) {
    final fadeSamples = (duration * sampleRate).round().clamp(0, samples.length);
    final result = Float64List.fromList(samples);
    for (int i = 0; i < fadeSamples; i++) {
      result[i] *= i / fadeSamples;
    }
    return result;
  }

  /// Linear fade-out over [duration] seconds.
  static Float64List fadeOut(Float64List samples, double duration, int sampleRate) {
    final fadeSamples = (duration * sampleRate).round().clamp(0, samples.length);
    final result = Float64List.fromList(samples);
    final start = samples.length - fadeSamples;
    for (int i = 0; i < fadeSamples; i++) {
      result[start + i] *= (fadeSamples - i) / fadeSamples;
    }
    return result;
  }

  /// Remove DC offset (subtract mean).
  static Float64List removeDCOffset(Float64List samples) {
    double sum = 0;
    for (final s in samples) {
      sum += s;
    }
    final mean = sum / samples.length;
    if (mean.abs() < 1e-10) return Float64List.fromList(samples);
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] - mean;
    }
    return result;
  }

  /// Simple hard-clip distortion.
  static Float64List distort(Float64List samples, double threshold) {
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i].clamp(-threshold, threshold);
    }
    return result;
  }

  /// Simple feedback delay.
  static Float64List delay(Float64List samples, int sampleRate,
      {double delayTime = 0.3, double feedback = 0.4, double mix = 0.5}) {
    final delaySamples = (delayTime * sampleRate).round();
    if (delaySamples <= 0) return Float64List.fromList(samples);
    final result = Float64List(samples.length + delaySamples);
    for (int i = 0; i < samples.length; i++) {
      result[i] += samples[i] * (1 - mix);
      result[i + delaySamples] += samples[i] * mix + result[i] * feedback;
    }
    return Float64List.sublistView(result, 0, samples.length);
  }

  /// Simple Schroeder-style reverb (comb filters + all-pass).
  static Float64List reverb(Float64List samples, int sampleRate,
      {double decay = 0.5, double mix = 0.3}) {
    final combDelays = [0.029, 0.037, 0.047, 0.061];
    final allpassDelays = [0.005, 0.0017];
    final result = Float64List(samples.length);

    for (final cd in combDelays) {
      final dSamples = (cd * sampleRate).round();
      if (dSamples <= 0) continue;
      final comb = Float64List(samples.length);
      for (int i = 0; i < samples.length; i++) {
        comb[i] = samples[i] + (i >= dSamples ? comb[i - dSamples] * decay : 0);
      }
      for (int i = 0; i < samples.length; i++) {
        result[i] += comb[i];
      }
    }
    // Average combs
    for (int i = 0; i < samples.length; i++) {
      result[i] /= combDelays.length;
    }

    // All-pass filters
    for (final ad in allpassDelays) {
      final dSamples = (ad * sampleRate).round();
      if (dSamples <= 0) continue;
      final ap = Float64List(samples.length);
      final gain = 0.7;
      for (int i = 0; i < samples.length; i++) {
        final input = result[i];
        ap[i] = input * -gain + (i >= dSamples ? ap[i - dSamples] : 0);
        result[i] = ap[i] + input * gain;
      }
    }

    // Mix dry/wet
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] * (1 - mix) + result[i] * mix;
    }
    return result;
  }

  // ═══════════════════════════════════════════════════
  //  12 New DSP Effects (WP3)
  // ═══════════════════════════════════════════════════

  /// 1. Compressor/Expander — feed-forward RMS dynamics processor.
  static Float64List dynamicsProcessor(
    Float64List samples, int sampleRate, {
    double threshold = -20,   // dB
    double ratio = 4,         // >1 = compressor, <1 = expander
    double knee = 6,          // dB soft knee
    double attackMs = 5,
    double releaseMs = 100,
    double makeupGain = 0,    // dB
  }) {
    final result = Float64List(samples.length);
    final attack = pow(2, -1000 / (attackMs * sampleRate / 1000));
    final release = pow(2, -1000 / (releaseMs * sampleRate / 1000));
    double envelope = 0;

    for (int i = 0; i < samples.length; i++) {
      final input = samples[i].abs();
      // Attack/release follower
      envelope = input > envelope
          ? attack * (envelope - input) + input
          : release * (envelope - input) + input;

      // dB domain
      final envDb = 20 * log(envelope + 1e-10) / ln10;
      double gainDb = 0;

      if (envDb > threshold - knee / 2) {
        if (knee > 0 && envDb > threshold - knee / 2 && envDb < threshold + knee / 2) {
          // Soft knee
          final x = (envDb - threshold + knee / 2) / knee;
          gainDb = (1 / ratio - 1) * x * x * knee / 2;
        } else {
          gainDb = (threshold - envDb) * (1 - 1 / ratio);
        }
      }

      final linearGain = pow(10, (gainDb + makeupGain) / 20).toDouble();
      result[i] = samples[i] * linearGain;
    }
    return result;
  }

  /// 2. Doppler (dynamic pitch shift via interpolated resampling + LFO).
  static Float64List doppler(Float64List samples, int sampleRate, {
    double depth = 0.5,    // max pitch shift in semitones
    double rate = 0.5,     // LFO rate in Hz
    double phase = 0,
  }) {
    final result = Float64List(samples.length);
    double readPos = 0;
    for (int i = 0; i < samples.length; i++) {
      final offset = depth * sin(2 * pi * rate * i / sampleRate + phase);
      final stretch = pow(2, offset / 12).toDouble();
      readPos += stretch;
      final r0 = readPos.floor();
      final r1 = r0 + 1;
      final frac = readPos - r0;
      if (r0 >= 0 && r0 < samples.length) {
        final s0 = samples[r0];
        final s1 = r1 < samples.length ? samples[r1] : 0;
        result[i] = s0 + (s1 - s0) * frac;
      }
    }
    return result;
  }

  /// 3. Amplitude mapping via transfer curve (lookup table).
  static Float64List amplitudeMap(Float64List samples, List<double> curve) {
    if (curve.isEmpty) return Float64List.fromList(samples);
    final result = Float64List(samples.length);
    final len = curve.length - 1;
    for (int i = 0; i < samples.length; i++) {
      final abs = samples[i].abs();
      final idx = (abs * len).round().clamp(0, len);
      final sign = samples[i] >= 0 ? 1.0 : -1.0;
      result[i] = sign * curve[idx];
    }
    return result;
  }

  /// 4. Echo (multi-tap with decay per tap).
  static Float64List echo(Float64List samples, int sampleRate, {
    List<double> delays = const [0.3, 0.5, 0.7],
    List<double> gains = const [0.4, 0.25, 0.15],
    double mix = 0.5,
  }) {
    final len = delays.length;
    final maxDelay = (delays.reduce(max) * sampleRate).ceil();
    final result = Float64List(samples.length + maxDelay);
    for (int i = 0; i < samples.length; i++) {
      result[i] += samples[i] * (1 - mix);
      for (int t = 0; t < len; t++) {
        final dSamples = (delays[t] * sampleRate).round();
        result[i + dSamples] += samples[i] * gains[t] * mix;
      }
    }
    return Float64List.sublistView(result, 0, samples.length);
  }

  /// 5. Waveform inversion (flip amplitude — instant, no params).
  static Float64List invert(Float64List samples) {
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = -samples[i];
    }
    return result;
  }

  /// 6. Mechanization (sample-and-hold + bitcrush).
  static Float64List mechanize(Float64List samples, int sampleRate, {
    double sampleRateReduce = 0.1, // fraction of original rate
    double bitDepth = 8,
  }) {
    final result = Float64List(samples.length);
    final holdSamples = (sampleRate * sampleRateReduce).round().clamp(1, 256);
    final quantize = pow(2, bitDepth - 1).toDouble();
    double held = 0;
    for (int i = 0; i < samples.length; i++) {
      if (i % holdSamples == 0) {
        held = (samples[i] * quantize).round() / quantize;
      }
      result[i] = held;
    }
    return result;
  }

  /// 7. Multi-channel mixer (sum multiple buffers with per-channel gain/pan).
  /// [channels] is a list of (samples, gain) pairs.
  static Float64List multiChannelMixer(
    List<({Float64List samples, double gain})> channels,
  ) {
    if (channels.isEmpty) return Float64List(0);
    int maxLen = 0;
    for (final ch in channels) {
      if (ch.samples.length > maxLen) maxLen = ch.samples.length;
    }
    final result = Float64List(maxLen);
    for (final ch in channels) {
      for (int i = 0; i < ch.samples.length; i++) {
        result[i] += ch.samples[i] * ch.gain;
      }
    }
    // Normalize
    double peak = 0;
    for (final s in result) {
      final a = s.abs();
      if (a > peak) peak = a;
    }
    if (peak > 1) {
      for (int i = 0; i < result.length; i++) {
        result[i] /= peak;
      }
    }
    return result;
  }

  /// 8a. Channel split by frequency (delegates to FftService).
  static List<Float64List> splitByFreq(
    Float64List samples, int sampleRate, List<FreqBand> bands,
  ) {
    return FftService.splitBands(samples, sampleRate, bands);
  }

  /// 8b. Channel split by time (slice at given seconds).
  static List<Float64List> splitByTime(
    Float64List samples, int sampleRate, List<double> splitPoints,
  ) {
    if (splitPoints.isEmpty) return [Float64List.fromList(samples)];
    final result = <Float64List>[];
    double prev = 0;
    for (final pt in splitPoints) {
      final startSample = (prev * sampleRate).round().clamp(0, samples.length);
      final endSample = (pt * sampleRate).round().clamp(0, samples.length);
      if (endSample > startSample) {
        result.add(samples.sublist(startSample, endSample));
      }
      prev = pt;
    }
    // Last segment
    final lastStart = (prev * sampleRate).round().clamp(0, samples.length);
    if (lastStart < samples.length) {
      result.add(samples.sublist(lastStart));
    }
    return result;
  }

  /// 9. Pitch shifter (phase vocoder: FFT → shift → IFFT).
  static Float64List pitchShift(Float64List samples, int sampleRate, {
    double semitones = 0,
    int fftSize = 2048,
  }) {
    if (semitones == 0) return Float64List.fromList(samples);
    final hop = fftSize ~/ 4;
    final window = _hannWindow(fftSize);
    final rate = pow(2, semitones / 12).toDouble();
    final output = Float64List((samples.length / rate).ceil());

    // Overlap-add STFT with phase vocoder
    final phase = Float64List(fftSize);
    final cumulativePhase = Float64List(fftSize);
    double readPos = 0;
    int writePos = 0;

    while (readPos + fftSize < samples.length && writePos < output.length) {
      final real = Float64List(fftSize);
      final imag = Float64List(fftSize);

      for (int i = 0; i < fftSize; i++) {
        real[i] = samples[readPos.round().clamp(0, samples.length - 1) + i] * window[i];
      }

      FftService.fft(real, imag);
      final mag = FftService.magnitude(real, imag);

      for (int i = 0; i <= fftSize ~/ 2; i++) {
        // Phase difference
        final theta = atan2(imag[i], real[i]);
        final delta = theta - phase[i];
        phase[i] = theta;
        cumulativePhase[i] += delta * rate;
        real[i] = mag[i] * cos(cumulativePhase[i]);
        imag[i] = mag[i] * sin(cumulativePhase[i]);
      }
      // Conjugate for IFFT
      for (int i = fftSize ~/ 2 + 1; i < fftSize; i++) {
        real[i] = real[fftSize - i];
        imag[i] = -imag[fftSize - i];
      }

      FftService.ifft(real, imag);

      for (int i = 0; i < fftSize && writePos + i < output.length; i++) {
        output[writePos + i] += real[i] * window[i] * 0.25;
      }
      readPos += hop * rate;
      writePos += hop;
    }
    return output;
  }

  /// 10. Enhanced reverb with room size, damping, predelay.
  static Float64List reverbEnhanced(Float64List samples, int sampleRate, {
    double roomSize = 0.6,   // 0-1
    double damping = 0.3,    // 0-1
    double predelayMs = 30,
    double mix = 0.3,
  }) {
    final predelaySamples = (predelayMs * sampleRate / 1000).round();
    final delayed = Float64List(samples.length + predelaySamples);
    for (int i = 0; i < samples.length; i++) {
      delayed[i + predelaySamples] = samples[i];
    }

    // Scaled comb delays based on roomSize
    final baseDelays = [0.029, 0.037, 0.047, 0.061];
    final combDelays = baseDelays.map((d) => d * (0.8 + roomSize * 0.4)).toList();
    final decay = 0.3 + roomSize * 0.5;
    final result = Float64List(samples.length);

    for (final cd in combDelays) {
      final dSamples = (cd * sampleRate).round();
      if (dSamples <= 0) continue;
      final comb = Float64List(samples.length + predelaySamples);
      for (int i = 0; i < samples.length + predelaySamples; i++) {
        comb[i] = delayed[i] + (i >= dSamples ? comb[i - dSamples] * decay * (1 - damping) : 0);
      }
      for (int i = 0; i < samples.length; i++) {
        result[i] += comb[i];
      }
    }
    for (int i = 0; i < samples.length; i++) {
      result[i] /= combDelays.length;
    }

    // All-pass
    for (int pass = 0; pass < 2; pass++) {
      final ad = 0.005 + pass * 0.003;
      final dSamples = (ad * sampleRate).round();
      if (dSamples <= 0) continue;
      for (int i = 0; i < samples.length; i++) {
        final input = result[i];
        result[i] = input * -0.7 + (i >= dSamples ? result[i - dSamples] * 0.7 : 0) + input * 0.7;
      }
    }

    // Dry/wet mix
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] * (1 - mix) + result[i] * mix;
    }
    return result;
  }

  /// 11. Equalizer — cascaded biquad IIR filters (peak/shelf).
  /// [bands] is list of (frequency, gainDB, Q).
  static Float64List equalizer(Float64List samples, int sampleRate, {
    List<({double freq, double gain, double q})> bands =
      const [(freq: 1000, gain: 0, q: 1.0)],
  }) {
    var result = Float64List.fromList(samples);
    for (final band in bands) {
      result = _biquadPeak(result, sampleRate, band.freq, band.gain, band.q);
    }
    return result;
  }

  /// 12. Spectrum filter — FFT → multiply magnitude by envelope → IFFT.
  static Float64List spectrumFilter(Float64List samples, int sampleRate, {
    required List<double> envelope, // one gain per bin, length = fftSize/2+1
    int fftSize = 2048,
  }) {
    final hop = fftSize ~/ 2;
    final window = _hannWindow(fftSize);
    final output = Float64List(samples.length);

    for (int start = 0; start < samples.length - fftSize; start += hop) {
      final real = Float64List(fftSize);
      final imag = Float64List(fftSize);
      for (int i = 0; i < fftSize; i++) {
        real[i] = samples[start + i] * window[i];
      }
      FftService.fft(real, imag);

      final half = fftSize ~/ 2;
      for (int i = 0; i <= half; i++) {
        final gain = i < envelope.length ? envelope[i] : 1.0;
        real[i] *= gain;
        imag[i] *= gain;
        if (i > 0 && i < half) {
          real[fftSize - i] *= gain;
          imag[fftSize - i] *= gain;
        }
      }
      FftService.ifft(real, imag);
      for (int i = 0; i < fftSize; i++) {
        output[start + i] += real[i] * window[i];
      }
    }
    return output;
  }

  // ── Private helpers ──

  static Float64List _hannWindow(int size) {
    final w = Float64List(size);
    for (int i = 0; i < size; i++) {
      w[i] = 0.5 * (1 - cos(2 * pi * i / (size - 1)));
    }
    return w;
  }

  /// Biquad peaking filter (EQ band).
  static Float64List _biquadPeak(Float64List samples, int sr, double freq, double gainDB, double q) {
    final a = pow(10, gainDB / 40).toDouble();
    final w0 = 2 * pi * freq / sr;
    final alpha = sin(w0) / (2 * q);
    final b0 = 1 + alpha * a;
    final b1 = -2 * cos(w0);
    final b2 = 1 - alpha * a;
    final a0 = 1 + alpha / a;
    final a1 = -2 * cos(w0);
    final a2 = 1 - alpha / a;

    final result = Float64List(samples.length);
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (int i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = (b0 / a0) * x + (b1 / a0) * x1 + (b2 / a0) * x2 - (a1 / a0) * y1 - (a2 / a0) * y2;
      x2 = x1; x1 = x;
      y2 = y1; y1 = y;
      result[i] = y;
    }
    return result;
  }
}
