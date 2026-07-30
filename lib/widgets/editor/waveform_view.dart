import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/utils/theme_colors.dart';
import '../../models/track.dart';

class WaveformView extends StatelessWidget {
  final Track track;
  final double pixelsPerSecond;
  final VoidCallback? onTap;

  const WaveformView({
    super.key,
    required this.track,
    this.pixelsPerSecond = 50,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor.withAlpha(77)),
        ),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: _WaveformPainter(
          color: track.color,
          hasFile: track.audioFilePath != null,
          emptyColor: context.outline,
          pixelsPerSecond: pixelsPerSecond,
        ),
      ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Color color;
  final bool hasFile;
  final Color emptyColor;
  final double pixelsPerSecond;

  _WaveformPainter({
    required this.color,
    required this.hasFile,
    required this.emptyColor,
    this.pixelsPerSecond = 50,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final step = pixelsPerSecond > 200
        ? 0.25
        : pixelsPerSecond > 100
            ? 0.5
            : pixelsPerSecond > 50
                ? 1.0
                : 2.0;

    if (hasFile) {
      final paint = Paint()
        ..color = color.withAlpha(77)
        ..strokeWidth = 1.5;

      final fillPaint = Paint()
        ..color = color.withAlpha(20);

      final path = Path();
      final centerY = size.height / 2;
      final random = Random(42);

      path.moveTo(0, centerY);
      for (double x = 0; x < size.width; x += step) {
        final amplitude = _getAmplitude(x, size.width, random);
        path.lineTo(x, centerY - amplitude);
      }
      for (double x = size.width - (size.width % step.toInt().clamp(1, 2));
          x >= 0;
          x -= step) {
        final amplitude = _getAmplitude(x, size.width, random);
        path.lineTo(x, centerY + amplitude);
      }
      path.close();
      canvas.drawPath(path, fillPaint);

      final outlinePath = Path();
      outlinePath.moveTo(0, centerY);
      for (double x = 0; x < size.width; x += step) {
        final amplitude = _getAmplitude(x, size.width, random);
        outlinePath.lineTo(x, centerY - amplitude);
      }
      for (double x = size.width - (size.width % step.toInt().clamp(1, 2));
          x >= 0;
          x -= step) {
        final amplitude = _getAmplitude(x, size.width, random);
        outlinePath.lineTo(x, centerY + amplitude);
      }
      outlinePath.close();
      canvas.drawPath(outlinePath, paint);

      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        Paint()..color = color.withAlpha(38)..strokeWidth = 0.5,
      );
    } else {
      final centerY = size.height / 2;
      final paint = Paint()
        ..color = emptyColor.withAlpha(77)
        ..strokeWidth = 1;

      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        paint..strokeWidth = 0.5,
      );

      final dashWidth = 4.0;
      final dashSpace = 4.0;
      double startX = 0;
      while (startX < size.width) {
        canvas.drawLine(
          Offset(startX, centerY),
          Offset(min(startX + dashWidth, size.width), centerY),
          paint..strokeWidth = 0.5,
        );
        startX += dashWidth + dashSpace;
      }
    }
  }

  double _getAmplitude(double x, double width, Random random) {
    final envelope = sin((x / width) * pi);
    final harmonics = sin(x * 0.05) * 0.5 +
        sin(x * 0.12) * 0.3 +
        sin(x * 0.03) * 0.2;
    return (harmonics * envelope * 30).abs().clamp(2, 35).toDouble();
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.hasFile != hasFile ||
        oldDelegate.color != color ||
        oldDelegate.emptyColor != emptyColor ||
        oldDelegate.pixelsPerSecond != pixelsPerSecond;
  }
}
