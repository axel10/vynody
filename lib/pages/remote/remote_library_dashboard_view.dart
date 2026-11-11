import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../player/remote/remote_server_models.dart';
import '../../widgets/carousel_scroll_wrapper.dart';
import '../../widgets/library_toolbar_buttons.dart';
import '../../widgets/playback_ui_tuning.dart';
import '../../widgets/remote_artwork_widget.dart';

/// 桌面横屏下专辑/歌单封面缩放系数（与本地媒体库保持一致）
const double kDashboardDesktopCoverScale = 1.9;

/// 竖屏移动端下封面缩放系数（与本地媒体库保持一致）
const double kDashboardMobileCoverScale = 1.2;

/// 远程媒体库概览页。
///
/// 与本地媒体库的 `LibraryDashboardView` 同一套视觉节奏：顶部大标题与统计 →
/// 快捷入口 → 若干横向内容板块。数据由 `RemoteLibraryPage` 传入（那里是唯一的
/// 数据宿主），本页只负责排版与跳转，不发起任何请求。
///
/// 板块取舍遵循「没有对应能力或无数据则不显示」：
/// 最近添加、最新发布、最近播放、最多播放、播放列表与收藏专辑在有数据时呈现对应板块；
/// 搜索按需求保持为独立子页，这里放快捷入口卡片。
class RemoteLibraryDashboardView extends StatelessWidget {
  const RemoteLibraryDashboardView({
    super.key,
    required this.server,
    required this.password,
    required this.albumCount,
    required this.artistCount,
    required this.songCount,
    required this.playlistCount,
    this.genreCount,
    required this.recentAlbums,
    this.releasedAlbums = const [],
    this.recentPlayedAlbums = const [],
    this.mostPlayedAlbums = const [],
    this.playlists = const [],
    this.favoriteAlbums = const [],
    required this.onNavigateToTab,
    required this.onOpenAlbum,
    this.onOpenPlaylist,
    required this.onRefresh,
    this.onPlayAll,
    this.onShufflePlay,
    @Deprecated('Use onShufflePlay instead') this.onShuffleAll,
    required this.onDisconnect,
    this.contentTopPadding = 16,
    this.contentLeftPadding = 0.0,
  });

  final RemoteServer server;
  final String password;

  final int albumCount;
  final int artistCount;
  final int songCount;
  final int playlistCount;
  final int? genreCount;

  /// 最近添加的专辑。空则不显示该板块。
  final List<Map<String, dynamic>> recentAlbums;

  /// 最新发布的专辑（按发行年份/首映日期降序）。空则不显示该板块。
  final List<Map<String, dynamic>> releasedAlbums;

  /// 最近播放的专辑。空则不显示该板块。
  final List<Map<String, dynamic>> recentPlayedAlbums;

  /// 最多播放的专辑。空则不显示该板块。
  final List<Map<String, dynamic>> mostPlayedAlbums;

  /// 播放列表。空则不显示该板块。
  final List<Map<String, dynamic>> playlists;

  /// 收藏的专辑。空则不显示该板块。
  final List<Map<String, dynamic>> favoriteAlbums;

  final ValueChanged<int> onNavigateToTab;

  /// 点封面直接进专辑详情。
  final void Function(String albumId, String albumTitle) onOpenAlbum;

  /// 点封面直接进歌单详情。
  final void Function(Map<String, dynamic> playlist)? onOpenPlaylist;

  final RefreshCallback onRefresh;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onShuffleAll;

  /// 断开当前媒体库（一级栏目的显式退出动作）。
  ///
  /// 一级 tab 没有「上一级」，返回键不再承担退出语义，所以退出必须是
  /// 这里一个看得见、且有确认的动作。
  final VoidCallback onDisconnect;

  final double contentTopPadding;
  final double contentLeftPadding;

  /// 分类索引，与 `RemoteLibraryPage` 的 tab 顺序保持一致。
  static const int tabAlbums = 0;
  static const int tabArtists = 1;
  static const int tabGenres = 2;
  static const int tabSongs = 3;
  static const int tabPlaylists = 4;
  static const int tabSearch = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth >= 780;
          final double horizontalPadding = isWide ? 32.0 : 16.0;
          final double scale =
              isWide ? kDashboardDesktopCoverScale : kDashboardMobileCoverScale;
          final double cardWidth = (126.0 * scale).roundToDouble();
          final double listHeight = cardWidth + 70.0;
          final double separatorWidth = isWide ? 16.0 : 14.0;

          return RefreshIndicator(
            onRefresh: onRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    contentLeftPadding + horizontalPadding,
                    contentTopPadding + 8,
                    horizontalPadding,
                    12,
                  ),
                  child: _DashboardHeader(
                    server: server,
                    onRefresh: onRefresh,
                    onPlayAll: onPlayAll,
                    onShufflePlay: onShufflePlay ?? onShuffleAll,
                    onDisconnect: onDisconnect,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: isWide
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 28),
                        child: _WideQuickAccessBar(
                          onTapTab: onNavigateToTab,
                          l10n: l10n,
                          albumCount: albumCount,
                          artistCount: artistCount,
                          genreCount: genreCount,
                          songCount: songCount,
                          playlistCount: playlistCount,
                          contentLeftPadding: contentLeftPadding,
                          horizontalPadding: horizontalPadding,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(
                          top: 8,
                          bottom: 22,
                        ),
                        child: _PortraitLibraryMenuCard(
                          onTapTab: onNavigateToTab,
                          l10n: l10n,
                          albumCount: albumCount,
                          artistCount: artistCount,
                          genreCount: genreCount,
                          songCount: songCount,
                          playlistCount: playlistCount,
                          contentLeftPadding: contentLeftPadding,
                          horizontalPadding: horizontalPadding,
                        ),
                      ),
              ),
              if (recentAlbums.isNotEmpty)
                _AlbumRowSection(
                  title: l10n.recentlyAdded,
                  albums: recentAlbums,
                  server: server,
                  password: password,
                  contentLeftPadding: contentLeftPadding,
                  horizontalPadding: horizontalPadding,
                  cardWidth: cardWidth,
                  listHeight: listHeight,
                  separatorWidth: separatorWidth,
                  isWide: isWide,
                  onOpenAlbum: onOpenAlbum,
                  onSeeAll: () => onNavigateToTab(tabAlbums),
                ),
              if (releasedAlbums.isNotEmpty)
                _AlbumRowSection(
                  title: l10n.recentlyReleased,
                  albums: releasedAlbums,
                  server: server,
                  password: password,
                  contentLeftPadding: contentLeftPadding,
                  horizontalPadding: horizontalPadding,
                  cardWidth: cardWidth,
                  listHeight: listHeight,
                  separatorWidth: separatorWidth,
                  isWide: isWide,
                  onOpenAlbum: onOpenAlbum,
                  onSeeAll: () => onNavigateToTab(tabAlbums),
                ),
              if (recentPlayedAlbums.isNotEmpty)
                _AlbumRowSection(
                  title: l10n.recentlyPlayed,
                  albums: recentPlayedAlbums,
                  server: server,
                  password: password,
                  contentLeftPadding: contentLeftPadding,
                  horizontalPadding: horizontalPadding,
                  cardWidth: cardWidth,
                  listHeight: listHeight,
                  separatorWidth: separatorWidth,
                  isWide: isWide,
                  onOpenAlbum: onOpenAlbum,
                  onSeeAll: () => onNavigateToTab(tabAlbums),
                ),
              if (mostPlayedAlbums.isNotEmpty)
                _AlbumRowSection(
                  title: l10n.mostPlayed,
                  albums: mostPlayedAlbums,
                  server: server,
                  password: password,
                  contentLeftPadding: contentLeftPadding,
                  horizontalPadding: horizontalPadding,
                  cardWidth: cardWidth,
                  listHeight: listHeight,
                  separatorWidth: separatorWidth,
                  isWide: isWide,
                  onOpenAlbum: onOpenAlbum,
                  onSeeAll: () => onNavigateToTab(tabAlbums),
                ),
              if (playlists.isNotEmpty)
                _PlaylistRowSection(
                  title: l10n.playlist,
                  playlists: playlists,
                  server: server,
                  password: password,
                  contentLeftPadding: contentLeftPadding,
                  horizontalPadding: horizontalPadding,
                  cardWidth: cardWidth,
                  listHeight: listHeight,
                  separatorWidth: separatorWidth,
                  isWide: isWide,
                  onOpenPlaylist: onOpenPlaylist,
                  onSeeAll: () => onNavigateToTab(tabPlaylists),
                ),
              if (favoriteAlbums.isNotEmpty)
                _AlbumRowSection(
                  title: l10n.starredAlbums,
                  albums: favoriteAlbums,
                  server: server,
                  password: password,
                  contentLeftPadding: contentLeftPadding,
                  horizontalPadding: horizontalPadding,
                  cardWidth: cardWidth,
                  listHeight: listHeight,
                  separatorWidth: separatorWidth,
                  isWide: isWide,
                  onOpenAlbum: onOpenAlbum,
                  onSeeAll: () => onNavigateToTab(tabAlbums),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      MiniPlayerUiTuning.getListBottomPadding(
                        context,
                        hasPlayingMusic: false,
                      ) +
                      24,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.server,
    this.onPlayAll,
    this.onShufflePlay,
    required this.onRefresh,
    required this.onDisconnect,
  });

  final RemoteServer server;
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback onRefresh;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final bool isJellyfin = server.type == RemoteServerType.jellyfin;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        // 竖屏下如果宽度不够（如 < 560，4 个按钮会严重挤压左侧文字），刷新按钮直接隐藏（由下拉刷新替代），
        // 且不再使用「更多」按钮收纳，直接展示「断开连接」按钮
        final bool hideRefresh =
            (isPortrait && constraints.maxWidth < 560) ||
            constraints.maxWidth < 480;

        final actions = <Widget>[
          if (onPlayAll != null)
            libraryToolbarIconButton(
              icon: Icons.play_arrow_rounded,
              tooltip: l10n.playAll,
              onPressed: onPlayAll,
            ),
          if (onShufflePlay != null)
            libraryToolbarIconButton(
              icon: Icons.shuffle_rounded,
              tooltip: l10n.shufflePlay,
              onPressed: onShufflePlay,
            ),
          if (!hideRefresh)
            libraryToolbarIconButton(
              icon: Icons.refresh_rounded,
              tooltip: l10n.refresh,
              onPressed: onRefresh,
            ),
          libraryToolbarIconButton(
            icon: Icons.link_off_rounded,
            tooltip: l10n.remoteDisconnect,
            onPressed: onDisconnect,
          ),
        ];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    server.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isJellyfin ? 'Jellyfin' : 'Navidrome / Subsonic',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions,
            ),
          ],
        );
      },
    );
  }
}

class _LibraryQuickItem {
  final int tab;
  final String title;
  final IconData icon;
  final List<Color> gradient;
  final String? badgeText;

  const _LibraryQuickItem({
    required this.tab,
    required this.title,
    required this.icon,
    required this.gradient,
    this.badgeText,
  });
}

List<_LibraryQuickItem> _buildQuickItems({
  required AppLocalizations l10n,
  int? albumCount,
  int? artistCount,
  int? genreCount,
  int? songCount,
  int? playlistCount,
}) => [
  _LibraryQuickItem(
    tab: RemoteLibraryDashboardView.tabAlbums,
    title: l10n.albums,
    icon: Icons.album_rounded,
    gradient: const [Color(0xFF007AFF), Color(0xFF0062D2)],
    badgeText: albumCount != null && albumCount > 0 ? '$albumCount' : null,
  ),
  _LibraryQuickItem(
    tab: RemoteLibraryDashboardView.tabArtists,
    title: l10n.artists,
    icon: Icons.mic_external_on_rounded,
    gradient: const [Color(0xFFFF9500), Color(0xFFE07D00)],
    badgeText: artistCount != null && artistCount > 0 ? '$artistCount' : null,
  ),
  _LibraryQuickItem(
    tab: RemoteLibraryDashboardView.tabGenres,
    title: l10n.genres,
    icon: Icons.style_rounded,
    gradient: const [Color(0xFF5856D6), Color(0xFF4745BA)],
    badgeText: genreCount != null && genreCount > 0 ? '$genreCount' : null,
  ),
  _LibraryQuickItem(
    tab: RemoteLibraryDashboardView.tabSongs,
    title: l10n.songs,
    icon: Icons.music_note_rounded,
    gradient: const [Color(0xFF2AC8A8), Color(0xFF1EAE91)],
    badgeText: songCount != null && songCount > 0 ? '$songCount' : null,
  ),
  _LibraryQuickItem(
    tab: RemoteLibraryDashboardView.tabPlaylists,
    title: l10n.playlists,
    icon: Icons.queue_music_rounded,
    gradient: const [Color(0xFFFA243C), Color(0xFFE01E37)],
    badgeText:
        playlistCount != null && playlistCount > 0 ? '$playlistCount' : null,
  ),
  _LibraryQuickItem(
    tab: RemoteLibraryDashboardView.tabSearch,
    title: l10n.search,
    icon: Icons.search_rounded,
    gradient: const [Color(0xFF30B0C7), Color(0xFF258C9E)],
    badgeText: null,
  ),
];

// ---------------------------------------------------------------------------
// 横屏大号快捷入口流（与本地媒体库保持完全一致的视觉样式）
// ---------------------------------------------------------------------------
class _WideQuickAccessBar extends StatelessWidget {
  const _WideQuickAccessBar({
    required this.onTapTab,
    required this.l10n,
    this.albumCount,
    this.artistCount,
    this.genreCount,
    this.songCount,
    this.playlistCount,
    this.contentLeftPadding = 0.0,
    this.horizontalPadding = 32.0,
  });

  final ValueChanged<int> onTapTab;
  final AppLocalizations l10n;
  final int? albumCount;
  final int? artistCount;
  final int? genreCount;
  final int? songCount;
  final int? playlistCount;
  final double contentLeftPadding;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final items = _buildQuickItems(
      l10n: l10n,
      albumCount: albumCount,
      artistCount: artistCount,
      genreCount: genreCount,
      songCount: songCount,
      playlistCount: playlistCount,
    );
    const cardHeight = 60.0;

    return CarouselScrollWrapper(
      height: cardHeight,
      buttonHeight: 40.0,
      buttonPadding: horizontalPadding > 20 ? 14.0 : 8.0,
      leftButtonOffset: contentLeftPadding,
      builder: (context, controller) {
        return SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(
            left: contentLeftPadding + horizontalPadding,
            right: horizontalPadding,
          ),
          child: Row(
            children: items.map((item) {
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _WideQuickCard(
                  title: item.title,
                  icon: item.icon,
                  gradient: item.gradient,
                  badgeText: item.badgeText,
                  onTap: () => onTapTab(item.tab),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

class _WideQuickCard extends StatefulWidget {
  const _WideQuickCard({
    required this.title,
    required this.icon,
    required this.gradient,
    this.badgeText,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final List<Color> gradient;
  final String? badgeText;
  final VoidCallback onTap;

  @override
  State<_WideQuickCard> createState() => _WideQuickCardState();
}

class _WideQuickCardState extends State<_WideQuickCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = widget.gradient.first;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: _isHovered
                ? primaryColor.withValues(alpha: isDark ? 0.20 : 0.12)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.45 : 0.65,
                  ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isHovered
                  ? primaryColor.withValues(alpha: 0.55)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
              width: 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: _isHovered
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.9),
                ),
              ),
              if (widget.badgeText != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.badgeText!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 竖屏列表菜单卡片（与本地媒体库保持完全一致的视觉样式）
// ---------------------------------------------------------------------------
class _PortraitLibraryMenuCard extends StatelessWidget {
  const _PortraitLibraryMenuCard({
    required this.onTapTab,
    required this.l10n,
    this.albumCount,
    this.artistCount,
    this.genreCount,
    this.songCount,
    this.playlistCount,
    this.contentLeftPadding = 0.0,
    this.horizontalPadding = 16.0,
  });

  final ValueChanged<int> onTapTab;
  final AppLocalizations l10n;
  final int? albumCount;
  final int? artistCount;
  final int? genreCount;
  final int? songCount;
  final int? playlistCount;
  final double contentLeftPadding;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _buildQuickItems(
      l10n: l10n,
      albumCount: albumCount,
      artistCount: artistCount,
      genreCount: genreCount,
      songCount: songCount,
      playlistCount: playlistCount,
    );

    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          _buildTile(context, items[i]),
          if (i < items.length - 1)
            Padding(
              padding: EdgeInsets.only(
                left: contentLeftPadding + horizontalPadding + 38 + 14,
                right: horizontalPadding,
              ),
              child: Divider(
                height: 1,
                thickness: 0.6,
                color: theme.dividerColor.withValues(alpha: isDark ? 0.12 : 0.08),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTile(BuildContext context, _LibraryQuickItem item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTapTab(item.tab),
        child: Padding(
          padding: EdgeInsets.only(
            left: contentLeftPadding + horizontalPadding,
            right: horizontalPadding,
            top: 13,
            bottom: 13,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: item.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
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

class _AlbumRowSection extends StatelessWidget {
  const _AlbumRowSection({
    required this.title,
    required this.albums,
    required this.server,
    required this.password,
    required this.contentLeftPadding,
    required this.horizontalPadding,
    required this.cardWidth,
    required this.listHeight,
    required this.separatorWidth,
    required this.isWide,
    required this.onOpenAlbum,
    required this.onSeeAll,
  });

  final String title;
  final List<Map<String, dynamic>> albums;
  final RemoteServer server;
  final String password;
  final double contentLeftPadding;
  final double horizontalPadding;
  final double cardWidth;
  final double listHeight;
  final double separatorWidth;
  final bool isWide;
  final void Function(String albumId, String albumTitle) onOpenAlbum;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: contentLeftPadding + horizontalPadding,
                right: horizontalPadding - 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onSeeAll,
                    child: Text(l10n.viewAll),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CarouselScrollWrapper(
              height: listHeight,
              centerHeight: cardWidth,
              buttonPadding: horizontalPadding > 20 ? 14.0 : 8.0,
              leftButtonOffset: contentLeftPadding,
              builder: (context, controller) {
                return ListView.separated(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: contentLeftPadding + horizontalPadding,
                    right: horizontalPadding,
                  ),
                  itemCount: albums.length,
                  separatorBuilder: (_, _) => SizedBox(width: separatorWidth),
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final id = album['id']?.toString() ?? '';
                    final name =
                        album['name'] as String? ??
                        album['title'] as String? ??
                        '';
                    final coverArtId = album['coverArt'] as String?;
                    return _DashboardAlbumCard(
                      title: name,
                      subtitle: album['artist'] as String?,
                      coverArtId: coverArtId,
                      server: server,
                      password: password,
                      width: cardWidth,
                      isWide: isWide,
                      onTap: () => onOpenAlbum(id, name),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardAlbumCard extends StatelessWidget {
  const _DashboardAlbumCard({
    required this.title,
    required this.subtitle,
    required this.coverArtId,
    required this.server,
    required this.password,
    required this.width,
    required this.isWide,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? coverArtId;
  final RemoteServer server;
  final String password;
  final double width;
  final bool isWide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RemoteArtworkWidget(
                  server: server,
                  password: password,
                  coverArtId: coverArtId,
                  size: width,
                  width: width,
                  height: width,
                  fallbackIcon: Icons.album_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: isWide ? 14.5 : 14.0,
                ),
              ),
              const SizedBox(height: 2),
              if ((subtitle ?? '').isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
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

class _PlaylistRowSection extends StatelessWidget {
  const _PlaylistRowSection({
    required this.title,
    required this.playlists,
    required this.server,
    required this.password,
    required this.contentLeftPadding,
    required this.horizontalPadding,
    required this.cardWidth,
    required this.listHeight,
    required this.separatorWidth,
    required this.isWide,
    this.onOpenPlaylist,
    required this.onSeeAll,
  });

  final String title;
  final List<Map<String, dynamic>> playlists;
  final RemoteServer server;
  final String password;
  final double contentLeftPadding;
  final double horizontalPadding;
  final double cardWidth;
  final double listHeight;
  final double separatorWidth;
  final bool isWide;
  final void Function(Map<String, dynamic> playlist)? onOpenPlaylist;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: contentLeftPadding + horizontalPadding,
                right: horizontalPadding - 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onSeeAll,
                    child: Text(l10n.viewAll),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            CarouselScrollWrapper(
              height: listHeight,
              centerHeight: cardWidth,
              buttonPadding: horizontalPadding > 20 ? 14.0 : 8.0,
              leftButtonOffset: contentLeftPadding,
              builder: (context, controller) {
                return ListView.separated(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    left: contentLeftPadding + horizontalPadding,
                    right: horizontalPadding,
                  ),
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => SizedBox(width: separatorWidth),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final name = playlist['name'] as String? ?? '';
                    final count = playlist['songCount'] as int? ?? 0;
                    final coverArtId = playlist['coverArt'] as String?;
                    return _DashboardPlaylistCard(
                      title: name,
                      songCount: count,
                      coverArtId: coverArtId,
                      server: server,
                      password: password,
                      width: cardWidth,
                      isWide: isWide,
                      onTap: () => onOpenPlaylist?.call(playlist),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardPlaylistCard extends StatelessWidget {
  const _DashboardPlaylistCard({
    required this.title,
    required this.songCount,
    required this.coverArtId,
    required this.server,
    required this.password,
    required this.width,
    required this.isWide,
    required this.onTap,
  });

  final String title;
  final int songCount;
  final String? coverArtId;
  final RemoteServer server;
  final String password;
  final double width;
  final bool isWide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RemoteArtworkWidget(
                  server: server,
                  password: password,
                  coverArtId: coverArtId,
                  size: width,
                  width: width,
                  height: width,
                  fallbackIcon: Icons.queue_music_rounded,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: isWide ? 14.5 : 14.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$songCount ${l10n.songs}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
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
