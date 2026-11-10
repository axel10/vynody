import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/sort_options_dialog.dart';
import '../l10n/app_localizations.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/library/playlist_service.dart';
import '../utils/app_log.dart';
import '../utils/app_snack_bar.dart';
import '../utils/drop_data_utils.dart';
import '../utils/file_selector_helper.dart';
import '../utils/playlist_name.dart';
import '../widgets/drag/drag_cover.dart';
import '../widgets/drag/drag_payload.dart';
import '../widgets/drag/drag_preview_card.dart';
import '../widgets/draggable_playlist_item.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/library_action_bar.dart';
import '../widgets/library_category_header.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/playlist_context_menu.dart';
import '../widgets/playlist_zoom_item.dart';
import '../widgets/zoom_reorder_ui.dart';
import 'main_layout_riverpod.dart';
import 'playlist_detail_page.dart';

/// 播放列表网格/列表与栏头（LibraryCategoryHeader）之间的顶部呼吸空间。
/// 避免条目紧贴分类头部，并在大网格卡片 hover 放大（1.03）时顶部被截断遮挡。
const double kPlaylistGridTopInset = 16.0;

/// 播放列表总览页（第一级页面）
class PlaylistTab extends ConsumerStatefulWidget {
  const PlaylistTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
    this.onBack,
  });

  final double contentTopPadding;
  final double contentLeftPadding;
  final VoidCallback? onBack;

  @override
  ConsumerState<PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends ConsumerState<PlaylistTab>
    with SelectionStateMixin<PlaylistTab, String> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.playlist;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final ZoomReorderController _reorderController = ZoomReorderController();
  String _searchQuery = '';
  PlaylistSortField _sortField = PlaylistSortField.updatedAt;
  bool _sortAscending = false;
  String? _pushedPlaylistId;
  bool get _isDetailPushed => _pushedPlaylistId != null;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);
    _sortField = settings.playlistSortField;
    _sortAscending = settings.playlistSortAscending;

    // 检查是否有外部选中的特定歌单需要直接进入详情
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final initialId = ref.read(selectedPlaylistIdProvider);
      if (initialId != null) {
        _checkAndOpenSelectedPlaylist(initialId);
      }
    });
  }

  @override
  void dispose() {
    _reorderController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _checkAndOpenSelectedPlaylist(String playlistId) {
    if (_pushedPlaylistId == playlistId) return;
    final playlistService = ref.read(playlistServiceProvider);
    final playlist = playlistService.playlists.firstWhereOrNull(
      (p) => p.id == playlistId,
    );
    if (playlist != null) {
      _openPlaylistDetail(playlist);
    }
  }

  void _openPlaylistDetail(Playlist playlist) {
    if (!mounted) return;
    if (_pushedPlaylistId == playlist.id) return;

    final wasPushed = _isDetailPushed;
    _pushedPlaylistId = playlist.id;
    ref.read(selectedPlaylistIdProvider.notifier).set(playlist.id);

    AppLog.log(
      '[NavTrace] PlaylistTab _openPlaylistDetail: ${wasPushed ? "replacing with" : "pushing"} PlaylistDetailPage for "${playlist.name}" (id=${playlist.id})',
      mirrorToConsole: true,
    );

    final detailWidget = PlaylistDetailPage(
      playlist: playlist,
      onGoBack: () {
        ref.read(selectedPlaylistIdProvider.notifier).set(null);
        Navigator.of(context).maybePop();
      },
    );

    final routeSettings = RouteSettings(name: 'playlist_detail_${playlist.id}');

    final Route<void> route = wasPushed
        ? PageRouteBuilder<void>(
            settings: routeSettings,
            pageBuilder: (_, _, _) => detailWidget,
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          )
        : MaterialPageRoute<void>(
            settings: routeSettings,
            builder: (_) => detailWidget,
          );

    final nav = Navigator.of(context);
    final pushFuture = wasPushed ? nav.pushReplacement(route) : nav.push(route);

    pushFuture.then((_) {
      if (mounted && _pushedPlaylistId == playlist.id) {
        _pushedPlaylistId = null;
        final currentSelected = ref.read(selectedPlaylistIdProvider);
        if (currentSelected == playlist.id) {
          ref.read(selectedPlaylistIdProvider.notifier).set(null);
        }
      }
    });
  }

  Future<void> _showSortDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.read(settingsServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    final result = await showDialog<SortResult<PlaylistSortField>>(
      context: context,
      builder: (dialogContext) => SortOptionsDialog<PlaylistSortField>(
        title: l10n.sortPlaylists,
        currentField: _sortField,
        sortAscending: _sortAscending,
        options: [
          SortOptionItem(
            value: PlaylistSortField.updatedAt,
            label: l10n.sortRecentlyUpdated,
            icon: Icons.update_rounded,
          ),
          SortOptionItem(
            value: PlaylistSortField.name,
            label: l10n.playlistName,
            icon: Icons.sort_by_alpha_rounded,
          ),
          SortOptionItem(
            value: PlaylistSortField.trackCount,
            label: l10n.sortTrackCount,
            icon: Icons.numbers_rounded,
          ),
          SortOptionItem(
            value: PlaylistSortField.createdAt,
            label: l10n.sortRecentlyCreated,
            icon: Icons.calendar_today_rounded,
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _sortField = result.field;
        _sortAscending = result.sortAscending;
      });
      settings.playlistSortField = result.field;
      settings.playlistSortAscending = result.sortAscending;
      await playlistService.sortPlaylists(
        field: result.field,
        ascending: result.sortAscending,
      );
    }
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    String? errorText;
    final l10n = AppLocalizations.of(context)!;

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.createPlaylist),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.playlistName,
              hintText: l10n.enterPlaylistName,
              errorText: errorText,
            ),
            onChanged: (val) {
              if (errorText != null) {
                setDialogState(() {
                  errorText = null;
                });
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final playlistService = ref.read(playlistServiceProvider);
                  if (playlistService.playlistExists(name)) {
                    setDialogState(() {
                      errorText = l10n.playlistNameExists;
                    });
                    return;
                  }
                  final newPl = await playlistService.createPlaylist(name);
                  if (context.mounted) {
                    Navigator.pop(context);
                    _openPlaylistDetail(newPl);
                  }
                }
              },
              child: Text(l10n.confirm),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importM3uPlaylist(BuildContext context) async {
    try {
      final filePaths = await FileSelectorHelper.pickFiles(
        extensions: ['m3u', 'm3u8'],
        label: 'M3U Playlist',
      );
      if (filePaths == null || filePaths.isEmpty || !context.mounted) return;

      final playlistService = ref.read(playlistServiceProvider);
      final scannerRoots = ref.read(scannerServiceProvider).rootPaths;
      final l10n = AppLocalizations.of(context)!;
      final imported = await playlistService.importPlaylistsFromM3u(
        filePaths,
        rootPaths: scannerRoots,
      );

      if (!context.mounted) return;
      if (imported.isNotEmpty) {
        final last = imported.last;
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text(
              l10n.importPlaylistSuccess(last.name, last.songs.length),
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      final l10n = AppLocalizations.of(context)!;
      AppSnackBar.show(
        context,
        ref,
        SnackBar(content: Text(l10n.importPlaylistFailed(e.toString()))),
      );
    }
  }

  List<Playlist> _filterAndSortPlaylists(List<Playlist> rawPlaylists) {
    var list = rawPlaylists;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    // 监听侧边栏等发起的歌单详情导航请求
    ref.listen<String?>(selectedPlaylistIdProvider, (prev, next) {
      AppLog.log(
        '[NavTrace] PlaylistTab listen: prev=$prev, next=$next, isDetailPushed=$_isDetailPushed',
        mirrorToConsole: true,
      );
      if (next == null) {
        if (_isDetailPushed) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (next != prev) {
        _checkAndOpenSelectedPlaylist(next);
      }
    });

    final l10n = AppLocalizations.of(context)!;

    // 退出多选整理态时收掉可能还在进行的拖拽，避免浮层与状态机卡住。
    ref.listen(librarySelectionScopeProvider, (previous, next) {
      if (previous == LibrarySelectionScope.playlist &&
          next != LibrarySelectionScope.playlist) {
        _reorderController.cancelDrag();
      }
    });

    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;

    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final playlists = _filterAndSortPlaylists(playlistService.playlists);

    final selectedPlaylists = playlists.where((p) => isSelected(p.id)).toList();
    final selectedSongs = selectedPlaylists.expand((p) => p.songs).toList();
    final allSongs = playlists.expand((p) => p.songs).toList();

    final isCustomPlaylists = selectedKeys
        .where(
          (id) => id != 'default' && id != PlaylistService.favoritePlaylistId,
        )
        .toList();

    return Padding(
      padding: EdgeInsets.only(left: widget.contentLeftPadding),
      child: Stack(
        children: [
          FolderZoomGestureLayer(
            reorderActive: _reorderController.reorderActive,
            zoomGesturesEnabled: !isSelectionMode,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final header = LibraryCategoryHeader(
                        onBack: widget.onBack,
                        title: l10n.playlist,
                        countLabel: l10n.playlistCount(playlists.length),
                        isWide: libraryToolbarIsWide(
                          isLandscape: !isPortrait,
                          maxWidth: width,
                        ),
                        searchController: _searchController,
                        searchQuery: _searchQuery,
                        onSearchChanged: (query) {
                          setState(() {
                            _searchQuery = query;
                          });
                        },
                        onSearchCleared: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                        },
                        onSortPressed: () => _showSortDialog(context),
                        showSourceFilter: false,
                        extraActions: [
                          LibraryToolbarAction(
                            icon: Icons.add_rounded,
                            label: l10n.createPlaylist,
                            onPressed: () => _showCreatePlaylistDialog(context),
                          ),
                          LibraryToolbarAction(
                            icon: Icons.file_download_outlined,
                            label: l10n.importPlaylist,
                            onPressed: () => _importM3uPlaylist(context),
                          ),
                        ],
                      );

                final playlistSlivers = <Widget>[
                  if (playlists.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 64.0),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.queue_music_rounded,
                                  size: 64,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l10n.emptyList,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      FolderZoomSliverBuilder(
                        zoomScale: snapFolderZoomScale(zoomScale),
                        width: width,
                        builder: (context, metrics) {
                          final hPad = folderContentHorizontalPadding(
                            isPortrait: isPortrait,
                            gridMorph: metrics.gridMorph,
                          );

                          final isSortable = _searchQuery.isEmpty;
                          final hasFavoriteAt0 = playlists.isNotEmpty &&
                              playlists.first.id ==
                                  PlaylistService.favoritePlaylistId;
                          final selectedIndices = isSelectionMode
                              ? <int>{
                                  for (var i = 0; i < playlists.length; i++)
                                    if (isSelected(playlists[i].id)) i,
                                }
                              : const <int>{};

                          final contentWidth = width - 2 * hPad;

                          return SliverPadding(
                            padding: EdgeInsets.only(
                              left: hPad,
                              right: hPad,
                              top: kPlaylistGridTopInset,
                              bottom: MiniPlayerUiTuning.getListBottomPadding(
                                context,
                                hasPlayingMusic: currentMusic != null,
                                isSelectionMode: isSelectionMode,
                              ),
                            ),
                            sliver: isSortable
                                ? ZoomReorderableSliverGrid(
                                    metrics: metrics,
                                    width: contentWidth,
                                    itemCount: playlists.length,
                                    itemKeyBuilder: (index) =>
                                        ValueKey<String>(playlists[index].id),
                                    controller: _reorderController,
                                    selectedIndices: selectedIndices,
                                    lockedIndices:
                                        hasFavoriteAt0 ? const {0} : const {},
                                    minInsertIndex: hasFavoriteAt0 ? 1 : 0,
                                    showHandles: isSelectionMode,
                                    handleChild:
                                        buildZoomReorderHandle(context),
                                    previewBuilder: (context, _, count) =>
                                        buildZoomReorderPreview(
                                          context,
                                          icon: Icons.queue_music_rounded,
                                          count: count,
                                        ),
                                    directDragPreviewBuilder:
                                        (context, index, selectedIndices) {
                                      final pl = playlists[index];
                                      final l10n = AppLocalizations.of(context)!;
                                      final playlistName =
                                          localizedPlaylistName(context, pl);
                                      final isFavorite = pl.id ==
                                          PlaylistService.favoritePlaylistId;
                                      final count = selectedIndices.length;
                                      final isBatch = count > 1;

                                      if (isBatch) {
                                        return AppDraggablePreviewCard(
                                          title: playlistName,
                                          subtitle: l10n
                                              .selectedPlaylistsCount(count),
                                          defaultIcon: isFavorite
                                              ? Icons.favorite_rounded
                                              : Icons.queue_music_rounded,
                                          badgeText: '$count',
                                          count: count,
                                          isBatch: true,
                                        );
                                      }

                                      final representative =
                                          pl.songs.firstWhereOrNull(
                                                (s) =>
                                                    (s.thumbnailPath != null &&
                                                        s.thumbnailPath!
                                                            .isNotEmpty) ||
                                                    (s.artworkPath != null &&
                                                        s.artworkPath!
                                                            .isNotEmpty),
                                              ) ??
                                              pl.songs.firstOrNull;

                                      final coverPath = representative != null
                                          ? resolveDragCoverPath(
                                              thumbnailPath:
                                                  representative.thumbnailPath,
                                              artworkPath:
                                                  representative.artworkPath,
                                            )
                                          : null;

                                      final songCount = pl.songs.length;
                                      return AppDraggablePreviewCard(
                                        title: playlistName,
                                        subtitle: songCount > 0
                                            ? l10n.songsCountFormat(songCount)
                                            : null,
                                        imagePath: coverPath,
                                        defaultIcon: isFavorite
                                            ? Icons.favorite_rounded
                                            : Icons.queue_music_rounded,
                                        badgeText: songCount > 0
                                            ? l10n.songsCountFormat(songCount)
                                            : null,
                                        count: songCount > 0 ? songCount : 1,
                                      );
                                    },
                                    itemDragItemBuilder: (
                                      index,
                                      pickedIndices,
                                      localData, [
                                      request,
                                    ]) {
                                      if (request != null) {
                                        DropDataUtils.trackInternalDrag(
                                          request.session,
                                        );
                                      }
                                      final isBatch = isSelectionMode &&
                                          selectedIndices.contains(index);
                                      if (isBatch) {
                                        final batch = [
                                          for (final i in selectedIndices)
                                            playlists[i],
                                        ];
                                        return SongPathsPayload.flattened(
                                          batch.map((p) => p.songs),
                                        ).toDragItem();
                                      }
                                      final pl = playlists[index];
                                      return SongPathsPayload(
                                        paths: [
                                          for (final song in pl.songs) song.path,
                                        ],
                                      ).toDragItem();
                                    },
                                    onReorder: (draggedIndices, insertIndex) {
                                      final reordered =
                                          ZoomReorderController.applyReorder(
                                        playlists,
                                        draggedIndices,
                                        insertIndex,
                                      );
                                      settings.playlistSortField =
                                          PlaylistSortField.custom;
                                      setState(() {
                                        _sortField = PlaylistSortField.custom;
                                      });
                                      unawaited(
                                        playlistService.reorderPlaylists(
                                          reordered,
                                        ),
                                      );
                                    },
                                    itemBuilder: (context, index) {
                                      final pl = playlists[index];
                                      final isPlSelected = isSelected(pl.id);

                                      return PlaylistZoomItem(
                                        playlist: pl,
                                        metrics: metrics,
                                        index: index,
                                        isSelected: isPlSelected,
                                        isSelectionMode: isSelectionMode,
                                        enableHero: !isSelectionMode,
                                        onTap: () {
                                          handleItemTap(
                                            index: index,
                                            itemKey: pl.id,
                                            allKeys: playlists
                                                .map((p) => p.id)
                                                .toList(),
                                            onNormalTap: () {
                                              if (isSelectionMode) {
                                                toggleSelection(pl.id);
                                              } else {
                                                _openPlaylistDetail(pl);
                                              }
                                            },
                                          );
                                        },
                                        onLongPress: () {
                                          lastAnchorIndex = index;
                                          if (isSelectionMode) {
                                            toggleSelection(pl.id);
                                          } else {
                                            enterSelectionMode(pl.id);
                                          }
                                        },
                                        onSecondaryTapDown: (details) {
                                          showPlaylistContextMenu(
                                            context: context,
                                            globalPosition:
                                                details.globalPosition,
                                            ref: ref,
                                            playlist: pl,
                                            onMultiSelect: (id) =>
                                                enterSelectionMode(id),
                                            onViewDetails: () =>
                                                _openPlaylistDetail(pl),
                                          );
                                        },
                                        onPlay: () => audio.playPlaylist(
                                          pl.songs,
                                          source: PlaybackSource(
                                            type: PlaybackSourceType.playlist,
                                            id: pl.id,
                                            name: pl.name,
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                : SliverGrid(
                                    gridDelegate:
                                        SliverAnimatedZoomGridDelegate(
                                      metrics: metrics,
                                    ),
                                    delegate: SliverChildBuilderDelegate((
                                      context,
                                      index,
                                    ) {
                                      final pl = playlists[index];
                                      final isPlSelected = isSelected(pl.id);
                                      final selectedPlaylistsList =
                                          isSelectionMode
                                              ? playlists
                                                  .where(
                                                    (p) => isSelected(p.id),
                                                  )
                                                  .toList()
                                              : null;

                                      return DraggablePlaylistItem(
                                        playlist: pl,
                                        isSelectionMode: isSelectionMode,
                                        isSelected: isPlSelected,
                                        selectedPlaylists:
                                            selectedPlaylistsList,
                                        child: PlaylistZoomItem(
                                          playlist: pl,
                                          metrics: metrics,
                                          index: index,
                                          isSelected: isPlSelected,
                                          isSelectionMode: isSelectionMode,
                                          enableHero: true,
                                          onTap: () {
                                            handleItemTap(
                                              index: index,
                                              itemKey: pl.id,
                                              allKeys: playlists
                                                  .map((p) => p.id)
                                                  .toList(),
                                              onNormalTap: () =>
                                                  _openPlaylistDetail(pl),
                                            );
                                          },
                                          onLongPress: () {
                                            lastAnchorIndex = index;
                                            if (isSelectionMode) {
                                              toggleSelection(pl.id);
                                            } else {
                                              enterSelectionMode(pl.id);
                                            }
                                          },
                                          onSecondaryTapDown: (details) {
                                            if (!isSelectionMode) {
                                              showPlaylistContextMenu(
                                                context: context,
                                                globalPosition:
                                                    details.globalPosition,
                                                ref: ref,
                                                playlist: pl,
                                                onMultiSelect: (id) =>
                                                    enterSelectionMode(id),
                                                onViewDetails: () =>
                                                    _openPlaylistDetail(pl),
                                              );
                                            }
                                          },
                                          onPlay: () => audio.playPlaylist(
                                            pl.songs,
                                            source: PlaybackSource(
                                              type: PlaybackSourceType.playlist,
                                              id: pl.id,
                                              name: pl.name,
                                            ),
                                          ),
                                        ),
                                      );
                                    }, childCount: playlists.length),
                                  ),
                          );
                        },
                      ),
                ];

                return isPortrait
                    ? CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          if (widget.contentTopPadding > 0)
                            SliverToBoxAdapter(
                              child: SizedBox(height: widget.contentTopPadding),
                            ),
                          SliverToBoxAdapter(child: header),
                          ...playlistSlivers,
                        ],
                      )
                    : Column(
                        children: [
                          if (widget.contentTopPadding > 0)
                            SizedBox(height: widget.contentTopPadding),
                          header,
                          Expanded(
                            child: CustomScrollView(
                              controller: _scrollController,
                              slivers: playlistSlivers,
                            ),
                          ),
                        ],
                      );
              },
            ),
          ),
          AnimatedSelectionPanel(
            isVisible: isSelectionMode,
            child: LibrarySelectionPanel(
              key: const ValueKey('playlist-batch-selection-panel'),
              selectedSongs: selectedSongs,
              allSongs: allSongs,
              title: l10n.selectedPlaylistsCount(selectedKeys.length),
              // 本页多选的对象是歌单，不是歌单里的歌。面板默认用
              // selectedSongs.isEmpty 反推「有没有选中东西」，遇到空歌单就会
              // 误判成「什么都没选」，把删除按钮灰掉。这里改用真实的选择集合。
              isSelectionEmpty: selectedKeys.isEmpty,
              // 全选态和「有没有可选歌单」同理：歌单之间会大量共用同一批歌曲，
              // 拿歌曲平铺数反推既会把空歌单判成没得选，也会在只选了
              // 「包含全部歌曲的那个歌单」时误显示成已全选。
              isAllSelected: playlists.isNotEmpty &&
                  selectedKeys.length == playlists.length,
              hasSelectableItems: playlists.isNotEmpty,
              onToggleSelectAll: () =>
                  toggleSelectAll(playlists.map((p) => p.id)),
              onCancel: () {
                _reorderController.cancelDrag();
                cancelSelection();
              },
              deleteLabel: l10n.deletePlaylists,
              onDelete: isCustomPlaylists.isNotEmpty
                  ? () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l10n.deletePlaylists),
                          content: Text(
                            l10n.confirmDeletePlaylists(
                              isCustomPlaylists.length,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l10n.cancel),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onError,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l10n.delete),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        for (final id in isCustomPlaylists) {
                          await playlistService.deletePlaylist(id);
                        }
                        cancelSelection();
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
