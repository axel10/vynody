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

    sections.add(
      AlbumSection(
        title: titles[key]!,
        songs: albumSongs,
        representativeSong: representativeSong,
        totalDurationMillis: totalDurationMillis,
        startIndex: startIndex,
      ),
    );
    startIndex += albumSongs.length;
  }

  return sections;
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

  void _playAlbum(BuildContext context, WidgetRef ref, {required bool shuffle}) {
    final audio = ref.read(audioServiceProvider);
    final songs = shuffle
        ? (List<MusicFile>.of(section.songs)..shuffle())
        : section.songs;
    audio.playPlaylist(songs, source: albumPlaybackSource(section));
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

  Widget _buildCover({required double size, double borderRadius = 10}) {
    return Container(
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
        ),
      ),
    );
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
          child: Column(
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
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
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
    final durationLabel =
        formatDurationClock(section.totalDurationMillis) ?? l10n.durationZero;
    return '${l10n.songCount(section.songs.length)} · $durationLabel';
  }

  Widget _buildWideLayout(
    BuildContext context,
    WidgetRef ref,
    double availableWidth,
  ) {
    final double coverSize;
    final double gap;
    final double coverRadius;

    if (availableWidth >= 1000) {
      coverSize = 350.0;
      gap = 28.0;
      coverRadius = 12.0;
    } else if (availableWidth >= 800) {
      coverSize = 190.0;
      gap = 24.0;
      coverRadius = 10.0;
    } else {
      coverSize = 160.0;
      gap = 20.0;
      coverRadius = 8.0;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCover(size: coverSize, borderRadius: coverRadius),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(context, ref, _subtitle(context)),
              const SizedBox(height: 8),
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
        const SizedBox(height: 10),
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

    final tileWidget = RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTopDivider && !isTileSelected)
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 32,
              endIndent: 8,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
          SizedBox(
            height: 38.0,
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
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                        child: Row(
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
