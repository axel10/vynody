import 'package:flutter/material.dart';
import 'package:vynody/widgets/app_tooltip.dart';

class AnimatedPlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback? onPressed;
  final Color color;
  final double size;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final MaterialTapTargetSize? materialTapTargetSize;

  const AnimatedPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    required this.color,
    required this.size,
    this.tooltip,
    this.padding = EdgeInsets.zero,
    this.materialTapTargetSize,
  });

  @override
  State<AnimatedPlayPauseButton> createState() => _AnimatedPlayPauseButtonState();
}

class _AnimatedPlayPauseButtonState extends State<AnimatedPlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedPlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget buttonWidget = IconButton(
      onPressed: widget.onPressed,
      padding: widget.padding,
      constraints: const BoxConstraints(),
      style: widget.materialTapTargetSize != null
          ? IconButton.styleFrom(tapTargetSize: widget.materialTapTargetSize)
          : null,
      icon: AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _animationController,
        color: widget.color,
        size: widget.size,
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return AppTooltip(
        message: widget.tooltip!,
        child: buttonWidget,
      );
    }

    return buttonWidget;
  }
}
