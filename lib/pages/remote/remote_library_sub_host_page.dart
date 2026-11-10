import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/platform/right_queue_drawer_controller.dart';import '../../l10n/app_localizations.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/app_top_nav_bar.dart';
import '../../widgets/library_selection_scope.dart';
import '../../widgets/library_tab_navigator.dart';
import '../main_layout_riverpod.dart';

/// 远程媒体库二级分类宿主，与本地库的 `LibrarySubHostPage` 同构。
///
/// 只负责「容器与路由」，不持有数据：六个分类的根页面、标题、导航栈 key、
/// 刷新与顶栏动作全部由 `RemoteLibraryPage` 传入 —— 那里是唯一的数据与
/// 状态宿主（5 个 loader、筛选、多选、排序偏好都在同一个 State 上）。
///
/// 与本地库子宿主的差别只有两点：
/// * 分类索引来自 [remoteLibraryActiveTabIndexProvider]（跨层信号，Rail 用），
///   而不是本地库的 `libraryActiveTabIndexProvider`；
/// * 横竖屏的顶栏显隐规则一致：横屏恒隐藏（由 Rail 承担分类导航），
///   竖屏滚动离开顶部后才滑出浮动胶囊。
class RemoteLibrarySubHostPage extends ConsumerStatefulWidget {
  const RemoteLibrarySubHostPage({
    super.key,
    required this.titles,
    required this.tabs,
    required this.navigatorKeys,
    required this.onBack,
    required this.onRefresh,
    this.initialIndex,
    this.selectionPanel,
    this.onPopBlocked,
  });

  /// 与 [tabs] 一一对应的分类标题（顶栏浮动胶囊用）。
  final List<String> titles;

  /// 各分类的根页面构建器，一条对应一个独立导航域。
  final List<WidgetBuilder> tabs;

  /// 各分类的导航栈 key，由父页持有以便返回键统一分发。
  final List<GlobalKey<NavigatorState>> navigatorKeys;

  /// 回到远程库概览页。
  final VoidCallback onBack;

  /// 刷新当前分类。
  final ValueChanged<int> onRefresh;

  /// 没有跨层信号时的初始分类（来自深链 / 会话恢复）。
  final int? initialIndex;

  /// 多选面板（必须是 `Stack` 的直接子元素）。
  final Widget? selectionPanel;

  /// 多选态下被系统返回拦住时的回调（取消多选）。由父页提供。
  final VoidCallback? onPopBlocked;

  @override
  ConsumerState<RemoteLibrarySubHostPage> createState() =>
      _RemoteLibrarySubHostPageState();
}

class _RemoteLibrarySubHostPageState
    extends ConsumerState<RemoteLibrarySubHostPage> {
  /// 栈里压了详情页的分类索引。详情页自带顶栏，位置与宿主顶栏重合，
  /// 不收起就会盖住详情页的返回按钮（与本地库同一处理）。
  final Set<int> _tabsWithChildRoutes = {};

  /// 各分类是否已向上滚动离开顶部（浮动胶囊的显隐依据）。
  final Map<int, bool> _tabScrolledPastTop = {};

  /// provider 被置 null（回概览）时冻结上一帧索引，避免离场瞬间跳回第一个分类。
  late int _lastIndex = (widget.initialIndex ?? 0).clamp(
    0,
    widget.tabs.length - 1,
  );

  void _handleChildRouteChanged(int index, bool hasChild) {
    if (!mounted) return;
    final bool changed = hasChild
        ? _tabsWithChildRoutes.add(index)
        : _tabsWithChildRoutes.remove(index);
    if (!changed) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final bool isLandscape = ref.watch(isEffectiveLandscapeProvider(size));

    final int? active = ref.watch(remoteLibraryActiveTabIndexProvider);
    if (active != null) {
      _lastIndex = active.clamp(0, widget.tabs.length - 1);
    }
    final int index = _lastIndex;

    final bool isSelectionActive = ref.watch(isLibrarySelectionActiveProvider);
    final bool tabHasChildRoute = _tabsWithChildRoutes.contains(index);
    final bool isPastTop = _tabScrolledPastTop[index] ?? false;

    // 与本地 `LibrarySubHostPage` 同一套规则：
    // * 横屏由 Rail 承担分类导航与「回概览」，胶囊收起来避免和栏目标题重复；
    // * 竖屏没有 Rail，页头又是 sliver（滚上去会把返回键带走），所以只在
    //   离开顶部后浮出胶囊。
    final bool hideTopNavBar =
        isLandscape || tabHasChildRoute || !isPastTop;

    final Duration headerDuration = tabHasChildRoute
        ? Duration.zero
        : const Duration(milliseconds: 250);

    // 顶部安全边距：窗口化时 `RemoteLibraryPage` 已经补过 32，这里只让
    // 系统状态栏（非窗口化）与横屏的 8dp 呼吸位。
    final double topInset =
        MediaQuery.paddingOf(context).top + (isLandscape ? 8.0 : 0.0);

    // 横屏避让 Rail：外层 `MainLayout` 已不再对远程库做 `Padding(left:)`，
    // 让位必须落在页面内部，否则整页会被 Rail 压住左边缘。
    final double railWidth = ref.watch(effectiveSidebarRailWidthProvider(size));

    final String? title = index < widget.titles.length
        ? widget.titles[index]
        : null;

    final Widget body = Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.metrics.axis != Axis.vertical) return false;
              if (tabHasChildRoute) return false;
              final bool past =
                  notification.metrics.pixels >
                  kHeaderFloatingCapsuleThreshold;
              if ((_tabScrolledPastTop[index] ?? false) != past) {
                setState(() => _tabScrolledPastTop[index] = past);
              }
              return false;
            },
            child: Padding(
              padding: EdgeInsets.only(top: topInset, left: railWidth),
              child: IndexedStack(
                index: index,
                children: [
                  for (int i = 0; i < widget.tabs.length; i++)
                    LibraryTabNavigator(
                      navigatorKey: widget.navigatorKeys[i],
                      builder: widget.tabs[i],
                      onHasChildRouteChanged: (hasChild) =>
                          _handleChildRouteChanged(i, hasChild),
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            offset: hideTopNavBar ? const Offset(0, -1.0) : Offset.zero,
            duration: headerDuration,
            curve: Curves.easeInOutCubic,
            child: AnimatedOpacity(
              opacity: hideTopNavBar ? 0.0 : 1.0,
              duration: headerDuration,
              curve: Curves.easeInOutCubic,
              child: IgnorePointer(
                ignoring: hideTopNavBar,
                // 胶囊与内容区同源避让：`Padding(left: railWidth)` 已经在外层
                // 生效，这里只补 4/8 的呼吸位。
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                  child: AppTopNavBar(
                    title: title ?? '',
                    titleKey: ValueKey('remote_library_sub_title_$index'),
                    isFloatingCapsule: true,
                    onBack: widget.onBack,
                    // 定位与下载管理器已随各分类页头常驻，胶囊只补一个刷新：
                    // 页头滚走之后仍需要「重试当前分类」的入口。
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: AppLocalizations.of(context)!.refresh,
                        onPressed: () => widget.onRefresh(index),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.selectionPanel != null) widget.selectionPanel!,
      ],
    );

    return PopScope(
      // 多选态先退多选；分类栈里有详情页时让给该分类自己的 Navigator。
      canPop: !isSelectionActive && !tabHasChildRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (tabHasChildRoute) {
          widget.navigatorKeys[index].currentState?.maybePop();
        } else {
          widget.onPopBlocked?.call();
        }
      },
      child: Scaffold(body: body),
    );
  }
}
