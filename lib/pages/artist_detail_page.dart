import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/album_detail_widgets.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/draggable_song_item.dart';
import '../widgets/auto_hide_header.dart';

class ArtistDetailPage extends ConsumerStatefulWidget {
  const ArtistDetailPage({
    super.key,
    required this.artist,
    this.onGoBack,
  });

  final ArtistSummary artist;
  final VoidCallback? onGoBack;

  @override
  ConsumerState<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends ConsumerState<ArtistDetailPage> {
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _isHeaderVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final isVisible = offset < 140.0;
    final progress = (offset / 100.0).clamp(0.0, 1.0);
    _scrollProgress.value = progress;
    if (isVisible != _isHeaderVisible.value) {
      _isHeaderVisible.value = isVisible;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isHeaderVisible.dispose();
    _scrollProgress.dispose();
    super.dispose();
  }

  static double getBarHeight(BuildContext context) =>
      AlbumDetailNavBar.getBarHeight(context);

  @override
  Widget build(BuildContext context) {
    final double barHeight = getBarHeight(context);

    return AutoHideHeaderScope(
      builder: (context, isHeaderVisible) {
        final Widget content = Scaffold(
          body: Stack(
            children: [
              ArtistDetailContent(
                artist: widget.artist,
                scrollController: _scrollController,
                topPadding: barHeight + 8,
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AutoHideHeader(
                  isVisible: isHeaderVisible,
                  child: AlbumDetailNavBar(
                    title: widget.artist.name,
                    scrollProgress: _scrollProgress,
                    isCoverVisible: _isHeaderVisible,
                    onGoBack: widget.onGoBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ],
          ),
        );

        return MiniPlayerWrapper(child: content);
      },
    );
  }
}

class ArtistDetailContent extends ConsumerStatefulWidget {
  const ArtistDetailContent({
    super.key,
    required this.artist,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final ArtistSummary artist;
  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  ConsumerState<ArtistDetailContent> createState() => _ArtistDetailContentState();
}

class _ArtistDetailContentState extends ConsumerState<ArtistDetailContent>
    with SongSelectionMixin<ArtistDetailContent> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  List<MusicFile>? _lastArtistSongs;
  String? _lastUnknownAlbumLabel;
  List<_AlbumSection>? _cachedAlbumSections;
  List<MusicFile>? _cachedDisplaySongs;

  void _ensureAlbumSectionsCached(String unknownAlbumLabel) {
    if (!identical(_lastArtistSongs, widget.artist.songs) ||
        _lastUnknownAlbumLabel != unknownAlbumLabel ||
        _cachedAlbumSections == null) {
      _lastArtistSongs = widget.artist.songs;
      _lastUnknownAlbumLabel = unknownAlbumLabel;
      _cachedAlbumSections = _buildAlbumSections(widget.artist.songs, unknownAlbumLabel);
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
                  28,
                  widget.topPadding > 0 ? widget.topPadding + 12 : 24,
                  28,
                  20,
                ),
                child: _ArtistInfo(
                  artist: widget.artist,
                  onPlayAll: () => audio.playPlaylist(
                    displaySongs,
                    source: PlaybackSource(
                      type: PlaybackSourceType.artist,
                      id: widget.artist.queryKey,
                      name: widget.artist.name,
                    ),
                  ),
                  onShufflePlay: () => audio.playPlaylist(
                    List.of(displaySongs)..shuffle(),
                    source: PlaybackSource(
                      type: PlaybackSourceType.artist,
                      id: widget.artist.queryKey,
                      name: widget.artist.name,
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
                              type: PlaybackSourceType.artist,
                              id: widget.artist.queryKey,
                              name: widget.artist.name,
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
                        lastAnchorIndex = albumSections[i].startIndex + songIndex;
                      }
                      if (!isSelectionMode) {
                        enterSongSelectionMode(song.path);
                      }
                    },
                    isSelectionMode: isSelectionMode,
                    selectedSongPaths: selectedSongPaths,
                  ),
              ],
            ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MiniPlayerUiTuning.getListBottomPadding(
                  context,
                  hasPlayingMusic: currentMusic != null,
                  isSelectionMode: widget.hasBottomPanel ||
                      (isSelectionMode && widget.showSelectionPanel),
                  selectionPanelHeight: 220.0,
                ),
              ),
            ),
          ],
        ),
        AnimatedSelectionPanel(
          isVisible: isSelectionMode && widget.showSelectionPanel,
          child: LibrarySelectionPanel(
            key: const ValueKey('library-selection-panel'),
            selectedSongs: selectedSongs,
            allSongs: displaySongs,
            onToggleSelectAll: () => toggleSelectAllSongs(displaySongs),
            onCancel: cancelSongSelection,
          ),
        ),
      ],
    );

    if (isSelectionMode) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          cancelSongSelection();
        },
        child: content,
      );
    }
    return content;
  }
}

class _ArtistInfo extends StatelessWidget {
  const _ArtistInfo({
    required this.artist,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final ArtistSummary artist;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final songCountLabel = l10n.songCount(artist.songCount);
    final playAllLabel = l10n.playAll;
    final shufflePlayLabel = l10n.shufflePlay;

    final metaParts = <String>[
      songCountLabel,
      if ((artist.country?.trim().isNotEmpty ?? false)) artist.country!.trim(),
      if ((artist.areaName?.trim().isNotEmpty ?? false)) artist.areaName!.trim(),
      if (artist.tags.isNotEmpty) artist.tags.take(3).join(', '),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      artist.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  RemoteMediaBadge.pillTrailing(
                    songs: artist.songs,
                    title: artist.name,
                  ),
                ],
              ),
              if (artist.disambiguation?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 2),
                Text(
                  artist.disambiguation!.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                metaParts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: playAllLabel,
          onPressed: onPlayAll,
          icon: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary,
            ),
            child: Icon(
              Icons.play_arrow,
              size: 22,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: shufflePlayLabel,
          onPressed: onShufflePlay,
          icon: Icon(
            Icons.shuffle,
            size: 22,
            color: theme.colorScheme.primary,
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
    this.isSelectionMode = false,
    required this.selectedSongPaths,
  });

  final _AlbumSection section;
  final MusicFile? currentMusic;
  final ThemeData theme;
  final VoidCallback onPlayAlbum;
  final VoidCallback onShufflePlayAlbum;
  final ValueChanged<int> onSongTap;
  final void Function(TapDownDetails details, MusicFile song)
  onSongSecondaryTapDown;
  final ValueChanged<MusicFile> onSongLongPress;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;

  @override
  Widget build(BuildContext context) {
    final isMixedSection = RemoteMediaHelper.isMixed(section.songs);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;
            return isWide
                ? _buildWideLayout(context, isMixedSection, constraints.maxWidth)
                : _buildNarrowLayout(context, isMixedSection);
          },
        ),
      ),
    );
  }

  Widget _buildAlbumCover({required double size, double borderRadius = 10}) {
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

  Widget _buildHeaderRow(BuildContext context, String subtitle) {
    final l10n = AppLocalizations.of(context)!;
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
          onPressed: onPlayAlbum,
        ),
        IconButton(
          tooltip: l10n.shufflePlay,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.shuffle_rounded, size: 18),
          onPressed: onShufflePlayAlbum,
        ),
      ],
    );
  }

  Widget _buildSongList(bool isMixedSection) {
    return Column(
      children: [
        for (int i = 0; i < section.songs.length; i++)
          _AlbumSongTile(
            key: ValueKey(section.songs[i].path),
            song: section.songs[i],
            trackIndex: i + 1,
            isCurrent: currentMusic?.path == section.songs[i].path,
            theme: theme,
            showRemoteIndicator:
                isMixedSection && RemoteMediaHelper.isRemote(section.songs[i]),
            onTap: () => onSongTap(i),
            onSecondaryTapDown: (details) =>
                onSongSecondaryTapDown(details, section.songs[i]),
            onLongPress: () => onSongLongPress(section.songs[i]),
            isSelectionMode: isSelectionMode,
            isSelected: selectedSongPaths.contains(section.songs[i].path),
            selectedPaths: selectedSongPaths,
            showTopDivider: i > 0,
          ),
      ],
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    bool isMixedSection,
    double availableWidth,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final durationLabel =
        _formatDuration(section.totalDurationMillis) ?? l10n.durationZero;
    final countLabel = l10n.songCount(section.songs.length);
    final subtitle = '$countLabel · $durationLabel';

    final double coverSize;
    final double gap;
    final double coverRadius;

    if (availableWidth >= 1000) {
      coverSize = 220.0;
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
        _buildAlbumCover(size: coverSize, borderRadius: coverRadius),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(context, subtitle),
              const SizedBox(height: 8),
              _buildSongList(isMixedSection),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowLayout(BuildContext context, bool isMixedSection) {
    final l10n = AppLocalizations.of(context)!;
    final durationLabel =
        _formatDuration(section.totalDurationMillis) ?? l10n.durationZero;
    final countLabel = l10n.songCount(section.songs.length);
    final subtitle = '$countLabel · $durationLabel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildAlbumCover(size: 84, borderRadius: 8),
            const SizedBox(width: 14),
            Expanded(
              child: _buildHeaderRow(context, subtitle),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildSongList(isMixedSection),
      ],
    );
  }
}

class _AlbumSongTile extends StatelessWidget {
  const _AlbumSongTile({
    super.key,
    required this.song,
    required this.trackIndex,
    required this.isCurrent,
    required this.theme,
    this.showRemoteIndicator = false,
    required this.onTap,
    required this.onSecondaryTapDown,
    required this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.selectedPaths,
    this.showTopDivider = false,
  });

  final MusicFile song;
  final int trackIndex;
  final bool isCurrent;
  final ThemeData theme;
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
    final durationLabel = _formatDuration(song.durationMillis);
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
                  ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55)
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
                                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
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
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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

bool _hasArtwork(MusicFile song) {
  final hasBytes = song.artworkBytes?.isNotEmpty ?? false;
  final hasArtworkPath = song.artworkPath?.isNotEmpty ?? false;
  final hasThumbnailPath = song.thumbnailPath?.isNotEmpty ?? false;
  return hasBytes || hasArtworkPath || hasThumbnailPath;
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
