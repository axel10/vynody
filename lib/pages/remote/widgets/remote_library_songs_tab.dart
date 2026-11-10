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
import '../../../widgets/library_action_bar.dart';
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
  final bool starredOnly;
  final ValueChanged<bool> onToggleStarredOnly;
  final VoidCallback onSortPressed;

  /// 播放与下载的实现在 [RemoteLibrarySongsView] 里（要读当前曲目列表与
  /// 页面 context），由 View 在构建页头时通过 [copyWith] 注入。
  final VoidCallback? onPlayAll;
  final VoidCallback? onShufflePlay;
  final VoidCallback? onDownloadAll;
  final String? countLabel;

  const RemoteLibrarySongsToolbar({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.starredOnly,
    required this.onToggleStarredOnly,
    required this.onSortPressed,
    this.onPlayAll,
    this.onShufflePlay,
    this.onDownloadAll,
    this.countLabel,
  });

  RemoteLibrarySongsToolbar copyWith({
    VoidCallback? onPlayAll,
    VoidCallback? onShufflePlay,
    VoidCallback? onDownloadAll,
    String? countLabel,
  }) {
    return RemoteLibrarySongsToolbar(
      key: key,
      searchController: searchController,
      searchFocusNode: searchFocusNode,
      searchQuery: searchQuery,
      onSearchChanged: onSearchChanged,
      onClearSearch: onClearSearch,
      starredOnly: starredOnly,
      onToggleStarredOnly: onToggleStarredOnly,
      onSortPressed: onSortPressed,
      onPlayAll: onPlayAll ?? this.onPlayAll,
      onShufflePlay: onShufflePlay ?? this.onShufflePlay,
      onDownloadAll: onDownloadAll ?? this.onDownloadAll,
      countLabel: countLabel ?? this.countLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RemoteLibraryActionBar(
      searchController: searchController,
      searchFocusNode: searchFocusNode,
      searchQuery: searchQuery,
      searchHintText: l10n.filterSongs,
      onSearchChanged: onSearchChanged,
      onSearchCleared: onClearSearch,
      onPlayAll: onPlayAll,
      onShufflePlay: onShufflePlay,
      countLabel: countLabel,
      actions: [
        remoteStarAction(
          active: starredOnly,
          label: l10n.starredSongsOnly,
          onToggle: onToggleStarredOnly,
        ),
        LibraryToolbarAction(
          icon: Icons.download_rounded,
          label: l10n.downloadAllTracks,
          onPressed: onDownloadAll,
        ),
        LibraryToolbarAction(
          icon: Icons.sort_rounded,
          label: l10n.sort,
          onPressed: onSortPressed,
        ),
        // 视图档位：横屏平铺、竖屏进「更多」。此前竖屏直接隐藏，只能捏合。
        remoteZoomAction(label: l10n.listView, scope: LibraryZoomScope.song),
      ],
    );
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

  Widget _buildHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalDurationStr = _formatTotalDuration(widget.songs);
    final countLabel = totalDurationStr.isNotEmpty
        ? '${l10n.trackCountShort(widget.songs.length)} · $totalDurationStr'
        : l10n.trackCountShort(widget.songs.length);

    // 顶部只保留一行：搜索 / 播放 / 其余动作的顺序与折叠全部由
    // LibraryActionBar 决定。播放与下载的回调实现在本 View，注入给外层
    // 构造的 toolbar（同一位置更新 widget，搜索展开态由 State 自己保留）。
    return widget.toolbar?.copyWith(
          onPlayAll: () => _playAll(),
          onShufflePlay: () => _playAll(shuffle: true),
          onDownloadAll: _downloadAll,
          countLabel: countLabel,
        ) ??
        const SizedBox.shrink();
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

    // 顶部动作行与下方曲目网格同宽：歌单 tab 已经去掉 1080 单列上限，
    // 这里也不能再锁 kSingleColumnContentMaxWidth，否则宽窗口下顶部明显比
    // 其它 tab 窄一截；左右内边距与曲目行共用 [kGridHorizontalPadding]，
    // 且**与缩放档位无关** —— 跟 gridMorph 走的话切到列表视图两侧会从 16
    // 缩到 8，顶部与曲目一起「变宽」，还会比其它 tab 宽出一截。
    final songZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.songZoomScale),
    );

    final headerSliver = SliverRemoteContentConstraint(
      maxWidth: kFolderPageMaxWidth,
      padding: const EdgeInsets.fromLTRB(
        kGridHorizontalPadding,
        6,
        kGridHorizontalPadding,
        8,
      ),
      child: _buildHeader(context),
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
                          return SliverPadding(
                            // 与顶部动作行同源、且不随档位变化。
                            padding: const EdgeInsets.symmetric(
                              horizontal: kGridHorizontalPadding,
                            ),
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
