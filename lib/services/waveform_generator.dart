import 'dart:math';
import 'dart:typed_data';

class WaveformGenerator {
  static const int defaultSampleRate = 44100;

  /// Generate a sine wave.
  static Float64List sine(
      double frequency, double duration, {int sampleRate = defaultSampleRate, double amplitude = 0.8}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final omega = 2 * pi * frequency / sampleRate;
    for (int i = 0; i < n; i++) {
      result[i] = sin(omega * i) * amplitude;
    }
    return result;
  }

  /// Generate a square wave with configurable duty cycle (0–1).
  static Float64List square(
      double frequency, double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.8, double dutyCycle = 0.5}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final period = sampleRate / frequency;
    final highSamples = (period * dutyCycle.clamp(0.01, 0.99)).round();
    for (int i = 0; i < n; i++) {
      result[i] = (i % period.round() < highSamples ? amplitude : -amplitude);
    }
    return result;
  }

  /// Generate a sawtooth wave (ramp up).
  static Float64List sawtooth(
      double frequency, double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.8}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final period = sampleRate / frequency;
    for (int i = 0; i < n; i++) {
      final phase = i / period;
      result[i] = (2.0 * (phase - (phase + 0.5).floor())) * amplitude;
    }
    return result;
  }

  /// Generate a triangle wave.
  static Float64List triangle(
      double frequency, double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.8}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final period = sampleRate / frequency;
    for (int i = 0; i < n; i++) {
      final t = (i / period) % 1.0;
      result[i] = (4.0 * (t < 0.5 ? t : 1.0 - t) - 1.0) * amplitude;
    }
    return result;
  }

  /// Generate a pulse wave (variable duty cycle, bipolar).
  static Float64List pulse(
      double frequency, double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.8, double dutyCycle = 0.1}) {
    return square(frequency, duration, sampleRate: sampleRate, amplitude: amplitude, dutyCycle: dutyCycle);
  }

  /// Generate white noise.
  static Float64List whiteNoise(
      double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.5, int? seed}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final rng = seed != null ? Random(seed) : Random();
    for (int i = 0; i < n; i++) {
      result[i] = (rng.nextDouble() * 2 - 1) * amplitude;
    }
    return result;
  }

  /// Generate pink noise using the Voss-McCartney algorithm.
  static Float64List pinkNoise(
      double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.5}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final numRows = 16;
    final rows = List.generate(numRows, (_) => Random().nextDouble() * 2 - 1);
    int counter = 0;

    for (int i = 0; i < n; i++) {
      counter++;
      int mask = 1;
      for (int r = 0; r < numRows; r++) {
        if ((counter & mask) != 0) {
          rows[r] = Random().nextDouble() * 2 - 1;
        }
        mask <<= 1;
      }
      double sum = 0;
      for (final v in rows) sum += v;
      result[i] = (sum / numRows) * amplitude;
    }
    return result;
  }

  /// Generate brown noise (Brownian / random walk).
  static Float64List brownNoise(
      double duration,
      {int sampleRate = defaultSampleRate, double amplitude = 0.5}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final rng = Random();
    double value = 0;
    for (int i = 0; i < n; i++) {
      value += (rng.nextDouble() - 0.5) * 0.02;
      value = value.clamp(-1.0, 1.0);
      result[i] = value * amplitude;
    }
    return result;
  }

  /// Additive synthesis from harmonic amplitudes.
  /// [harmonics] is a list of (frequency multiplier, amplitude) pairs.
  static Float64List additive(
      double fundamental, double duration, List<MapEntry<double, double>> harmonics,
      {int sampleRate = defaultSampleRate}) {
    final n = (sampleRate * duration).ceil();
    final result = Float64List(n);
    final base = 2 * pi / sampleRate;
    for (int i = 0; i < n; i++) {
      double s = 0;
      for (final h in harmonics) {
        s += sin(base * fundamental * h.key * i) * h.value;
      }
      result[i] = s;
    }
    return result;
  }

  /// Normalize peak amplitude to target (0–1).
  static Float64List normalizePeak(Float64List samples, {double target = 0.95}) {
    double maxAmp = 0;
    for (final s in samples) {
      final a = s.abs();
      if (a > maxAmp) maxAmp = a;
    }
    if (maxAmp <= 0 || maxAmp >= target) return samples;
    final scale = target / maxAmp;
    final result = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      result[i] = samples[i] * scale;
    }
    return result;
  }
}
