import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../player/remote/remote_server_models.dart';
import '../../widgets/playback_ui_tuning.dart';
import '../../widgets/remote_artwork_widget.dart';

/// 远程媒体库概览页。
///
/// 与本地媒体库的 `LibraryDashboardView` 同一套视觉节奏：顶部大标题与统计 →
/// 快捷入口 → 若干横向内容板块。数据由 `RemoteLibraryPage` 传入（那里是唯一的
/// 数据宿主），本页只负责排版与跳转，不发起任何请求。
///
/// 板块取舍遵循「没有对应能力就不显示」：远程没有播放历史与用户评分，
/// 所以不出现「最近播放 / 最常播放 / 高分」；搜索按需求保持为独立子页，
/// 这里只放一个入口卡片。
class RemoteLibraryDashboardView extends StatelessWidget {
  const RemoteLibraryDashboardView({
    super.key,
    required this.server,
    required this.password,
    required this.albumCount,
    required this.artistCount,
    required this.songCount,
    required this.playlistCount,
    required this.recentAlbums,
    required this.favoriteAlbums,
    required this.onNavigateToTab,
    required this.onOpenAlbum,
    required this.onRefresh,
    required this.onShuffleAll,
    required this.onDisconnect,
    this.contentTopPadding = 16,
  });

  final RemoteServer server;
  final String password;

  final int albumCount;
  final int artistCount;
  final int songCount;
  final int playlistCount;

  /// 最近添加的专辑（父页按 `created` 降序取前若干张）。空则不显示该板块。
  final List<Map<String, dynamic>> recentAlbums;

  /// 收藏的专辑。空则不显示该板块。
  final List<Map<String, dynamic>> favoriteAlbums;

  final ValueChanged<int> onNavigateToTab;

  /// 点封面直接进专辑详情。
  final void Function(String albumId, String albumTitle) onOpenAlbum;

  final VoidCallback onRefresh;
  final VoidCallback onShuffleAll;

  /// 断开当前媒体库（一级栏目的显式退出动作）。
  ///
  /// 一级 tab 没有「上一级」，返回键不再承担退出语义，所以退出必须是
  /// 这里一个看得见、且有确认的动作。
  final VoidCallback onDisconnect;

  final double contentTopPadding;

  /// 分类索引，与 `RemoteLibraryPage` 的 tab 顺序保持一致。
  static const int tabAlbums = 0;
  static const int tabArtists = 1;
  static const int tabGenres = 2;
  static const int tabSongs = 3;
  static const int tabPlaylists = 4;
  static const int tabSearch = 5;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth >= 780;
        final double horizontalPadding = isWide ? 32.0 : 16.0;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  contentTopPadding + 8,
                  horizontalPadding,
                  12,
                ),
                child: _DashboardHeader(
                  server: server,
                  albumCount: albumCount,
                  artistCount: artistCount,
                  songCount: songCount,
                  onRefresh: onRefresh,
                  onShuffleAll: onShuffleAll,
                  onDisconnect: onDisconnect,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _QuickAccessGrid(
                  l10n: l10n,
                  albumCount: albumCount,
                  artistCount: artistCount,
                  songCount: songCount,
                  playlistCount: playlistCount,
                  onNavigateToTab: onNavigateToTab,
                ),
              ),
            ),
            if (recentAlbums.isNotEmpty)
              _AlbumRowSection(
                title: l10n.recentlyAdded,
                albums: recentAlbums,
                server: server,
                password: password,
                horizontalPadding: horizontalPadding,
                onOpenAlbum: onOpenAlbum,
                onSeeAll: () => onNavigateToTab(tabAlbums),
              ),
            if (favoriteAlbums.isNotEmpty)
              _AlbumRowSection(
                title: l10n.starredAlbums,
                albums: favoriteAlbums,
                server: server,
                password: password,
                horizontalPadding: horizontalPadding,
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
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.server,
    required this.albumCount,
    required this.artistCount,
    required this.songCount,
    required this.onRefresh,
    required this.onShuffleAll,
    required this.onDisconnect,
  });

  final RemoteServer server;
  final int albumCount;
  final int artistCount;
  final int songCount;
  final VoidCallback onRefresh;
  final VoidCallback onShuffleAll;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final bool isJellyfin = server.type == RemoteServerType.jellyfin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.casino_outlined, size: 20),
              tooltip: l10n.shufflePlay,
              onPressed: onShuffleAll,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: l10n.refresh,
              onPressed: onRefresh,
            ),
            IconButton(
              icon: const Icon(Icons.link_off_rounded, size: 20),
              tooltip: l10n.remoteDisconnect,
              onPressed: onDisconnect,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          isJellyfin ? 'Jellyfin' : 'Navidrome / Subsonic',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${l10n.albums} $albumCount · ${l10n.artists} $artistCount · '
          '${l10n.songs} $songCount',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid({
    required this.l10n,
    required this.albumCount,
    required this.artistCount,
    required this.songCount,
    required this.playlistCount,
    required this.onNavigateToTab,
  });

  final AppLocalizations l10n;
  final int albumCount;
  final int artistCount;
  final int songCount;
  final int playlistCount;
  final ValueChanged<int> onNavigateToTab;

  @override
  Widget build(BuildContext context) {
    final entries = <_QuickEntry>[
      _QuickEntry(
        icon: Icons.album_outlined,
        label: l10n.albums,
        count: albumCount,
        tabIndex: RemoteLibraryDashboardView.tabAlbums,
      ),
      _QuickEntry(
        icon: Icons.mic_none_rounded,
        label: l10n.artists,
        count: artistCount,
        tabIndex: RemoteLibraryDashboardView.tabArtists,
      ),
      _QuickEntry(
        icon: Icons.style_outlined,
        label: l10n.genres,
        tabIndex: RemoteLibraryDashboardView.tabGenres,
      ),
      _QuickEntry(
        icon: Icons.music_note_rounded,
        label: l10n.songs,
        count: songCount,
        tabIndex: RemoteLibraryDashboardView.tabSongs,
      ),
      _QuickEntry(
        icon: Icons.queue_music_rounded,
        label: l10n.playlists,
        count: playlistCount,
        tabIndex: RemoteLibraryDashboardView.tabPlaylists,
      ),
      _QuickEntry(
        icon: Icons.search_rounded,
        label: l10n.search,
        tabIndex: RemoteLibraryDashboardView.tabSearch,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡片定宽，列数由可用宽度决定：桌面宽窗一行放满，手机竖屏两列。
        const double minCardWidth = 160;
        const double spacing = 12;
        final int columns = (constraints.maxWidth / (minCardWidth + spacing))
            .floor()
            .clamp(2, entries.length);
        final double cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in entries)
              SizedBox(
                width: cardWidth,
                child: _QuickAccessCard(
                  entry: entry,
                  onTap: () => onNavigateToTab(entry.tabIndex),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuickEntry {
  const _QuickEntry({
    required this.icon,
    required this.label,
    required this.tabIndex,
    this.count,
  });

  final IconData icon;
  final String label;
  final int tabIndex;
  final int? count;
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({required this.entry, required this.onTap});

  final _QuickEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(entry.icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (entry.count != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${entry.count}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
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
    required this.horizontalPadding,
    required this.onOpenAlbum,
    required this.onSeeAll,
  });

  final String title;
  final List<Map<String, dynamic>> albums;
  final RemoteServer server;
  final String password;
  final double horizontalPadding;
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
                left: horizontalPadding,
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
            SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
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
                    onTap: () => onOpenAlbum(id, name),
                  );
                },
              ),
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
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? coverArtId;
  final RemoteServer server;
  final String password;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 140,
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
                  size: 140,
                  width: 140,
                  height: 140,
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
                ),
              ),
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
