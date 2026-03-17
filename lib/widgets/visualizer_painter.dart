import 'package:flutter/material.dart';

class FftPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double opacity;
  final bool useGradient;
  final Color? startColor;
  final Color? endColor;
  final double? gradientStop1;
  final double? gradientStop2;
  final int? gradientTileMode;

  FftPainter({
    required this.values,
    required this.color,
    this.opacity = 0.2,
    this.useGradient = false,
    this.startColor,
    this.endColor,
    this.gradientStop1,
    this.gradientStop2,
    this.gradientTileMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    if (useGradient && startColor != null && endColor != null) {
      paint.shader = LinearGradient(
        colors: [
          startColor!.withOpacity(opacity),
          endColor!.withOpacity(opacity),
        ],
        stops: gradientStop1 != null && gradientStop2 != null
            ? [gradientStop1!, gradientStop2!]
            : null,
        tileMode: gradientTileMode != null
            ? TileMode.values[gradientTileMode!]
            : TileMode.clamp,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }

    final barCount = values.length;
    final gap = 2.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (size.width - totalGap) / barCount;

    for (var i = 0; i < barCount; i++) {
      final barHeight = values[i] * size.height * 0.5;
      final x = i * (barWidth + gap);
      final y = size.height - barHeight;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FftPainter oldDelegate) => true;
}