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
  });

  /// 由 [LibrarySubHostPage] 统一持有并交给返回键分发使用。
  final GlobalKey<NavigatorState> navigatorKey;

  /// 子分类根页面。
  final WidgetBuilder builder;

  @override
  State<LibraryTabNavigator> createState() => _LibraryTabNavigatorState();
}

class _LibraryTabNavigatorState extends State<LibraryTabNavigator> {
  late final HeroController _heroController = HeroController();

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

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
        observers: [_heroController],
        onGenerateInitialRoutes: (navigator, initialRoute) =>
            <Route<void>>[_buildRootRoute()],
        onGenerateRoute: (settings) => _buildRootRoute(),
      ),
    );
  }
}
