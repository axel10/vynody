import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Helper to check if the current target platform is mobile (Android or iOS).
bool get isMobileAutoHidePlatform =>
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// A scope that listens to vertical scroll notifications and determines whether
/// the top header should be visible.
///
/// On mobile platforms (Android and iOS):
/// - Scrolling down (dragging finger upwards, [ScrollDirection.reverse]) smoothly hides the header.
/// - Scrolling up (dragging finger downwards, [ScrollDirection.forward]) or reaching the top immediately reveals the header.
///
/// On desktop platforms (Windows, Linux, macOS), the header is ALWAYS kept visible.
class AutoHideHeaderScope extends StatefulWidget {
  final Widget Function(BuildContext context, bool isVisible) builder;
  final bool forceVisible;
  final bool enabled;
  final double hideThreshold;
  final double showThreshold;

  const AutoHideHeaderScope({
    super.key,
    required this.builder,
    this.forceVisible = false,
    this.enabled = true,
    this.hideThreshold = 72.0,
    this.showThreshold = 72.0,
  });

  @override
  State<AutoHideHeaderScope> createState() => _AutoHideHeaderScopeState();
}

class _AutoHideHeaderScopeState extends State<AutoHideHeaderScope> {
  bool _isVisible = true;
  double _accumulatedDownScroll = 0.0;
  double _accumulatedUpScroll = 0.0;

  bool get _effectiveEnabled => widget.enabled && isMobileAutoHidePlatform;

  void _resetAccumulated() {
    _accumulatedDownScroll = 0.0;
    _accumulatedUpScroll = 0.0;
  }

  bool _onNotification(ScrollNotification notification) {
    if (!_effectiveEnabled) return false;
    if (widget.forceVisible) {
      _resetAccumulated();
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
      return false;
    }
    // Only respond to vertical scrolling, ignore horizontal lists/breadcrumbs
    if (notification.metrics.axis != Axis.vertical) return false;

    final pixels = notification.metrics.pixels;

    // 接近顶部缓冲区时，展开顶部栏并清空所有累计距离
    if (pixels <= 20) {
      _resetAccumulated();
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
      return false;
    }

    // 若已经收起：判断向上滚动展开（单次手势达到阈值展开，换向或松手清零）
    if (!_isVisible) {
      _accumulatedDownScroll = 0.0;

      // 手势换向或手势结束（松手）：清空向上累计，保证慢速小幅微调不误触
      if (notification is UserScrollNotification ||
          notification is ScrollEndNotification) {
        _accumulatedUpScroll = 0.0;
      } else if (notification is ScrollUpdateNotification) {
        final dy = notification.scrollDelta ?? 0.0;
        if (dy > 0) {
          // 向下滚动：重置向上累计
          _accumulatedUpScroll = 0.0;
        } else if (dy < 0) {
          // 向上滚动（dy < 0，对应内容向下移动，浏览之前的内容）
          _accumulatedUpScroll += -dy;
          if (_accumulatedUpScroll >= widget.showThreshold) {
            _accumulatedUpScroll = 0.0;
            setState(() => _isVisible = true);
          }
        }
      }
      return false;
    }

    // 若当前处于展开状态：重置向上累计，计算向下滚动收起
    _accumulatedUpScroll = 0.0;

    if (notification is ScrollUpdateNotification) {
      final dy = notification.scrollDelta ?? 0.0;
      if (pixels > 40.0) {
        if (dy > 0) {
          _accumulatedDownScroll += dy;
          if (_accumulatedDownScroll >= widget.hideThreshold) {
            _accumulatedDownScroll = 0.0;
            setState(() => _isVisible = false);
          }
        } else if (dy < 0) {
          // 向上轻微回滚时抵消部分向下累计
          _accumulatedDownScroll = (_accumulatedDownScroll + dy * 1.5)
              .clamp(0.0, widget.hideThreshold);
        }
      }
    } else if (notification is ScrollEndNotification) {
      if (_accumulatedDownScroll > 0.0) {
        _accumulatedDownScroll = 0.0;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveVisible =
        !_effectiveEnabled || widget.forceVisible || _isVisible;
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.builder(context, effectiveVisible),
    );
  }
}

/// An animated wrapper for top headers that smoothly slides up and fades out when [isVisible] is false.
/// On desktop platforms (Windows, Linux, macOS), it always renders without translation or fading.
class AutoHideHeader extends StatelessWidget {
  final bool isVisible;
  final Widget child;
  final Duration duration;

  const AutoHideHeader({
    super.key,
    required this.isVisible,
    required this.child,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  Widget build(BuildContext context) {
    final bool show = !isMobileAutoHidePlatform || isVisible;

    return AnimatedSlide(
      offset: show ? Offset.zero : const Offset(0, -1.0),
      duration: duration,
      curve: Curves.easeInOutCubic,
      child: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: duration,
        curve: Curves.easeInOutCubic,
        child: IgnorePointer(
          ignoring: !show,
          child: child,
        ),
      ),
    );
  }
}
