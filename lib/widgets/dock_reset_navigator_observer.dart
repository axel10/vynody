import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';

/// 监听局部或全局 [Navigator] 的路由变更，在页面跳转或返回时
/// 将浮动 Dock 栏平滑复位至原位（最上方）。
class DockResetNavigatorObserver extends NavigatorObserver {
  DockResetNavigatorObserver({ProviderContainer? container})
    : _container = container;

  final ProviderContainer? _container;

  void _scheduleReset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigator?.context;
      final container =
          _container ??
          (ctx != null && ctx.mounted
              ? ProviderScope.containerOf(ctx, listen: false)
              : null);
      if (container == null) return;
      resetFloatingDockWithContainer(container, animated: true);
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 跳过 Navigator 首次构建初始路由（previousRoute == null）
    if (previousRoute == null) return;
    _scheduleReset();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _scheduleReset();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null && newRoute == null) return;
    _scheduleReset();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) return;
    _scheduleReset();
  }
}
