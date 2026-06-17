import 'dart:math' as math;
import 'package:flutter/material.dart';

class PlayingEqualizerIcon extends StatefulWidget {
  const PlayingEqualizerIcon({
    super.key,
    required this.color,
    this.size = 16.0,
    this.isPlaying = true,
  });

  final Color color;
  final double size;
  final bool isPlaying;

  @override
  State<PlayingEqualizerIcon> createState() => _PlayingEqualizerIconState();
}

class _PlayingEqualizerIconState extends State<PlayingEqualizerIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800), // 动画速度 
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant PlayingEqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / 4.5;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(0, barWidth),
              _buildBar(1, barWidth),
              _buildBar(2, barWidth),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBar(int index, double width) {
    double value = 0.2; // default min height ratio when not playing
    if (widget.isPlaying) {
      final animationValue = _controller.value;
      switch (index) {
        case 0:
          // 2 cycles per loop
          value = 0.25 + 0.75 * (math.sin(animationValue * 2 * math.pi * 2) + 1.0) / 2.0;
          break;
        case 1:
          // 3 cycles per loop, with phase offset
          value = 0.15 + 0.85 * (math.sin(animationValue * 2 * math.pi * 3 + math.pi / 4) + 1.0) / 2.0;
          break;
        case 2:
          // 4 cycles per loop, with phase offset
          value = 0.3 + 0.7 * (math.sin(animationValue * 2 * math.pi * 4 + math.pi / 2) + 1.0) / 2.0;
          break;
      }
    } else {
      // Pause state: static varying heights for a clean look
      switch (index) {
        case 0:
          value = 0.35;
          break;
        case 1:
          value = 0.6;
          break;
        case 2:
          value = 0.4;
          break;
      }
    }

    final barHeight = math.max(1.5, widget.size * value);

    return Container(
      width: width,
      height: barHeight,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(width / 2),
      ),
    );
  }
}
