import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/draggable_song_item.dart';
import '../widgets/auto_hide_header.dart';
import '../widgets/app_top_nav_bar.dart';
import '../utils/layout_constants.dart';

class YearDetailPage extends ConsumerStatefulWidget {
  const YearDetailPage({
    super.key,
    required this.year,
    this.onGoBack,
  });

  final YearSummary year;
  final VoidCallback? onGoBack;

  @override
  ConsumerState<YearDetailPage> createState() => _YearDetailPageState();
}

class _YearDetailPageState extends ConsumerState<YearDetailPage> {
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

  static double getBarHeight(BuildContext context) =>
      AppTopNavBar.getBarHeight(context);

  @override
  Widget build(BuildContext context) {
    final double barHeight = getBarHeight(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final double leftPadding =
        isLandscape ? sidebarRailWidthFor(MediaQuery.of(context).size.width) : 0.0;
    final l10n = AppLocalizations.of(context)!;
    final String title = widget.year.labelWith(l10n.unknownYear);

    return AutoHideHeaderScope(
      builder: (context, isHeaderVisible) {
        final Widget content = Scaffold(
          body: Padding(
            padding: EdgeInsets.only(left: leftPadding),
            child: Stack(
              children: [
                YearDetailContent(
                  year: widget.year,
                  scrollController: _scrollController,
                  topPadding: barHeight + 8,
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AutoHideHeader(
                    isVisible: isHeaderVisible,
                    child: AppTopNavBar(
                      title: title,
                      titleKey: const ValueKey('year_title'),
                      onBack: widget.onGoBack ?? () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

        return MiniPlayerWrapper(child: content);
      },
    );
  }
}

class YearDetailContent extends ConsumerStatefulWidget {
  const YearDetailContent({
    super.key,
    required this.year,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final YearSummary year;
  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  ConsumerState<YearDetailContent> createState() => _YearDetailContentState();
}

class _YearDetailContentState extends ConsumerState<YearDetailContent>
    with SongSelectionMixin<YearDetailContent> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  List<MusicFile>? _lastYearSongs;
  String? _lastUnknownAlbumLabel;
  List<_AlbumSection>? _cachedAlbumSections;
  List<MusicFile>? _cachedDisplaySongs;

  void _ensureAlbumSectionsCached(String unknownAlbumLabel) {
    if (!identical(_lastYearSongs, widget.year.songs) ||
        _lastUnknownAlbumLabel != unknownAlbumLabel ||
        _cachedAlbumSections == null) {
      _lastYearSongs = widget.year.songs;
      _lastUnknownAlbumLabel = unknownAlbumLabel;
      _cachedAlbumSections = _buildAlbumSections(widget.year.songs, unknownAlbumLabel);
      _cachedDisplaySongs = _cachedAlbumSections!
          .expand((section) => section.songs)
          .toList(growable: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final unknownAlbumLabel = l10n.unknownAlbum;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    _ensureAlbumSectionsCached(unknownAlbumLabel);
    final albumSections = _cachedAlbumSections!;
    final displaySongs = _cachedDisplaySongs!;

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(displaySongs)
        : const <MusicFile>[];

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    final content = Stack(
      children: [
        CustomScrollView(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isPortrait ? 20 : 28,
                  widget.topPadding > 0 ? widget.topPadding + 12 : 24,
                  isPortrait ? 20 : 28,
                  20,
                ),
                child: _YearInfo(
                  year: widget.year,
                  onPlayAll: () => audio.playPlaylist(
                    displaySongs,
                    source: PlaybackSource(
                      type: PlaybackSourceType.year,
                      id: widget.year.queryKey,
                      name: widget.year.labelWith(l10n.unknownYear),
                    ),
                  ),
                  onShufflePlay: () => audio.playPlaylist(
                    List.of(displaySongs)..shuffle(),
                    source: PlaybackSource(
                      type: PlaybackSourceType.year,
                      id: widget.year.queryKey,
                      name: widget.year.labelWith(l10n.unknownYear),
                    ),
                  ),
                ),
              ),
            ),
            if (albumSections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(l10n.emptyList, style: theme.textTheme.titleMedium),
                ),
              )
            else ...[
              for (int i = 0; i < albumSections.length; i++) ...[
                if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 36)),
                _AlbumSectionSliver(
                  section: albumSections[i],
                  currentMusic: currentMusic,
                  theme: theme,
                  onPlayAlbum: () => audio.playPlaylist(
                    albumSections[i].songs,
                    source: PlaybackSource(
                      type: PlaybackSourceType.album,
                      id: '${albumSections[i].title.toLowerCase()}::${(albumSections[i].songs.firstOrNull?.albumArtist ?? albumSections[i].songs.firstOrNull?.artist ?? "").toLowerCase()}',
                      name: albumSections[i].title,
                    ),
                  ),
                  onShufflePlayAlbum: () => audio.playPlaylist(
                    List.of(albumSections[i].songs)..shuffle(),
                    source: PlaybackSource(
                      type: PlaybackSourceType.album,
                      id: '${albumSections[i].title.toLowerCase()}::${(albumSections[i].songs.firstOrNull?.albumArtist ?? albumSections[i].songs.firstOrNull?.artist ?? "").toLowerCase()}',
                      name: albumSections[i].title,
                    ),
                  ),
                  onSongTap: (songIndex) {
                    final song = albumSections[i].songs[songIndex];
                    final globalIndex = albumSections[i].startIndex + songIndex;

                    handleSongTap(
                      index: globalIndex,
                      songPath: song.path,
                      allSongs: displaySongs,
                      onNormalTap: () {
                        audio.playPlaylist(
                          displaySongs,
                          initialIndex: globalIndex,
                          source: PlaybackSource(
                            type: PlaybackSourceType.year,
                            id: widget.year.queryKey,
                            name: widget.year.labelWith(l10n.unknownYear),
                          ),
                        );
                      },
                    );
                  },
                  onSongSecondaryTapDown: (details, song) {
                    if (!isSelectionMode) {
                      showSongContextMenu(
                        context,
                        details.globalPosition,
                        song: song,
                        songs: [song],
                        mode: SongContextMenuMode.full,
                        onPlayNext: () =>
                            ref.read(audioServiceProvider).enqueueNext([song]),
                        onAddToQueue: () =>
                            ref.read(audioServiceProvider).appendToQueue([song]),
                        onAddToPlaylist: () async {
                          await showAddSongsToPlaylistDialog(
                            context,
                            ref.read(playlistServiceProvider),
                            [song],
                          );
                        },
                      );
                    }
                  },
                  onSongLongPress: (song) {
                    final songIndex = albumSections[i].songs.indexOf(song);
                    if (songIndex != -1) {
                      lastAnchorIndex =
                          albumSections[i].startIndex + songIndex;
                    }
                    if (!isSelectionMode) {
                      enterSongSelectionMode(song.path);
                    }
                  },
                  isSongSelected: (songPath) => isSongSelected(songPath),
                  isSelectionMode: isSelectionMode,
                  selectedSongPaths: selectedSongPaths,
                ),
              ],
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: (isSelectionMode || widget.hasBottomPanel) ? 140 : 40,
              ),
            ),
          ],
        ),
        if (widget.showSelectionPanel)
          AnimatedSelectionPanel(
            isVisible: isSelectionMode,
            child: LibrarySelectionPanel(
              selectedSongs: selectedSongs,
              allSongs: displaySongs,
              onToggleSelectAll: () => toggleSelectAllSongs(displaySongs),
              onCancel: cancelSongSelection,
            ),
          ),
      ],
    );

    return content;
  }
}

class _YearInfo extends StatelessWidget {
  const _YearInfo({
    required this.year,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final YearSummary year;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final String label = year.labelWith(l10n.unknownYear);

    final hasCover = (year.representativeArtworkPath != null &&
            year.representativeArtworkPath!.isNotEmpty) ||
        (year.representativeThumbnailPath != null &&
            year.representativeThumbnailPath!.isNotEmpty);

    final coverWidget = Container(
      width: isPortrait ? 96 : 116,
      height: isPortrait ? 96 : 116,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: hasCover && year.songs.isNotEmpty
            ? SongThumbnail(
                path: year.songs.first.path,
                artworkPath: year.representativeArtworkPath,
                thumbnailPath: year.representativeThumbnailPath,
                size: isPortrait ? 96 : 116,
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                      theme.colorScheme.secondary.withValues(alpha: 0.4),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: isPortrait ? 44 : 52,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
      ),
    );

    final String durationText = _formatTotalDuration(year.totalDurationMillis);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        coverWidget,
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${l10n.songCount(year.songCount)} · ${l10n.albumCount(year.albumCount)} · $durationText',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = isPortrait && constraints.maxWidth < 260;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        onPressed: onPlayAll,
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(l10n.playAll),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isNarrow)
                        Tooltip(
                          message: l10n.shuffle,
                          child: OutlinedButton(
                            onPressed: onShufflePlay,
                            style: OutlinedButton.styleFrom(
                              fixedSize: const Size(32, 32),
                              minimumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Icon(Icons.shuffle_rounded, size: 18),
                          ),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: onShufflePlay,
                          icon: const Icon(Icons.shuffle_rounded, size: 18),
                          label: Text(l10n.shuffle),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlbumSectionSliver extends StatelessWidget {
  const _AlbumSectionSliver({
    required this.section,
    required this.currentMusic,
    required this.theme,
    required this.onPlayAlbum,
    required this.onShufflePlayAlbum,
    required this.onSongTap,
    required this.onSongSecondaryTapDown,
    required this.onSongLongPress,
    required this.isSongSelected,
    required this.isSelectionMode,
    required this.selectedSongPaths,
  });

  final _AlbumSection section;
  final MusicFile? currentMusic;
  final ThemeData theme;
  final VoidCallback onPlayAlbum;
  final VoidCallback onShufflePlayAlbum;
  final void Function(int songIndex) onSongTap;
  final void Function(TapDownDetails details, MusicFile song)
      onSongSecondaryTapDown;
  final void Function(MusicFile song) onSongLongPress;
  final bool Function(String songPath) isSongSelected;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final horizontalPadding = isPortrait ? 20.0 : 28.0;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SongThumbnail(
                      path: section.representativeSong.path,
                      artworkPath: section.representativeSong.artworkPath,
                      thumbnailPath: section.representativeSong.thumbnailPath,
                      size: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.songCount(section.songs.length)} · ${_formatTotalDuration(section.totalDurationMillis)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_circle_filled_rounded, size: 28),
                    color: theme.colorScheme.primary,
                    tooltip: l10n.playAll,
                    onPressed: onPlayAlbum,
                  ),
                  IconButton(
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    tooltip: l10n.shuffle,
                    onPressed: onShufflePlayAlbum,
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, songIndex) {
                final song = section.songs[songIndex];
                final isCurrent = currentMusic != null &&
                    currentMusic!.path == song.path;
                final isSelected = isSongSelected(song.path);

                final tileWidget = _SongTile(
                  song: song,
                  trackIndex: songIndex + 1,
                  isCurrent: isCurrent,
                  isSelected: isSelected,
                  isSelectionMode: isSelectionMode,
                  showDivider: songIndex > 0,
                  onTap: () => onSongTap(songIndex),
                  onLongPress: () => onSongLongPress(song),
                  onSecondaryTapDown: (details) =>
                      onSongSecondaryTapDown(details, song),
                );

                return DraggableSongItem(
                  song: song,
                  enabled: !song.isMissing,
                  isSelected: isSelected,
                  isSelectionMode: isSelectionMode,
                  selectedPaths: selectedSongPaths,
                  child: tileWidget,
                );
              },
              childCount: section.songs.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.trackIndex,
    required this.isCurrent,
    required this.isSelected,
    required this.isSelectionMode,
    required this.showDivider,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTapDown,
  });

  final MusicFile song;
  final int trackIndex;
  final bool isCurrent;
  final bool isSelected;
  final bool isSelectionMode;
  final bool showDivider;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(TapDownDetails details) onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final durationLabel = _formatDuration(song.durationMillis);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDivider)
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
            color: isSelected
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                            ? Icon(
                                Icons.volume_up_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
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
                            isMixed: false,
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
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlbumSection {
  const _AlbumSection({
    required this.title,
    required this.songs,
    required this.representativeSong,
    required this.totalDurationMillis,
    required this.startIndex,
  });

  final String title;
  final List<MusicFile> songs;
  final MusicFile representativeSong;
  final int totalDurationMillis;
  final int startIndex;
}

List<_AlbumSection> _buildAlbumSections(
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

  final sections = <_AlbumSection>[];
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
    final title = titles[key]!;

    sections.add(
      _AlbumSection(
        title: title,
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

bool _hasArtwork(MusicFile song) =>
    (song.artworkBytes?.isNotEmpty ?? false) ||
    (song.artworkPath != null && song.artworkPath!.isNotEmpty) ||
    (song.thumbnailPath != null && song.thumbnailPath!.isNotEmpty);

String _formatTotalDuration(int totalMillis) {
  final duration = Duration(milliseconds: totalMillis);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '$hours 小时 $minutes 分钟';
  }
  return '$minutes 分钟';
}

String? _formatDuration(int? durationMs) {
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
