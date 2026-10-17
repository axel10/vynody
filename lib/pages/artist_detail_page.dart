import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/metadata/theaudiodb_artist_service.dart';
import '../widgets/album_sections.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/detail_page_shell.dart';
import '../widgets/library_selection_back_guard.dart';

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({
    super.key,
    required this.artist,
    this.onGoBack,
  });

  final ArtistSummary artist;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) {
    return LibrarySelectionBackGuard(
      child: DetailPageShell(
        title: artist.name,
        titleKey: const ValueKey('album_title'),
        onGoBack: onGoBack,
        contentBuilder: (context, scrollController, topPadding) =>
            ArtistDetailContent(
          artist: artist,
          scrollController: scrollController,
          topPadding: topPadding,
        ),
      ),
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

  String? _cachedImagePath;
  StreamSubscription<String>? _imageUpdateSub;

  final AlbumSectionsCache _albumCache = AlbumSectionsCache();

  @override
  void initState() {
    super.initState();
    _cachedImagePath = widget.artist.cachedImagePath;
    _imageUpdateSub = TheAudioDbArtistService.instance.onArtistImageUpdated
        .listen((queryKey) {
      if (queryKey == widget.artist.queryKey && mounted) {
        _refreshImage();
      }
    });
    _fetchArtistImageIfNeeded();
  }

  @override
  void dispose() {
    _imageUpdateSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArtistDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist.queryKey != widget.artist.queryKey) {
      _cachedImagePath = widget.artist.cachedImagePath;
      _fetchArtistImageIfNeeded();
    } else if (widget.artist.cachedImagePath != null &&
        widget.artist.cachedImagePath != _cachedImagePath) {
      _cachedImagePath = widget.artist.cachedImagePath;
    }
  }

  Future<void> _refreshImage() async {
    final imagePath = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist, priority: true);
    if (!mounted) return;
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        imagePath != _cachedImagePath) {
      setState(() {
        _cachedImagePath = imagePath;
      });
      ref.invalidate(artistLibraryProvider);
    }
  }

  Future<void> _fetchArtistImageIfNeeded() async {
    if (_cachedImagePath != null &&
        _cachedImagePath!.isNotEmpty &&
        File(_cachedImagePath!).existsSync()) {
      return;
    }
    final imagePath = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist, priority: true);
    if (!mounted) return;
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        imagePath != _cachedImagePath) {
      setState(() {
        _cachedImagePath = imagePath;
      });
      ref.invalidate(artistLibraryProvider);
    }
  }

  PlaybackSource get _artistSource => PlaybackSource(
        type: PlaybackSourceType.artist,
        id: widget.artist.queryKey,
        name: widget.artist.name,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    _albumCache.update(widget.artist.songs, l10n.unknownAlbum);
    final sections = _albumCache.sections;
    final displaySongs = _albumCache.allSongs;

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(displaySongs)
        : const <MusicFile>[];

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final horizontalPadding = isPortrait ? 20.0 : 28.0;

    return Stack(
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
                  horizontalPadding,
                  widget.topPadding > 0 ? widget.topPadding + 12 : 24,
                  horizontalPadding,
                  20,
                ),
                child: _ArtistInfo(
                  artist: widget.artist,
                  cachedImagePath: _cachedImagePath,
                  onPlayAll: () =>
                      audio.playPlaylist(displaySongs, source: _artistSource),
                  onShufflePlay: () => audio.playPlaylist(
                    List.of(displaySongs)..shuffle(),
                    source: _artistSource,
                  ),
                ),
              ),
            ),
            if (sections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(l10n.emptyList, style: theme.textTheme.titleMedium),
                ),
              )
            else
              for (int i = 0; i < sections.length; i++) ...[
                if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 36)),
                AlbumSectionSliver(
                  section: sections[i],
                  currentMusicPath: currentMusic?.path,
                  onSongTap: (section, songIndex) {
                    final song = section.songs[songIndex];
                    final globalIndex = section.startIndex + songIndex;
                    handleSongTap(
                      index: globalIndex,
                      songPath: song.path,
                      allSongs: displaySongs,
                      onNormalTap: () {
                        audio.playPlaylist(
                          displaySongs,
                          initialIndex: globalIndex,
                          source: _artistSource,
                        );
                      },
                    );
                  },
                  onSongLongPress: (section, song) {
                    final songIndex = section.songs.indexOf(song);
                    if (songIndex != -1) {
                      lastAnchorIndex = section.startIndex + songIndex;
                    }
                    if (!isSelectionMode) {
                      enterSongSelectionMode(song.path);
                    }
                  },
                  isSelectionMode: isSelectionMode,
                  selectedSongPaths: selectedSongPaths,
                ),
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
  }
}

class _ArtistInfo extends StatelessWidget {
  const _ArtistInfo({
    required this.artist,
    this.cachedImagePath,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final ArtistSummary artist;
  final String? cachedImagePath;
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

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    if (isPortrait) {
      final avatarSize = screenWidth < 360 ? 92.0 : 104.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Row 1: 艺术家头像居中占一行
          Center(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ArtistAvatar(
                diameter: avatarSize,
                imagePath: cachedImagePath ?? artist.cachedImagePath,
                imageUrl: artist.imageUrl,
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Row 2: 名字占一行
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    artist.name,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontSize: 24,
                    ),
                  ),
                ),
                RemoteMediaBadge.pillTrailing(
                  songs: artist.songs,
                  title: artist.name,
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),

          // 轻量副标题展示
          if (artist.hasDistinctCanonicalName) ...[
            const SizedBox(height: 2),
            Text(
              artist.canonicalName!.trim(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (artist.disambiguation?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 2),
            Text(
              artist.disambiguation!.trim(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metaParts.join(' · '),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Row 3: 播放与随机播放操作按钮（与专辑详情页对齐：FilledButton + OutlinedButton 居中 Wrap 排列）
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow),
                label: Text(playAllLabel),
              ),
              OutlinedButton.icon(
                onPressed: onShufflePlay,
                icon: const Icon(Icons.shuffle),
                label: Text(shufflePlayLabel),
              ),
            ],
          ),
        ],
      );
    }

    final avatarSize = screenWidth < 420 ? 56.0 : 72.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ArtistAvatar(
          diameter: avatarSize,
          imagePath: cachedImagePath ?? artist.cachedImagePath,
          imageUrl: artist.imageUrl,
        ),
        const SizedBox(width: 16),
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
              if (artist.hasDistinctCanonicalName) ...[
                const SizedBox(height: 2),
                Text(
                  artist.canonicalName!.trim(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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
