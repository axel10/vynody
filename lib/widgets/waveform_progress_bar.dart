import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/playback_utils.dart';

class WaveformProgressBar extends StatefulWidget {
  final List<double> waveform;
  final double progress;
  final Duration duration;
  final Function(double) onSeek;
  final Function(double) onScrubbing;
  final Color activeColor;
  final Color inactiveColor;

  const WaveformProgressBar({
    super.key,
    required this.waveform,
    required this.progress,
    required this.duration,
    required this.onSeek,
    required this.onScrubbing,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white24,
  });

  @override
  State<WaveformProgressBar> createState() => _WaveformProgressBarState();
}

class _WaveformProgressBarState extends State<WaveformProgressBar> {
  double? _hoverProgress;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          onHover: (event) {
            setState(() {
              _hoverProgress = (event.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            });
          },
          onExit: (event) {
            setState(() {
              _hoverProgress = null;
            });
          },
          child: GestureDetector(
            onHorizontalDragStart: (_) => setState(() => _isDragging = true),
            onHorizontalDragUpdate: (details) {
              final double localX = details.localPosition.dx;
              final double newProgress = (localX / constraints.maxWidth).clamp(
                0.0,
                1.0,
              );
              widget.onScrubbing(newProgress);
              setState(() {
                _hoverProgress = newProgress;
              });
            },
            onHorizontalDragEnd: (details) {
              widget.onSeek(widget.progress);
              setState(() {
                _isDragging = false;
                _hoverProgress = null;
              });
            },
            onTapDown: (details) {
              final double localX = details.localPosition.dx;
              final double newProgress = (localX / constraints.maxWidth).clamp(
                0.0,
                1.0,
              );
              widget.onScrubbing(newProgress);
              widget.onSeek(newProgress);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 时间显示预览
                if (_hoverProgress != null || _isDragging)
                  SizedBox(
                    height: 20,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          formatDuration(Duration(
                            milliseconds: (widget.duration.inMilliseconds * (_hoverProgress ?? widget.progress)).toInt(),
                          )),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20), // Keep space to prevent jumping
                SizedBox(
                  height: 60, // 调整进度条高度
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // 背景波形
                      ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [widget.activeColor, widget.inactiveColor],
                            stops: [widget.progress, widget.progress],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.srcIn,
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, 60),
                          painter: WaveformPainter(
                            waveform: widget.waveform,
                          ),
                        ),
                      ),
                      // 悬浮指示线
                      if (_hoverProgress != null)
                        Positioned(
                          left: _hoverProgress! * constraints.maxWidth,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: widget.activeColor.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
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
