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
                      // 波形显示
                      CustomPaint(
                        size: Size(constraints.maxWidth, 60),
                        painter: WaveformPainter(
                          waveform: widget.waveform,
                          progress: widget.progress,
                          activeColor: widget.activeColor,
                          inactiveColor: widget.inactiveColor,
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

    final double barWidth = size.width / waveform.length;
    final double maxBarHeight = size.height;
    // 限制波形数量，避免过度绘制导致花屏
    final int step = (1 / barWidth).ceil().clamp(1, 100);

    // 1. 绘制底色 (未播放部分)
    final inactivePaint = Paint()..color = inactiveColor;
    _drawBars(canvas, size, barWidth, maxBarHeight, step, inactivePaint);

    // 2. 绘制激活色 (已播放部分)
    // 使用 clipRect 实现精确到像素的裁剪，从而实现“柱子内部”的颜色渐变效果
    canvas.save();
    final double activeWidth = size.width * progress;
    canvas.clipRect(Rect.fromLTWH(0, 0, activeWidth, size.height));
    
    final activePaint = Paint()..color = activeColor;
    // 性能优化：在绘制激活部分时，只绘制在裁剪区域内的柱子
    final int activeEndIndex = (activeWidth / barWidth).ceil().clamp(0, waveform.length);
    _drawBars(canvas, size, barWidth, maxBarHeight, step, activePaint, maxIndex: activeEndIndex);
    
    canvas.restore();
  }

  void _drawBars(
    Canvas canvas,
    Size size,
    double barWidth,
    double maxBarHeight,
    int step,
    Paint paint, {
    int? maxIndex,
  }) {
    final int end = maxIndex ?? waveform.length;
    for (int i = 0; i < end; i += step) {
      final double barHeight = waveform[i] * maxBarHeight;
      final double x = i * barWidth;
      final double y = (size.height - barHeight) / 2;

      // 如果宽度太窄，直接绘制直线而不是圆角矩形，提高性能并减少渲染错误
      if (barWidth < 3) {
        canvas.drawLine(
          Offset(x + barWidth / 2, y),
          Offset(x + barWidth / 2, y + barHeight),
          paint..strokeWidth = math.max(1, barWidth),
        );
      } else {
        final RRect rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 1, y, barWidth - 2, barHeight),
          const Radius.circular(2),
        );
        canvas.drawRRect(rrect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
