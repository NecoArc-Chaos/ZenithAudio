import 'dart:math';
import 'dart:typed_data';

class FreqBand {
  final double lowFreq;
  final double highFreq;
  final double crossfadeHz;

  const FreqBand({
    required this.lowFreq,
    required this.highFreq,
    this.crossfadeHz = 0,
  });
}

class FftService {
  /// In-place radix-2 FFT.
  /// [real] and [imag] must be same length and a power of 2.
  static void fft(Float64List real, Float64List imag) {
    final n = real.length;
    if (n <= 1) return;

    _bitReverse(real, imag);

    for (int len = 2; len <= n; len <<= 1) {
      final halfLen = len >> 1;
      final wAngle = -2 * pi / len;
      final wReal = cos(wAngle);
      final wImag = sin(wAngle);

      for (int i = 0; i < n; i += len) {
        double wr = 1, wi = 0;
        for (int j = 0; j < halfLen; j++) {
          final k = i + j + halfLen;
          final tr = wr * real[k] - wi * imag[k];
          final ti = wr * imag[k] + wi * real[k];
          real[k] = real[i + j] - tr;
          imag[k] = imag[i + j] - ti;
          real[i + j] += tr;
          imag[i + j] += ti;
          final newWr = wr * wReal - wi * wImag;
          wi = wr * wImag + wi * wReal;
          wr = newWr;
        }
      }
    }
  }

  /// In-place radix-2 IFFT.
  static void ifft(Float64List real, Float64List imag) {
    final n = real.length;
    for (int i = 0; i < n; i++) {
      imag[i] = -imag[i];
    }
    fft(real, imag);
    for (int i = 0; i < n; i++) {
      real[i] /= n;
      imag[i] /= n;
    }
  }

  /// Compute magnitude spectrum. Returns [Float64List] of length n~/2+1.
  static Float64List magnitude(Float64List real, Float64List imag) {
    final n = real.length;
    final mag = Float64List(n ~/ 2 + 1);
    for (int i = 0; i <= n ~/ 2; i++) {
      mag[i] = sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }
    return mag;
  }

  /// Apply a frequency-domain mask: zero out bins outside [lowFreq, highFreq].
  /// Uses raised-cosine crossfade if [crossfadeHz] > 0.
  static void applyBandMask(
      Float64List real, Float64List imag, int sampleRate,
      double lowFreq, double highFreq,
      {double crossfadeHz = 0}) {
    final n = real.length;
    final binWidth = sampleRate / n;

    for (int i = 0; i <= n ~/ 2; i++) {
      final freq = i * binWidth;
      double gain = 1.0;

      if (freq < lowFreq) {
        if (crossfadeHz > 0 && freq > lowFreq - crossfadeHz) {
          gain = 0.5 * (1 - cos(pi * (freq - (lowFreq - crossfadeHz)) / crossfadeHz));
        } else {
          gain = 0;
        }
      } else if (freq > highFreq) {
        if (crossfadeHz > 0 && freq < highFreq + crossfadeHz) {
          gain = 0.5 * (1 + cos(pi * (freq - highFreq) / crossfadeHz));
        } else {
          gain = 0;
        }
      }

      if (gain < 1.0) {
        real[i] *= gain;
        imag[i] *= gain;
        if (i > 0 && i < n ~/ 2) {
          real[n - i] *= gain;
          imag[n - i] *= gain;
        }
      }
    }
  }

  /// Split audio into multiple frequency bands using overlap-add FFT.
  /// Returns one [Float64List] per band.
  static List<Float64List> splitBands(
      Float64List samples, int sampleRate, List<FreqBand> bands,
      {int fftSize = 4096}) {
    if (samples.isEmpty || bands.isEmpty) return [];

    final hopSize = fftSize ~/ 4;
    final window = _hannWindow(fftSize);
    final numBands = bands.length;

    final outputs = List.generate(numBands, (_) => Float64List(samples.length));

    for (int start = 0; start < samples.length - fftSize; start += hopSize) {
      final real = Float64List(fftSize);
      final imag = Float64List(fftSize);

      for (int i = 0; i < fftSize; i++) {
        real[i] = samples[start + i] * window[i];
      }

      fft(real, imag);

      for (int b = 0; b < numBands; b++) {
        final bandReal = Float64List.fromList(real);
        final bandImag = Float64List.fromList(imag);

        applyBandMask(bandReal, bandImag, sampleRate,
            bands[b].lowFreq, bands[b].highFreq,
            crossfadeHz: bands[b].crossfadeHz);

        ifft(bandReal, bandImag);

        for (int i = 0; i < fftSize; i++) {
          outputs[b][start + i] += bandReal[i] * window[i];
        }
      }
    }

    return outputs;
  }

  static void _bitReverse(Float64List real, Float64List imag) {
    final n = real.length;
    int j = 0;
    for (int i = 0; i < n - 1; i++) {
      if (i < j) {
        double tmp = real[i]; real[i] = real[j]; real[j] = tmp;
        tmp = imag[i]; imag[i] = imag[j]; imag[j] = tmp;
      }
      int k = n >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }
  }

  static Float64List _hannWindow(int size) {
    final w = Float64List(size);
    for (int i = 0; i < size; i++) {
      w[i] = 0.5 * (1 - cos(2 * pi * i / (size - 1)));
    }
    return w;
  }
}
