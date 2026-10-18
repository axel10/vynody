import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'albums_tab.dart';
import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'recently_played_tab.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';
import 'rated_songs_tab.dart';
import 'genres_tab.dart';
import 'years_tab.dart';
import 'library_dashboard_view.dart';
import 'main_layout_riverpod.dart';
import '../player/library/library_overview_providers.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_tab_navigator.dart';
import '../widgets/auto_hide_header.dart';
import '../widgets/app_top_nav_bar.dart';
import '../utils/layout_constants.dart';
import '../utils/app_log.dart';

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
      ref.read(isAlbum3DViewActiveProvider.notifier).set(false);
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
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final double safeTop = getTitleBarTopPadding(
          context,
          defaultWindowPadding: isLandscape ? 32.0 : 36.0,
        );
        final double topPadding = isLandscape ? (safeTop + 8.0) : safeTop;
        final double leftPadding =
            isLandscape ? sidebarRailWidthFor(MediaQuery.of(context).size.width) : 0.0;

        return LibraryDashboardView(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
          onNavigateToSubIndex: (sub) => _openSubHost(sub),
        );
      },
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape;

    final double railWidth =
        isLandscape ? sidebarRailWidthFor(MediaQuery.of(context).size.width) : 0.0;
    final double headerHeight = AppTopNavBar.getBarHeight(context);

    final int? activeIndex = ref.watch(libraryActiveTabIndexProvider);
    if (activeIndex != null) {
      _lastSubIndex = activeIndex.clamp(0, 8);
    }
    final int clampedIndex = _lastSubIndex;
    _builtSubTabs.add(clampedIndex);

    final String title = switch (clampedIndex) {
      0 => l10n.playlist,
      1 => l10n.recentlyPlayed,
      2 => l10n.mostPlayed,
      3 => l10n.recentlyAdded,
      4 => l10n.albums,
      5 => l10n.artists,
      6 => l10n.ratedSongs,
      7 => l10n.genres,
      8 => l10n.years,
      _ => l10n.list,
    };

    final isSelectionActive = ref.watch(isLibrarySelectionActiveProvider);
    final is3DViewActive =
        (clampedIndex == 4) && ref.watch(isAlbum3DViewActiveProvider);

    final bool hideTopNavBar = isLandscape && is3DViewActive;

    final scaffold = AutoHideHeaderScope(
      forceVisible: isSelectionActive || (!isLandscape && is3DViewActive),
      builder: (context, isHeaderVisible) => Scaffold(
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
                        )
                      : const SizedBox.shrink(),
              ],
            ),
            Positioned(
              top: 0,
              left: railWidth,
              right: 0,
              height: headerHeight,
              child: AnimatedSlide(
                offset: hideTopNavBar ? const Offset(0, -1.0) : Offset.zero,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                    opacity: hideTopNavBar ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOutCubic,
                    child: IgnorePointer(
                      ignoring: hideTopNavBar,
                      child: AutoHideHeader(
                        isVisible: isHeaderVisible,
                        child: AppTopNavBar(
                          title: title,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

    // PopScope 必须常驻、只切换 canPop。
    // 若按 isSelectionActive 在「包一层 PopScope」与「直接返回 scaffold」之间切换，
    // 根节点类型会从 AutoHideHeaderScope 变成 PopScope，Flutter 会销毁并重建整棵子树：
    // 各子 tab 的 State 连同选中项一起被 dispose，mixin 的 dispose 又会 clear 共享的多选状态，
    // 于是表现为「一进入多选就立刻退出」。
    return PopScope(
      canPop: !isSelectionActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(librarySelectionStateProvider.notifier).clear();
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
        final bool isLandscape =
            MediaQuery.of(tabContext).orientation == Orientation.landscape;
        return _buildSubTab(
          index,
          topPadding: AppTopNavBar.getBarHeight(tabContext),
          leftPadding: isLandscape
              ? sidebarRailWidthFor(MediaQuery.of(tabContext).size.width)
              : 0.0,
        );
      },
    );
  }

  Widget _buildSubTab(
    int index, {
    required double topPadding,
    required double leftPadding,
  }) {
    switch (index) {
      case 0:
        return PlaylistTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 1:
        return RecentlyPlayedTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 2:
        return MostPlayedTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 3:
        return RecentlyAddedTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 4:
        return AlbumsTab(
          initial3DView: widget.initialAlbums3DView,
          initial3DIndex: widget.initialAlbums3DIndex,
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 5:
        return ArtistsTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 6:
        return RatedSongsTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 7:
        return GenresTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
        );
      case 8:
        return YearsTab(
          contentTopPadding: topPadding,
          contentLeftPadding: leftPadding,
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
