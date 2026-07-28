import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/fft_service.dart';

class SpectrogramPainter extends CustomPainter {
  final Float64List samples;
  final int sampleRate;
  final double pps;
  final double scrollOffset;
  final Color lowColor;
  final Color midColor;
  final Color highColor;

  final int _fftSize = 1024;
  int get _hopSize => _fftSize ~/ 4;

  SpectrogramPainter({
    required this.samples,
    required this.sampleRate,
    required this.pps,
    this.scrollOffset = 0,
    this.lowColor = const Color(0xFF000033),
    this.midColor = const Color(0xFF00CCFF),
    this.highColor = const Color(0xFFFFCC00),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final window = _hannWindow(_fftSize);
    final numWindows = ((samples.length - _fftSize) / _hopSize).ceil().clamp(1, 99999);
    final binsPerWindow = _fftSize ~/ 2;

    // Track visible range
    final startSec = scrollOffset / pps;
    final endSec = (scrollOffset + size.width) / pps;
    final startSample = (startSec * sampleRate).round().clamp(0, samples.length - 1);
    final endSample = (endSec * sampleRate).round().clamp(0, samples.length);
    final startWin = (startSample / _hopSize).round().clamp(0, numWindows - 1);
    final endWin = (endSample / _hopSize).round().clamp(startWin + 1, numWindows);

    final visibleWindows = endWin - startWin;
    if (visibleWindows <= 0) return;

    final xScale = size.width / visibleWindows;

    // Build magnitude matrix for visible range
    final magMatrix = List.generate(visibleWindows, (_) => Float64List(binsPerWindow));
    double maxMag = 0;

    for (int wi = 0; wi < visibleWindows; wi++) {
      final globalWi = startWin + wi;
      final real = Float64List(_fftSize);
      final imag = Float64List(_fftSize);
      final offset = globalWi * _hopSize;

      for (int i = 0; i < _fftSize && offset + i < samples.length; i++) {
        real[i] = samples[offset + i] * window[i];
      }

      FftService.fft(real, imag);
      final mag = FftService.magnitude(real, imag);

      for (int b = 0; b < binsPerWindow; b++) {
        final m = mag[b];
        magMatrix[wi][b] = m;
        if (m > maxMag) maxMag = m;
      }
    }

    if (maxMag <= 0) maxMag = 1;

    // Color stops
    final lowHSL = HSLColor.fromColor(lowColor);
    final midHSL = HSLColor.fromColor(midColor);
    final highHSL = HSLColor.fromColor(highColor);

    // Render each pixel column
    for (int wi = 0; wi < visibleWindows; wi++) {
      final x = wi * xScale;
      final nextX = (wi + 1) * xScale;
      final w = nextX - x;

      for (int b = 0; b < binsPerWindow; b++) {
        // Logarithmic frequency scale: map bin index to Y with more space for low freqs
        final freq = (b + 1) * sampleRate / _fftSize;
        final freqNorm = log(freq / 20) / log(sampleRate / 40);
        final y = (1.0 - freqNorm.clamp(0.0, 1.0)) * size.height;

        final nextFreq = (b + 2) * sampleRate / _fftSize;
        final nextFreqNorm = log(nextFreq / 20) / log(sampleRate / 40);
        final nextY = (1.0 - nextFreqNorm.clamp(0.0, 1.0)) * size.height;
        final h = max(nextY - y, 1.0);

        if (y >= size.height || y + h <= 0) continue;

        // Amplitude to color
        final magVal = magMatrix[wi][b];
        final db = 20 * log(magVal + 1); // Simple dB-like scale
        final dbMax = 20 * log(maxMag + 1);
        final intensity = (db / dbMax).clamp(0.0, 1.0);

        final color = _gradientColor(lowHSL, midHSL, highHSL, intensity);
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), Paint()..color = color);
      }
    }
  }

  Color _gradientColor(HSLColor low, HSLColor mid, HSLColor high, double t) {
    if (t <= 0.5) {
      final u = t / 0.5;
      return HSLColor.lerp(low, mid, u)!.toColor();
    } else {
      final u = (t - 0.5) / 0.5;
      return HSLColor.lerp(mid, high, u)!.toColor();
    }
  }

  Float64List _hannWindow(int size) {
    final w = Float64List(size);
    for (int i = 0; i < size; i++) {
      w[i] = 0.5 * (1 - cos(2 * pi * i / (size - 1)));
    }
    return w;
  }

  @override
  bool shouldRepaint(covariant SpectrogramPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.sampleRate != sampleRate ||
        oldDelegate.pps != pps ||
        oldDelegate.scrollOffset != scrollOffset;
  }
}
