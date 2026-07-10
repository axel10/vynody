import 'dart:async';
import 'package:flutter/material.dart';

/// A custom, memory-leak-safe tooltip widget.
///
/// It uses a standard [OverlayEntry] (instead of `OverlayPortal`) to avoid framework leaks
/// when semantics are active, and wraps its child with [Semantics] to ensure screen readers
/// can still read the tooltip message.
class AppTooltip extends StatefulWidget {
  const AppTooltip({
    super.key,
    required this.child,
    required this.message,
    this.excludeFromSemantics = false,
    this.preferBelow = true,
    this.waitDuration,
    this.showDuration,
    this.padding,
    this.margin,
    this.decoration,
    this.textStyle,
    this.verticalOffset,
  });

  final Widget child;
  final String message;
  final bool excludeFromSemantics;
  final bool preferBelow;
  final Duration? waitDuration;
  final Duration? showDuration;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Decoration? decoration;
  final TextStyle? textStyle;
  final double? verticalOffset;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;
  Timer? _waitTimer;
  Timer? _showTimer;
  bool _mouseIsInside = false;
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _animationController.addStatusListener(_handleAnimationStatus);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _removeEntry();
    }
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  void _showTooltip() {
    if (!mounted) return;

    if (_entry != null) {
      _showTimer?.cancel();
      _animationController.forward();
      if (widget.showDuration != null) {
        _showTimer = Timer(widget.showDuration!, _hideTooltip);
      }
      return;
    }

    final theme = Theme.of(context);
    final tooltipTheme = TooltipTheme.of(context);

    final TextStyle textStyle = widget.textStyle ??
        tooltipTheme.textStyle ??
        theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.onInverseSurface,
          fontSize: 12.0,
        );

    final Decoration decoration = widget.decoration ??
        tooltipTheme.decoration ??
        BoxDecoration(
          color: theme.colorScheme.inverseSurface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6.0),
        );

    final EdgeInsetsGeometry padding = widget.padding ??
        tooltipTheme.padding ??
        const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0);

    final EdgeInsetsGeometry margin = widget.margin ??
        tooltipTheme.margin ??
        const EdgeInsets.symmetric(horizontal: 16.0);

    final double verticalOffset = widget.verticalOffset ?? (widget.preferBelow ? 10.0 : -10.0);

    _entry = OverlayEntry(
      builder: (context) {
        return IgnorePointer(
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: widget.preferBelow
                ? Alignment.bottomCenter
                : Alignment.topCenter,
            followerAnchor: widget.preferBelow
                ? Alignment.topCenter
                : Alignment.bottomCenter,
            offset: Offset(0.0, verticalOffset),
            child: Align(
              alignment: widget.preferBelow ? Alignment.topCenter : Alignment.bottomCenter,
              child: FadeTransition(
                opacity: _animationController,
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 300.0),
                    decoration: decoration,
                    padding: padding,
                    margin: margin,
                    child: Text(
                      widget.message,
                      style: textStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_entry!);
    _animationController.forward();

    if (widget.showDuration != null) {
      _showTimer?.cancel();
      _showTimer = Timer(widget.showDuration!, _hideTooltip);
    }
  }

  void _hideTooltip() {
    _showTimer?.cancel();
    _showTimer = null;
    if (_entry == null) return;

    _animationController.reverse();
  }

  void _onPointerEnter() {
    _mouseIsInside = true;
    _waitTimer?.cancel();
    final waitDuration = widget.waitDuration ?? const Duration(milliseconds: 500);
    _waitTimer = Timer(waitDuration, () {
      if (_mouseIsInside) {
        _showTooltip();
      }
    });
  }

  void _onPointerExit() {
    _mouseIsInside = false;
    _waitTimer?.cancel();
    _hideTooltip();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _showTimer?.cancel();
    _animationController.removeStatusListener(_handleAnimationStatus);
    _animationController.dispose();
    _removeEntry();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = CompositedTransformTarget(
      link: _layerLink,
      child: widget.child,
    );

    result = MouseRegion(
      onEnter: (_) => _onPointerEnter(),
      onExit: (_) => _onPointerExit(),
      child: result,
    );

    result = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () {
        _showTooltip();
        _showTimer?.cancel();
        // Automatically hide after 2 seconds on mobile long press unless showDuration is provided
        _showTimer = Timer(widget.showDuration ?? const Duration(seconds: 2), _hideTooltip);
      },
      child: result,
    );

    if (!widget.excludeFromSemantics && widget.message.isNotEmpty) {
      result = Semantics(
        tooltip: widget.message,
        child: result,
      );
    }

    return result;
  }
}
