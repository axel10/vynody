import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/album_cover.dart';
import '../widgets/album_detail_widgets.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/draggable_song_item.dart';
import '../widgets/song_thumbnail.dart';
import 'package:vynody/utils/layout_constants.dart';

class AlbumDetailPage extends ConsumerStatefulWidget {
  const AlbumDetailPage({super.key, required this.album});

  final AlbumSummary album;

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage>
    with SongSelectionMixin<AlbumDetailPage> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  late final ScrollController _scrollController;
  final ValueNotifier<bool> _isCoverVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final isVisible = offset < 220.0;
    final progress = (offset / 140.0).clamp(0.0, 1.0);
    _scrollProgress.value = progress;
    if (isVisible != _isCoverVisible.value) {
      _isCoverVisible.value = isVisible;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isCoverVisible.dispose();
    _scrollProgress.dispose();
    super.dispose();
  }

  static double getBarHeight(BuildContext context) =>
      AlbumDetailNavBar.getBarHeight(context);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(widget.album.songs)
        : const <MusicFile>[];
    final isLargeAlbum = widget.album.songs.length >= 100;
    final isMixedAlbum = RemoteMediaHelper.isMixed(widget.album.songs);
    final unknownArtist = l10n.unknownArtist;
    final double barHeight = getBarHeight(context);
    final durationText =
        _formatDuration(widget.album.totalDurationMillis) ?? l10n.durationZero;

    final metadataWidget = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          '${l10n.songCount(widget.album.trackCount)} · $durationText',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: (isPortrait && isDark)
                ? Colors.white.withValues(alpha: 0.85)
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: (isPortrait && isDark) ? 13 : 14,
            shadows: (isPortrait && isDark)
                ? const [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black87,
                    ),
                  ]
                : null,
          ),
        ),
        if (RemoteMediaHelper.isAllRemote(widget.album.songs))
          RemoteMediaBadge.chip(
            songs: widget.album.songs,
            title: widget.album.title,
          ),
      ],
    );

    final actionButtons = [
      FilledButton.icon(
        onPressed: () => audio.playPlaylist(
          widget.album.songs,
          source: PlaybackSource(
            type: PlaybackSourceType.album,
            id: widget.album.id,
            name: widget.album.title,
          ),
        ),
        icon: const Icon(Icons.play_arrow),
        label: Text(l10n.playAll),
        style: !isPortrait
            ? FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              )
            : null,
      ),
      isPortrait
          ? OutlinedButton.icon(
              onPressed: () => audio.playPlaylist(
                List.of(widget.album.songs)..shuffle(),
                source: PlaybackSource(
                  type: PlaybackSourceType.album,
                  id: widget.album.id,
                  name: widget.album.title,
                ),
              ),
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
              style: isDark
                  ? OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                    )
                  : null,
            )
          : FilledButton.tonalIcon(
              onPressed: () => audio.playPlaylist(
                List.of(widget.album.songs)..shuffle(),
                source: PlaybackSource(
                  type: PlaybackSourceType.album,
                  id: widget.album.id,
                  name: widget.album.title,
                ),
              ),
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
    ];

    final Widget scrollBody = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (!isPortrait)
          SliverToBoxAdapter(
            child: SizedBox(height: barHeight),
          ),
        SliverToBoxAdapter(
          child: isPortrait
              ? AlbumPortraitHeaderBanner(
                  title: widget.album.title,
                  subtitle: widget.album.artist,
                  metadata: metadataWidget,
                  actionButtons: actionButtons,
                  coverBackground: _AlbumCoverBackground(album: widget.album),
                  coverWidget: AlbumCover(
                    album: widget.album,
                    size: 160,
                    enableHero: true,
                  ),
                  barHeight: barHeight,
                )
              : AlbumLandscapeHeaderBanner(
                  title: widget.album.title,
                  subtitle: widget.album.artist,
                  metadata: metadataWidget,
                  actionButtons: actionButtons,
                  coverWidget: AlbumCover(
                    album: widget.album,
                    size: 220,
                    enableHero: true,
                  ),
                ),
        ),
        SliverFixedExtentList.builder(
          itemExtent: 64.0,
          itemCount: widget.album.songs.length,
          itemBuilder: (context, index) {
            final song = widget.album.songs[index];
            final isCurrent = currentMusic?.path == song.path;
            final isSelected = isSongSelected(song.path);
            final showRemote =
                isMixedAlbum && RemoteMediaHelper.isRemote(song);

            return _AlbumSongItem(
              song: song,
              index: index,
              isCurrent: isCurrent,
              isSelected: isSelected,
              isSelectionMode: isSelectionMode,
              selectedPaths: selectedSongPaths,
              isLargeAlbum: isLargeAlbum,
              showRemoteIndicator: showRemote,
              unknownArtist: unknownArtist,
              onTap: () {
                handleSongTap(
                  index: index,
                  songPath: song.path,
                  allSongs: widget.album.songs,
                  onNormalTap: () {
                    audio.playPlaylist(
                      widget.album.songs,
                      initialIndex: index,
                      source: PlaybackSource(
                        type: PlaybackSourceType.album,
                        id: widget.album.id,
                        name: widget.album.title,
                      ),
                    );
                  },
                );
              },
              onLongPress: () {
                lastAnchorIndex = index;
                if (!isSelectionMode) {
                  enterSongSelectionMode(song.path);
                }
              },
              onSecondaryTapDown: (details) {
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
              onToggleSelection: () {
                lastAnchorIndex = index;
                toggleSongSelection(song.path);
              },
            );
          },
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: MiniPlayerUiTuning.getListBottomPadding(
              context,
              hasPlayingMusic: currentMusic != null,
              isSelectionMode: isSelectionMode,
              selectionPanelHeight: 220.0,
            ),
          ),
        ),
      ],
    );

    final Widget content = Scaffold(
      body: Stack(
        children: [
          scrollBody,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AlbumDetailNavBar(
              title: widget.album.title,
              scrollProgress: _scrollProgress,
              isCoverVisible: _isCoverVisible,
              onGoBack: () => Navigator.of(context).maybePop(),
            ),
          ),
          AnimatedSelectionPanel(
            isVisible: isSelectionMode,
            child: LibrarySelectionPanel(
              key: const ValueKey('library-selection-panel'),
              selectedSongs: selectedSongs,
              allSongs: widget.album.songs,
              onToggleSelectAll: () =>
                  toggleSelectAllSongs(widget.album.songs),
              onCancel: cancelSongSelection,
            ),
          ),
        ],
      ),
    );

    final wrapped = MiniPlayerWrapper(child: content);
    if (isSelectionMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          cancelSongSelection();
        },
        child: wrapped,
      );
    }
    return wrapped;
  }
}

/// Helper to render the album artwork across memory, file, and remote sources.
class _AlbumCoverBackground extends StatelessWidget {
  const _AlbumCoverBackground({required this.album});

  final AlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final rep = album.representativeSong;
    final rawPath = rep.thumbnailPath ?? rep.artworkPath;
    final resolvedPath = rawPath != null
        ? ScannerPathUtils.resolveIosSandboxPath(rawPath)
        : null;

    if (rep.artworkBytes != null && rep.artworkBytes!.isNotEmpty) {
      return Image.memory(
        rep.artworkBytes!,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    if (resolvedPath != null &&
        resolvedPath.isNotEmpty &&
        File(resolvedPath).existsSync()) {
      return Image.file(
        File(resolvedPath),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      );
    }

    return SongThumbnail.fromAlbum(
      album,
      size: 400,
      width: double.infinity,
      height: double.infinity,
      borderRadius: BorderRadius.zero,
    );
  }
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

class _AlbumSongItem extends StatelessWidget {
  const _AlbumSongItem({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isSelected,
    required this.isSelectionMode,
    this.selectedPaths,
    required this.isLargeAlbum,
    required this.unknownArtist,
    this.showRemoteIndicator = false,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTapDown,
    required this.onToggleSelection,
  });

  final MusicFile song;
  final int index;
  final bool isCurrent;
  final bool isSelected;
  final bool isSelectionMode;
  final Iterable<String>? selectedPaths;
  final bool isLargeAlbum;
  final String unknownArtist;
  final bool showRemoteIndicator;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<TapDownDetails> onSecondaryTapDown;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final durationLabel = _formatDuration(song.durationMillis);
    final trackLabel = '${index + 1}'.padLeft(2, '0');
    final isTileSelected = isSelectionMode ? isSelected : isCurrent;

    final leadingWidget = isSelectionMode
        ? SizedBox(
            width: isLargeAlbum ? 40 : 32,
            child: Center(
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelection(),
              ),
            ),
          )
        : SizedBox(
            width: isLargeAlbum ? 40 : 32,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  trackLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isCurrent ? theme.colorScheme.primary : null,
                    fontWeight: isCurrent ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ),
          );

    final tileWidget = Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
        child: Container(
          decoration: (!isPortrait)
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: isDark ? 0.5 : 0.4,
                      ),
                      width: 0.8,
                    ),
                  ),
                )
              : null,
          child: Material(
            color: isTileSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: !isPortrait ? BorderRadius.circular(8) : BorderRadius.zero,
            child: InkWell(
              borderRadius: !isPortrait ? BorderRadius.circular(8) : BorderRadius.zero,
              enableFeedback: false,
              canRequestFocus: false,
              onTap: onTap,
              onLongPress: onLongPress,
              onSecondaryTapDown: onSecondaryTapDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    leadingWidget,
                    const SizedBox(width: 16),
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
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: isCurrent ? theme.colorScheme.primary : null,
                                    fontWeight: isCurrent ? FontWeight.w700 : null,
                                  ),
                                ),
                              ),
                              RemoteMediaBadge.songTrailing(
                                song: song,
                                isMixed: showRemoteIndicator,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist ?? unknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
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
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
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
