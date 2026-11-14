import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'albums_tab.dart';import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'recently_played_tab.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';
import 'rated_songs_tab.dart';
import 'genres_tab.dart';
import 'years_tab.dart';
import 'library_dashboard_view.dart';
import 'library_search_page.dart';
import 'main_layout_riverpod.dart';
import '../player/library/library_overview_providers.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_tab_navigator.dart';
import '../widgets/app_top_nav_bar.dart';
import '../widgets/library_header_actions.dart';
import '../widgets/library_large_title.dart';
import '../widgets/library_sub_host_layout.dart';
import '../widgets/scroll_past_top.dart';
import '../utils/layout_constants.dart';
import '../utils/app_log.dart';
import '../utils/app_orientation_manager.dart';
import '../player/platform/right_queue_drawer_controller.dart';

// 媒体库页面：两级嵌套 Navigator 架构。
//
// 第一级是本页自带的局部 Navigator，栈里只有「仪表盘」与「二级宿主」；第二级是
// 二级宿主内部为每个子分类各开的一个 Navigator（见 library_tab_navigator.dart），
// 三级页面（专辑 / 艺术家 / 流派 / 年份详情）压在自己子分类的栈里。
//
// 这样横向切换子分类（Rail 子项）只是改 IndexedStack 的索引，不动任何路由栈：
// 各分类的滚动位置、搜索词、多选状态与详情页原地保留，也不会因为「出栈」而触发
// 封面 Hero 飞向不可见的分类。
//
// 状态生命周期：切子分类 / 切主页面都不销毁页面，状态保留；只有真正退出页面
// （二级宿主出栈回到仪表盘）才会 dispose 并复位。
//
// 横屏下外层 Rail 栏始终常驻显示，右侧二级页面平级流畅切换并避让 Rail；
// 竖屏下二级页面渲染顶部标题与返回按钮，原生支持 iOS 边缘滑动返回与 Android 物理/手势返回；
// 横竖屏旋转期间，当前二级页面位置、滚动偏好与路由栈天然保活，零闪烁。

class LibraryPage extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;
  final bool? useSidebar;

  /// 左侧导航栏（Rail）当前实际宽度，宽屏布局下用它作为内容区左侧避让间距
  final double railWidth;

  const LibraryPage({
    super.key,
    this.initialTabIndex = 0,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
    this.useSidebar,
    this.railWidth = kSidebarRailWidthCollapsed,
  });

  @override
  ConsumerState<LibraryPage> createState() => LibraryPageState();
}

class LibraryPageState extends ConsumerState<LibraryPage> {
  late final HeroController _heroController;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// 各子分类各自持有的 Navigator key，交给二级宿主挂载、由返回键统一分发。
  final List<GlobalKey<NavigatorState>> _tabNavigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
        9,
        (index) => GlobalKey<NavigatorState>(debugLabel: 'library_tab_$index'),
      );

  /// 标记二级宿主页是否已压在局部 Navigator 栈顶
  bool _isSubHostPushed = false;

  /// 当前展示的子分类索引，null 表示停在仪表盘。
  /// 与 [libraryActiveTabIndexProvider] 同步，但页面退出动画期间 provider 会被置回
  /// null，这里保留最后的值，避免返回键分发瞬间找不到当前分类。
  int? _activeSubIndex;

  @override
  void initState() {
    super.initState();
    _heroController = HeroController();
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  /// 供外层（如 MainLayout 的 Android 返回键或快捷键）拦截调用。
  ///
  /// 顺序：多选 → 3D 视图 → 当前子分类的三级详情 → 二级宿主 → 交给外层。
  bool handleBackPressed() {
    final selectionState = ref.read(librarySelectionStateProvider);
    final is3d = ref.read(isAlbum3DViewActiveProvider);
    final int? subIndex = _activeSubIndex;
    final NavigatorState? tabNavigator =
        subIndex == null ? null : _tabNavigatorKeys[subIndex].currentState;
    final bool tabCanPop = tabNavigator?.canPop() ?? false;
    final bool hostCanPop = _navigatorKey.currentState?.canPop() ?? false;
    AppLog.log(
      '[NavTrace] LibraryPageState.handleBackPressed: '
      'selectionActive=${selectionState.isActive}, '
      'is3DActive=$is3d, '
      'subIndex=$subIndex, '
      'tabCanPop=$tabCanPop, '
      'hostCanPop=$hostCanPop, '
      '_isSubHostPushed=$_isSubHostPushed',
      mirrorToConsole: true,
    );
    if (selectionState.isActive &&
        selectionState.scope != LibrarySelectionScope.none) {
      AppLog.log('[NavTrace] LibraryPageState: clearing selection mode', mirrorToConsole: true);
      ref.read(librarySelectionStateProvider.notifier).clear();
      return true;
    }
    if (is3d) {
      AppLog.log('[NavTrace] LibraryPageState: clearing 3D view', mirrorToConsole: true);
      AppOrientationManager.toggleCoverFlow(ref, context, target: false);
      return true;
    }
    if (tabCanPop) {
      AppLog.log('[NavTrace] LibraryPageState: popping tab navigator route', mirrorToConsole: true);
      tabNavigator?.maybePop();
      return true;
    }
    if (hostCanPop) {
      AppLog.log('[NavTrace] LibraryPageState: popping nested navigator route', mirrorToConsole: true);
      _navigatorKey.currentState?.maybePop();
      return true;
    }
    AppLog.log('[NavTrace] LibraryPageState: cannot pop nested navigator, returning false', mirrorToConsole: true);
    return false;
  }

  void _openSubHost(
    int index, {
    bool initialAlbums3DView = false,
    int initialAlbums3DIndex = 0,
  }) {
    AppLog.log(
      '[NavTrace] LibraryPage._openSubHost: index=$index, isSubHostPushed=$_isSubHostPushed',
      mirrorToConsole: true,
    );
    ref.read(librarySelectionScopeProvider.notifier).clear();
    if (index == 0) {
      ref.read(selectedPlaylistIdProvider.notifier).set(null);
    }

    if (_isSubHostPushed) {
      // 已在二级宿主内：只切换子分类索引，各分类的路由栈原地保留。
      ref.read(libraryActiveTabIndexProvider.notifier).set(index);
      return;
    }

    _isSubHostPushed = true;
    ref.read(libraryActiveTabIndexProvider.notifier).set(index);
    final route = _buildSubHostRoute(
      initialAlbums3DView: initialAlbums3DView,
      initialAlbums3DIndex: initialAlbums3DIndex,
    );

    _navigatorKey.currentState?.push(route).then((_) {
      AppLog.log('[NavTrace] LibraryPage: subHost route popped! isSubHostPushed=false', mirrorToConsole: true);
      _isSubHostPushed = false;
      if (mounted && ref.read(libraryActiveTabIndexProvider) != null) {
        ref.read(libraryActiveTabIndexProvider.notifier).set(null);
      }
    });
  }

  Route<void> _buildDashboardRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'library_dashboard'),
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final isLandscape = ref.watch(isEffectiveLandscapeProvider(size));
        final double safeTop = getTitleBarTopPadding(
          context,
          defaultWindowPadding: isLandscape ? 32.0 : 36.0,
        );
        final double topPadding = isLandscape ? (safeTop + 8.0) : safeTop;
        final double leftPadding =
            ref.watch(effectiveSidebarRailWidthProvider(size));

        return LibraryDashboardView(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onNavigateToSubIndex: (sub) => _openSubHost(sub),
          onOpenSearch: () =>
              _navigatorKey.currentState?.push(_buildSearchRoute()),
        );
      },
    );
  }

  /// 全局搜索页：压在局部 Navigator 上，返回手势与三级页面同一套机制。
  ///
  /// 它不属于任何子分类，所以不占 `libraryActiveTabIndexProvider` 的索引，
  /// 也不会动各分类原有的路由栈。
  Route<void> _buildSearchRoute() {
    final page = Builder(
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final isLandscape = ref.watch(isEffectiveLandscapeProvider(size));
        final double safeTop = getTitleBarTopPadding(
          context,
          defaultWindowPadding: isLandscape ? 32.0 : 36.0,
        );
        final double topPadding = isLandscape ? (safeTop + 8.0) : safeTop;
        final double leftPadding =
            ref.watch(effectiveSidebarRailWidthProvider(size));
        return LibrarySearchPage(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      },
    );

    return (Platform.isIOS || Platform.isMacOS)
        ? CupertinoPageRoute<void>(
            settings: const RouteSettings(name: 'library_search'),
            builder: (_) => page,
          )
        : MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'library_search'),
            builder: (_) => page,
          );
  }

  Route<void> _buildSubHostRoute({
    bool initialAlbums3DView = false,
    int initialAlbums3DIndex = 0,
  }) {
    final page = LibrarySubHostPage(
      initialAlbums3DView: initialAlbums3DView,
      initialAlbums3DIndex: initialAlbums3DIndex,
      tabNavigatorKeys: _tabNavigatorKeys,
    );

    return (Platform.isIOS || Platform.isMacOS)
        ? CupertinoPageRoute<void>(
            settings: const RouteSettings(name: 'library_sub_host'),
            builder: (_) => page,
          )
        : MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'library_sub_host'),
            builder: (_) => page,
          );
  }

  @override
  Widget build(BuildContext context) {
    // 监听全局或 Rail 触发的子分类索引变更。
    //
    // 关键：非 null 时不再做任何出栈动作。二级宿主是局部 Navigator 上的一条路由，
    // 里面每个子分类各自持有 Navigator，切分类只是换 IndexedStack 的索引；
    // 曾经在这里 popUntil 到宿主，导致切走就丢详情、还顺带播放了一次封面 Hero
    // 反向飞向不可见分类的动画。
    ref.listen<int?>(libraryActiveTabIndexProvider, (previous, next) {
      if (next != null) {
        _activeSubIndex = next;
        if (!_isSubHostPushed) {
          _openSubHost(next);
        }
      } else {
        _activeSubIndex = null;
        if (_isSubHostPushed) {
          // 语义是「回到仪表盘」，属于真正退出二级页面，出栈即复位页面状态。
          _navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      }
    });

    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        // 阻止嵌套 Navigator 向上冒泡 NavigationNotification 覆盖外层返回控制
        return true;
      },
      child: Navigator(
        key: _navigatorKey,
        observers: [_heroController],
        onGenerateInitialRoutes: (navigator, initialRoute) {
          final int? persistedIndex = ref.read(libraryActiveTabIndexProvider);
          final bool hasDeepLink =
              widget.initialAlbums3DView || widget.initialTabIndex != 0;
          final int? targetIndex = widget.initialAlbums3DView
              ? 4
              : (widget.initialTabIndex != 0
                  ? widget.initialTabIndex
                  : persistedIndex);
          AppLog.log(
            '[NavTrace] LibraryPage onGenerateInitialRoutes: initialTabIndex=${widget.initialTabIndex}, '
            'persistedIndex=$persistedIndex, targetIndex=$targetIndex, hasDeepLink=$hasDeepLink',
            mirrorToConsole: true,
          );

          final routes = <Route<void>>[_buildDashboardRoute()];
          if (hasDeepLink || targetIndex != null) {
            _isSubHostPushed = true;
            _activeSubIndex = targetIndex;
            final subRoute = _buildSubHostRoute(
              initialAlbums3DView: widget.initialAlbums3DView,
              initialAlbums3DIndex: widget.initialAlbums3DIndex,
            );
            subRoute.popped.then((_) {
              AppLog.log(
                '[NavTrace] LibraryPage subRoute (initial) POPPED! Resetting libraryActiveTabIndexProvider to null',
                mirrorToConsole: true,
              );
              _isSubHostPushed = false;
              if (mounted && ref.read(libraryActiveTabIndexProvider) != null) {
                ref.read(libraryActiveTabIndexProvider.notifier).set(null);
              }
            });
            routes.add(subRoute);
          }
          return routes;
        },
        onGenerateRoute: (settings) => _buildDashboardRoute(),
      ),
    );
  }
}

/// 媒体库二级分类通用宿主页面：
/// 内部通过 IndexedStack 平级常驻承载所有子分类，保证滚动位置不丢失；
/// 每个子分类外包一层 [LibraryTabNavigator]，各自持有独立的路由栈，三级详情页
/// 归属到自己的分类，横向切分类不会出栈、也不会丢详情；
/// 竖屏下显示 AppBar 返回顶栏并支持边缘侧滑返回手势；横屏下自动隐藏顶栏，左侧避让 Rail 栏。
class LibrarySubHostPage extends ConsumerStatefulWidget {
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;

  /// 各子分类 Navigator 的 key。由 [LibraryPageState] 持有，返回键在宿主层
  /// 统一分发到「当前子分类的导航栈」时要用到；缺省时自建（供独立挂载与测试使用）。
  final List<GlobalKey<NavigatorState>>? tabNavigatorKeys;

  const LibrarySubHostPage({
    super.key,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
    this.tabNavigatorKeys,
  });

  @override
  ConsumerState<LibrarySubHostPage> createState() => _LibrarySubHostPageState();
}

class _LibrarySubHostPageState extends ConsumerState<LibrarySubHostPage> {
  final Set<int> _builtSubTabs = {};

  /// 各分类页头动作的注册表，供滚动后浮出的顶栏胶囊取「更多」菜单内容。
  final LibraryHeaderActionsController _headerActions =
      LibraryHeaderActionsController();

  /// 栈里压了三级页面的子分类索引。
  ///
  /// 三级详情页自带 [AppTopNavBar]，位置与宿主顶栏完全重合；宿主顶栏是 Stack 里
  /// 后画的那个，会盖在 `IndexedStack` 之上。若不放它让位，用户看到的是子分类标题，
  /// 点左上角返回实际弹掉的是二级宿主（直接回媒体库首页），而不是当前分类的详情页。
  final Set<int> _tabsWithChildRoutes = {};

  late final List<GlobalKey<NavigatorState>> _tabNavigatorKeys =
      widget.tabNavigatorKeys ??
      List<GlobalKey<NavigatorState>>.generate(
        9,
        (index) => GlobalKey<NavigatorState>(debugLabel: 'library_tab_$index'),
      );

  /// 最后一次有效的子分类索引。
  /// 退出二级页时 [libraryActiveTabIndexProvider] 会被置回 null（语义是「回到仪表盘」），
  /// 而 route.popped / push().then() 是在 pop 被调用的瞬间就完成的（不等离场动画结束），
  /// 宿主页在离场动画播放期间仍会重建一次。此处在 provider 为 null 时冻结上一帧的
  /// 索引，避免离场瞬间 IndexedStack 回落到默认页造成视觉跳变。
  int _lastSubIndex = 0;

  /// 三类洞察页（最近播放 / 最多播放 / 最近添加）的筛选 Notifier。
  ///
  /// 这些状态放在全局常驻的 [LibraryInsightFilterNotifier] 里，不随 Widget 树销毁
  /// 而回收；而页面的滚动进度依附于 Widget 树，退出即归零。若只在「某些入口」
  /// 手动 reset，就会出现「滚动回到顶部、视图却还停在专辑 tab」的半记忆状态。
  /// 这里把筛选状态的生命周期与本宿主页对齐：页面销毁 → 全部复位成「歌曲 + 全部时间」，
  /// 于是无论从仪表盘、Rail 侧边栏还是深链进入，行为都一致。
  ///
  /// Riverpod 禁止在 [dispose] 中使用 ref，必须在 initState 里取出 Notifier 存为字段。
  late final LibraryInsightFilterNotifier _recentlyPlayedFilter;
  late final LibraryInsightFilterNotifier _mostPlayedFilter;
  late final LibraryInsightFilterNotifier _recentlyAddedFilter;

  @override
  void initState() {
    super.initState();
    _recentlyPlayedFilter = ref.read(recentlyPlayedFilterProvider.notifier);
    _mostPlayedFilter = ref.read(mostPlayedFilterProvider.notifier);
    _recentlyAddedFilter = ref.read(recentlyAddedFilterProvider.notifier);
  }

  @override
  void dispose() {
    // 不能在这里直接改 provider：Riverpod 把 dispose 也算作「生命周期内修改」，
    // 会抛 “Tried to modify a provider while the widget tree was building”。
    // 放到微任务里执行，此时页面已彻底离场，不会出现视图回跳。
    final filters = [
      _recentlyPlayedFilter,
      _mostPlayedFilter,
      _recentlyAddedFilter,
    ];
    Future.microtask(() {
      for (final filter in filters) {
        filter.reset();
      }
    });
    super.dispose();
  }

  /// 某个子分类栈里「根路由之上是否还有页面」发生变化。
  ///
  /// 只在真正变化时 setState，且只可能由 push / pop 手势触发（初始根路由的
  /// didPush 会被 observer 过滤掉），所以不会落到 build 阶段。
  void _handleSubHostBack() {
    Navigator.of(context).maybePop();
  }

  void _handleTabChildRouteChanged(int index, bool hasChild) {
    if (!mounted) return;
    final bool changed = hasChild
        ? _tabsWithChildRoutes.add(index)
        : _tabsWithChildRoutes.remove(index);
    if (!changed) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hostInsets = LibrarySubHostInsets.of(context, ref);
    final bool isLandscape = hostInsets.isLandscape;
    final double railWidth = hostInsets.railWidth;

    final int? activeIndex = ref.watch(libraryActiveTabIndexProvider);
    if (activeIndex != null) {
      _lastSubIndex = activeIndex.clamp(0, 8);
    }
    final int clampedIndex = _lastSubIndex;
    _builtSubTabs.add(clampedIndex);
    // 胶囊只读当前分类的动作；IndexedStack 里所有已建分类都会 build，
    // 必须先钉住 activeTab，注册表才能按索引分账。
    _headerActions.setActiveTab(clampedIndex);

    final isSelectionActive = ref.watch(isLibrarySelectionActiveProvider);
    final is3DViewActive =
        (clampedIndex == 4) && ref.watch(isAlbum3DViewActiveProvider);

    // 当前分类压着三级页面时宿主顶栏必须让位：
    // 详情页自带同位置的 AppTopNavBar，而宿主这条在 Stack 里后画，会整个盖住它。
    final bool tabHasChildRoute = _tabsWithChildRoutes.contains(clampedIndex);

    // 竖屏滚离顶部后才浮出「返回 + 更多」：
    // 横屏各子分类顶栏固定常驻（自带返回键与标题），详情页压栈要让位，
    // 多选态底部已有选中面板 —— 胶囊再挂一枚「更多」只会挤占视线。
    final bool capsuleAllowed =
        !isLandscape && !tabHasChildRoute && !isSelectionActive;

    final scaffold = ScrollPastTopScope(
      tabIndex: clampedIndex,
      enabled: !isLandscape && !tabHasChildRoute,
      builder: (context, isPastTop) => Scaffold(
        key: const ValueKey('library_subhost_scaffold'),
        body: Stack(
          fit: StackFit.expand,
          children: [
            IndexedStack(
              sizing: StackFit.expand,
              index: clampedIndex,
              children: [
                for (int i = 0; i < 9; i++)
                  _builtSubTabs.contains(i)
                      ? LibraryTabNavigator(
                          key: ValueKey('library_tab_navigator_$i'),
                          navigatorKey: _tabNavigatorKeys[i],
                          builder: (_) => _buildSubTabRoot(i),
                          onHasChildRouteChanged: (hasChild) =>
                              _handleTabChildRouteChanged(i, hasChild),
                        )
                      : const SizedBox.shrink(),
              ],
            ),
            LibraryFloatingNavCapsuleOverlay(
              railWidth: railWidth,
              // 3D 视图收起时也算「已离开常规列表」，胶囊跟着浮出。
              visible: capsuleAllowed && (isPastTop || is3DViewActive),
              tabHasChildRoute: tabHasChildRoute,
              controller: _headerActions,
              capsuleKey: const ValueKey('library_subhost_top_bar'),
              onBack: () {
                Navigator.of(context).maybePop();
              },
            ),
          ],
        ),
      ),
    );

    // PopScope 必须常驻、只切换 canPop。
    // 若按 isSelectionActive 在「包一层 PopScope」与「直接返回 scaffold」之间切换，
    // 根节点类型会从 ScrollPastTopScope 变成 PopScope，Flutter 会销毁并重建整棵子树：
    // 各子 tab 的 State 连同选中项一起被 dispose，mixin 的 dispose 又会 clear 共享的多选状态，
    // 于是表现为「一进入多选就立刻退出」。
    //
    // 此外：当前分类压有三级详情页（tabHasChildRoute 为 true）时，外层宿主路由绝不能
    // 直接出栈，必须将 canPop 置为 false。这在 iOS 上会自动禁用外层 CupertinoPageRoute
    // 的侧滑返回手势，让渡给内层详情页的原生侧滑返回；在收到未 pop 的返回通知时，
    // 优先将事件分发给出栈内层详情页。
    return PopScope(
      canPop: !isSelectionActive && !tabHasChildRoute,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isSelectionActive) {
          ref.read(librarySelectionStateProvider.notifier).clear();
          return;
        }
        if (tabHasChildRoute) {
          _tabNavigatorKeys[clampedIndex].currentState?.maybePop();
        }
      },
      child: scaffold,
    );
  }
  /// 子分类根页面。
  ///
  /// 这段代码在 [LibraryTabNavigator] 的路由里执行，路由的 builder 只在创建时取一次，
  /// 所以内边距必须在这里基于「当前路由的 context」重新计算：宿主 build 时算出的值
  /// 一旦被捕获，横竖屏旋转后就会停在旧值上。
  Widget _buildSubTabRoot(int index) {
    return Builder(
      builder: (tabContext) {
        final insets = LibrarySubHostInsets.of(tabContext, ref);
        return LibraryHeaderActionsScope(
          tabIndex: index,
          controller: _headerActions,
          child: LibrarySubHostScope(
            onBack: _handleSubHostBack,
            topPadding: insets.topPadding,
            leftPadding: insets.railWidth,
            child: _buildSubTab(
              index,
              topPadding: insets.topPadding,
              leftPadding: insets.railWidth,
              onBack: _handleSubHostBack,
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubTab(
    int index, {
    required double topPadding,
    required double leftPadding,
    VoidCallback? onBack,
  }) {
    switch (index) {
      case 0:
        return PlaylistTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 1:
        return RecentlyPlayedTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 2:
        return MostPlayedTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 3:
        return RecentlyAddedTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 4:
        return AlbumsTab(
          initial3DView: widget.initialAlbums3DView,
          initial3DIndex: widget.initialAlbums3DIndex,
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 5:
        return ArtistsTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 6:
        return RatedSongsTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 7:
        return GenresTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      case 8:
        return YearsTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onBack: onBack,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// 兼容别名
typedef LibrarySubPage = LibrarySubHostPage;

/// 支持桌面端鼠标滚轮和鼠标拖拽滑动的横向滚动容器
class _HorizontalMouseScrollable extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller) builder;

  const _HorizontalMouseScrollable({required this.builder});

  @override
  State<_HorizontalMouseScrollable> createState() =>
      _HorizontalMouseScrollableState();
}

class _HorizontalMouseScrollableState
    extends State<_HorizontalMouseScrollable> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent &&
            _scrollController.hasClients) {
          final delta = pointerSignal.scrollDelta.dx != 0
              ? pointerSignal.scrollDelta.dx
              : pointerSignal.scrollDelta.dy;
          if (delta != 0) {
            final targetOffset = (_scrollController.offset + delta).clamp(
              0.0,
              _scrollController.position.maxScrollExtent,
            );
            _scrollController.jumpTo(targetOffset);
          }
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
          scrollbars: false,
        ),
        child: widget.builder(context, _scrollController),
      ),
    );
  }
}

class KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
