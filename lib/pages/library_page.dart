import 'dart:io';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/widgets/album_cover.dart';
import 'album_detail_page.dart';
import 'albums_tab.dart';
import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'recently_played_tab.dart';
import '../widgets/library_selection_scope.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';
import 'main_layout_riverpod.dart';

// 媒体库页面

class LibraryPage extends ConsumerStatefulWidget {
  final int initialTabIndex;
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;
  final bool? useSidebar;

  const LibraryPage({
    super.key,
    this.initialTabIndex = 0,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
    this.useSidebar,
  });

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;
  int? _portraitSubIndex;
  bool? _wasLandscape;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex;
    if (widget.initialAlbums3DView) {
      _portraitSubIndex = 4;
    } else if (widget.initialTabIndex != 0) {
      _portraitSubIndex = widget.initialTabIndex;
    }

    _tabController = TabController(
      length: 6,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    )..addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabIndex == _tabController.index) return;
      _tabIndex = _tabController.index;
      ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);
      ref.read(librarySelectionScopeProvider.notifier).clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openSubPage(int index) {
    ref.read(librarySelectionScopeProvider.notifier).clear();
    setState(() {
      _portraitSubIndex = index;
      _tabIndex = index;
      if (_tabController.index != index) {
        _tabController.index = index;
      }
    });
    ref.read(libraryActiveTabIndexProvider.notifier).set(index);
  }

  void _closeSubPage() {
    ref.read(librarySelectionScopeProvider.notifier).clear();
    setState(() {
      _portraitSubIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // 跨横竖屏切换时无缝保持当前分类上下文
    if (_wasLandscape != null && _wasLandscape != isLandscape) {
      if (isLandscape) {
        // 竖屏 -> 横屏：如果当前处于二级页，同步 TabController 为该分类
        if (_portraitSubIndex != null) {
          _tabIndex = _portraitSubIndex!;
          if (_tabController.index != _tabIndex) {
            _tabController.index = _tabIndex;
          }
          ref.read(libraryActiveTabIndexProvider.notifier).set(_tabIndex);
        }
      } else {
        // 横屏 -> 竖屏：保持横屏当前所在的 Tab 分类，作为竖屏二级页展示
        _portraitSubIndex = _tabIndex;
      }
    }
    _wasLandscape = isLandscape;

    if (isLandscape) {
      return _buildLandscapeLayout(context);
    } else {
      return _buildPortraitLayout(context);
    }
  }

  /// 横屏 / 宽屏模式：保持原有顶部可滑动 TabBar + TabBarView 结构
  Widget _buildLandscapeLayout(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool isCoverFlowImmersive =
        isLandscape && ref.watch(isCoverFlowImmersiveActiveProvider);
    final bool effectiveUseSidebar = widget.useSidebar ?? isLandscape;
    final double leftPadding = effectiveUseSidebar ? 80.0 : 0.0;
    final double safeTopPadding =
        isDesktop ? 32.0 : MediaQuery.of(context).padding.top;
    final double topPadding = safeTopPadding + kToolbarHeight;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          TabBarView(
            controller: _tabController,
            physics:
                isCoverFlowImmersive
                    ? const NeverScrollableScrollPhysics()
                    : null,
            children: [
              KeepAliveWrapper(
                child: PlaylistTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: RecentlyPlayedTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: MostPlayedTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: RecentlyAddedTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: AlbumsTab(
                  initial3DView: widget.initialAlbums3DView,
                  initial3DIndex: widget.initialAlbums3DIndex,
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
              KeepAliveWrapper(
                child: ArtistsTab(
                  contentTopPadding: topPadding,
                  contentLeftPadding: leftPadding,
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: leftPadding,
            right: 0,
            height: topPadding,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              opacity: isCoverFlowImmersive ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: isCoverFlowImmersive,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: EdgeInsets.only(top: safeTopPadding),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(
                          alpha: isDark ? 0.66 : 0.80,
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: theme.dividerColor.withValues(alpha: 0.12),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.center,
                        dividerColor: Colors.transparent,
                        tabs: [
                          Tab(text: l10n.playlist),
                          Tab(text: l10n.recentlyPlayed),
                          Tab(text: l10n.mostPlayed),
                          Tab(text: l10n.recentlyAdded),
                          Tab(text: l10n.albums),
                          Tab(text: l10n.artists),
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
    );
  }

  /// 竖屏模式：一级目录入口 / 二级页面切换
  Widget _buildPortraitLayout(BuildContext context) {
    return PopScope(
      canPop: _portraitSubIndex == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_portraitSubIndex != null) {
          _closeSubPage();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _portraitSubIndex == null
            ? _buildPortraitIndexView(context)
            : _buildPortraitSubPageView(context, _portraitSubIndex!),
      ),
    );
  }

  /// 竖屏一级主页面
  Widget _buildPortraitIndexView(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final safeTop = isDesktop ? 36.0 : MediaQuery.of(context).padding.top;
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final playlistsCount =
        ref.watch(playlistServiceProvider).playlists.length;
    final albumsCount = ref.watch(albumLibraryProvider).value?.length;
    final artistsCount = ref.watch(artistLibraryProvider).value?.length;
    final albumsAsync = ref.watch(albumLibraryProvider);

    final bottomPadding = (currentMusic != null ? 140.0 : 90.0) +
        MediaQuery.of(context).padding.bottom;

    return Scaffold(
      key: const ValueKey('portrait_index_view'),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // 顶部标题栏（预留桌面端窗口标题栏安全间距）
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, safeTop + 16, 20, 12),
              child: Text(
                l10n.list,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          // 一级分组菜单入口卡片
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            sliver: SliverToBoxAdapter(
              child: _PortraitLibraryMenuCard(
                items: [
                  _LibraryMenuItem(
                    icon: Icons.queue_music_rounded,
                    iconGradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    title: l10n.playlist,
                    badgeText: playlistsCount > 0 ? '$playlistsCount' : null,
                    onTap: () => _openSubPage(0),
                  ),
                  _LibraryMenuItem(
                    icon: Icons.mic_external_on_rounded,
                    iconGradient: const [Color(0xFFF97316), Color(0xFFFB923C)],
                    title: l10n.artists,
                    badgeText:
                        artistsCount != null && artistsCount > 0
                            ? '$artistsCount'
                            : null,
                    onTap: () => _openSubPage(5),
                  ),
                  _LibraryMenuItem(
                    icon: Icons.album_rounded,
                    iconGradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                    title: l10n.albums,
                    badgeText:
                        albumsCount != null && albumsCount > 0
                            ? '$albumsCount'
                            : null,
                    onTap: () => _openSubPage(4),
                  ),
                  _LibraryMenuItem(
                    icon: Icons.history_rounded,
                    iconGradient: const [Color(0xFF10B981), Color(0xFF14B8A6)],
                    title: l10n.recentlyPlayed,
                    onTap: () => _openSubPage(1),
                  ),
                  _LibraryMenuItem(
                    icon: Icons.local_fire_department_rounded,
                    iconGradient: const [Color(0xFFEF4444), Color(0xFFF43F5E)],
                    title: l10n.mostPlayed,
                    onTap: () => _openSubPage(2),
                  ),
                  _LibraryMenuItem(
                    icon: Icons.auto_awesome_rounded,
                    iconGradient: const [Color(0xFFF59E0B), Color(0xFFEAB308)],
                    title: l10n.recentlyAdded,
                    onTap: () => _openSubPage(3),
                  ),
                ],
              ),
            ),
          ),

          // 下半部分：快捷探索 / 最近添加专辑预览
          albumsAsync.when(
            data: (albums) {
              if (albums.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              final previewAlbums = albums.take(10).toList();

              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n.recentlyAdded,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            InkWell(
                              onTap: () => _openSubPage(3),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      l10n.recentlyAdded,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 190,
                        child: _HorizontalMouseScrollable(
                          builder: (context, scrollController) {
                            return ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: previewAlbums.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(width: 14),
                              itemBuilder: (context, index) {
                                final album = previewAlbums[index];
                                return _PortraitAlbumPreviewCard(album: album);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (err, stack) =>
                const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),

          // 底部留白，避开 MiniPlayer / Floating Dock
          SliverToBoxAdapter(
            child: SizedBox(height: bottomPadding),
          ),
        ],
      ),
    );
  }

  /// 竖屏二级页面
  Widget _buildPortraitSubPageView(BuildContext context, int subIndex) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    final String title = switch (subIndex) {
      0 => l10n.playlist,
      1 => l10n.recentlyPlayed,
      2 => l10n.mostPlayed,
      3 => l10n.recentlyAdded,
      4 => l10n.albums,
      5 => l10n.artists,
      _ => l10n.list,
    };

    final Widget child = switch (subIndex) {
      0 => const PlaylistTab(),
      1 => const RecentlyPlayedTab(),
      2 => const MostPlayedTab(),
      3 => const RecentlyAddedTab(),
      4 => AlbumsTab(
          initial3DView: widget.initialAlbums3DView,
          initial3DIndex: widget.initialAlbums3DIndex,
        ),
      5 => const ArtistsTab(),
      _ => const SizedBox.shrink(),
    };

    return Scaffold(
      key: ValueKey('portrait_subpage_$subIndex'),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          kToolbarHeight + (isDesktop ? 32.0 : 0.0),
        ),
        child: Container(
          padding: EdgeInsets.only(top: isDesktop ? 32.0 : 0.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(
              alpha: isDark ? 0.75 : 0.85,
            ),
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.1),
                width: 0.8,
              ),
            ),
          ),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AppBar(
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                  ),
                  tooltip: l10n.goBack,
                  onPressed: _closeSubPage,
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
      body: child,
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

class _LibraryMenuItem {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String? badgeText;
  final VoidCallback onTap;

  const _LibraryMenuItem({
    required this.icon,
    required this.iconGradient,
    required this.title,
    this.badgeText,
    required this.onTap,
  });
}

class _PortraitLibraryMenuCard extends StatelessWidget {
  final List<_LibraryMenuItem> items;

  const _PortraitLibraryMenuCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? 0.12 : 0.06),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              _buildTile(context, items[i]),
              if (i < items.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 64, right: 16),
                  child: Divider(
                    height: 1,
                    thickness: 0.6,
                    color: theme.dividerColor.withValues(alpha: 0.1),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, _LibraryMenuItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: item.iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: item.iconGradient.first.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    item.icon,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              if (item.badgeText != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.badgeText!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortraitAlbumPreviewCard extends StatelessWidget {
  final AlbumSummary album;

  const _PortraitAlbumPreviewCard({required this.album});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final artistName =
        album.artist.isNotEmpty ? album.artist : l10n.unknownArtist;

    return SizedBox(
      width: 124,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => AlbumDetailPage(album: album),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AlbumCover(
                  album: album,
                  size: 124,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
