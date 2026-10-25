import 'package:flutter/material.dart';

/// 媒体库子分类根路由的名称。
const String kLibraryTabRootRouteName = 'library_tab_root';

/// 媒体库单个子分类的独立导航域。
///
/// 每个子分类（歌单 / 最近播放 / 专辑 / 艺术家 / 流派 / 年份 …）各持有一个
/// [Navigator]，三级页面（专辑、艺术家、流派、年份详情）压在自己分类的栈里。
/// 于是 Rail 上横向切换子分类时：
///
/// * 各分类的路由栈互不影响，切走再切回仍停在原来的详情页；
/// * 不会发生「出栈」这件事，也就不会顺带触发封面 Hero 反向飞向隐藏分类；
/// * 每个 Navigator 自带 [HeroController]，Hero 只会在同一分类内配对，
///   不会跨分类取到不可见的目标。
///
/// 状态生命周期 = Widget 生命周期：切分类不销毁 → 保留；真正退出
/// （宿主路由出栈）才销毁 → 复位。
class LibraryTabNavigator extends StatefulWidget {
  const LibraryTabNavigator({
    super.key,
    required this.navigatorKey,
    required this.builder,
    this.onHasChildRouteChanged,
  });

  /// 由 [LibrarySubHostPage] 统一持有并交给返回键分发使用。
  final GlobalKey<NavigatorState> navigatorKey;

  /// 子分类根页面。
  final WidgetBuilder builder;

  /// 本分类栈里「根路由之上是否还有页面」变化时回调。
  ///
  /// 宿主据此收起自己的顶部导航栏：三级页面自带 [AppTopNavBar]，两者位置完全重合，
  /// 若宿主顶栏继续盖在上面，用户点到的会是宿主的返回按钮（弹掉整个二级宿主），
  /// 看到的是子分类标题而不是详情页标题。
  final ValueChanged<bool>? onHasChildRouteChanged;

  @override
  State<LibraryTabNavigator> createState() => _LibraryTabNavigatorState();
}

class _LibraryTabNavigatorState extends State<LibraryTabNavigator> {
  late final _TabRouteStackObserver _stackObserver = _TabRouteStackObserver(
    (hasChild) => widget.onHasChildRouteChanged?.call(hasChild),
  );

  Route<void> _buildRootRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: kLibraryTabRootRouteName),
      builder: widget.builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      // 阻止子分类 Navigator 的导航通知向上冒泡，避免干扰外层返回控制。
      onNotification: (notification) => true,
      child: Navigator(
        key: widget.navigatorKey,
        observers: [_stackObserver],
        onGenerateInitialRoutes: (navigator, initialRoute) =>
            <Route<void>>[_buildRootRoute()],
        onGenerateRoute: (settings) => _buildRootRoute(),
      ),
    );
  }
}

/// 只关心「根路由之上是否还有页面」，用推入/弹出计数而不是 `canPop()`，
/// 避免依赖 pop 过程中 `_history` 的中间态。
class _TabRouteStackObserver extends NavigatorObserver {
  _TabRouteStackObserver(this.onChanged);

  final ValueChanged<bool> onChanged;
  int _childRouteCount = 0;

  bool _isRoot(Route<dynamic> route) =>
      route.settings.name == kLibraryTabRootRouteName;

  void _emit() => onChanged(_childRouteCount > 0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 初始路由的 didPush 发生在 Navigator 首次构建期间，此时 previousRoute 为 null
    // 且计数本就不该变化 —— 早退可以顺带避开「build 中 setState」。
    if (_isRoot(route)) return;
    _childRouteCount++;
    _emit();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isRoot(route)) return;
    if (_childRouteCount > 0) _childRouteCount--;
    _emit();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isRoot(route)) return;
    if (_childRouteCount > 0) _childRouteCount--;
    _emit();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null && _isRoot(oldRoute)) return;
    if (newRoute != null && _isRoot(newRoute)) return;
    // 非根路由之间的替换不改变计数。
  }
}
