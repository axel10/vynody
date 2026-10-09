import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/widgets/album_cover.dart';
import 'package:vynody/widgets/artist_avatar.dart';
import 'package:vynody/widgets/song_thumbnail.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';

/// 桌面端与移动端统一的响应式媒体库首页（Dashboard 仪表盘）
class LibraryDashboardView extends ConsumerWidget {
  const LibraryDashboardView({
    super.key,
    required this.onNavigateToSubIndex,
    this.contentTopPadding = 32.0,
    this.contentLeftPadding = 0.0,
  });

  final ValueChanged<int> onNavigateToSubIndex;
  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final bottomInset = (currentMusic != null ? 140.0 : 90.0) +
        MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 780;
          final horizontalPadding = isWide ? 32.0 : 20.0;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 1. 顶部大标题与曲库统计
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    contentLeftPadding + horizontalPadding,
                    contentTopPadding + 16,
                    horizontalPadding,
                    8,
                  ),
                  child: _DashboardHeader(l10n: l10n),
                ),
              ),

              // 2. 快速入口胶囊行
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding + horizontalPadding,
                    right: horizontalPadding,
                    top: 12,
                    bottom: 24,
                  ),
                  child: _QuickAccessChips(
                    onTapSubIndex: onNavigateToSubIndex,
                    l10n: l10n,
                  ),
                ),
              ),

              // 3. 最近播放（横向单曲卡片流）
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding,
                    bottom: 28,
                  ),
                  child: _RecentlyPlayedSection(
                    horizontalPadding: horizontalPadding,
                    onViewAll: () => onNavigateToSubIndex(1),
                    l10n: l10n,
                  ),
                ),
              ),

              // 4. 双栏对比区 1：本周常听 TOP 5 vs 拾光机 / 重温旧爱
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding + horizontalPadding,
                    right: horizontalPadding,
                    bottom: 28,
                  ),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _ThisWeekTopCard(
                                onViewAll: () => onNavigateToSubIndex(2),
                                l10n: l10n,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _TimeMachineCard(l10n: l10n),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _ThisWeekTopCard(
                              onViewAll: () => onNavigateToSubIndex(2),
                              l10n: l10n,
                            ),
                            const SizedBox(height: 20),
                            _TimeMachineCard(l10n: l10n),
                          ],
                        ),
                ),
              ),

              // 5. 双栏对比区 2：最近添加 vs 你的收藏 / 高评分
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding + horizontalPadding,
                    right: horizontalPadding,
                    bottom: 32,
                  ),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _RecentlyAddedCard(
                                onViewAll: () => onNavigateToSubIndex(3),
                                l10n: l10n,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _TopRatedCard(
                                onViewAll: () => onNavigateToSubIndex(6),
                                l10n: l10n,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            _RecentlyAddedCard(
                              onViewAll: () => onNavigateToSubIndex(3),
                              l10n: l10n,
                            ),
                            const SizedBox(height: 20),
                            _TopRatedCard(
                              onViewAll: () => onNavigateToSubIndex(6),
                              l10n: l10n,
                            ),
                          ],
                        ),
                ),
              ),

              // 6. 独立通栏：专辑
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding,
                    bottom: 32,
                  ),
                  child: _AlbumsRowSection(
                    horizontalPadding: horizontalPadding,
                    onViewAll: () => onNavigateToSubIndex(4),
                    l10n: l10n,
                  ),
                ),
              ),

              // 7. 独立通栏：艺术家
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding,
                    bottom: 32,
                  ),
                  child: _ArtistsRowSection(
                    horizontalPadding: horizontalPadding,
                    onViewAll: () => onNavigateToSubIndex(5),
                    l10n: l10n,
                  ),
                ),
              ),

              // 8. 独立通栏：流派（只展示有歌曲的流派）
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: contentLeftPadding,
                    bottom: bottomInset,
                  ),
                  child: _GenresRowSection(
                    horizontalPadding: horizontalPadding,
                    l10n: l10n,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部标题与统计
// ---------------------------------------------------------------------------
class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final albumsCount = ref.watch(albumLibraryProvider).value?.length ?? 0;
    final artistsCount = ref.watch(artistLibraryProvider).value?.length ?? 0;
    final playlistsCount = ref.watch(playlistServiceProvider).playlists.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          l10n.list,
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 14),
        if (albumsCount > 0 || artistsCount > 0)
          Text(
            '$albumsCount ${l10n.albums} · $artistsCount ${l10n.artists}${playlistsCount > 0 ? " · $playlistsCount ${l10n.playlist}" : ""}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 快速入口胶囊行
// ---------------------------------------------------------------------------
class _QuickAccessChips extends StatelessWidget {
  const _QuickAccessChips({
    required this.onTapSubIndex,
    required this.l10n,
  });

  final ValueChanged<int> onTapSubIndex;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        index: 1,
        title: l10n.recentlyPlayed,
        icon: Icons.history_rounded,
        color: const Color(0xFF10B981),
      ),
      (
        index: 2,
        title: l10n.mostPlayed,
        icon: Icons.local_fire_department_rounded,
        color: const Color(0xFFEF4444),
      ),
      (
        index: 3,
        title: l10n.recentlyAdded,
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFF59E0B),
      ),
      (
        index: 6,
        title: l10n.ratedSongs,
        icon: Icons.star_rounded,
        color: const Color(0xFFEAB308),
      ),
      (
        index: 0,
        title: l10n.playlist,
        icon: Icons.queue_music_rounded,
        color: const Color(0xFF8B5CF6),
      ),
      (
        index: 5,
        title: l10n.artists,
        icon: Icons.mic_external_on_rounded,
        color: const Color(0xFFF97316),
      ),
      (
        index: 4,
        title: l10n.albums,
        icon: Icons.album_rounded,
        color: const Color(0xFF06B6D4),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _QuickChip(
              title: item.title,
              icon: item.icon,
              color: item.color,
              onTap: () => onTapSubIndex(item.index),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _QuickChip extends StatefulWidget {
  const _QuickChip({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_QuickChip> createState() => _QuickChipState();
}

class _QuickChipState extends State<_QuickChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.color.withValues(alpha: isDark ? 0.22 : 0.16)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: isDark ? 0.45 : 0.70,
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.color,
              ),
              const SizedBox(width: 7),
              Text(
                widget.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _isHovered
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 最近播放横向单曲卡片流
// ---------------------------------------------------------------------------
class _RecentlyPlayedSection extends ConsumerWidget {
  const _RecentlyPlayedSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSongs = ref.watch(
      recentlyPlayedSongsProvider(LibraryTimeRange.allTime),
    );

    return asyncSongs.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final previewItems = items.take(8).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: _SectionHeader(
                title: l10n.recentlyPlayed,
                onViewAll: onViewAll,
                l10n: l10n,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 195,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: previewItems.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final entry = previewItems[index];
                  final allSongs = previewItems.map((e) => e.song).toList();
                  return _SongCard(
                    song: entry.song,
                    onPlay: () {
                      ref.read(audioServiceProvider).playPlaylist(
                            allSongs,
                            initialIndex: index,
                          );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _SongCard extends StatefulWidget {
  const _SongCard({
    required this.song,
    required this.onPlay,
  });

  final MusicFile song;
  final VoidCallback onPlay;

  @override
  State<_SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<_SongCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPlay,
        child: SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SongThumbnail.fromSong(
                    widget.song,
                    size: 130,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  Positioned.fill(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _isHovered ? 1.0 : 0.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.song.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.song.artist ?? 'Unknown Artist',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 双栏 1：本周常听 TOP 5 vs 拾光机 / 重温旧爱
// ---------------------------------------------------------------------------
class _ThisWeekTopCard extends ConsumerWidget {
  const _ThisWeekTopCard({
    required this.onViewAll,
    required this.l10n,
  });

  final VoidCallback onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncSongs = ref.watch(
      mostPlayedSongsProvider(LibraryTimeRange.last7Days),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.35 : 0.55,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: l10n.thisWeekTop,
            subtitle: l10n.thisWeekTopSubtitle,
            onViewAll: onViewAll,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          asyncSongs.when(
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l10n.emptyThisWeekTop,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              final topItems = items.take(5).toList();
              final allSongs = topItems.map((e) => e.song).toList();

              return Column(
                children: List.generate(topItems.length, (idx) {
                  final entry = topItems[idx];
                  return _RankedSongRow(
                    index: idx + 1,
                    song: entry.song,
                    metric: '${entry.playCount} 次',
                    onTap: () {
                      ref.read(audioServiceProvider).playPlaylist(
                            allSongs,
                            initialIndex: idx,
                          );
                    },
                  );
                }),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TimeMachineCard extends ConsumerWidget {
  const _TimeMachineCard({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncAlbums = ref.watch(timeMachineAlbumsProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.35 : 0.55,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.timeMachine,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.timeMachineSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          asyncAlbums.when(
            data: (albums) {
              if (albums.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l10n.emptyTimeMachine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }

              final preview = albums.take(4).toList();
              return Column(
                children: preview.map((entry) {
                  return _TimeMachineAlbumRow(entry: entry);
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TimeMachineAlbumRow extends ConsumerWidget {
  const _TimeMachineAlbumRow({required this.entry});
  final TimeMachineAlbumEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (entry.songs.isEmpty) return;
        final albumSummary = AlbumSummary(
          id: '${entry.album}|${entry.artist}',
          title: entry.album,
          artist: entry.artist,
          songs: entry.songs,
          representativeSong: entry.songs.first,
          totalDurationMillis: entry.songs.fold<int>(
            0,
            (sum, s) => sum + (s.durationMillis ?? 0),
          ),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AlbumDetailPage(album: albumSummary),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        child: Row(
          children: [
            SongThumbnail(
              path: entry.songs.isNotEmpty ? entry.songs.first.path : entry.album,
              artworkPath: entry.artworkPath,
              thumbnailPath: entry.thumbnailPath,
              size: 46,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.album,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.play_circle_fill_rounded),
              iconSize: 30,
              color: theme.colorScheme.primary,
              tooltip: '播放整张专辑',
              onPressed: () {
                if (entry.songs.isNotEmpty) {
                  ref.read(audioServiceProvider).playPlaylist(
                        entry.songs,
                        initialIndex: 0,
                      );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 双栏 2：最近添加 vs 你的收藏 / 高评分
// ---------------------------------------------------------------------------
class _RecentlyAddedCard extends ConsumerWidget {
  const _RecentlyAddedCard({
    required this.onViewAll,
    required this.l10n,
  });

  final VoidCallback onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncSongs = ref.watch(
      recentlyAddedSongsProvider(LibraryTimeRange.allTime),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.35 : 0.55,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: l10n.recentlyAdded,
            onViewAll: onViewAll,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          asyncSongs.when(
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l10n.noRecentlyAddedSongs,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              final preview = items.take(5).toList();
              final allSongs = preview.map((e) => e.song).toList();

              return Column(
                children: List.generate(preview.length, (idx) {
                  final entry = preview[idx];
                  return _SimpleSongRow(
                    song: entry.song,
                    trailingText: entry.createdAt != null
                        ? _formatDate(entry.createdAt!)
                        : null,
                    onTap: () {
                      ref.read(audioServiceProvider).playPlaylist(
                            allSongs,
                            initialIndex: idx,
                          );
                    },
                  );
                }),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _formatDate(int millis) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.month}/${date.day}';
  }
}

class _TopRatedCard extends ConsumerWidget {
  const _TopRatedCard({
    required this.onViewAll,
    required this.l10n,
  });

  final VoidCallback onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncSongs = ref.watch(topRatedSongsProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.35 : 0.55,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: l10n.topRated,
            subtitle: l10n.topRatedSubtitle,
            onViewAll: onViewAll,
            l10n: l10n,
          ),
          const SizedBox(height: 12),
          asyncSongs.when(
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l10n.emptyTopRated,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              final preview = items.take(5).toList();
              final allSongs = preview.map((e) => e.song).toList();

              return Column(
                children: List.generate(preview.length, (idx) {
                  final entry = preview[idx];
                  return _SimpleSongRow(
                    song: entry.song,
                    trailingWidget: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${entry.playCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    onTap: () {
                      ref.read(audioServiceProvider).playPlaylist(
                            allSongs,
                            initialIndex: idx,
                          );
                    },
                  );
                }),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator.adaptive()),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 独立通栏：专辑
// ---------------------------------------------------------------------------
class _AlbumsRowSection extends ConsumerWidget {
  const _AlbumsRowSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncAlbums = ref.watch(albumLibraryProvider);

    return asyncAlbums.when(
      data: (albums) {
        if (albums.isEmpty) return const SizedBox.shrink();
        final preview = albums.take(10).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: _SectionHeader(
                title: l10n.albums,
                onViewAll: onViewAll,
                l10n: l10n,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 185,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: preview.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final album = preview[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AlbumDetailPage(album: album),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 125,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AlbumCover(album: album, size: 125),
                          const SizedBox(height: 8),
                          Text(
                            album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            album.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// 独立通栏：艺术家
// ---------------------------------------------------------------------------
class _ArtistsRowSection extends ConsumerWidget {
  const _ArtistsRowSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncArtists = ref.watch(artistLibraryProvider);

    return asyncArtists.when(
      data: (artists) {
        if (artists.isEmpty) return const SizedBox.shrink();
        final preview = artists.take(10).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: _SectionHeader(
                title: l10n.artists,
                onViewAll: onViewAll,
                l10n: l10n,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 145,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: preview.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final artist = preview[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(50),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ArtistDetailPage(artist: artist),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 96,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ArtistAvatar(
                            diameter: 96,
                            imagePath: artist.cachedImagePath,
                            imageUrl: artist.imageUrl,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// 独立通栏：流派（只展示有歌曲的流派）
// ---------------------------------------------------------------------------
class _GenresRowSection extends ConsumerWidget {
  const _GenresRowSection({
    required this.horizontalPadding,
    required this.l10n,
  });

  final double horizontalPadding;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncGenres = ref.watch(genreLibraryProvider);

    return asyncGenres.when(
      data: (genres) {
        if (genres.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Text(
                l10n.genres,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                itemCount: genres.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final genre = genres[index];
                  return _GenreCard(
                    genre: genre,
                    onTap: () {
                      if (genre.sampleSongs.isNotEmpty) {
                        ref.read(audioServiceProvider).playPlaylist(
                              genre.sampleSongs,
                              initialIndex: 0,
                            );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _GenreCard extends StatefulWidget {
  const _GenreCard({
    required this.genre,
    required this.onTap,
  });

  final GenreSummary genre;
  final VoidCallback onTap;

  @override
  State<_GenreCard> createState() => _GenreCardState();
}

class _GenreCardState extends State<_GenreCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 160,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isHovered
                  ? [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.surfaceContainerHighest,
                    ]
                  : [
                      theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: isDark ? 0.65 : 0.85,
                      ),
                      theme.colorScheme.surfaceContainerLow.withValues(
                        alpha: isDark ? 0.45 : 0.75,
                      ),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isHovered
                  ? theme.colorScheme.primary.withValues(alpha: 0.4)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              if (widget.genre.sampleSongs.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SongThumbnail(
                    path: widget.genre.sampleSongs.first.path,
                    artworkPath: widget.genre.representativeArtworkPath,
                    thumbnailPath: widget.genre.representativeThumbnailPath,
                    size: 44,
                  ),
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.music_note_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.genre.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.genre.songCount} 首',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// 基础微组件
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.onViewAll,
    required this.l10n,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onViewAll;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        if (onViewAll != null)
          InkWell(
            onTap: onViewAll,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.viewAll,
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
    );
  }
}

class _RankedSongRow extends StatelessWidget {
  const _RankedSongRow({
    required this.index,
    required this.song,
    required this.metric,
    required this.onTap,
  });

  final int index;
  final MusicFile song;
  final String metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                index.toString().padLeft(2, '0'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: index <= 3
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SongThumbnail.fromSong(
              song,
              size: 38,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    song.artist ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              metric,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleSongRow extends StatelessWidget {
  const _SimpleSongRow({
    required this.song,
    this.trailingText,
    this.trailingWidget,
    required this.onTap,
  });

  final MusicFile song;
  final String? trailingText;
  final Widget? trailingWidget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SongThumbnail.fromSong(
              song,
              size: 38,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    song.artist ?? 'Unknown Artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingWidget != null)
              trailingWidget!
            else if (trailingText != null)
              Text(
                trailingText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
