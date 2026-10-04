import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
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

  static double getBarHeight(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final topPadding = statusBarHeight > 0
        ? statusBarHeight + 2.0
        : (isDesktop ? 38.0 : 4.0);
    const bottomPadding = 4.0;
    const contentHeight = 40.0;
    return topPadding + contentHeight + bottomPadding;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              ? _AlbumPortraitHeaderBanner(
                  album: widget.album,
                  barHeight: barHeight,
                  onPlayAll: () => audio.playPlaylist(
                    widget.album.songs,
                    source: PlaybackSource(
                      type: PlaybackSourceType.album,
                      id: widget.album.id,
                      name: widget.album.title,
                    ),
                  ),
                  onShufflePlay: () => audio.playPlaylist(
                    List.of(widget.album.songs)..shuffle(),
                    source: PlaybackSource(
                      type: PlaybackSourceType.album,
                      id: widget.album.id,
                      name: widget.album.title,
                    ),
                  ),
                )
              : _AlbumLandscapeHeaderBanner(
                  album: widget.album,
                  onPlayAll: () => audio.playPlaylist(
                    widget.album.songs,
                    source: PlaybackSource(
                      type: PlaybackSourceType.album,
                      id: widget.album.id,
                      name: widget.album.title,
                    ),
                  ),
                  onShufflePlay: () => audio.playPlaylist(
                    List.of(widget.album.songs)..shuffle(),
                    source: PlaybackSource(
                      type: PlaybackSourceType.album,
                      id: widget.album.id,
                      name: widget.album.title,
                    ),
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
            child: _AlbumDetailNavBar(
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

    return MiniPlayerWrapper(child: content);
  }
}

/// Dynamic Frosted Glass Top Navigation Bar for Album Detail Page
class _AlbumDetailNavBar extends StatelessWidget {
  const _AlbumDetailNavBar({
    required this.title,
    required this.scrollProgress,
    required this.isCoverVisible,
    required this.onGoBack,
  });

  final String title;
  final ValueListenable<double> scrollProgress;
  final ValueListenable<bool> isCoverVisible;
  final VoidCallback onGoBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    final topPadding = statusBarHeight > 0
        ? statusBarHeight + 2.0
        : (isDesktop ? 38.0 : 4.0);
    const bottomPadding = 4.0;
    final targetSurface = theme.colorScheme.surface;
    final maxAlpha = isDark ? 0.70 : 0.82;

    return ValueListenableBuilder<double>(
      valueListenable: scrollProgress,
      builder: (context, progress, _) {
        final navBackgroundColor = Color.lerp(
          targetSurface.withValues(alpha: 0.0),
          targetSurface.withValues(alpha: maxAlpha),
          progress,
        )!;

        final overlayIconColor =
            isDark ? Colors.white : theme.colorScheme.onSurface;
        final solidIconColor = theme.colorScheme.onSurface;
        final iconColor = Color.lerp(
              overlayIconColor,
              solidIconColor,
              progress,
            ) ??
            solidIconColor;

        final shadowAlpha = 1.0 - progress;
        final shadows = (isDark && shadowAlpha > 0.05)
            ? [
                Shadow(
                  offset: const Offset(0, 1),
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.87 * shadowAlpha),
                ),
              ]
            : null;

        final Widget barContent = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: navBackgroundColor,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.12 * progress),
                width: 0.8,
              ),
            ),
          ),
          padding: EdgeInsets.only(
            top: topPadding,
            bottom: bottomPadding,
            left: 4,
            right: 16,
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: iconColor,
                  shadows: shadows,
                ),
                onPressed: onGoBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: isCoverVisible,
                  builder: (context, visible, _) {
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: visible ? 0.0 : 1.0,
                      child: Text(
                        title,
                        key: const ValueKey('album_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        );

        final blurSigma = 24.0 * progress;
        if (progress > 0.01) {
          return ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: barContent,
            ),
          );
        }

        return barContent;
      },
    );
  }
}

/// Directory-page-styled Portrait Header Banner for Album Detail
class _AlbumPortraitHeaderBanner extends StatelessWidget {
  const _AlbumPortraitHeaderBanner({
    required this.album,
    required this.barHeight,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final AlbumSummary album;
  final double barHeight;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final durationText = _formatDuration(album.totalDurationMillis) ?? l10n.durationZero;

    return _OverscrollStretchBuilder(
      builder: (context, overscroll) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Background cover layer extending all the way to top with elastic overscroll stretch
              Positioned(
                top: -overscroll,
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.12)
                            : theme.colorScheme.shadow.withValues(alpha: 0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          color: isDark ? Colors.black : theme.colorScheme.surface,
                        ),
                        // Album cover with opacity as background
                        Positioned.fill(
                          child: Opacity(
                            opacity: isDark ? 0.38 : 0.30,
                            child: _AlbumCoverBackground(album: album),
                          ),
                        ),
                        // Gradient overlay for text readability
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDark
                                  ? [
                                      Colors.black.withValues(alpha: 0.35),
                                      Colors.black.withValues(alpha: 0.55),
                                      Colors.black.withValues(alpha: 0.85),
                                    ]
                                  : [
                                      theme.colorScheme.surface.withValues(alpha: 0.25),
                                      theme.colorScheme.surface.withValues(alpha: 0.60),
                                      theme.colorScheme.surface.withValues(alpha: 0.92),
                                    ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Foreground content layer
              Padding(
                padding: EdgeInsets.only(
                  top: barHeight,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 4, bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: AlbumCover(
                          album: album,
                          size: 160,
                          enableHero: true,
                        ),
                      ),
                    ),
                    Text(
                      album.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : theme.colorScheme.onSurface,
                        shadows: isDark
                            ? const [
                                Shadow(
                                  offset: Offset(0, 1),
                                  blurRadius: 4,
                                  color: Colors.black87,
                                ),
                              ]
                            : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (album.artist.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        album.artist,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.85)
                              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                          shadows: isDark
                              ? const [
                                  Shadow(
                                    offset: Offset(0, 1),
                                    blurRadius: 4,
                                    color: Colors.black87,
                                  ),
                                ]
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          '${l10n.songCount(album.trackCount)} · $durationText',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.85)
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontSize: isDark ? 13 : 14,
                            shadows: isDark
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
                        if (RemoteMediaHelper.isAllRemote(album.songs))
                          RemoteMediaBadge.chip(
                            songs: album.songs,
                            title: album.title,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: onPlayAll,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(l10n.playAll),
                        ),
                        OutlinedButton.icon(
                          onPressed: onShufflePlay,
                          icon: const Icon(Icons.shuffle),
                          label: Text(l10n.shufflePlay),
                          style: isDark
                              ? OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Landscape / Wide Screen Header Banner
class _AlbumLandscapeHeaderBanner extends StatelessWidget {
  const _AlbumLandscapeHeaderBanner({
    required this.album,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final AlbumSummary album;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerColor = theme.colorScheme.secondaryContainer.withValues(
      alpha: 0.65,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [headerColor, theme.colorScheme.surface],
        ),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AlbumCover(
                album: album,
                size: 200,
                enableHero: true,
              ),
              const SizedBox(width: 24),
              Expanded(
                child: _AlbumInfo(
                  album: album,
                  onPlayAll: onPlayAll,
                  onShufflePlay: onShufflePlay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

/// Helper widget to observe overscroll from the ambient [Scrollable].
class _OverscrollStretchBuilder extends StatefulWidget {
  const _OverscrollStretchBuilder({required this.builder});

  final Widget Function(BuildContext context, double overscroll) builder;

  @override
  State<_OverscrollStretchBuilder> createState() =>
      _OverscrollStretchBuilderState();
}

class _OverscrollStretchBuilderState extends State<_OverscrollStretchBuilder> {
  ScrollPosition? _position;
  double _lastOverscroll = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newPosition = Scrollable.maybeOf(context)?.position;
    if (_position != newPosition) {
      _position?.removeListener(_onScroll);
      _position = newPosition;
      _position?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _position = null;
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    final pos = _position;
    final currentOverscroll = (pos != null && pos.hasPixels && pos.pixels < 0)
        ? -pos.pixels
        : 0.0;
    if (currentOverscroll != _lastOverscroll) {
      _lastOverscroll = currentOverscroll;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    double overscroll = 0.0;
    if (_position != null && _position!.hasPixels && _position!.pixels < 0) {
      overscroll = -_position!.pixels;
    }
    return widget.builder(context, overscroll);
  }
}

class _AlbumInfo extends StatelessWidget {
  const _AlbumInfo({
    required this.album,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final AlbumSummary album;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          album.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          album.artist,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              '${l10n.songCount(album.trackCount)} · ${_formatDuration(album.totalDurationMillis) ?? l10n.durationZero}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (RemoteMediaHelper.isAllRemote(album.songs))
              RemoteMediaBadge.chip(
                songs: album.songs,
                title: album.title,
              ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: onPlayAll,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.playAll),
            ),
            OutlinedButton.icon(
              onPressed: onShufflePlay,
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
            ),
          ],
        ),
      ],
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

    final tileWidget = Material(
      color: isTileSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        enableFeedback: false,
        canRequestFocus: false,
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Align(
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
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
