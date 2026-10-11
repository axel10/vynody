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
import 'library_dashboard_view.dart';
import 'main_layout_riverpod.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/auto_hide_header.dart';
import '../widgets/app_root_tooltip.dart';
import '../utils/layout_constants.dart';
import '../utils/blur_constants.dart';

// 媒体库页面：统一采用局部嵌套 Navigator 架构。
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

  /// 标记二级宿主页是否已压在局部 Navigator 栈顶
  bool _isSubHostPushed = false;

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

  /// 供外层（如 MainLayout 的 Android 返回键或快捷键）拦截调用
  bool handleBackPressed() {
    final selectionState = ref.read(librarySelectionStateProvider);
    if (selectionState.isActive &&
        selectionState.scope != LibrarySelectionScope.none) {
      ref.read(librarySelectionStateProvider.notifier).clear();
      return true;
    }
    if (ref.read(isAlbum3DViewActiveProvider)) {
      ref.read(isAlbum3DViewActiveProvider.notifier).set(false);
      return true;
    }
    if (_navigatorKey.currentState?.canPop() ?? false) {
      _navigatorKey.currentState?.maybePop();
      return true;
    }
    return false;
  }

  void _openSubHost(
    int index, {
    bool initialAlbums3DView = false,
    int initialAlbums3DIndex = 0,
  }) {
    ref.read(librarySelectionScopeProvider.notifier).clear();
    ref.read(libraryActiveTabIndexProvider.notifier).set(index);

    if (_isSubHostPushed) {
      // 已经在二级页面宿主，若栈顶有三级详情页，先退回到二级宿主
      _navigatorKey.currentState?.popUntil(
        (route) => route.settings.name == 'library_sub_host' || route.isFirst,
      );
      return;
    }

    _isSubHostPushed = true;
    final route = _buildSubHostRoute(
      initialAlbums3DView: initialAlbums3DView,
      initialAlbums3DIndex: initialAlbums3DIndex,
    );

    _navigatorKey.currentState?.push(route).then((_) {
      _isSubHostPushed = false;
      if (mounted && ref.read(libraryActiveTabIndexProvider) != -1) {
        ref.read(libraryActiveTabIndexProvider.notifier).set(-1);
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
    // 监听全局或 Rail 触发的子分类索引变更
    ref.listen<int>(libraryActiveTabIndexProvider, (previous, next) {
      if (next >= 0) {
        if (!_isSubHostPushed) {
          _openSubHost(next);
        } else {
          // 已在宿主中，若栈顶有三级详情页，先退回到二级宿主以显示新选中的子分类
          _navigatorKey.currentState?.popUntil(
            (route) =>
                route.settings.name == 'library_sub_host' || route.isFirst,
          );
        }
      } else if (next == -1 && _isSubHostPushed) {
        // 重置为仪表盘，退回根路由
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      }
    });

    return Navigator(
      key: _navigatorKey,
      observers: [_heroController],
      onGenerateInitialRoutes: (navigator, initialRoute) {
        final persistedIndex = ref.read(libraryActiveTabIndexProvider);
        final bool hasDeepLink =
            widget.initialAlbums3DView || widget.initialTabIndex != 0;
        final int targetIndex = widget.initialAlbums3DView
            ? 4
            : (widget.initialTabIndex != 0
                ? widget.initialTabIndex
                : persistedIndex);

        final routes = <Route<void>>[_buildDashboardRoute()];
        if (hasDeepLink || targetIndex >= 0) {
          _isSubHostPushed = true;
          final subRoute = _buildSubHostRoute(
            initialAlbums3DView: widget.initialAlbums3DView,
            initialAlbums3DIndex: widget.initialAlbums3DIndex,
          );
          subRoute.popped.then((_) {
            _isSubHostPushed = false;
            if (mounted && ref.read(libraryActiveTabIndexProvider) != -1) {
              ref.read(libraryActiveTabIndexProvider.notifier).set(-1);
            }
          });
          routes.add(subRoute);
        }
        return routes;
      },
      onGenerateRoute: (settings) => _buildDashboardRoute(),
    );
  }
}

/// 媒体库二级分类通用宿主页面：
/// 内部通过 IndexedStack 平级常驻承载所有子分类，保证滚动位置不丢失；
/// 竖屏下显示 AppBar 返回顶栏并支持边缘侧滑返回手势；横屏下自动隐藏顶栏，左侧避让 Rail 栏。
class LibrarySubHostPage extends ConsumerStatefulWidget {
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;

  const LibrarySubHostPage({
    super.key,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
  });

  @override
  ConsumerState<LibrarySubHostPage> createState() => _LibrarySubHostPageState();
}

class _LibrarySubHostPageState extends ConsumerState<LibrarySubHostPage> {
  final Set<int> _builtSubTabs = {};

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final orientation = MediaQuery.of(context).orientation;
    final bool isLandscape = orientation == Orientation.landscape;

    final double railWidth =
        isLandscape ? sidebarRailWidthFor(MediaQuery.of(context).size.width) : 0.0;
    final double safeTopPadding = isLandscape
        ? 0.0
        : getTitleBarTopPadding(context, defaultWindowPadding: 32.0);
    const double subHostHeaderContentHeight = 44.0;
    final double headerHeight = safeTopPadding + subHostHeaderContentHeight;
    final double topPadding = headerHeight;
    final double leftPadding = railWidth;

    final int activeIndex = ref.watch(libraryActiveTabIndexProvider);
    final int clampedIndex = activeIndex.clamp(0, 6);
    _builtSubTabs.add(clampedIndex);

    final String title = switch (clampedIndex) {
      0 => l10n.playlist,
      1 => l10n.recentlyPlayed,
      2 => l10n.mostPlayed,
      3 => l10n.recentlyAdded,
      4 => l10n.albums,
      5 => l10n.artists,
      6 => l10n.ratedSongs,
      _ => l10n.list,
    };

    Widget buildSubTab(int index) {
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
        default:
          return const SizedBox.shrink();
      }
    }

    final isSelectionActive = ref.watch(isLibrarySelectionActiveProvider);
    final is3DViewActive =
        (clampedIndex == 4) && ref.watch(isAlbum3DViewActiveProvider);
    final canPop = !isSelectionActive && !is3DViewActive;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isSelectionActive) {
          ref.read(librarySelectionStateProvider.notifier).clear();
          return;
        }
        if (is3DViewActive) {
          ref.read(isAlbum3DViewActiveProvider.notifier).set(false);
          return;
        }
      },
      child: AutoHideHeaderScope(
        forceVisible: isSelectionActive || is3DViewActive,
        builder: (context, isHeaderVisible) => Scaffold(
          key: const ValueKey('library_subhost_scaffold'),
          body: Stack(
            fit: StackFit.expand,
            children: [
              IndexedStack(
                sizing: StackFit.expand,
                index: clampedIndex,
                children: [
                  for (int i = 0; i < 7; i++)
                    _builtSubTabs.contains(i)
                        ? buildSubTab(i)
                        : const SizedBox.shrink(),
                ],
              ),
              Positioned(
                top: 0,
                left: leftPadding,
                right: 0,
                height: headerHeight,
                child: AutoHideHeader(
                  isVisible: isHeaderVisible,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: AppBlur.heavyFilter,
                      child: Container(
                        padding: EdgeInsets.only(top: safeTopPadding),
                        decoration: BoxDecoration(
                          color: AppBlur.heavySurface(context),
                          border: Border(
                            bottom: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.12),
                              width: 0.8,
                            ),
                          ),
                        ),
                        child: SizedBox(
                          height: subHostHeaderContentHeight,
                          child: Row(
                            children: [
                              const SizedBox(width: 4),
                              AppRootTooltip(
                                message: l10n.goBack,
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: () => Navigator.of(context).maybePop(),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
