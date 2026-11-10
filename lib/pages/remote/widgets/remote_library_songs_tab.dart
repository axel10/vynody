import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/music_file.dart';
import '../../../dialogs/remote_track_load_progress_dialog.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/audio/playback_source.dart';
import '../../../player/remote/proxy/remote_media_resolver.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../player/remote/services/remote_download_service.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/remote_download_feedback.dart';
import '../../../utils/selection_utils.dart';
import '../../../utils/song_locator_helper.dart';
import '../../../widgets/folder_layout_utils.dart';
import '../../../widgets/folder_zoom_gesture_layer.dart';
import '../../../widgets/library_zoom_popover.dart';
import '../../../widgets/remote_artwork_widget.dart';
import '../../../widgets/song_zoom_item.dart';
import '../../../player/remote/remote_library_navigation.dart';
import 'remote_library_common_widgets.dart';
import 'remote_library_toolbar_widgets.dart';

class RemoteLibrarySongsToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final bool isSearchExpanded;
  final ValueChanged<bool> onToggleSearchExpanded;
  final bool starredOnly;
  final ValueChanged<bool> onToggleStarredOnly;
  final VoidCallback onSortPressed;

  const RemoteLibrarySongsToolbar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.isSearchExpanded,
    required this.onToggleSearchExpanded,
    required this.starredOnly,
    required this.onToggleStarredOnly,
    required this.onSortPressed,
  });

  Widget buildConditions(
    BuildContext context, {
    bool expandSearch = false,
    double searchWidth = 190.0,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    final searchField = RemoteSearchBar(
      controller: searchController,
      focusNode: searchFocusNode,
      hintText: l10n.filterSongs,
      searchQuery: searchQuery,
      onChanged: onSearchChanged,
      onClear: onClearSearch,
    );

    return Row(
      mainAxisSize: expandSearch ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (expandSearch)
          Expanded(child: searchField)
        else
          SizedBox(width: searchWidth, child: searchField),
        const SizedBox(width: 4),
        IconButton(
          style: kCompactIconButtonStyle,
          tooltip: l10n.starredSongsOnly,
          icon: Icon(
            starredOnly
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 18,
            color: starredOnly
                ? Colors.redAccent
                : theme.colorScheme.onSurfaceVariant,
          ),
          onPressed: () => onToggleStarredOnly(!starredOnly),
        ),
        const SizedBox(width: 4),
        // 排序入口与歌单 tab 一致：单个图标按钮点开排序弹窗，
        // 不再用带文字标签的下拉胶囊（竖屏会把顶部两行挤窄）。
        IconButton(
          style: kCompactIconButtonStyle,
          tooltip: l10n.sort,
          icon: const Icon(Icons.sort_rounded, size: 18),
          onPressed: onSortPressed,
        ),
        // 竖屏下顶部两行已占满内容宽，视图档位交给捏合手势；横屏才显示按钮。
        if (!isPortrait) ...[
          const SizedBox(width: 4),
          const LibraryZoomButton(scope: LibraryZoomScope.song),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return buildConditions(context, expandSearch: true);
  }
}

class RemoteLibrarySongsView extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final List<MusicFile> songs;
  final int totalServerSongsCount;
  final Set<String> starredSongIds;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback? onLoadMore;
  final String searchQuery;
  final double bottomOffset;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;
  final int? lastSongAnchorIndex;
  final void Function(Set<String> keys) onSetSelection;
  final void Function(String songPath) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;
  final void Function(MusicFile song) onToggleStar;
  final RemoteLibrarySongsToolbar? toolbar;

  const RemoteLibrarySongsView({
    super.key,
    required this.server,
    required this.password,
    required this.songs,
    required this.totalServerSongsCount,
    required this.starredSongIds,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.error,
    required this.onRefresh,
    required this.onLoadMore,
    required this.searchQuery,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedSongPaths,
    required this.lastSongAnchorIndex,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    required this.onToggleStar,
    this.toolbar,
  });

  @override
  ConsumerState<RemoteLibrarySongsView> createState() =>
      _RemoteLibrarySongsViewState();
}

class _RemoteLibrarySongsViewState
    extends ConsumerState<RemoteLibrarySongsView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _formatTotalDuration(List<MusicFile> songs) {
    int totalMs = 0;
    for (final s in songs) {
      if (s.durationMillis != null) {
        totalMs += s.durationMillis!;
      }
    }
    final totalSeconds = totalMs ~/ 1000;
    if (totalSeconds <= 0) return '';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes min';
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (widget.songs.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final audioService = ref.read(audioServiceProvider);
    final playlist = List<MusicFile>.from(widget.songs);
    if (shuffle) {
      playlist.shuffle();
    }
    await audioService.playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.playlist,
        id: 'remote-${widget.server.id}-songs',
        name: l10n.songs,
      ),
    );
  }

  Future<void> _downloadAll() async {
    if (widget.songs.isEmpty) return;

    // 整库下载可能要入队上千首，逐首入队期间用进度浮层报数。
    // null = 用户在浮层里点了取消，这时不该再报「已加入 N 首」。
    final queued = await runWithRemoteTrackLoadProgress<bool>(
      context: context,
      immediate: true,
      task: () async {
        await ref.read(remoteDownloadTasksProvider.notifier).enqueue(
              RemoteDownloadRequest(
                server: widget.server,
                password: widget.password,
                songs: widget.songs,
              ),
            );
        return true;
      },
    );
    if (queued != true) return;

    showRemoteDownloadQueuedFeedback(context, ref, widget.songs.length);
  }

  Widget _buildHeader(BuildContext context, BoxConstraints constraints) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final totalDurationStr = _formatTotalDuration(widget.songs);

    final countAndDurationText = Text(
      totalDurationStr.isNotEmpty
          ? '${l10n.trackCountShort(widget.songs.length)} · $totalDurationStr'
          : l10n.trackCountShort(widget.songs.length),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
    );

    final playButtons = [
      SizedBox(
        height: 32,
        child: FilledButton.icon(
          onPressed: widget.songs.isNotEmpty ? () => _playAll() : null,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(l10n.playAll),
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          fixedSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        tooltip: l10n.shufflePlay,
        onPressed: widget.songs.isNotEmpty ? () => _playAll(shuffle: true) : null,
        icon: const Icon(Icons.shuffle_rounded, size: 18),
      ),
      const SizedBox(width: 8),
      IconButton.filledTonal(
        style: IconButton.styleFrom(
          minimumSize: const Size(32, 32),
          fixedSize: const Size(32, 32),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        tooltip: l10n.downloadAllTracks,
        onPressed: widget.songs.isNotEmpty ? _downloadAll : null,
        icon: const Icon(Icons.download_rounded, size: 18),
      ),
    ];

    final isWide = constraints.maxWidth >= 740;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...playButtons,
          const Spacer(),
          if (widget.toolbar != null) ...[
            widget.toolbar!.buildConditions(
              context,
              expandSearch: false,
              searchWidth: 190,
            ),
            const SizedBox(width: 12),
          ],
          countAndDurationText,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.toolbar != null) ...[
          widget.toolbar!.buildConditions(
            context,
            expandSearch: true,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ...playButtons,
            const Spacer(),
            countAndDurationText,
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // 只订阅当前曲目路径：MusicFile 的其它字段被补齐时不该重建整个 sliver。
    final currentPath = ref.watch(
      audioCurrentMusicProvider.select((music) => music?.path),
    );
    final isAudioPlaying = ref.watch(audioIsPlayingProvider);
    final highlightedPath = ref.watch(songHighlightProvider);

    final isJellyfin = widget.server.type == RemoteServerType.jellyfin;
    final brandColor = isJellyfin ? const Color(0xFF9D65C9) : Colors.orange;

    if (widget.isLoading && widget.songs.isEmpty) {
      return RemoteLibraryLoadingView(
        server: widget.server,
        icon: Icons.music_note_rounded,
      );
    }

    if (widget.error != null && widget.songs.isEmpty) {
      return RemoteLibraryErrorView(
        error: l10n.errorLoadingSongs(widget.error!),
        onRetry: widget.onRefresh,
      );
    }

    // 顶部两行（搜索/收藏/排序 + 播放全部/随机/下载）与下方曲目网格同宽：
    // 歌单 tab 已经去掉 1080 单列上限，这里也不能再锁 kSingleColumnContentMaxWidth，
    // 否则宽窗口下顶部明显比其它 tab 窄一截；左右内边距同样与下方网格同源，
    // 竖屏下不再额外缩 28/36 两档。
    final songZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.songZoomScale),
    );
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final headerHPad = folderContentHorizontalPadding(
      isPortrait: isPortrait,
      gridMorph: isFolderZoomGrid(snapFolderZoomScale(songZoomScale))
          ? 1.0
          : 0.0,
    );

    final headerSliver = SliverRemoteContentConstraint(
      maxWidth: kFolderPageMaxWidth,
      padding: EdgeInsets.fromLTRB(headerHPad, 6, headerHPad, 8),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            _buildHeader(context, constraints),
      ),
    );

    if (widget.songs.isEmpty) {
      return CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          headerSliver,
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                widget.searchQuery.isEmpty
                    ? l10n.noSongsOnServer
                    : l10n.noMatchingSongs,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }

    return FolderZoomGestureLayer(
      scope: LibraryZoomScope.song,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.min(
            constraints.maxWidth,
            kFolderPageMaxWidth,
          );

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo.metrics.pixels >=
                      scrollInfo.metrics.maxScrollExtent - 300) {
                    if (widget.hasMore &&
                        !widget.isLoadingMore &&
                        !widget.isLoading) {
                      widget.onLoadMore?.call();
                    }
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      headerSliver,

                      FolderZoomSliverBuilder(
                        zoomScale: snapFolderZoomScale(songZoomScale),
                        width: contentWidth,
                        builder: (context, metrics) {
                          final hPad = folderContentHorizontalPadding(
                            isPortrait: isPortrait,
                            gridMorph: metrics.gridMorph,
                          );

                          return SliverPadding(
                            padding: EdgeInsets.symmetric(horizontal: hPad),
                            sliver: SliverGrid(
                              gridDelegate:
                                  SliverAnimatedZoomGridDelegate(
                                metrics: metrics,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, songIndex) {
                                  final song = widget.songs[songIndex];
                                  final isCurrent = currentPath == song.path;
                                  final isHighlighted =
                                      highlightedPath == song.path;
                                  final isSelected = widget.selectedSongPaths
                                      .contains(song.path);

                                  final trackId =
                                      RemoteMediaResolver.extractTrackId(song) ??
                                          (song.id != null && song.id! > 0
                                              ? song.id.toString()
                                              : '');
                                  final isStarred =
                                      widget.starredSongIds.contains(trackId);

                                  String? coverId;
                                  if (song.artworkPath != null &&
                                      song.artworkPath!.isNotEmpty) {
                                    coverId = song.artworkPath!.replaceFirst(
                                        'subsonic-cover://${widget.server.id}/',
                                        '');
                                  }
                                  if (coverId == null || coverId.isEmpty) {
                                    coverId =
                                        trackId.isNotEmpty ? trackId : null;
                                  }

                                  final customCover = RemoteArtworkWidget(
                                    server: widget.server,
                                    password: widget.password,
                                    coverArtId: coverId,
                                    size: 200,
                                    width: double.infinity,
                                    height: double.infinity,
                                    borderRadius: BorderRadius.zero,
                                  );

                                  final trailing = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        iconSize: 20,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        icon: Icon(
                                          isStarred
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          color: isStarred
                                              ? Colors.redAccent
                                              : theme.colorScheme
                                                  .onSurfaceVariant
                                                  .withValues(alpha: 0.6),
                                        ),
                                        tooltip: isStarred
                                            ? l10n.starredSongsOnly
                                            : l10n.addToFavorites,
                                        onPressed: () =>
                                            widget.onToggleStar(song),
                                      ),
                                      Builder(
                                        builder: (btnContext) => IconButton(
                                          iconSize: 20,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 32,
                                            minHeight: 32,
                                          ),
                                          icon: const Icon(
                                              Icons.more_vert_rounded),
                                          tooltip: l10n.more,
                                          onPressed: () {
                                            final renderBox = btnContext
                                                    .findRenderObject()
                                                as RenderBox?;
                                            final position = renderBox != null
                                                ? renderBox.localToGlobal(
                                                        Offset.zero) +
                                                    Offset(
                                                      renderBox.size.width / 2,
                                                      renderBox.size.height,
                                                    )
                                                : Offset.zero;
                                            showRemoteSongContextMenu(
                                              context: context,
                                              globalPosition: position,
                                              ref: ref,
                                              server: widget.server,
                                              password: widget.password,
                                              song: song,
                                              playlist: widget.songs,
                                              onMultiSelect: widget
                                                      .isSelectionMode
                                                  ? null
                                                  : () {
                                                      widget.onUpdateAnchor(
                                                          songIndex);
                                                      widget.onToggleSelection(
                                                          song.path);
                                                    },
                                              onViewArtist: () {
                                                if (song.artist != null &&
                                                    song.artist!.isNotEmpty) {
                                                  RemoteLibraryNavUtils
                                                      .openArtist(
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
                                          },
                                        ),
                                      ),
                                    ],
                                  );

                                  return SongZoomItem(
                                    key: ValueKey(song.path),
                                    song: song,
                                    metrics: metrics,
                                    isCurrent: isCurrent,
                                    isPlaying: isAudioPlaying,
                                    isSelected: isSelected,
                                    isSelectionMode: widget.isSelectionMode,
                                    selectedPaths: widget.selectedSongPaths,
                                    isHighlighted: isHighlighted,
                                    customCover: customCover,
                                    showRemoteBadge: false,
                                    trailing: trailing,
                                    trailingWidth: 72.0,
                                    onTap: () {
                                      SelectionActionHelper.handleItemTap(
                                        index: songIndex,
                                        itemKey: song.path,
                                        items: widget.songs,
                                        keySelector: (s) => s.path,
                                        isSelectionMode:
                                            widget.isSelectionMode,
                                        selectedKeys:
                                            widget.selectedSongPaths,
                                        lastAnchorIndex:
                                            widget.lastSongAnchorIndex,
                                        onUpdateAnchor: widget.onUpdateAnchor,
                                        onSetSelection: widget.onSetSelection,
                                        onToggleSelection:
                                            widget.onToggleSelection,
                                        onNormalTap: () async {
                                          final audio =
                                              ref.read(audioServiceProvider);
                                          await audio.playPlaylist(
                                            widget.songs,
                                            initialIndex: songIndex,
                                            source: PlaybackSource(
                                              type: PlaybackSourceType.playlist,
                                              id: 'remote-${widget.server.id}-songs',
                                              name: l10n.songs,
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    onLongPress: () {
                                      widget.onUpdateAnchor(songIndex);
                                      widget.onToggleSelection(song.path);
                                    },
                                    onSecondaryTapDown: (details) {
                                      if (!widget.isSelectionMode) {
                                        showRemoteSongContextMenu(
                                          context: context,
                                          globalPosition:
                                              details.globalPosition,
                                          ref: ref,
                                          server: widget.server,
                                          password: widget.password,
                                          song: song,
                                          playlist: widget.songs,
                                          onMultiSelect: widget.isSelectionMode
                                              ? null
                                              : () {
                                                  widget.onUpdateAnchor(
                                                      songIndex);
                                                  widget.onToggleSelection(
                                                      song.path);
                                                },
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
                                  );
                                },
                                childCount: widget.songs.length,
                              ),
                            ),
                          );
                        },
                      ),

                      // Loader item at bottom
                      if (widget.hasMore || widget.isLoadingMore)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                16, 20, 16, widget.bottomOffset + 24),
                            child: Center(
                              child: widget.isLoadingMore
                                  ? SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                brandColor),
                                      ),
                                    )
                                  : (widget.hasMore
                                      ? TextButton.icon(
                                          onPressed: widget.onLoadMore,
                                          icon: const Icon(
                                              Icons.expand_more_rounded),
                                          label: Text(l10n.loadMore),
                                        )
                                      : const SizedBox.shrink()),
                            ),
                          ),
                        )
                      else if (widget.bottomOffset > 0)
                        SliverToBoxAdapter(
                          child: SizedBox(height: widget.bottomOffset + 16),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

typedef NavidromeSongsToolbar = RemoteLibrarySongsToolbar;
typedef NavidromeSongsView = RemoteLibrarySongsView;
