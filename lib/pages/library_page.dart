import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'albums_tab.dart';
import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'recently_played_tab.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/auto_hide_header.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';
import 'rated_songs_tab.dart';
import 'library_dashboard_view.dart';
import 'main_layout_riverpod.dart';
import '../utils/layout_constants.dart';

// 媒体库页面

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
  int _tabIndex = 0;

  /// 已构建过的二级页面索引，避免宽屏布局一次性实例化全部六个子页
  final Set<int> _builtSubTabs = {};

  @override
  void initState() {
    super.initState();
    // 若用户在别的页面先通过 Rail 选中了某个媒体库子页，provider 里已有值，
    // 此时不能再用 initialTabIndex 覆盖掉（否则会跳回第一个子页）
    final int persistedIndex = ref.read(libraryActiveTabIndexProvider);
    _tabIndex =
        widget.initialAlbums3DView
            ? 4
            : (widget.initialTabIndex != 0
                ? widget.initialTabIndex
                : persistedIndex);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);

      if (!_useSidebarLayout &&
          (widget.initialAlbums3DView || widget.initialTabIndex != 0)) {
        final targetIndex =
            widget.initialAlbums3DView ? 4 : widget.initialTabIndex;
        _openSubPage(
          context,
          targetIndex,
          initialAlbums3DView: widget.initialAlbums3DView,
          initialAlbums3DIndex: widget.initialAlbums3DIndex,
        );
      }
    });
  }

  /// 与 MainLayout 的 Rail 开关保持完全一致：宽屏布局下入口由左侧 Rail 承载，
  /// 不再显示顶部 TabBar
  bool get _useSidebarLayout {
    if (widget.useSidebar != null) return widget.useSidebar!;
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  void _openSubPage(
    BuildContext context,
    int index, {
    bool initialAlbums3DView = false,
    int initialAlbums3DIndex = 0,
  }) {
    ref.read(librarySelectionScopeProvider.notifier).clear();
    ref.read(libraryActiveTabIndexProvider.notifier).set(index);

    final route = (Platform.isIOS || Platform.isMacOS)
        ? CupertinoPageRoute<void>(
            builder: (_) => LibrarySubPage(
              subIndex: index,
              initialAlbums3DView: initialAlbums3DView,
              initialAlbums3DIndex: initialAlbums3DIndex,
            ),
          )
        : MaterialPageRoute<void>(
            builder: (_) => LibrarySubPage(
              subIndex: index,
              initialAlbums3DView: initialAlbums3DView,
              initialAlbums3DIndex: initialAlbums3DIndex,
            ),
          );

    Navigator.of(context).push(route).then((_) {
      if (mounted) {
        ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);
      }
    });
  }

  bool handleBackPressed() {
    final selectionState = ref.read(librarySelectionStateProvider);
    if (selectionState.isActive &&
        selectionState.scope != LibrarySelectionScope.none) {
      ref.read(librarySelectionStateProvider.notifier).clear();
      return true;
    }
    final activeIndex = ref.read(libraryActiveTabIndexProvider);
    if (_useSidebarLayout && activeIndex >= 0) {
      ref.read(libraryActiveTabIndexProvider.notifier).set(-1);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 宽屏布局：入口由左侧 Rail 承载，不再渲染顶部 TabBar
    if (_useSidebarLayout) {
      return _buildSidebarLayout(context);
    }
    return _buildPortraitIndexView(context);
  }

  /// 宽屏 / 桌面模式：
  /// activeIndex == -1 时展示媒体库仪表盘首页；>= 0 时由左侧 Rail 切换对应二级页面
  Widget _buildSidebarLayout(BuildContext context) {
    final double safeTopPadding =
        getTitleBarTopPadding(context, defaultWindowPadding: 32.0);
    final double topPadding = safeTopPadding + 8.0;
    final double leftPadding = widget.railWidth;

    final int activeIndex = ref.watch(libraryActiveTabIndexProvider);

    if (activeIndex == -1) {
      return LibraryDashboardView(
        contentTopPadding: topPadding,
        contentLeftPadding: leftPadding,
        onNavigateToSubIndex: (sub) {
          ref.read(libraryActiveTabIndexProvider.notifier).set(sub);
        },
      );
    }

    final int clampedIndex = activeIndex.clamp(0, 6);
    // 按需构建：Rail 切到哪个子页才实例化哪个，避免一次打开媒体库就构建全部子页
    _builtSubTabs.add(clampedIndex);

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

    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Stack(
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
            top: safeTopPadding + 4,
            left: leftPadding + 14,
            child: Material(
              color: Colors.transparent,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                tooltip: l10n.goBack,
                onPressed: () {
                  ref.read(libraryActiveTabIndexProvider.notifier).set(-1);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 竖屏/移动端主页面：统一使用响应式媒体库仪表盘首页
  Widget _buildPortraitIndexView(BuildContext context) {
    final safeTop = getTitleBarTopPadding(context, defaultWindowPadding: 36.0);
    return LibraryDashboardView(
      contentTopPadding: safeTop,
      onNavigateToSubIndex: (sub) => _openSubPage(context, sub),
    );
  }
}

/// 媒体库二级独立页面（标准 PageRoute 结构，完整支持 Android 物理返回、iOS 边缘手势以及浮层弹窗/抽屉优先级）
class LibrarySubPage extends ConsumerStatefulWidget {
  final int subIndex;
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;

  const LibrarySubPage({
    super.key,
    required this.subIndex,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
  });

  @override
  ConsumerState<LibrarySubPage> createState() => _LibrarySubPageState();
}

class _LibrarySubPageState extends ConsumerState<LibrarySubPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(libraryActiveTabIndexProvider.notifier).set(widget.subIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final double safeTopPadding =
        getTitleBarTopPadding(context, defaultWindowPadding: 32.0);
    final double topPadding = safeTopPadding + kToolbarHeight;

    final String title = switch (widget.subIndex) {
      0 => l10n.playlist,
      1 => l10n.recentlyPlayed,
      2 => l10n.mostPlayed,
      3 => l10n.recentlyAdded,
      4 => l10n.albums,
      5 => l10n.artists,
      6 => l10n.ratedSongs,
      _ => l10n.list,
    };

    final Widget child = switch (widget.subIndex) {
      0 => PlaylistTab(contentTopPadding: topPadding),
      1 => RecentlyPlayedTab(contentTopPadding: topPadding),
      2 => MostPlayedTab(contentTopPadding: topPadding),
      3 => RecentlyAddedTab(contentTopPadding: topPadding),
      4 => AlbumsTab(
          initial3DView: widget.initialAlbums3DView,
          initial3DIndex: widget.initialAlbums3DIndex,
          contentTopPadding: topPadding,
        ),
      5 => ArtistsTab(contentTopPadding: topPadding),
      6 => RatedSongsTab(contentTopPadding: topPadding),
      _ => const SizedBox.shrink(),
    };

    final isSelectionActive = ref.watch(isLibrarySelectionActiveProvider);
    final is3DViewActive =
        (widget.subIndex == 4) && ref.watch(isAlbum3DViewActiveProvider);
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
      child: MiniPlayerWrapper(
        child: AutoHideHeaderScope(
          forceVisible: isSelectionActive || is3DViewActive,
          builder: (context, isHeaderVisible) => Scaffold(
            key: ValueKey('library_subpage_${widget.subIndex}'),
            body: Stack(
              fit: StackFit.expand,
              children: [
                child,
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topPadding,
                  child: AutoHideHeader(
                    isVisible: isHeaderVisible,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: EdgeInsets.only(top: safeTopPadding),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: isDark ? 0.70 : 0.82,
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: theme.dividerColor.withValues(alpha: 0.12),
                                width: 0.8,
                              ),
                            ),
                          ),
                          child: AppBar(
                            primary: false,
                            forceMaterialTransparency: true,
                            scrolledUnderElevation: 0,
                            surfaceTintColor: Colors.transparent,
                            leading: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 20,
                              ),
                              tooltip: l10n.goBack,
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            centerTitle: true,
                            elevation: 0,
                            backgroundColor: Colors.transparent,
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
      ),
    );
  }
}

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
