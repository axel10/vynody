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
    this.hideThreshold = 24.0,
    this.showThreshold = 36.0,
  });

  @override
  State<AutoHideHeaderScope> createState() => _AutoHideHeaderScopeState();
}

class _AutoHideHeaderScopeState extends State<AutoHideHeaderScope> {
  bool _isVisible = true;
  double _accumulatedScroll = 0.0;

  bool get _effectiveEnabled => widget.enabled && isMobileAutoHidePlatform;

  bool _onNotification(ScrollNotification notification) {
    if (!_effectiveEnabled) return false;
    if (widget.forceVisible) {
      _accumulatedScroll = 0.0;
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
      return false;
    }
    // Only respond to vertical scrolling, ignore horizontal lists/breadcrumbs
    if (notification.metrics.axis != Axis.vertical) return false;

    final pixels = notification.metrics.pixels;

    if (pixels <= 20) {
      _accumulatedScroll = 0.0;
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
      return false;
    }

    if (notification is UserScrollNotification) {
      // Clear accumulated distance on user gesture direction changes or idle.
      _accumulatedScroll = 0.0;
    } else if (notification is ScrollEndNotification) {
      _accumulatedScroll = 0.0;
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null && delta != 0.0) {
        if (delta > 0) {
          // Scrolling down (content moves up, viewing lower content)
          if (_accumulatedScroll < 0) {
            _accumulatedScroll = 0.0;
          }
          if (_isVisible && pixels > 40) {
            _accumulatedScroll += delta;
            if (_accumulatedScroll >= widget.hideThreshold) {
              setState(() => _isVisible = false);
              _accumulatedScroll = 0.0;
            }
          }
        } else if (delta < 0) {
          // Scrolling up (content moves down, viewing previous content)
          if (_accumulatedScroll > 0) {
            _accumulatedScroll = 0.0;
          }
          if (!_isVisible) {
            _accumulatedScroll += -delta;
            if (_accumulatedScroll >= widget.showThreshold) {
              setState(() => _isVisible = true);
              _accumulatedScroll = 0.0;
            }
          }
        }
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
