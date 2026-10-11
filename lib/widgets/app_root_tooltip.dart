import 'dart:async';
import 'package:flutter/material.dart';

/// 在全局根 Overlay ([OverlayChildLocation.rootOverlay]) 上显示工具提示的组件。
///
/// 相比 Flutter 原生 [Tooltip] 强制挂载到最近祖先 Overlay，本组件始终挂载到顶层根 Overlay，
/// 可避免嵌套路由（如媒体库局部 Navigator）的 Tooltip 浮层被外层同级或上层组件（如侧边 Rail 栏）遮挡。
class AppRootTooltip extends StatefulWidget {
  final String message;
  final Widget child;
  final Duration waitDuration;

  const AppRootTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration = const Duration(milliseconds: 350),
  });

  @override
  State<AppRootTooltip> createState() => _AppRootTooltipState();
}

class _AppRootTooltipState extends State<AppRootTooltip> {
  final OverlayPortalController _controller = OverlayPortalController();
  Timer? _showTimer;
  Timer? _dismissTimer;

  @override
  void dispose() {
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _onMouseEnter() {
    if (widget.message.isEmpty) return;
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    _showTimer = Timer(widget.waitDuration, () {
      if (mounted) {
        _controller.show();
      }
    });
  }

  void _onMouseExit() {
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    if (_controller.isShowing) {
      _controller.hide();
    }
  }

  void _onLongPress() {
    if (widget.message.isEmpty) return;
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    _controller.show();
    _dismissTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted && _controller.isShowing) {
        _controller.hide();
      }
    });
  }

  void _onPointerDown() {
    _showTimer?.cancel();
    _dismissTimer?.cancel();
    if (_controller.isShowing) {
      _controller.hide();
    }
  }

  Widget _buildOverlay(BuildContext context, OverlayChildLayoutInfo layoutInfo) {
    if (layoutInfo.childPaintTransform.determinant() == 0.0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tooltipTheme = theme.tooltipTheme;

    final Offset target = MatrixUtils.transformPoint(
      layoutInfo.childPaintTransform,
      layoutInfo.childSize.center(Offset.zero),
    );

    final Widget bubble = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: child,
        );
      },
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: tooltipTheme.decoration ??
                BoxDecoration(
                  color: isDark
                      ? const Color(0xE62C2C2E)
                      : const Color(0xE6F2F2F7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
            padding: tooltipTheme.padding ??
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              widget.message,
              style: tooltipTheme.textStyle ??
                  theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _RootTooltipPositionDelegate(
          target: target,
          targetSize: layoutInfo.childSize,
        ),
        child: bubble,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) {
      return widget.child;
    }

    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _controller,
      overlayLocation: OverlayChildLocation.rootOverlay,
      overlayChildBuilder: _buildOverlay,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _onPointerDown(),
        child: MouseRegion(
          onEnter: (_) => _onMouseEnter(),
          onExit: (_) => _onMouseExit(),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: _onLongPress,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RootTooltipPositionDelegate extends SingleChildLayoutDelegate {
  final Offset target;
  final Size targetSize;

  _RootTooltipPositionDelegate({
    required this.target,
    required this.targetSize,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return positionDependentBox(
      size: size,
      childSize: childSize,
      target: target,
      verticalOffset: targetSize.height / 2 + 6.0,
      preferBelow: true,
      margin: 8.0,
    );
  }

  @override
  bool shouldRelayout(_RootTooltipPositionDelegate oldDelegate) {
    return target != oldDelegate.target || targetSize != oldDelegate.targetSize;
  }
}
