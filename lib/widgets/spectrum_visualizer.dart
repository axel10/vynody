import 'package:flutter/material.dart';

class SpectrumVisualizer extends StatelessWidget {
  final List<double> fft;
  final Color color;

  const SpectrumVisualizer({
    super.key,
    required this.fft,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: SpectrumPainter(fft: fft, color: color),
      child: Container(),
    );
  }
}

class SpectrumPainter extends CustomPainter {
  final List<double> fft;
  final Color color;

  SpectrumPainter({required this.fft, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (fft.isEmpty) return;

    final barWidth = size.width / fft.length;
    final maxHeight = size.height * 0.4;

    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < fft.length; i++) {
      // fft values are from media_kit, they are usually normalized
      // Use some smoothing or amplification if needed
      final h = (fft[i] * maxHeight).clamp(2.0, maxHeight);
      final x = i * barWidth;

      // Center the spectrum vertically a bit or keep at bottom
      final rect = Rect.fromLTWH(
        x + 2,
        size.height - h - 100, // Move it up from very bottom
        barWidth - 4,
        h,
      );

      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.8), color.withOpacity(0.1)],
      ).createShader(rect);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumPainter oldDelegate) {
    return oldDelegate.fft != fft;
  }
}
