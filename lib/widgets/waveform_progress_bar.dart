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
            height: 60, // 调整进度条高度
            width: double.infinity,
            child: ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [activeColor, inactiveColor],
                  stops: [progress, progress],
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: CustomPaint(
                painter: WaveformPainter(
                  waveform: waveform,
                ),
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

  WaveformPainter({
    required this.waveform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) {
      // Draw a simple line if no waveform data
      final paint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    final paint = Paint()..color = Colors.white;

    final double barWidth = size.width / waveform.length;
    final double maxBarHeight = size.height;

    for (int i = 0; i < waveform.length; i++) {
      final double barHeight = waveform[i] * maxBarHeight;
      final double x = i * barWidth;
      final double y = (size.height - barHeight) / 2;

      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 1, y, math.max(1, barWidth - 2), barHeight),
        const Radius.circular(2),
      );

      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform;
  }
}
