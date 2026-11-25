import 'dart:async';

import 'package:flutter/material.dart';

/// 仅在键盘 `viewInsets.bottom` 停止变化（动画结束）后才触发一次重建的构建器。
///
/// 在 Android 键盘弹出/收起动画期间，`MediaQuery.viewInsets.bottom` 会在十几帧内连续变化。
/// 直接在表单或页面 `build()` 中读取会导致每帧都触发重建与重排。
/// 使用本组件可在动画过程中保持布局静止，待动画稳定后一次性完成布局调整。
class SettledViewInsetsBuilder extends StatefulWidget {
  const SettledViewInsetsBuilder({
    super.key,
    required this.builder,
    this.child,
    this.settleDelay = const Duration(milliseconds: 120),
  });

  final Widget Function(BuildContext context, double bottomInset, Widget? child)
      builder;
  final Widget? child;
  final Duration settleDelay;

  @override
  State<SettledViewInsetsBuilder> createState() =>
      _SettledViewInsetsBuilderState();
}

class _SettledViewInsetsBuilderState extends State<SettledViewInsetsBuilder> {
  double _settledBottomInset = 0.0;
  double _pendingBottomInset = 0.0;
  Timer? _settleTimer;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final latest = MediaQuery.viewInsetsOf(context).bottom;
    if (!_initialized) {
      _initialized = true;
      _settledBottomInset = latest;
      _pendingBottomInset = latest;
      return;
    }

    _pendingBottomInset = latest;
    if (latest == _settledBottomInset) {
      _settleTimer?.cancel();
      _settleTimer = null;
      return;
    }

    _settleTimer?.cancel();
    _settleTimer = Timer(widget.settleDelay, () {
      if (!mounted) return;
      if (_settledBottomInset != _pendingBottomInset) {
        setState(() {
          _settledBottomInset = _pendingBottomInset;
        });
      }
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _settledBottomInset, widget.child);
  }
}

/// 仅在键盘可见性（`viewInsets.bottom > 0`）布尔状态切换时重建的构建器。
///
/// 通过 [WidgetsBindingObserver.didChangeMetrics] 监听窗口指标，不订阅 `MediaQuery`
/// InheritedWidget，从而避免键盘动画期间每一帧都触发外层页面或底栏重建。
class KeyboardVisibilityBuilder extends StatefulWidget {
  const KeyboardVisibilityBuilder({
    super.key,
    required this.builder,
    this.child,
  });

  final Widget Function(
    BuildContext context,
    bool isKeyboardVisible,
    Widget? child,
  ) builder;
  final Widget? child;

  @override
  State<KeyboardVisibilityBuilder> createState() =>
      _KeyboardVisibilityBuilderState();
}

class _KeyboardVisibilityBuilderState extends State<KeyboardVisibilityBuilder>
    with WidgetsBindingObserver {
  bool _isKeyboardVisible = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _isKeyboardVisible = _readKeyboardVisible();
    }
  }

  bool _readKeyboardVisible() {
    final view = View.maybeOf(context);
    if (view == null) return false;
    return view.viewInsets.bottom > 0;
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final next = _readKeyboardVisible();
    if (next != _isKeyboardVisible) {
      setState(() {
        _isKeyboardVisible = next;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _isKeyboardVisible, widget.child);
  }
}
