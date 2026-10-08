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

  const AutoHideHeaderScope({
    super.key,
    required this.builder,
    this.forceVisible = false,
    this.enabled = true,
  });

  @override
  State<AutoHideHeaderScope> createState() => _AutoHideHeaderScopeState();
}

class _AutoHideHeaderScopeState extends State<AutoHideHeaderScope> {
  bool _isVisible = true;

  bool get _effectiveEnabled => widget.enabled && isMobileAutoHidePlatform;

  bool _onNotification(ScrollNotification notification) {
    if (!_effectiveEnabled) return false;
    if (widget.forceVisible) {
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
      return false;
    }
    // Only respond to vertical scrolling, ignore horizontal lists/breadcrumbs
    if (notification.metrics.axis != Axis.vertical) return false;

    final pixels = notification.metrics.pixels;

    if (pixels <= 20) {
      if (!_isVisible) {
        setState(() => _isVisible = true);
      }
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        if (!_isVisible) {
          setState(() => _isVisible = true);
        }
      } else if (notification.direction == ScrollDirection.reverse &&
          pixels > 40) {
        if (_isVisible) {
          setState(() => _isVisible = false);
        }
      }
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (delta != null) {
        if (delta > 2.0 && pixels > 40) {
          if (_isVisible) {
            setState(() => _isVisible = false);
          }
        } else if (delta < -2.0) {
          if (!_isVisible) {
            setState(() => _isVisible = true);
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
