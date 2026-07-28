import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/audio_clip.dart';

class WaveformPainter extends CustomPainter {
  final Float64List samples;
  final int sampleRate;
  final double pps; // pixels per second
  final double playheadSec;
  final Selection? selection;
  final Color waveformColor;
  final Color selectionColor;
  final Color playheadColor;
  final Color gridColor;
  final double scrollOffset;

  WaveformPainter({
    required this.samples,
    required this.sampleRate,
    required this.pps,
    this.playheadSec = -1,
    this.selection,
    this.waveformColor = const Color(0xFF40C4FF),
    this.selectionColor = const Color(0x3340C4FF),
    this.playheadColor = const Color(0xFFFF5252),
    this.gridColor = const Color(0x1AFFFFFF),
    this.scrollOffset = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()..strokeWidth = 1;
    final centerY = size.height / 2;

    // Grid lines (seconds)
    paint.color = gridColor;
    paint.strokeWidth = 0.5;
    final startSec = scrollOffset / pps;
    final endSec = startSec + size.width / pps;
    final gridInterval = _gridInterval(pps);
    final firstGrid = (startSec / gridInterval).ceil() * gridInterval;
    for (double t = firstGrid; t <= endSec; t += gridInterval) {
      final x = t * pps - scrollOffset;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Zero line
    paint.color = waveformColor.withAlpha(60);
    paint.strokeWidth = 0.5;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paint);

    // Calculate visible sample range
    final startSample = (startSec * sampleRate).round().clamp(0, samples.length - 1);
    final endSample = (endSec * sampleRate).round().clamp(0, samples.length - 1);
    final visibleSamples = endSample - startSample;
    if (visibleSamples <= 0) return;

    // Determine decimation factor
    final pixelsForSamples = size.width;
    final samplesPerPixel = max(1, visibleSamples / pixelsForSamples).ceil();

    // Draw waveform envelope
    final path = Path();
    bool started = false;
    final wavePaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          waveformColor.withAlpha(180),
          waveformColor.withAlpha(40),
          waveformColor.withAlpha(40),
          waveformColor.withAlpha(180),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int px = 0; px < pixelsForSamples; px++) {
      final sampleIdx = startSample + (px * samplesPerPixel).round();
      if (sampleIdx >= samples.length) break;

      final endIdx = min(sampleIdx + samplesPerPixel, samples.length);
      double minVal = 0, maxVal = 0;
      for (int s = sampleIdx; s < endIdx; s++) {
        if (samples[s] < minVal) minVal = samples[s];
        if (samples[s] > maxVal) maxVal = samples[s];
      }

      final x = px.toDouble();
      final yTop = centerY - maxVal * centerY;

      if (!started) {
        path.moveTo(x, yTop);
        started = true;
      }
      path.lineTo(x, yTop);
    }
    // Close the upper envelope
    for (int px = pixelsForSamples.toInt() - 1; px >= 0; px--) {
      final sampleIdx = startSample + (px * samplesPerPixel).round();
      if (sampleIdx >= samples.length) break;
      final endIdx = min(sampleIdx + samplesPerPixel, samples.length);
      double minVal = 0;
      for (int s = sampleIdx; s < endIdx; s++) {
        if (samples[s] < minVal) minVal = samples[s];
      }
      final x = px.toDouble();
      final yBottom = centerY - minVal * centerY;
      path.lineTo(x, yBottom);
    }
    path.close();
    canvas.drawPath(path, wavePaint);

    // Selection highlight
    if (selection != null && selection!.isValid) {
      final selStartX = selection!.startSec * pps - scrollOffset;
      final selEndX = selection!.endSec * pps - scrollOffset;
      final selRect = Rect.fromLTRB(
        max(0, selStartX), 0,
        min(size.width, selEndX), size.height,
      );
      if (selRect.width > 0) {
        canvas.drawRect(selRect, Paint()..color = selectionColor);
      }
    }

    // Playhead
    if (playheadSec >= 0) {
      final phx = playheadSec * pps - scrollOffset;
      if (phx >= 0 && phx <= size.width) {
        paint.color = playheadColor;
        paint.strokeWidth = 2;
        canvas.drawLine(Offset(phx, 0), Offset(phx, size.height), paint);
      }
    }
  }

  double _gridInterval(double pps) {
    if (pps >= 200) return 0.1;
    if (pps >= 100) return 0.2;
    if (pps >= 50) return 0.5;
    if (pps >= 20) return 1;
    if (pps >= 10) return 2;
    return 5;
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.pps != pps ||
      oldDelegate.playheadSec != playheadSec ||
      oldDelegate.selection != selection ||
      oldDelegate.scrollOffset != scrollOffset;
}
