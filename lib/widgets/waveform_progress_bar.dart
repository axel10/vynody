import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../utils/playback_utils.dart';

class WaveformProgressBar extends StatefulWidget {
  final List<double> waveform;
  final double progress;
  final Duration duration;
  final Function(double) onSeek;
  final Function(double) onScrubbing;
  final Color activeColor;
  final Color inactiveColor;
  final bool isScrolling;

  const WaveformProgressBar({
    super.key,
    required this.waveform,
    required this.progress,
    required this.duration,
    required this.onSeek,
    required this.onScrubbing,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white24,
    this.isScrolling = true, // Default to scrolling as requested
    this.height = 80,
  });

  final double height;

  @override
  State<WaveformProgressBar> createState() => _WaveformProgressBarState();
}

class _WaveformProgressBarState extends State<WaveformProgressBar> {
  double? _hoverProgress;
  bool _isDragging = false;
  double _dragStartX = 0;
  double _dragStartProgress = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        // 缩放因子：决定波形的“宽度”。这里我们让每个波形点占据一定的像素宽度
        // 如果是滚动模式，我们让波形更宽一些，超出屏幕
        final double barWidth = widget.isScrolling ? 4.0 : (width / math.max(1, widget.waveform.length));
        final double barGap = widget.isScrolling ? 2.0 : 0.0;
        final double totalBarWidth = barWidth + barGap;
        final double totalWaveformWidth = widget.waveform.length * totalBarWidth;

        return MouseRegion(
          onHover: (event) {
            if (!widget.isScrolling) {
              setState(() {
                _hoverProgress = (event.localPosition.dx / width).clamp(0.0, 1.0);
              });
            }
          },
          onExit: (event) {
            setState(() {
              _hoverProgress = null;
            });
          },
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              setState(() {
                _isDragging = true;
                _dragStartX = details.localPosition.dx;
                _dragStartProgress = widget.progress;
              });
            },
            onHorizontalDragUpdate: (details) {
              final double deltaX = details.localPosition.dx - _dragStartX;
              double newProgress;
              
              if (widget.isScrolling) {
                // 滚动模式下，拖动是“移动波形”
                // 移动的距离 deltaX 对应的进度变化是 deltaX / totalWaveformWidth
                // 向右拖动（deltaX > 0）意味着波形向右移，即播放进度减少
                newProgress = (_dragStartProgress - (deltaX / totalWaveformWidth)).clamp(0.0, 1.0);
              } else {
                newProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
              }
              
              widget.onScrubbing(newProgress);
              if (!widget.isScrolling) {
                setState(() {
                  _hoverProgress = newProgress;
                });
              }
            },
            onHorizontalDragEnd: (details) {
              widget.onSeek(widget.progress);
              setState(() {
                _isDragging = false;
                _hoverProgress = null;
              });
            },
            onTapDown: (details) {
              if (!widget.isScrolling) {
                final double newProgress = (details.localPosition.dx / width).clamp(0.0, 1.0);
                widget.onScrubbing(newProgress);
                widget.onSeek(newProgress);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 时间显示预览
                if (_hoverProgress != null || _isDragging)
                  SizedBox(
                    height: 24,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 0.5),
                        ),
                        child: Text(
                          formatDuration(Duration(
                            milliseconds: (widget.duration.inMilliseconds * (widget.progress)).toInt(),
                          )),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                
                ClipRect(
                  child: SizedBox(
                    height: widget.height,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 波形显示
                        CustomPaint(
                          size: Size(width, widget.height),
                          painter: WaveformPainter(
                            waveform: widget.waveform,
                            progress: widget.progress,
                            activeColor: widget.activeColor,
                            inactiveColor: widget.inactiveColor,
                            isScrolling: widget.isScrolling,
                            barWidth: barWidth,
                            barGap: barGap,
                          ),
                        ),
                        
                        // 播放头指示线 (仅在滚动模式下居中显示，或者在静态模式下跟随进度)
                        if (widget.isScrolling)
                          Container(
                            width: 2,
                            height: widget.height * 0.75,
                            decoration: BoxDecoration(
                              color: widget.activeColor,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.activeColor.withValues(alpha: 0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          )
                        else if (_hoverProgress != null)
                          Positioned(
                            left: _hoverProgress! * width,
                            top: 10,
                            bottom: 10,
                            child: Container(
                              width: 2,
                              color: widget.activeColor.withValues(alpha: 0.3),
                            ),
                          ),
                      ],
                    ),
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
  final bool isScrolling;
  final double barWidth;
  final double barGap;

  WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.isScrolling,
    required this.barWidth,
    required this.barGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) {
      final paint = Paint()
        ..color = inactiveColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
      return;
    }

    final double centerY = size.height / 2;
    final double maxBarHeight = size.height * 0.8;
    final double totalBarWidth = barWidth + barGap;
    
    // 计算当前进度对应的索引（浮点数，用于精确偏移）
    final double currentIdx = progress * (waveform.length - 1);
    
    // 绘制区域的中心 X (播放头位置)
    final double centerX = isScrolling ? size.width / 2 : size.width * progress;

    // 1. 绘制底色层 (全量绘制未激活颜色)
    _drawWaveformLayer(canvas, size, centerY, maxBarHeight, totalBarWidth, currentIdx, inactiveColor);

    // 2. 绘制激活层 (使用裁剪实现像素级颜色平滑过渡)
    canvas.save();
    // 裁剪出播放头左侧的区域
    canvas.clipRect(Rect.fromLTWH(0, 0, centerX, size.height));
    _drawWaveformLayer(canvas, size, centerY, maxBarHeight, totalBarWidth, currentIdx, activeColor, withGlow: true);
    canvas.restore();
  }

  void _drawWaveformLayer(
    Canvas canvas,
    Size size,
    double centerY,
    double maxBarHeight,
    double totalBarWidth,
    double currentIdx,
    Color color, {
    bool withGlow = false,
  }) {
    final double viewCenterX = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < waveform.length; i++) {
      double x;
      if (isScrolling) {
        x = viewCenterX + (i - currentIdx) * totalBarWidth;
      } else {
        x = i * (size.width / math.max(1, waveform.length));
      }

      // 只绘制可见区域内的波形
      if (x + barWidth < 0 || x > size.width) continue;

      final double barHeight = math.max(2.0, waveform[i] * maxBarHeight);
      final double y = centerY - barHeight / 2;

      // 设置颜色和渐变
      paint.color = color;
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.7),
          color,
          color.withValues(alpha: 0.7),
        ],
      ).createShader(Rect.fromLTWH(x, y, barWidth, barHeight));

      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );
      
      canvas.drawRRect(rrect, paint);
      
      // 添加发光效果 (只针对激活层)
      if (withGlow && barWidth > 2) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: 0.1)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRRect(rrect.inflate(1), glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.isScrolling != isScrolling;
  }
}
