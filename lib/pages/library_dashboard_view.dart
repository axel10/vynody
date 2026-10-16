import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_overview_providers.dart';
import 'package:vynody/player/metadata/theaudiodb_artist_service.dart';
import 'package:vynody/widgets/album_cover.dart';
import 'package:vynody/widgets/artist_avatar.dart';
import 'package:vynody/widgets/song_thumbnail.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';
import 'genre_detail_page.dart';
import 'main_layout_riverpod.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/section_type_toggle.dart';

// ===========================================================================
// 媒体库首页封面缩放系数配置（可在此自由修改数值调节大小）
// ===========================================================================
/// 桌面横屏下专辑/歌曲封面缩放系数（修改此数值即可全局等比放大/缩小，例如 1.3, 1.45, 1.6, 1.8 等）
const double kDashboardDesktopCoverScale = 1.9;

/// 竖屏移动端下封面缩放系数
const double kDashboardMobileCoverScale = 1.2;

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
    final bottomInset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 780;
          final horizontalPadding = isWide ? 32.0 : 16.0;

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

              // 2. 快速入口：横屏使用大号卡片流，竖屏保持经典大菜单卡片
              SliverToBoxAdapter(
                child: isWide
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 28),
                        child: _WideQuickAccessBar(
                          onTapSubIndex: (sub) {
                            if (sub == 2) {
                              ref.read(mostPlayedFilterProvider.notifier).reset();
                            }
                            onNavigateToSubIndex(sub);
                          },
                          l10n: l10n,
                          contentLeftPadding: contentLeftPadding,
                          horizontalPadding: horizontalPadding,
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.only(
                          left: horizontalPadding,
                          right: horizontalPadding,
                          top: 8,
                          bottom: 22,
                        ),
                        child: _PortraitLibraryMenuCard(
                          onTapSubIndex: (sub) {
                            if (sub == 2) {
                              ref.read(mostPlayedFilterProvider.notifier).reset();
                            }
                            onNavigateToSubIndex(sub);
                          },
                          l10n: l10n,
                        ),
                      ),
              ),

              // 3. 最近播放（横向单曲卡片流）
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 28,
                  ),
                  child: _RecentlyPlayedSection(
                    horizontalPadding: horizontalPadding,
                    contentLeftPadding: contentLeftPadding,
                    onViewAll: () => onNavigateToSubIndex(1),
                    l10n: l10n,
                    isWide: isWide,
                  ),
                ),
              ),

              // 4. 本周常听（横向专辑流）
              SliverToBoxAdapter(
                child: _ThisWeekAlbumsSection(
                  horizontalPadding: horizontalPadding,
                  contentLeftPadding: contentLeftPadding,
                  onViewAll: () {
                    ref.read(mostPlayedFilterProvider.notifier).setBoth(
                      type: SectionItemType.albums,
                      range: LibraryTimeRange.last7Days,
                    );
                    onNavigateToSubIndex(2);
                  },
                  l10n: l10n,
                  isWide: isWide,
                ),
              ),

              // 5. 重温旧爱（横向专辑流）
              SliverToBoxAdapter(
                child: _TimeMachineAlbumsSection(
                  horizontalPadding: horizontalPadding,
                  contentLeftPadding: contentLeftPadding,
                  onViewAll: () => onNavigateToSubIndex(2),
                  l10n: l10n,
                  isWide: isWide,
                ),
              ),

              // 6. 最近添加（横向专辑流）
              SliverToBoxAdapter(
                child: _RecentlyAddedAlbumsSection(
                  horizontalPadding: horizontalPadding,
                  contentLeftPadding: contentLeftPadding,
                  onViewAll: () => onNavigateToSubIndex(3),
                  l10n: l10n,
                  isWide: isWide,
                ),
              ),

              // 7. 已评分（横向专辑流）
              SliverToBoxAdapter(
                child: _TopRatedAlbumsSection(
                  horizontalPadding: horizontalPadding,
                  contentLeftPadding: contentLeftPadding,
                  onViewAll: () => onNavigateToSubIndex(6),
                  l10n: l10n,
                  isWide: isWide,
                ),
              ),

              // 6. 独立通栏：专辑
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 32,
                  ),
                  child: _AlbumsRowSection(
                    horizontalPadding: horizontalPadding,
                    contentLeftPadding: contentLeftPadding,
                    onViewAll: () => onNavigateToSubIndex(4),
                    l10n: l10n,
                    isWide: isWide,
                  ),
                ),
              ),

              // 7. 独立通栏：艺术家
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    bottom: 32,
                  ),
                  child: _ArtistsRowSection(
                    horizontalPadding: horizontalPadding,
                    contentLeftPadding: contentLeftPadding,
                    onViewAll: () => onNavigateToSubIndex(5),
                    l10n: l10n,
                    isWide: isWide,
                  ),
                ),
              ),

              // 8. 独立通栏：流派（只展示有歌曲的流派）
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: bottomInset,
                  ),
                  child: _GenresRowSection(
                    horizontalPadding: horizontalPadding,
                    contentLeftPadding: contentLeftPadding,
                    l10n: l10n,
                    isWide: isWide,
                    onViewAll: () => onNavigateToSubIndex(7),
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
          Expanded(
            child: Text(
              '$albumsCount ${l10n.albums} · $artistsCount ${l10n.artists}${playlistsCount > 0 ? " · $playlistsCount ${l10n.playlist}" : ""}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 横屏大号快捷入口流
// ---------------------------------------------------------------------------
class _WideQuickAccessBar extends ConsumerWidget {
  const _WideQuickAccessBar({
    required this.onTapSubIndex,
    required this.l10n,
    this.contentLeftPadding = 0.0,
    this.horizontalPadding = 32.0,
  });

  final ValueChanged<int> onTapSubIndex;
  final AppLocalizations l10n;
  final double contentLeftPadding;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsCount =
        ref.watch(playlistServiceProvider).playlists.length;
    final albumsCount = ref.watch(albumLibraryProvider).value?.length;
    final artistsCount = ref.watch(artistLibraryProvider).value?.length;
    final genresCount = ref.watch(genreLibraryProvider).value?.length;

    final items = [
      (
        index: 1,
        title: l10n.recentlyPlayed,
        icon: Icons.history_rounded,
        gradient: const [Color(0xFF10B981), Color(0xFF14B8A6)],
        badgeText: null,
      ),
      (
        index: 2,
        title: l10n.mostPlayed,
        icon: Icons.local_fire_department_rounded,
        gradient: const [Color(0xFFEF4444), Color(0xFFF43F5E)],
        badgeText: null,
      ),
      (
        index: 3,
        title: l10n.recentlyAdded,
        icon: Icons.auto_awesome_rounded,
        gradient: const [Color(0xFFF59E0B), Color(0xFFEAB308)],
        badgeText: null,
      ),
      (
        index: 6,
        title: l10n.ratedSongs,
        icon: Icons.star_rounded,
        gradient: const [Color(0xFFEAB308), Color(0xFFF59E0B)],
        badgeText: null,
      ),
      (
        index: 0,
        title: l10n.playlist,
        icon: Icons.queue_music_rounded,
        gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        badgeText: playlistsCount > 0 ? '$playlistsCount' : null,
      ),
      (
        index: 5,
        title: l10n.artists,
        icon: Icons.mic_external_on_rounded,
        gradient: const [Color(0xFFF97316), Color(0xFFFB923C)],
        badgeText:
            artistsCount != null && artistsCount > 0 ? '$artistsCount' : null,
      ),
      (
        index: 4,
        title: l10n.albums,
        icon: Icons.album_rounded,
        gradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
        badgeText:
            albumsCount != null && albumsCount > 0 ? '$albumsCount' : null,
      ),
      (
        index: 7,
        title: l10n.genres,
        icon: Icons.style_rounded,
        gradient: const [Color(0xFF8B5CF6), Color(0xFFA855F7)],
        badgeText:
            genresCount != null && genresCount > 0 ? '$genresCount' : null,
      ),
    ];

    return SingleChildScrollView(
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
              onTap: () => onTapSubIndex(item.index),
            ),
          );
        }).toList(),
      ),
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
                      color: widget.gradient.first.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
// 竖屏大菜单卡片（保持 a3ec2752 之前的经典卡片样式）
// ---------------------------------------------------------------------------
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

class _PortraitLibraryMenuCard extends ConsumerWidget {
  const _PortraitLibraryMenuCard({
    required this.onTapSubIndex,
    required this.l10n,
  });

  final ValueChanged<int> onTapSubIndex;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final playlistsCount =
        ref.watch(playlistServiceProvider).playlists.length;
    final albumsCount = ref.watch(albumLibraryProvider).value?.length;
    final artistsCount = ref.watch(artistLibraryProvider).value?.length;
    final genresCount = ref.watch(genreLibraryProvider).value?.length;

    final items = [
      _LibraryMenuItem(
        icon: Icons.queue_music_rounded,
        iconGradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        title: l10n.playlist,
        badgeText: playlistsCount > 0 ? '$playlistsCount' : null,
        onTap: () => onTapSubIndex(0),
      ),
      _LibraryMenuItem(
        icon: Icons.mic_external_on_rounded,
        iconGradient: const [Color(0xFFF97316), Color(0xFFFB923C)],
        title: l10n.artists,
        badgeText:
            artistsCount != null && artistsCount > 0 ? '$artistsCount' : null,
        onTap: () => onTapSubIndex(5),
      ),
      _LibraryMenuItem(
        icon: Icons.album_rounded,
        iconGradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
        title: l10n.albums,
        badgeText:
            albumsCount != null && albumsCount > 0 ? '$albumsCount' : null,
        onTap: () => onTapSubIndex(4),
      ),
      _LibraryMenuItem(
        icon: Icons.style_rounded,
        iconGradient: const [Color(0xFF8B5CF6), Color(0xFFA855F7)],
        title: l10n.genres,
        badgeText:
            genresCount != null && genresCount > 0 ? '$genresCount' : null,
        onTap: () => onTapSubIndex(7),
      ),
      _LibraryMenuItem(
        icon: Icons.history_rounded,
        iconGradient: const [Color(0xFF10B981), Color(0xFF14B8A6)],
        title: l10n.recentlyPlayed,
        onTap: () => onTapSubIndex(1),
      ),
      _LibraryMenuItem(
        icon: Icons.local_fire_department_rounded,
        iconGradient: const [Color(0xFFEF4444), Color(0xFFF43F5E)],
        title: l10n.mostPlayed,
        onTap: () => onTapSubIndex(2),
      ),
      _LibraryMenuItem(
        icon: Icons.auto_awesome_rounded,
        iconGradient: const [Color(0xFFF59E0B), Color(0xFFEAB308)],
        title: l10n.recentlyAdded,
        onTap: () => onTapSubIndex(3),
      ),
      _LibraryMenuItem(
        icon: Icons.star_rounded,
        iconGradient: const [Color(0xFFEAB308), Color(0xFFF59E0B)],
        title: l10n.ratedSongs,
        onTap: () => onTapSubIndex(6),
      ),
    ];

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
                  padding: const EdgeInsets.only(left: 68, right: 16),
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

// ---------------------------------------------------------------------------
// 横向走马灯滚动容器（支持悬浮竖胶囊翻页按钮）
// ---------------------------------------------------------------------------
enum _PillNavDirection { left, right }

class _PillNavButton extends StatefulWidget {
  const _PillNavButton({
    required this.direction,
    required this.visible,
    required this.onTap,
  });

  final _PillNavDirection direction;
  final bool visible;
  final VoidCallback onTap;

  @override
  State<_PillNavButton> createState() => _PillNavButtonState();
}

class _PillNavButtonState extends State<_PillNavButton> {
  bool _isButtonHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 暗色模式：基础半透明深灰，悬停时加深至纯黑；亮色模式：基础半透明白，悬停时加深为沉着深灰
    final baseColor = isDark
        ? const Color(0xFF28282A).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.90);
    final hoverColor = isDark
        ? const Color(0xFF101012).withValues(alpha: 0.98)
        : const Color(0xFFD1D5DB).withValues(alpha: 0.98);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: _isButtonHovered ? 0.25 : 0.12)
        : Colors.black.withValues(alpha: _isButtonHovered ? 0.16 : 0.08);

    final iconColor = isDark
        ? Colors.white.withValues(alpha: _isButtonHovered ? 1.0 : 0.85)
        : (_isButtonHovered ? Colors.black : Colors.black87);

    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        opacity: widget.visible ? 1.0 : 0.0,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isButtonHovered = true),
          onExit: (_) => setState(() => _isButtonHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 56,
              decoration: BoxDecoration(
                color: _isButtonHovered ? hoverColor : baseColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark
                          ? (_isButtonHovered ? 0.45 : 0.28)
                          : (_isButtonHovered ? 0.20 : 0.10),
                    ),
                    blurRadius: _isButtonHovered ? 12 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  widget.direction == _PillNavDirection.left
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 22,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CarouselScrollWrapper extends StatefulWidget {
  const _CarouselScrollWrapper({
    required this.height,
    required this.builder,
    this.centerHeight,
    this.buttonPadding = 12.0,
    this.leftButtonOffset = 0.0,
  });

  final double height;
  final Widget Function(BuildContext context, ScrollController controller) builder;
  final double? centerHeight;
  final double buttonPadding;
  final double leftButtonOffset;

  @override
  State<_CarouselScrollWrapper> createState() => _CarouselScrollWrapperState();
}

class _CarouselScrollWrapperState extends State<_CarouselScrollWrapper> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void didUpdateWidget(covariant _CarouselScrollWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.pixels > 6.0;
    final canRight = position.pixels < (position.maxScrollExtent - 6.0);
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scrollNext() {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    // 翻一页：滑动约 82% 视口宽度，保留上下文锚点
    final delta = (viewport * 0.82).clamp(120.0, double.infinity);
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollPrevious() {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final delta = (viewport * 0.82).clamp(120.0, double.infinity);
    final target = (_scrollController.offset - delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetCenter = widget.centerHeight ?? widget.height;
    const btnHeight = 56.0;
    final btnTop = ((targetCenter - btnHeight) / 2.0).clamp(0.0, double.infinity);

    return MouseRegion(
      onEnter: (_) {
        _updateScrollState();
        setState(() => _isHovered = true);
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification ||
              notification is OverscrollNotification ||
              notification is UserScrollNotification) {
            _updateScrollState();
          }
          return false;
        },
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              widget.builder(context, _scrollController),

              // 左侧往前翻一页按钮
              Positioned(
                left: widget.leftButtonOffset + widget.buttonPadding,
                top: btnTop,
                child: _PillNavButton(
                  direction: _PillNavDirection.left,
                  visible: _isHovered && _canScrollLeft,
                  onTap: _scrollPrevious,
                ),
              ),

              // 右侧往后翻一页按钮
              Positioned(
                right: widget.buttonPadding,
                top: btnTop,
                child: _PillNavButton(
                  direction: _PillNavDirection.right,
                  visible: _isHovered && _canScrollRight,
                  onTap: _scrollNext,
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
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSongs = ref.watch(
      recentlyPlayedSongsProvider(LibraryTimeRange.allTime),
    );

    final scale = isWide ? kDashboardDesktopCoverScale : kDashboardMobileCoverScale;
    final cardWidth = (126.0 * scale).roundToDouble();
    final listHeight = cardWidth + 70.0;

    return asyncSongs.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final previewItems = items.take(20).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: contentLeftPadding + horizontalPadding,
                right: horizontalPadding,
              ),
              child: _SectionHeader(
                title: l10n.recentlyPlayed,
                onViewAll: onViewAll,
                l10n: l10n,
              ),
            ),
            const SizedBox(height: 12),
            _CarouselScrollWrapper(
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
                  itemCount: previewItems.length,
                  separatorBuilder: (_, _) => SizedBox(width: isWide ? 16 : 14),
                  itemBuilder: (context, index) {
                    final entry = previewItems[index];
                    final allSongs = previewItems.map((e) => e.song).toList();
                    return _SongCard(
                      song: entry.song,
                      width: cardWidth,
                      isWide: isWide,
                      onPlay: () {
                        ref.read(audioServiceProvider).playPlaylist(
                              allSongs,
                              initialIndex: index,
                            );
                      },
                    );
                  },
                );
              },
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
    this.width = 126.0,
    this.isWide = false,
  });

  final MusicFile song;
  final VoidCallback onPlay;
  final double width;
  final bool isWide;

  @override
  State<_SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<_SongCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = widget.width;
    final btnSize = widget.isWide ? 40.0 : 36.0;
    final iconSize = widget.isWide ? 24.0 : 22.0;
    final btnOffset = widget.isWide ? 10.0 : 8.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPlay,
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SongThumbnail.fromSong(
                    widget.song,
                    size: size,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  Positioned(
                    right: btnOffset,
                    bottom: btnOffset,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _isHovered ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_isHovered,
                        child: _CoverPlayButton(
                          size: btnSize,
                          iconSize: iconSize,
                          onTap: widget.onPlay,
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
                  fontSize: widget.isWide ? 14.5 : 14.0,
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

class _CoverPlayButton extends StatefulWidget {
  const _CoverPlayButton({
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  State<_CoverPlayButton> createState() => _CoverPlayButtonState();
}

class _CoverPlayButtonState extends State<_CoverPlayButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: _isHovered ? 0.50 : 0.36),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 1.5),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: widget.iconSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 通用横向专辑流滚动区块（Apple Music 风格 Carousel）
// ---------------------------------------------------------------------------
class _HorizontalAlbumSection extends StatelessWidget {
  const _HorizontalAlbumSection({
    required this.title,
    this.subtitle,
    required this.albums,
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final String title;
  final String? subtitle;
  final List<AlbumSummary> albums;
  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) return const SizedBox.shrink();

    final scale = isWide ? kDashboardDesktopCoverScale : kDashboardMobileCoverScale;
    final cardWidth = (126.0 * scale).roundToDouble();
    final coverSize = cardWidth;
    final listHeight = coverSize + 70.0;
    final separatorWidth = isWide ? 16.0 : 14.0;
    final preview = albums.take(15).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: contentLeftPadding + horizontalPadding,
              right: horizontalPadding,
            ),
            child: _SectionHeader(
              title: title,
              subtitle: subtitle,
              onViewAll: onViewAll,
              l10n: l10n,
            ),
          ),
          const SizedBox(height: 12),
          _CarouselScrollWrapper(
            height: listHeight,
            centerHeight: coverSize,
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
                itemCount: preview.length,
                separatorBuilder: (_, _) => SizedBox(width: separatorWidth),
                itemBuilder: (context, index) {
                  final album = preview[index];
                  return Consumer(
                    builder: (context, ref, _) {
                      return _AlbumCard(
                        key: ValueKey(album.id),
                        album: album,
                        width: cardWidth,
                        isWide: isWide,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AlbumDetailPage(album: album),
                            ),
                          );
                        },
                        onPlay: () {
                          if (album.songs.isNotEmpty) {
                            ref.read(audioServiceProvider).playPlaylist(
                                  album.songs,
                                  source: PlaybackSource(
                                    type: PlaybackSourceType.album,
                                    id: album.id,
                                  ),
                                );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. 本周常听（专辑横向流）
// ---------------------------------------------------------------------------
class _ThisWeekAlbumsSection extends ConsumerStatefulWidget {
  const _ThisWeekAlbumsSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  ConsumerState<_ThisWeekAlbumsSection> createState() =>
      _ThisWeekAlbumsSectionState();
}

class _ThisWeekAlbumsSectionState extends ConsumerState<_ThisWeekAlbumsSection> {
  List<AlbumSummary>? _cachedAlbums;

  @override
  Widget build(BuildContext context) {
    // 监听本周常听，并在首次获得数据时拷贝一份展示，生命周期内保持稳定，防止播完切歌时列表闪烁
    ref.listen(thisWeekTopAlbumsProvider, (_, next) {
      if (_cachedAlbums == null && next.hasValue) {
        setState(() {
          _cachedAlbums =
              next.value!.map((e) => e.toAlbumSummary()).toList(growable: false);
        });
      }
    });

    if (_cachedAlbums == null) {
      final initial = ref.read(thisWeekTopAlbumsProvider);
      if (initial.hasValue) {
        _cachedAlbums =
            initial.value!.map((e) => e.toAlbumSummary()).toList(growable: false);
      }
    }

    if (_cachedAlbums != null) {
      if (_cachedAlbums!.isEmpty) return const SizedBox.shrink();
      return _HorizontalAlbumSection(
        title: widget.l10n.thisWeekTop,
        subtitle: widget.l10n.thisWeekTopAlbumsSubtitle,
        albums: _cachedAlbums!,
        horizontalPadding: widget.horizontalPadding,
        contentLeftPadding: widget.contentLeftPadding,
        onViewAll: widget.onViewAll,
        l10n: widget.l10n,
        isWide: widget.isWide,
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// 5. 重温旧爱（专辑横向流）
// ---------------------------------------------------------------------------
class _TimeMachineAlbumsSection extends ConsumerStatefulWidget {
  const _TimeMachineAlbumsSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  ConsumerState<_TimeMachineAlbumsSection> createState() =>
      _TimeMachineAlbumsSectionState();
}

class _TimeMachineAlbumsSectionState
    extends ConsumerState<_TimeMachineAlbumsSection> {
  List<AlbumSummary>? _cachedAlbums;

  @override
  Widget build(BuildContext context) {
    // 监听重温旧爱，在首次获得数据时拷贝一份快照展示，页面停留期间不重新触发，避免刚听完的歌曲立刻被踢出导致列表闪动
    ref.listen(timeMachineAlbumsProvider, (_, next) {
      if (_cachedAlbums == null && next.hasValue) {
        setState(() {
          _cachedAlbums =
              next.value!.map((e) => e.toAlbumSummary()).toList(growable: false);
        });
      }
    });

    if (_cachedAlbums == null) {
      final initial = ref.read(timeMachineAlbumsProvider);
      if (initial.hasValue) {
        _cachedAlbums =
            initial.value!.map((e) => e.toAlbumSummary()).toList(growable: false);
      }
    }

    if (_cachedAlbums != null) {
      if (_cachedAlbums!.isEmpty) return const SizedBox.shrink();
      return _HorizontalAlbumSection(
        title: widget.l10n.timeMachine,
        subtitle: widget.l10n.timeMachineSubtitle,
        albums: _cachedAlbums!,
        horizontalPadding: widget.horizontalPadding,
        contentLeftPadding: widget.contentLeftPadding,
        onViewAll: widget.onViewAll,
        l10n: widget.l10n,
        isWide: widget.isWide,
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 6. 最近添加（专辑横向流）
// ---------------------------------------------------------------------------
class _RecentlyAddedAlbumsSection extends ConsumerStatefulWidget {
  const _RecentlyAddedAlbumsSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  ConsumerState<_RecentlyAddedAlbumsSection> createState() =>
      _RecentlyAddedAlbumsSectionState();
}

class _RecentlyAddedAlbumsSectionState
    extends ConsumerState<_RecentlyAddedAlbumsSection> {
  List<AlbumSummary>? _cachedAlbums;

  @override
  Widget build(BuildContext context) {
    ref.listen(recentlyAddedAlbumsProvider, (_, next) {
      if (_cachedAlbums == null && next.hasValue) {
        setState(() {
          _cachedAlbums = next.value!.toList(growable: false);
        });
      }
    });

    if (_cachedAlbums == null) {
      final initial = ref.read(recentlyAddedAlbumsProvider);
      if (initial.hasValue) {
        _cachedAlbums = initial.value!.toList(growable: false);
      }
    }

    if (_cachedAlbums != null) {
      if (_cachedAlbums!.isEmpty) return const SizedBox.shrink();
      return _HorizontalAlbumSection(
        title: widget.l10n.recentlyAdded,
        albums: _cachedAlbums!,
        horizontalPadding: widget.horizontalPadding,
        contentLeftPadding: widget.contentLeftPadding,
        onViewAll: widget.onViewAll,
        l10n: widget.l10n,
        isWide: widget.isWide,
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// 7. 已评分（专辑横向流）
// ---------------------------------------------------------------------------
class _TopRatedAlbumsSection extends ConsumerStatefulWidget {
  const _TopRatedAlbumsSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  ConsumerState<_TopRatedAlbumsSection> createState() =>
      _TopRatedAlbumsSectionState();
}

class _TopRatedAlbumsSectionState
    extends ConsumerState<_TopRatedAlbumsSection> {
  List<AlbumSummary>? _cachedAlbums;

  @override
  Widget build(BuildContext context) {
    ref.listen(topRatedAlbumsProvider, (_, next) {
      if (_cachedAlbums == null && next.hasValue) {
        setState(() {
          _cachedAlbums = next.value!.toList(growable: false);
        });
      }
    });

    if (_cachedAlbums == null) {
      final initial = ref.read(topRatedAlbumsProvider);
      if (initial.hasValue) {
        _cachedAlbums = initial.value!.toList(growable: false);
      }
    }

    if (_cachedAlbums != null) {
      if (_cachedAlbums!.isEmpty) return const SizedBox.shrink();
      return _HorizontalAlbumSection(
        title: widget.l10n.ratedSongs,
        subtitle: widget.l10n.ratedSongsSubtitle,
        albums: _cachedAlbums!,
        horizontalPadding: widget.horizontalPadding,
        contentLeftPadding: widget.contentLeftPadding,
        onViewAll: widget.onViewAll,
        l10n: widget.l10n,
        isWide: widget.isWide,
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// 8. 独立通栏：专辑
// ---------------------------------------------------------------------------
class _AlbumsRowSection extends ConsumerStatefulWidget {
  const _AlbumsRowSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  ConsumerState<_AlbumsRowSection> createState() => _AlbumsRowSectionState();
}

class _AlbumsRowSectionState extends ConsumerState<_AlbumsRowSection> {
  List<AlbumSummary>? _cachedAlbums;

  @override
  Widget build(BuildContext context) {
    ref.listen(albumLibraryProvider, (_, next) {
      if (_cachedAlbums == null && next.hasValue) {
        setState(() {
          _cachedAlbums = next.value!.toList(growable: false);
        });
      }
    });

    if (_cachedAlbums == null) {
      final initial = ref.read(albumLibraryProvider);
      if (initial.hasValue) {
        _cachedAlbums = initial.value!.toList(growable: false);
      }
    }

    if (_cachedAlbums != null) {
      if (_cachedAlbums!.isEmpty) return const SizedBox.shrink();
      return _HorizontalAlbumSection(
        title: widget.l10n.albums,
        albums: _cachedAlbums!,
        horizontalPadding: widget.horizontalPadding,
        contentLeftPadding: widget.contentLeftPadding,
        onViewAll: widget.onViewAll,
        l10n: widget.l10n,
        isWide: widget.isWide,
      );
    }

    return const SizedBox.shrink();
  }
}

class _AlbumCard extends StatefulWidget {
  const _AlbumCard({
    super.key,
    required this.album,
    required this.width,
    required this.isWide,
    required this.onTap,
    required this.onPlay,
  });

  final AlbumSummary album;
  final double width;
  final bool isWide;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = widget.width;
    final btnSize = widget.isWide ? 40.0 : 36.0;
    final iconSize = widget.isWide ? 24.0 : 22.0;
    final btnOffset = widget.isWide ? 10.0 : 8.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AlbumCover(album: widget.album, size: size),
                  Positioned(
                    right: btnOffset,
                    bottom: btnOffset,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _isHovered ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_isHovered,
                        child: _CoverPlayButton(
                          size: btnSize,
                          iconSize: iconSize,
                          onTap: widget.onPlay,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: widget.isWide ? 14.5 : 14.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.album.artist,
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

// ---------------------------------------------------------------------------
// 独立通栏：艺术家
// ---------------------------------------------------------------------------
class _ArtistsRowSection extends ConsumerStatefulWidget {
  const _ArtistsRowSection({
    required this.horizontalPadding,
    required this.onViewAll,
    required this.l10n,
    this.isWide = false,
    this.contentLeftPadding = 0.0,
  });

  final double horizontalPadding;
  final VoidCallback onViewAll;
  final AppLocalizations l10n;
  final bool isWide;
  final double contentLeftPadding;

  @override
  ConsumerState<_ArtistsRowSection> createState() => _ArtistsRowSectionState();
}

class _ArtistsRowSectionState extends ConsumerState<_ArtistsRowSection> {
  final Set<String> _prefetchedKeys = <String>{};
  StreamSubscription<String>? _imageUpdateSub;
  Timer? _debounceInvalidateTimer;
  List<ArtistSummary>? _cachedArtists;

  @override
  void initState() {
    super.initState();
    _imageUpdateSub =
        TheAudioDbArtistService.instance.onArtistImageUpdated.listen((_) {
      _debounceInvalidateTimer?.cancel();
      _debounceInvalidateTimer =
          Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          ref.invalidate(artistLibraryProvider);
        }
      });
    });
  }

  @override
  void dispose() {
    _debounceInvalidateTimer?.cancel();
    _imageUpdateSub?.cancel();
    super.dispose();
  }

  void _prefetchDisplayedArtists(List<ArtistSummary> preview) {
    for (final artist in preview) {
      if (_prefetchedKeys.add(artist.queryKey)) {
        if (artist.cachedImagePath == null ||
            artist.cachedImagePath!.isEmpty ||
            !File(artist.cachedImagePath!).existsSync()) {
          TheAudioDbArtistService.instance.fetchAndCacheArtistImage(artist);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(artistLibraryProvider, (_, next) {
      if (_cachedArtists == null && next.hasValue) {
        setState(() {
          _cachedArtists = next.value!.toList(growable: false);
        });
      }
    });

    if (_cachedArtists == null) {
      final initial = ref.read(artistLibraryProvider);
      if (initial.hasValue) {
        _cachedArtists = initial.value!.toList(growable: false);
      }
    }

    if (_cachedArtists != null) {
      if (_cachedArtists!.isEmpty) return const SizedBox.shrink();
      final preview = _cachedArtists!.take(12).toList();
      _prefetchDisplayedArtists(preview);

      final scale = widget.isWide
          ? kDashboardDesktopCoverScale
          : kDashboardMobileCoverScale;
      final avatarDiameter = (96.0 * scale).roundToDouble();
      final cardWidth = avatarDiameter;
      final listHeight = avatarDiameter + 52.0;
      final separatorWidth = widget.isWide ? 18.0 : 16.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: widget.contentLeftPadding + widget.horizontalPadding,
              right: widget.horizontalPadding,
            ),
            child: _SectionHeader(
              title: widget.l10n.artists,
              onViewAll: widget.onViewAll,
              l10n: widget.l10n,
            ),
          ),
          const SizedBox(height: 12),
          _CarouselScrollWrapper(
            height: listHeight,
            centerHeight: avatarDiameter,
            buttonPadding: widget.horizontalPadding > 20 ? 14.0 : 8.0,
            leftButtonOffset: widget.contentLeftPadding,
            builder: (context, controller) {
              return ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(
                  left: widget.contentLeftPadding + widget.horizontalPadding,
                  right: widget.horizontalPadding,
                ),
                itemCount: preview.length,
                separatorBuilder: (_, _) => SizedBox(width: separatorWidth),
                itemBuilder: (context, index) {
                  final artist = preview[index];
                  return _DashboardArtistItem(
                    artist: artist,
                    avatarDiameter: avatarDiameter,
                    cardWidth: cardWidth,
                    isWide: widget.isWide,
                    onViewAll: widget.onViewAll,
                  );
                },
              );
            },
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _DashboardArtistItem extends ConsumerStatefulWidget {
  const _DashboardArtistItem({
    required this.artist,
    required this.avatarDiameter,
    required this.cardWidth,
    required this.isWide,
    required this.onViewAll,
  });

  final ArtistSummary artist;
  final double avatarDiameter;
  final double cardWidth;
  final bool isWide;
  final VoidCallback onViewAll;

  @override
  ConsumerState<_DashboardArtistItem> createState() =>
      _DashboardArtistItemState();
}

class _DashboardArtistItemState extends ConsumerState<_DashboardArtistItem> {
  String? _cachedImagePath;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _cachedImagePath = widget.artist.cachedImagePath;
    _sub = TheAudioDbArtistService.instance.onArtistImageUpdated
        .listen((queryKey) {
      if (queryKey == widget.artist.queryKey && mounted) {
        _refreshImage();
      }
    });
    _checkAndFetch();
  }

  void _checkAndFetch() {
    if (_cachedImagePath != null &&
        _cachedImagePath!.isNotEmpty &&
        File(_cachedImagePath!).existsSync()) {
      return;
    }
    TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist)
        .then((path) {
      if (!mounted) return;
      if (path != null && path.isNotEmpty && path != _cachedImagePath) {
        setState(() {
          _cachedImagePath = path;
        });
      }
    });
  }

  Future<void> _refreshImage() async {
    final path = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist);
    if (!mounted) return;
    if (path != null && path.isNotEmpty && path != _cachedImagePath) {
      setState(() {
        _cachedImagePath = path;
      });
    }
  }

  @override
  void didUpdateWidget(covariant _DashboardArtistItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.artist.queryKey != oldWidget.artist.queryKey) {
      _cachedImagePath = widget.artist.cachedImagePath;
      _checkAndFetch();
    } else if (widget.artist.cachedImagePath != null &&
        widget.artist.cachedImagePath != _cachedImagePath) {
      _cachedImagePath = widget.artist.cachedImagePath;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artist = widget.artist;
    final displayPath = _cachedImagePath ?? artist.cachedImagePath;

    return InkWell(
      borderRadius: BorderRadius.circular(50),
      onTap: () {
        if (widget.isWide) {
          ref.read(selectedArtistKeyProvider.notifier).set(artist.queryKey);
          widget.onViewAll();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'artist_detail'),
              builder: (_) => ArtistDetailPage(artist: artist),
            ),
          );
        }
      },
      child: SizedBox(
        width: widget.cardWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtistAvatar(
              diameter: widget.avatarDiameter,
              imagePath: displayPath,
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
                fontSize: widget.isWide ? 14.5 : 14.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 独立通栏：流派（只展示有歌曲的流派）
// ---------------------------------------------------------------------------
class _GenresRowSection extends ConsumerStatefulWidget {
  const _GenresRowSection({
    required this.horizontalPadding,
    required this.l10n,
    required this.onViewAll,
    this.contentLeftPadding = 0.0,
    required this.isWide,
  });

  final double horizontalPadding;
  final AppLocalizations l10n;
  final VoidCallback onViewAll;
  final double contentLeftPadding;
  final bool isWide;

  @override
  ConsumerState<_GenresRowSection> createState() => _GenresRowSectionState();
}

class _GenresRowSectionState extends ConsumerState<_GenresRowSection> {
  List<GenreSummary>? _cachedGenres;

  @override
  Widget build(BuildContext context) {
    ref.listen(genreLibraryProvider, (_, next) {
      if (_cachedGenres == null && next.hasValue) {
        setState(() {
          _cachedGenres = next.value!.toList(growable: false);
        });
      }
    });

    if (_cachedGenres == null) {
      final initial = ref.read(genreLibraryProvider);
      if (initial.hasValue) {
        _cachedGenres = initial.value!.toList(growable: false);
      }
    }

    if (_cachedGenres != null) {
      if (_cachedGenres!.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: widget.contentLeftPadding + widget.horizontalPadding,
              right: widget.horizontalPadding,
            ),
            child: _SectionHeader(
              title: widget.l10n.genres,
              onViewAll: widget.onViewAll,
              l10n: widget.l10n,
            ),
          ),
          const SizedBox(height: 12),
          _CarouselScrollWrapper(
            height: 80,
            buttonPadding: widget.horizontalPadding > 20 ? 14.0 : 8.0,
            leftButtonOffset: widget.contentLeftPadding,
            builder: (context, controller) {
              return ListView.separated(
                controller: controller,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.only(
                  left: widget.contentLeftPadding + widget.horizontalPadding,
                  right: widget.horizontalPadding,
                ),
                itemCount: _cachedGenres!.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final genre = _cachedGenres![index];
                  return _GenreCard(
                    genre: genre,
                    onTap: () {
                      if (widget.isWide) {
                        ref
                            .read(selectedGenreKeyProvider.notifier)
                            .set(genre.queryKey);
                        widget.onViewAll();
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            settings: const RouteSettings(
                              name: 'genre_detail',
                            ),
                            builder: (_) => GenreDetailPage(genre: genre),
                          ),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ],
      );
    }

    return const SizedBox.shrink();
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
    final l10n = AppLocalizations.of(context)!;
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
                      l10n.trackCountShort(widget.genre.songCount),
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


class _SectionHeader extends StatefulWidget {
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
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canNavigate = widget.onViewAll != null;

    final headerRow = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (canNavigate) ...[
          const SizedBox(width: 4),
          AnimatedSlide(
            offset: _isHovered ? const Offset(0.12, 0) : Offset.zero,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _isHovered
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        headerRow,
        if (widget.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    if (canNavigate) {
      content = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onViewAll,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.transparent,
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4, right: 6),
            child: content,
          ),
        ),
      );
    }

    return Semantics(
      button: canNavigate,
      label: canNavigate
          ? '${widget.title}, ${widget.l10n.viewAll}'
          : widget.title,
      child: content,
    );
  }
}


