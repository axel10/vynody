import 'package:flutter/material.dart';
import 'dart:math' as math;

class WaveformProgressBar extends StatelessWidget {
  final List<double> waveform;
  final double progress;
  final Function(double) onSeek;
  final Function(double) onScrubbing;
  final Color activeColor;
  final Color inactiveColor;

  const WaveformProgressBar({
    super.key,
    required this.waveform,
    required this.progress,
    required this.onSeek,
    required this.onScrubbing,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white24,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final double localX = details.localPosition.dx;
            final double newProgress = (localX / constraints.maxWidth).clamp(
              0.0,
              1.0,
            );
            onScrubbing(newProgress);
          },
          onHorizontalDragEnd: (details) {
            onSeek(progress);
          },
          onTapDown: (details) {
            final double localX = details.localPosition.dx;
            final double newProgress = (localX / constraints.maxWidth).clamp(
              0.0,
              1.0,
            );
            onScrubbing(newProgress);
            onSeek(newProgress);
          },
          child: SizedBox(
            height: 60,
            width: double.infinity,
            child: CustomPaint(
              painter: WaveformPainter(
                waveform: waveform,
                progress: progress,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
            ),
          ),
        );
      },
    );
  }
}

class WaveformPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) {
      // Draw a simple line if no waveform data
      final paint = Paint()
        ..color = inactiveColor
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    final paintActive = Paint()..color = activeColor;
    final paintInactive = Paint()..color = inactiveColor;

    final double barWidth = size.width / waveform.length;
    final double maxBarHeight = size.height;

    for (int i = 0; i < waveform.length; i++) {
      final double barHeight = waveform[i] * maxBarHeight;
      final double x = i * barWidth;
      final double y = (size.height - barHeight) / 2;

      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y, math.max(1, barWidth - 2), barHeight),
        Radius.circular(2),
      );

      if (x / size.width <= progress) {
        canvas.drawRRect(rrect, paintActive);
      } else {
        canvas.drawRRect(rrect, paintInactive);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform || oldDelegate.progress != progress;
  }
}
