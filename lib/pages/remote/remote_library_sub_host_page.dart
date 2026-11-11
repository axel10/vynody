import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/platform/right_queue_drawer_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/floating_capsule_header.dart';
import '../../widgets/library_action_bar.dart';
import '../../widgets/library_header_actions.dart';
import '../../widgets/library_selection_scope.dart';
import '../../widgets/library_tab_navigator.dart';
import '../../widgets/scroll_past_top.dart';
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
    required this.tabs,
    required this.navigatorKeys,
    required this.onBack,
    required this.onRefresh,
    this.initialIndex,
    this.selectionPanel,
    this.onPopBlocked,
  });

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
  /// 各分类页头动作的注册表，供滚动后浮出的顶栏胶囊取「更多」菜单内容。
  final LibraryHeaderActionsController _headerActions =
      LibraryHeaderActionsController();

  /// 栈里压了详情页的分类索引。详情页自带顶栏，位置与宿主顶栏重合，
  /// 不收起就会盖住详情页的返回按钮（与本地库同一处理）。
  final Set<int> _tabsWithChildRoutes = {};

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
    // IndexedStack 里所有分类都会 build，注册表必须按当前索引分账。
    _headerActions.setActiveTab(index);

    final bool isSelectionActive = ref.watch(isLibrarySelectionActiveProvider);
    final bool tabHasChildRoute = _tabsWithChildRoutes.contains(index);

    // 与本地 `LibrarySubHostPage` 同一套规则：
    // * 横屏由 Rail 承担分类导航与「回概览」，胶囊收起来避免和栏目标题重复；
    // * 竖屏没有 Rail，页头又是 sliver（滚上去会把返回键带走），所以只在
    //   离开顶部后浮出胶囊。
    final bool capsuleAllowed =
        !isLandscape && !tabHasChildRoute && !isSelectionActive;

    final Duration headerDuration = tabHasChildRoute
        ? Duration.zero
        : const Duration(milliseconds: 250);

    // 横屏避让 Rail 宽度，供顶栏浮动胶囊等宿主级组件定位。
    // 分类根页面的安全边距由各 LibraryTabNavigator 根路由自行计算并避让，
    // 使得 IndexedStack 保持全屏，子路由（详情页）自带的 avoidRail 可以精确生效一次。
    final double railWidth = ref.watch(effectiveSidebarRailWidthProvider(size));

    final Widget body = ScrollPastTopScope(
      tabIndex: index,
      enabled: !isLandscape && !tabHasChildRoute,
      builder: (context, isPastTop) => Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: index,
              children: [
                for (int i = 0; i < widget.tabs.length; i++)
                  LibraryTabNavigator(
                    navigatorKey: widget.navigatorKeys[i],
                    builder: (tabContext) => Consumer(
                      builder: (context, ref, child) {
                        final tabSize = MediaQuery.sizeOf(context);
                        final tabIsLandscape =
                            ref.watch(isEffectiveLandscapeProvider(tabSize));
                        final tabTopInset =
                            MediaQuery.paddingOf(context).top +
                            (tabIsLandscape ? 8.0 : 0.0);
                        final tabRailWidth = ref.watch(
                          effectiveSidebarRailWidthProvider(tabSize),
                        );
                        return LibraryHeaderActionsScope(
                          tabIndex: i,
                          controller: _headerActions,
                          child: Padding(
                            padding: EdgeInsets.only(
                              top: tabTopInset,
                              left: tabRailWidth,
                            ),
                            child: widget.tabs[i](context),
                          ),
                        );
                      },
                    ),
                    onHasChildRouteChanged: (hasChild) =>
                        _handleChildRouteChanged(i, hasChild),
                  ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: railWidth,
            right: 0,
            child: FloatingCapsuleHeader(
              visible: capsuleAllowed && isPastTop,
              duration: headerDuration,
              // 胶囊与内容区同源避让：`Padding(left: railWidth)` 已经在外层
              // 生效，这里只补 4/8 的呼吸位。
              child: Padding(
                padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                // 竖屏滚动离开顶部后只剩「返回 + 更多」。刷新不属于页头动作行
                // （每页页头都没有它），作为固定项附在菜单末尾 —— 页头滚走之后
                // 仍然需要「重试当前分类」的入口。
                child: LibraryTopNavCapsule(
                  controller: _headerActions,
                  onBack: widget.onBack,
                  extraActions: <LibraryToolbarAction>[
                    LibraryToolbarAction(
                      icon: Icons.refresh_rounded,
                      label: AppLocalizations.of(context)!.refresh,
                      onPressed: () => widget.onRefresh(index),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.selectionPanel != null) widget.selectionPanel!,
        ],
      ),
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
