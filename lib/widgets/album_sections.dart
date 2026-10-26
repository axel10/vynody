import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'draggable_song_item.dart';
import 'playing_equalizer_icon.dart';
import 'remote_media_badge.dart';
import 'song_thumbnail.dart';

/// 按专辑分组的歌曲集合。
///
/// 艺术家、流派、年份三类详情页都以「专辑分组 + 曲目列表」的形式展示歌曲，
/// 分组结构与渲染逻辑完全一致，因此统一收敛到本文件，避免三处各写一份。
class AlbumSection {
  const AlbumSection({
    required this.title,
    required this.songs,
    required this.representativeSong,
    required this.totalDurationMillis,
    required this.startIndex,
    this.artist,
    this.year,
  });

  /// 专辑标题（缺失专辑统一显示为本地化的「未知专辑」）。
  final String title;

  /// 本组歌曲，已按碟号 / 音轨号排序。
  final List<MusicFile> songs;

  /// 用于取封面的代表曲目，优先选择带封面的歌曲。
  final MusicFile representativeSong;

  final int totalDurationMillis;

  /// 本组第一首歌在扁平化后的完整曲目列表中的下标。
  final int startIndex;

  /// 专辑艺术家（可选，留空时从歌曲中自动解析）。
  final String? artist;

  /// 专辑发行年份（可选，留空时从歌曲中自动解析）。
  final int? year;
}

/// 横屏专辑分组的封面尺寸档位。
///
/// 本地流派 / 年份 / 艺术家详情与远程媒体库的流派页共用同一套档位，
/// 避免两边各自写一份阈值导致封面大小对不上。
class AlbumSectionCoverMetrics {
  const AlbumSectionCoverMetrics({
    required this.coverSize,
    required this.gap,
    required this.radius,
  });

  /// 封面边长。
  final double coverSize;

  /// 封面与右侧曲目列表的间距。
  final double gap;

  /// 封面圆角。
  final double radius;
}

/// 按分组可用宽度（已扣除左右内边距）取封面档位。
AlbumSectionCoverMetrics albumSectionCoverMetrics(double availableWidth) {
  if (availableWidth >= 1000) {
    return const AlbumSectionCoverMetrics(
      coverSize: 350.0,
      gap: 28.0,
      radius: 12.0,
    );
  }
  if (availableWidth >= 800) {
    return const AlbumSectionCoverMetrics(
      coverSize: 190.0,
      gap: 24.0,
      radius: 10.0,
    );
  }
  return const AlbumSectionCoverMetrics(
    coverSize: 160.0,
    gap: 20.0,
    radius: 8.0,
  );
}

/// 专辑分组的播放来源（与专辑详情页使用同一套标识方式）。
PlaybackSource albumPlaybackSource(AlbumSection section) {
  final firstSong = section.songs.firstOrNull;
  final artistKey =
      (firstSong?.albumArtist ?? firstSong?.artist ?? '').toLowerCase();
  return PlaybackSource(
    type: PlaybackSourceType.album,
    id: '${section.title.toLowerCase()}::$artistKey',
    name: section.title,
  );
}

/// [buildAlbumSections] 的结果缓存：歌曲列表与「未知专辑」文案未变化时复用上次结果。
class AlbumSectionsCache {
  List<MusicFile>? _songs;
  String? _unknownAlbumLabel;
  List<AlbumSection>? _sections;
  List<MusicFile>? _allSongs;

  void update(List<MusicFile> songs, String unknownAlbumLabel) {
    if (identical(_songs, songs) &&
        _unknownAlbumLabel == unknownAlbumLabel &&
        _sections != null) {
      return;
    }
    _songs = songs;
    _unknownAlbumLabel = unknownAlbumLabel;
    _sections = buildAlbumSections(songs, unknownAlbumLabel);
    _allSongs = _sections!
        .expand((section) => section.songs)
        .toList(growable: false);
  }

  List<AlbumSection> get sections => _sections!;

  /// 按分组顺序扁平化后的完整曲目列表，用于顺序播放与多选。
  List<MusicFile> get allSongs => _allSongs!;
}

List<AlbumSection> buildAlbumSections(
  List<MusicFile> songs,
  String unknownAlbumLabel,
) {
  final grouped = <String, List<MusicFile>>{};
  final titles = <String, String>{};
  final unknownKey = unknownAlbumLabel.toLowerCase();

  for (final song in songs) {
    final rawAlbum = song.album?.trim();
    final isUnknown = rawAlbum == null || rawAlbum.isEmpty;
    final normalizedTitle = isUnknown ? unknownAlbumLabel : rawAlbum;
    final key = normalizedTitle.toLowerCase();

    grouped.putIfAbsent(key, () => <MusicFile>[]).add(song);
    titles[key] = normalizedTitle;
  }

  final orderedKeys = grouped.keys.toList()
    ..sort((a, b) {
      final leftUnknown = a == unknownKey;
      final rightUnknown = b == unknownKey;
      if (leftUnknown != rightUnknown) {
        return leftUnknown ? 1 : -1;
      }
      return titles[a]!.toLowerCase().compareTo(titles[b]!.toLowerCase());
    });

  final sections = <AlbumSection>[];
  var startIndex = 0;

  for (final key in orderedKeys) {
    final albumSongs = List<MusicFile>.from(grouped[key]!)
      ..sort(_compareAlbumSongs);
    final representativeSong = albumSongs.firstWhere(
      (song) => _hasArtwork(song),
      orElse: () => albumSongs.first,
    );
    final totalDurationMillis = albumSongs.fold<int>(
      0,
      (sum, song) => sum + (song.durationMillis ?? 0),
    );

    final resolvedArtist = resolveAlbumArtist(albumSongs);
    final resolvedYear = resolveAlbumYear(albumSongs);

    sections.add(
      AlbumSection(
        title: titles[key]!,
        songs: albumSongs,
        representativeSong: representativeSong,
        totalDurationMillis: totalDurationMillis,
        startIndex: startIndex,
        artist: resolvedArtist,
        year: resolvedYear,
      ),
    );
    startIndex += albumSongs.length;
  }

  return sections;
}

/// 从专辑歌曲集合中解析出主艺术家（优先取 albumArtist，其次 artist）。
String? resolveAlbumArtist(List<MusicFile> songs) {
  for (final song in songs) {
    final albumArtist = song.albumArtist?.trim();
    if (albumArtist != null && albumArtist.isNotEmpty) {
      return albumArtist;
    }
  }
  for (final song in songs) {
    final artist = song.artist?.trim();
    if (artist != null && artist.isNotEmpty) {
      return artist;
    }
  }
  return null;
}

/// 从专辑歌曲集合中解析出发行年份（取最小正整数年份）。
int? resolveAlbumYear(List<MusicFile> songs) {
  int? minYear;
  for (final song in songs) {
    final y = song.year;
    if (y != null && y > 0) {
      if (minYear == null || y < minYear) {
        minYear = y;
      }
    }
  }
  return minYear;
}

bool _hasArtwork(MusicFile song) =>
    (song.artworkBytes?.isNotEmpty ?? false) ||
    (song.artworkPath != null && song.artworkPath!.isNotEmpty) ||
    (song.thumbnailPath != null && song.thumbnailPath!.isNotEmpty);

int _compareAlbumSongs(MusicFile a, MusicFile b) {
  final leftTrack = a.trackNumber;
  final rightTrack = b.trackNumber;
  if (leftTrack != null && rightTrack != null && leftTrack != rightTrack) {
    return leftTrack.compareTo(rightTrack);
  }
  if (leftTrack != null && rightTrack == null) return -1;
  if (leftTrack == null && rightTrack != null) return 1;

  final titleCompare = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  if (titleCompare != 0) return titleCompare;
  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
}

/// 通用的时钟式时长文案（`m:ss` / `h:mm:ss`），与语言无关。
String? formatDurationClock(int? durationMs) {
  if (durationMs == null) return null;
  final duration = Duration(milliseconds: durationMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

/// 单个专辑分组。
///
/// 宽屏（>= 600）时左侧展示专辑大图、右侧展示分组标题与曲目列表；
/// 窄屏时专辑封面收为分组标题左侧的小图，曲目列表在下方展开。
class AlbumSectionSliver extends ConsumerWidget {
  const AlbumSectionSliver({
    super.key,
    required this.section,
    required this.currentMusicPath,
    required this.onSongTap,
    required this.onSongLongPress,
    this.isSelectionMode = false,
    this.selectedSongPaths = const <String>{},
    this.horizontalPadding,
    this.onOpenAlbum,
    this.playbackSourceBuilder,
    this.showRemoteBadge = true,
  });

  final AlbumSection section;
  final String? currentMusicPath;

  /// 参数为该曲目在本分组内的下标；调用方据此换算全局下标。
  final void Function(AlbumSection section, int songIndex) onSongTap;

  /// 长按进入多选，调用方负责记录锚点下标。
  final void Function(AlbumSection section, MusicFile song) onSongLongPress;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;

  /// 左右内边距，留空时横屏 28、竖屏 20。
  final double? horizontalPadding;

  /// 点击封面 / 专辑标题时的回调（通常是跳转专辑详情），留空则不可点。
  final VoidCallback? onOpenAlbum;

  /// 自定义播放来源，留空时用 [albumPlaybackSource]（按专辑名 + 专辑艺术家）。
  ///
  /// 远程媒体库的专辑有服务端下发的稳定 id，需要用自己的标识，
  /// 否则同一张专辑在「远程直连」与「混入本地库」两条路径下会被当成两个来源。
  final PlaybackSource Function(AlbumSection section)? playbackSourceBuilder;

  /// 封面右上角是否显示远程来源云朵角标。
  ///
  /// 本地列表里混入远程歌曲时，角标用来区分「这张专辑有歌在服务器上」，
  /// 是有用信息；而远程媒体库的流派页整页都是远程内容，角标只是噪声。
  final bool showRemoteBadge;

  void _playAlbum(BuildContext context, WidgetRef ref, {required bool shuffle}) {
    final audio = ref.read(audioServiceProvider);
    final songs = shuffle
        ? (List<MusicFile>.of(section.songs)..shuffle())
        : section.songs;
    final source =
        playbackSourceBuilder?.call(section) ?? albumPlaybackSource(section);
    audio.playPlaylist(songs, source: source);
  }

  void _showSongMenu(
    BuildContext context,
    WidgetRef ref,
    TapDownDetails details,
    MusicFile song,
  ) {
    if (isSelectionMode) return;
    showSongContextMenu(
      context,
      details.globalPosition,
      song: song,
      songs: [song],
      mode: SongContextMenuMode.full,
      onMultiSelect: () => onSongLongPress(section, song),
      onPlayNext: () => ref.read(audioServiceProvider).enqueueNext([song]),
      onAddToQueue: () => ref.read(audioServiceProvider).appendToQueue([song]),
      onAddToPlaylist: () async {
        await showAddSongsToPlaylistDialog(
          context,
          ref.read(playlistServiceProvider),
          [song],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final padding =
        horizontalPadding ?? (isPortrait ? 20.0 : 28.0);

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: padding),
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            return isWide
                ? _buildWideLayout(
                    context,
                    ref,
                    constraints.maxWidth,
                  )
                : _buildNarrowLayout(context, ref);
          },
        ),
      ),
    );
  }

  /// 给可点击区域套上鼠标指针；[onOpenAlbum] 为空时原样返回。
  Widget _maybeTappable(Widget child) {
    final onTap = onOpenAlbum;
    if (onTap == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }

  Widget _buildCover({required double size, double borderRadius = 10}) {
    final cover = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: RemoteMediaBadge.wrapCover(
          child: SongThumbnail.fromSong(
            section.representativeSong,
            size: size,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          songs: section.songs,
          title: section.title,
          showRemoteBadge: showRemoteBadge,
        ),
      ),
    );

    return _maybeTappable(cover);
  }

  Widget _buildHeaderRow(
    BuildContext context,
    WidgetRef ref,
    String subtitle,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _maybeTappable(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.playAll,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          onPressed: () => _playAlbum(context, ref, shuffle: false),
        ),
        IconButton(
          tooltip: l10n.shufflePlay,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.shuffle_rounded, size: 18),
          onPressed: () => _playAlbum(context, ref, shuffle: true),
        ),
      ],
    );
  }

  Widget _buildSongList(
    BuildContext context,
    WidgetRef ref,
    bool isMixedSection,
  ) {
    final currentPath = currentMusicPath;
    return Column(
      children: [
        for (int i = 0; i < section.songs.length; i++)
          AlbumSongTile(
            key: ValueKey(section.songs[i].path),
            song: section.songs[i],
            trackIndex: i + 1,
            isCurrent: currentPath != null && currentPath == section.songs[i].path,
            showRemoteIndicator:
                isMixedSection && RemoteMediaHelper.isRemote(section.songs[i]),
            onTap: () => onSongTap(section, i),
            onSecondaryTapDown: (details) =>
                _showSongMenu(context, ref, details, section.songs[i]),
            onLongPress: () => onSongLongPress(section, section.songs[i]),
            isSelectionMode: isSelectionMode,
            isSelected: selectedSongPaths.contains(section.songs[i].path),
            selectedPaths: selectedSongPaths,
            showTopDivider: i > 0,
          ),
      ],
    );
  }

  String _subtitle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    var artist = section.artist?.trim();
    if (artist == null || artist.isEmpty) {
      artist = resolveAlbumArtist(section.songs);
    }
    final year = section.year ?? resolveAlbumYear(section.songs);

    final hasYear = year != null && year > 0;
    if (artist == null || artist.isEmpty) {
      artist = hasYear ? null : l10n.unknownArtist;
    }

    if (artist != null && hasYear) {
      return '$artist · $year';
    } else if (artist != null) {
      return artist;
    } else if (hasYear) {
      return '$year';
    }
    return '';
  }

  Widget _buildWideLayout(
    BuildContext context,
    WidgetRef ref,
    double availableWidth,
  ) {
    final metrics = albumSectionCoverMetrics(availableWidth);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCover(size: metrics.coverSize, borderRadius: metrics.radius),
        SizedBox(width: metrics.gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(context, ref, _subtitle(context)),
              const SizedBox(height: 14),
              _buildSongList(
                context,
                ref,
                RemoteMediaHelper.isMixed(section.songs),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildCover(size: 84, borderRadius: 8),
            const SizedBox(width: 14),
            Expanded(
              child: _buildHeaderRow(context, ref, _subtitle(context)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSongList(context, ref, RemoteMediaHelper.isMixed(section.songs)),
      ],
    );
  }
}

/// 专辑分组内单首曲目。
class AlbumSongTile extends StatelessWidget {
  const AlbumSongTile({
    super.key,
    required this.song,
    required this.trackIndex,
    required this.isCurrent,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onLongPress,
    this.showRemoteIndicator = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedPaths,
    this.showTopDivider = false,
  });

  final MusicFile song;
  final int trackIndex;
  final bool isCurrent;
  final bool showRemoteIndicator;
  final VoidCallback onTap;
  final void Function(TapDownDetails details) onSecondaryTapDown;
  final VoidCallback onLongPress;
  final bool isSelectionMode;
  final bool isSelected;
  final Iterable<String>? selectedPaths;
  final bool showTopDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationLabel = formatDurationClock(song.durationMillis);
    final isTileSelected = isSelectionMode ? isSelected : isCurrent;
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = theme.colorScheme.onSurface.withValues(
      alpha: isDark ? 0.18 : 0.12,
    );

    final rawArtist = song.artist?.trim();
    final effectiveArtist = (rawArtist != null && rawArtist.isNotEmpty)
        ? rawArtist
        : (song.albumArtist?.trim().isNotEmpty == true
            ? song.albumArtist!.trim()
            : null);
    final hasArtist = effectiveArtist != null && effectiveArtist.isNotEmpty;

    final tileWidget = RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTopDivider && !isTileSelected)
            Divider(
              height: 1,
              thickness: 1.0,
              indent: 8,
              endIndent: 8,
              color: dividerColor,
            ),
          SizedBox(
            height: hasArtist ? 48.0 : 38.0,
            child: Material(
              color: isTileSelected
                  ? theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.55)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                enableFeedback: false,
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(6),
                onTap: onTap,
                onLongPress: onLongPress,
                onSecondaryTapDown: onSecondaryTapDown,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      if (isSelectionMode) ...[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: isSelected,
                            onChanged: (_) => onTap(),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        SizedBox(
                          width: 24,
                          child: isCurrent
                              ? Center(
                                  child: PlayingEqualizerIcon(
                                    color: theme.colorScheme.primary,
                                    size: 16,
                                  ),
                                )
                              : Text(
                                  '${song.trackNumber ?? trackIndex}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    song.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: isCurrent
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                RemoteMediaBadge.songTrailing(
                                  song: song,
                                  isMixed: showRemoteIndicator,
                                ),
                              ],
                            ),
                            if (hasArtist) ...[
                              const SizedBox(height: 2),
                              Text(
                                effectiveArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                          .withValues(alpha: 0.8)
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (durationLabel != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          durationLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: onSecondaryTapDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return DraggableSongItem(
      song: song,
      enabled: !song.isMissing,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      selectedPaths: selectedPaths,
      child: tileWidget,
    );
  }
}
