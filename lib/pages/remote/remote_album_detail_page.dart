import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../player/metadata/metadata_database.dart';
import 'package:oktoast/oktoast.dart';
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/remote_server_riverpod.dart';
import '../../player/remote/clients/remote_media_library_client.dart';
import '../../widgets/remote_artwork_widget.dart';
import '../../widgets/album_detail_widgets.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../widgets/playing_equalizer_icon.dart';
import '../../dialogs/remote_playlist_dialog.dart';
import '../../widgets/draggable_song_item.dart';
import '../../l10n/app_localizations.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../player/remote/remote_library_navigation.dart';
import '../../utils/app_snack_bar.dart';
import '../../utils/layout_constants.dart';
import '../../utils/remote_context_menu_utils.dart';
import '../../widgets/library_selection_panel.dart';
import '../../widgets/library_selection_scope.dart';
import 'remote_download_manager_page.dart';
import 'widgets/remote_library_selection_actions.dart';
import '../../utils/song_locator_helper.dart';
import '../../widgets/auto_hide_header.dart';

class RemoteAlbumDetailPage extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String albumId;
  final String albumName;
  final String? artistName;
  final String? coverArtId;
  final String? highlightedSongPath;

  const RemoteAlbumDetailPage({
    super.key,
    required this.server,
    required this.password,
    required this.albumId,
    required this.albumName,
    this.artistName,
    this.coverArtId,
    this.highlightedSongPath,
  });

  @override
  ConsumerState<RemoteAlbumDetailPage> createState() =>
      _RemoteAlbumDetailPageState();
}

class _RemoteAlbumDetailPageState
    extends ConsumerState<RemoteAlbumDetailPage>
    with SongSelectionMixin {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _albumData;
  List<MusicFile> _tracks = [];
  bool _isStarred = false;
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _isCoverVisible = ValueNotifier<bool>(true);
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);
  String? _highlightedSongPath;
  Timer? _highlightTimer;

  bool _isRevalidating = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    if (widget.highlightedSongPath != null) {
      _highlightedSongPath = widget.highlightedSongPath;
    }
    _loadAlbumDetails();
  }

  @override
  void didUpdateWidget(RemoteAlbumDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId ||
        oldWidget.server.id != widget.server.id) {
      _loadAlbumDetails();
    }
    if (widget.highlightedSongPath != null &&
        widget.highlightedSongPath != oldWidget.highlightedSongPath) {
      _scrollToTrack(widget.highlightedSongPath!);
    }
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
    _highlightTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _isCoverVisible.dispose();
    _scrollProgress.dispose();
    super.dispose();
  }

  void _scrollToTrack(String songPath) {
    if (!mounted || _tracks.isEmpty) return;
    final index = _tracks.indexWhere((t) => t.path == songPath);
    if (index == -1) return;

    setState(() {
      _highlightedSongPath = songPath;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightedSongPath = null;
        });
      }
    });

    if (_scrollController.hasClients) {
      final double headerEstimatedHeight = 280.0;
      final double trackHeight = 52.0;
      final double itemOffset = headerEstimatedHeight + index * trackHeight;
      final double viewportHeight = _scrollController.position.viewportDimension;
      double targetOffset = itemOffset - (viewportHeight / 2) + (trackHeight / 2);
      final maxScroll = _scrollController.position.maxScrollExtent;
      targetOffset = targetOffset.clamp(0.0, maxScroll);
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _locateCurrentSong() async {
    final currentMusic = ref.read(audioCurrentMusicProvider);
    if (currentMusic == null) return;

    final inCurrentAlbum = _tracks.any((t) => t.path == currentMusic.path);
    if (inCurrentAlbum) {
      _scrollToTrack(currentMusic.path);
      return;
    }

    await SongLocatorHelper.locateCurrentPlayingSong(ref, context);
  }

  Future<void> _loadAlbumDetails({bool forceRefresh = false}) async {
    // 1. Try reading from SQLite cache first for instant UI (SWR)
    if (!forceRefresh && _tracks.isEmpty) {
      try {
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'album_detail_${widget.albumId}',
        );
        if (cache != null && mounted) {
          final data = jsonDecode(cache.dataJson) as Map<String, dynamic>;
          final album = data['album'] as Map<String, dynamic>?;
          final songList = (data['songs'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              [];
          final client = RemoteMediaLibraryClient.create(
            server: widget.server,
            password: widget.password,
          );
          final parsedTracks = songList.map(client.buildMusicFile).toList();
          final isStarred = data['isStarred'] == true;

          if (parsedTracks.isNotEmpty || album != null) {
            setState(() {
              _albumData = album;
              _tracks = parsedTracks;
              _isStarred = isStarred;
              _isLoading = false;
              _error = null;
            });

            if (_highlightedSongPath != null) {
              final targetPath = _highlightedSongPath!;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToTrack(targetPath);
              });
            }

            _revalidateAlbumDetails();
            return;
          }
        }
      } catch (_) {}
    }

    if (!forceRefresh && _tracks.isNotEmpty) {
      _revalidateAlbumDetails();
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    await _fetchAndApplyAlbumDetails(isBackground: false);
  }

  Future<void> _revalidateAlbumDetails() async {
    if (_isRevalidating || !mounted) return;
    _isRevalidating = true;
    try {
      await _fetchAndApplyAlbumDetails(isBackground: true);
    } finally {
      _isRevalidating = false;
    }
  }

  Future<void> _fetchAndApplyAlbumDetails({required bool isBackground}) async {
    try {
      final client = RemoteMediaLibraryClient.create(
        server: widget.server,
        password: widget.password,
      );
      final album = await client.getAlbum(widget.albumId);
      if (album == null) {
        if (!mounted || isBackground) return;
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.albumNotFound;
          _isLoading = false;
        });
        return;
      }

      final songList = album['song'] as List?;
      final List<MusicFile> parsedTracks = [];
      final List<Map<String, dynamic>> rawSongs = [];
      if (songList != null) {
        for (final item in songList) {
          if (item is Map<String, dynamic>) {
            rawSongs.add(item);
            parsedTracks.add(
              client.buildMusicFile(item),
            );
          }
        }
      }

      final isStarred = album['starred'] != null;
      if (!mounted) return;

      bool hasChanged = true;
      if (isBackground && _tracks.isNotEmpty) {
        if (_tracks.length == parsedTracks.length && _isStarred == isStarred) {
          hasChanged = false;
          for (int i = 0; i < _tracks.length; i++) {
            if (_tracks[i].path != parsedTracks[i].path ||
                _tracks[i].title != parsedTracks[i].title) {
              hasChanged = true;
              break;
            }
          }
        }
      }

      if (!isBackground || hasChanged) {
        setState(() {
          _albumData = album;
          _tracks = parsedTracks;
          _isStarred = isStarred;
          _isLoading = false;
          _error = null;
        });
      }

      if (_highlightedSongPath != null && !isBackground) {
        final targetPath = _highlightedSongPath!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTrack(targetPath);
        });
      }

      final cachePayload = {
        'album': album,
        'isStarred': isStarred,
        'songs': rawSongs,
      };
      unawaited(MetadataDatabase().saveRemoteLibraryCache(
        serverId: widget.server.id,
        category: 'album_detail_${widget.albumId}',
        dataJson: jsonEncode(cachePayload),
        count: parsedTracks.length,
      ));
    } catch (e) {
      if (!mounted || isBackground) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_tracks.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final audioService = ref.read(audioServiceProvider);
    final playlist = List<MusicFile>.from(_tracks);
    if (shuffle) {
      playlist.shuffle();
    }
    await audioService.playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.album,
        id: 'remote-${widget.server.id}-${widget.albumId}',
        name: widget.albumName,
      ),
    );
    showToast(l10n.playingTracksCount(_tracks.length));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final coverId = widget.coverArtId ?? _albumData?['coverArt'] as String?;
    final artist = widget.artistName ??
        _albumData?['artist'] as String? ??
        l10n.unknownArtist;
    final year = _albumData?['year'] as int?;
    final genre = _albumData?['genre'] as String?;

    final bottomOffset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: isSelectionMode,
      selectionPanelHeight: 220.0,
    );
    final selectedSongs = getSelectedSongs(_tracks);

    final albumTitle = (widget.albumName.isNotEmpty && widget.albumName != 'Untitled')
        ? widget.albumName
        : (_albumData?['name'] as String? ??
            _albumData?['title'] as String? ??
            widget.albumName);

    final double barHeight = AlbumDetailNavBar.getBarHeight(context);

    final metadataWidget = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _InfoChip(
          label: l10n.songCount(_tracks.length),
          isOverlay: isPortrait && isDark,
        ),
        if (year != null && year > 0)
          _InfoChip(
            label: '$year',
            isOverlay: isPortrait && isDark,
          ),
        if (genre != null && genre.isNotEmpty)
          _InfoChip(
            label: genre,
            isOverlay: isPortrait && isDark,
          ),
      ],
    );

    final outlinedStyle = (isPortrait && isDark)
        ? OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          )
        : (!isPortrait
            ? OutlinedButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              )
            : null);

    final actionButtons = [
      FilledButton.icon(
        onPressed: _tracks.isNotEmpty ? () => _playAll(shuffle: false) : null,
        icon: const Icon(Icons.play_arrow_rounded, size: 20),
        label: Text(l10n.playAll),
        style: !isPortrait
            ? FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              )
            : null,
      ),
      OutlinedButton.icon(
        onPressed: _tracks.isNotEmpty ? () => _playAll(shuffle: true) : null,
        icon: const Icon(Icons.shuffle_rounded, size: 18),
        label: Text(l10n.shufflePlay),
        style: outlinedStyle,
      ),
      OutlinedButton.icon(
        onPressed: _tracks.isNotEmpty
            ? () => RemoteAddToPlaylistDialog.show(
                  context,
                  ref: ref,
                  server: widget.server,
                  password: widget.password,
                  songs: _tracks,
                )
            : null,
        icon: const Icon(Icons.playlist_add_rounded, size: 18),
        label: Text(l10n.addToPlaylist),
        style: outlinedStyle,
      ),
      OutlinedButton.icon(
        onPressed: _tracks.isNotEmpty
            ? () async {
                final notifier =
                    ref.read(remoteDownloadTasksProvider.notifier);
                await notifier.enqueueRemoteTracks(
                  server: widget.server,
                  password: widget.password,
                  songs: _tracks,
                  collectionName: widget.albumName,
                );
                if (context.mounted) {
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text(
                        l10n.batchAddedToDownloadQueue(_tracks.length),
                      ),
                      action: SnackBarAction(
                        label: l10n.viewDownloadProgress,
                        onPressed: () {
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const RemoteDownloadManagerPage(),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }
              }
            : null,
        icon: const Icon(Icons.download_rounded, size: 18),
        label: Text(l10n.download),
        style: outlinedStyle,
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final l10n = AppLocalizations.of(context)!;
          final client = RemoteMediaLibraryClient.create(
            server: widget.server,
            password: widget.password,
          );
          if (_isStarred) {
            final ok = await client.unstar(albumId: widget.albumId);
            if (ok && mounted) {
              setState(() => _isStarred = false);
              showToast(l10n.unstarredSuccess);
            }
          } else {
            final ok = await client.star(albumId: widget.albumId);
            if (ok && mounted) {
              setState(() => _isStarred = true);
              showToast(l10n.starredSuccess);
            }
          }
        },
        icon: Icon(
          _isStarred ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color: _isStarred
              ? theme.colorScheme.primary
              : ((isPortrait && isDark) ? Colors.white : null),
        ),
        label: Text(
          l10n.btnFavorite,
          style: TextStyle(
            color: _isStarred
                ? theme.colorScheme.primary
                : ((isPortrait && isDark) ? Colors.white : null),
          ),
        ),
        style: outlinedStyle,
      ),
    ];

    final navActions = [
      IconButton(
        icon: const Icon(Icons.my_location_rounded, size: 20),
        tooltip: l10n.locateCurrentSong,
        onPressed: _locateCurrentSong,
      ),
      Consumer(
        builder: (context, ref, child) {
          final activeCount = ref.watch(activeDownloadsCountProvider);
          return IconButton(
            icon: Badge(
              isLabelVisible: activeCount > 0,
              label: Text('$activeCount'),
              child: const Icon(Icons.download_rounded, size: 20),
            ),
            tooltip: l10n.downloadManager,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => const RemoteDownloadManagerPage(),
                ),
              );
            },
          );
        },
      ),
    ];

    final Widget scrollBody = RefreshIndicator(
      onRefresh: () => _loadAlbumDetails(forceRefresh: true),
      child: CustomScrollView(
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
                    title: albumTitle,
                    subtitle: artist,
                    tagLabel: l10n.albumLabel.toUpperCase(),
                    metadata: metadataWidget,
                    actionButtons: actionButtons,
                    coverBackground: RemoteArtworkWidget(
                      server: widget.server,
                      password: widget.password,
                      coverArtId: coverId,
                      size: 400,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.zero,
                    ),
                    coverWidget: RemoteArtworkWidget(
                      server: widget.server,
                      password: widget.password,
                      coverArtId: coverId,
                      size: 160,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    barHeight: barHeight,
                  )
                : AlbumLandscapeHeaderBanner(
                    title: albumTitle,
                    subtitle: artist,
                    tagLabel: l10n.albumLabel.toUpperCase(),
                    metadata: metadataWidget,
                    actionButtons: actionButtons,
                    coverWidget: RemoteArtworkWidget(
                      server: widget.server,
                      password: widget.password,
                      coverArtId: coverId,
                      size: 220,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
          ),
          if (isPortrait) const SliverToBoxAdapter(child: SizedBox(height: 8)),
          // Track List
                          SliverFixedExtentList.builder(
                            itemExtent: 52.0,
                            itemCount: _tracks.length,
                            itemBuilder: (context, index) {
                              final song = _tracks[index];
                              final isPlaying = currentMusic?.path == song.path;
                              final isHighlighted = _highlightedSongPath == song.path;
                              final isAudioPlaying = ref.watch(audioIsPlayingProvider);
                              final isSelected = isSongSelected(song.path);
                              final trackNum = song.trackNumber ?? (index + 1);
                              final trackLabel = '$trackNum'.padLeft(2, '0');
                              final durationLabel = song.durationMillis != null &&
                                      song.durationMillis! > 0
                                  ? _formatDuration(song.durationMillis!)
                                  : null;

                              return DraggableSongItem(
                                song: song,
                                enabled: true,
                                isSelected: isSelected,
                                isSelectionMode: isSelectionMode,
                                selectedPaths: selectedSongPaths,
                                child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onSecondaryTapDown: (details) {
                                  if (!isSelectionMode) {
                                    showRemoteSongContextMenu(
                                      context: context,
                                      globalPosition: details.globalPosition,
                                      ref: ref,
                                      server: widget.server,
                                      password: widget.password,
                                      song: song,
                                      playlist: _tracks,
                                      onViewArtist: () {
                                        if (song.artist != null && song.artist!.isNotEmpty) {
                                          RemoteLibraryNavUtils.openArtist(
                                            context,
                                            ref,
                                            server: widget.server,
                                            password: widget.password,
                                            artistId: '',
                                            artistName: song.artist!,
                                          );
                                        }
                                      },
                                    );
                                  }
                                },
                                onLongPressStart: (details) {
                                  lastAnchorIndex = index;
                                  if (!isSelectionMode) {
                                    enterSongSelectionMode(song.path);
                                  } else {
                                    toggleSongSelection(song.path);
                                  }
                                },
                                child: Align(
                                  alignment: Alignment.center,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: kSingleColumnContentMaxWidth,
                                    ),
                                    child: Container(
                                      decoration: (!isPortrait)
                                          ? BoxDecoration(
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: theme
                                                      .colorScheme.outlineVariant
                                                      .withValues(
                                                    alpha: isDark ? 0.5 : 0.4,
                                                  ),
                                                  width: 0.8,
                                                ),
                                              ),
                                            )
                                          : null,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                        decoration: BoxDecoration(
                                          color: isSelectionMode && isSelected
                                              ? theme.colorScheme.primaryContainer
                                                  .withValues(alpha: 0.35)
                                              : (isHighlighted
                                                  ? theme.colorScheme.primaryContainer
                                                      .withValues(alpha: 0.6)
                                                  : (isPlaying
                                                      ? theme.colorScheme.primaryContainer
                                                          .withValues(alpha: 0.35)
                                                      : Colors.transparent)),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(8),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(8),
                                            onTap: () {
                                              handleSongTap(
                                                index: index,
                                                songPath: song.path,
                                                allSongs: _tracks,
                                                onNormalTap: () async {
                                                  final audioService =
                                                      ref.read(audioServiceProvider);
                                                  await audioService.playPlaylist(
                                                    _tracks,
                                                    initialIndex: index,
                                                    source: PlaybackSource(
                                                      type: PlaybackSourceType.album,
                                                      id: 'remote-${widget.server.id}-${widget.albumId}',
                                                      name: widget.albumName,
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 6,
                                              ),
                                              child: Row(
                                              children: [
                                                SizedBox(
                                                  width: _tracks.length >= 100 ? 40 : 32,
                                                  child: Center(
                                                    child: isSelectionMode
                                                        ? Checkbox(
                                                            value: isSelected,
                                                            onChanged: (_) =>
                                                                toggleSongSelection(
                                                              song.path,
                                                            ),
                                                          )
                                                        : (isPlaying
                                                            ? PlayingEqualizerIcon(
                                                                color:
                                                                    theme.colorScheme.primary,
                                                                size: 16,
                                                                isPlaying: isAudioPlaying,
                                                              )
                                                            : FittedBox(
                                                                fit: BoxFit.scaleDown,
                                                                child: Text(
                                                                  trackLabel,
                                                                  textAlign: TextAlign.center,
                                                                  style: theme
                                                                      .textTheme.bodyMedium
                                                                      ?.copyWith(
                                                                    color: isHighlighted
                                                                        ? theme.colorScheme.primary
                                                                        : theme.colorScheme
                                                                            .onSurfaceVariant,
                                                                    fontWeight:
                                                                        FontWeight.w600,
                                                                  ),
                                                                ),
                                                              )),
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Text(
                                                    song.displayName,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: theme.textTheme.bodyLarge
                                                        ?.copyWith(
                                                      color: (isPlaying || isHighlighted)
                                                          ? theme.colorScheme.primary
                                                          : null,
                                                      fontWeight: (isPlaying || isHighlighted)
                                                          ? FontWeight.w700
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                                if (durationLabel != null) ...[
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    durationLabel,
                                                  style: theme.textTheme.bodyMedium
                                                      ?.copyWith(
                                                    color: theme
                                                        .colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                              if (!isSelectionMode) ...[
                                                const SizedBox(width: 4),
                                                Builder(
                                                  builder: (btnContext) => IconButton(
                                                    icon: const Icon(Icons.more_vert_rounded, size: 18),
                                                    visualDensity: VisualDensity.compact,
                                                    padding: EdgeInsets.zero,
                                                    splashRadius: 18,
                                                    onPressed: () {
                                                      final renderBox = btnContext
                                                          .findRenderObject() as RenderBox?;
                                                      if (renderBox != null) {
                                                        final position = renderBox
                                                            .localToGlobal(Offset.zero);
                                                        final size = renderBox.size;
                                                        showRemoteSongContextMenu(
                                                          context: context,
                                                          globalPosition: position +
                                                              Offset(
                                                                size.width / 2,
                                                                size.height,
                                                              ),
                                                          ref: ref,
                                                          server: widget.server,
                                                          password: widget.password,
                                                          song: song,
                                                          playlist: _tracks,
                                                          onViewArtist: () {
                                                            if (song.artist != null &&
                                                                song.artist!.isNotEmpty) {
                                                              RemoteLibraryNavUtils.openArtist(
                                                                context,
                                                                ref,
                                                                server: widget.server,
                                                                password: widget.password,
                                                                artistId: '',
                                                                artistName: song.artist!,
                                                              );
                                                            }
                                                          },
                                                        );
                                                      }
                                                    },
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
                              ),
                            ),
                          ),
                        );
                      },
                          ),
                          SliverToBoxAdapter(child: SizedBox(height: bottomOffset)),
                        ],
                      ),
                    );

    final Widget content = AutoHideHeaderScope(
      forceVisible: isSelectionMode,
      builder: (context, isHeaderVisible) => Scaffold(
        body: Stack(
          children: [
            if (_isLoading)
              const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              )
            else if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(l10n.errorWithMessage(_error!), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _loadAlbumDetails,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              )
            else
              scrollBody,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AutoHideHeader(
                isVisible: isHeaderVisible,
                child: AlbumDetailNavBar(
                  title: albumTitle,
                  scrollProgress: (_isLoading || _error != null)
                      ? const AlwaysStoppedAnimation(1.0)
                      : _scrollProgress,
                  isCoverVisible: (_isLoading || _error != null)
                      ? const AlwaysStoppedAnimation(false)
                      : _isCoverVisible,
                  onGoBack: () => Navigator.of(context).maybePop(),
                  actions: navActions,
                ),
              ),
            ),
          if (!_isLoading && _error == null)
            AnimatedSelectionPanel(
              isVisible: isSelectionMode,
              child: LibrarySelectionPanel(
                key: const ValueKey('remote-album-selection-panel'),
                selectedSongs: selectedSongs,
                allSongs: _tracks,
                onToggleSelectAll: () => toggleSelectAllSongs(_tracks),
                onCancel: cancelSongSelection,
                onAddToFavorites: () =>
                    RemoteLibrarySelectionActions.handleBatchAddToLocalFavorites(
                  context: context,
                  ref: ref,
                  onFetchSongs: () async => selectedSongs,
                  onClearSelection: cancelSongSelection,
                ),
                onAddToCloudFavorites: () =>
                    RemoteLibrarySelectionActions.handleBatchAddToCloudFavorites(
                  context: context,
                  ref: ref,
                  server: widget.server,
                  password: widget.password,
                  onFetchSongs: () async => selectedSongs,
                  onClearSelection: cancelSongSelection,
                  onStarredChanged: (starredIds) {
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromeSongs(
                          starredSongIds: {
                            ...?ref
                                .read(activeRemoteSessionProvider)
                                ?.navidromeStarredSongIds,
                            ...starredIds,
                          },
                        );
                  },
                ),
                onDownload: () async {
                  final sel = List<MusicFile>.from(selectedSongs);
                  if (sel.isEmpty) return;
                  final notifier =
                      ref.read(remoteDownloadTasksProvider.notifier);
                  await notifier.enqueueRemoteTracks(
                    server: widget.server,
                    password: widget.password,
                    songs: sel,
                    collectionName: widget.albumName,
                  );
                  cancelSongSelection();
                  if (context.mounted) {
                    AppSnackBar.show(
                      context,
                      ref,
                      SnackBar(
                        content: Text(
                          l10n.batchAddedToDownloadQueue(sel.length),
                        ),
                        action: SnackBarAction(
                          label: l10n.viewDownloadProgress,
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true)
                                .push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const RemoteDownloadManagerPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    ),
  );

    return MiniPlayerWrapper(child: content);
  }

  String _formatDuration(int millis) {
    final dur = Duration(milliseconds: millis);
    final m = dur.inMinutes;
    final s = dur.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    this.isOverlay = false,
  });

  final String label;
  final bool isOverlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isOverlay && isDark
            ? Colors.white.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isOverlay && isDark
              ? Colors.white.withValues(alpha: 0.95)
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

typedef NavidromeAlbumDetailPage = RemoteAlbumDetailPage;
