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
import '../utils/file_selector_helper.dart';
import '../widgets/draggable_playlist_item.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/library_category_header.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/playlist_context_menu.dart';
import '../widgets/playlist_zoom_item.dart';
import 'main_layout_riverpod.dart';
import 'playlist_detail_page.dart';

/// 播放列表总览页（第一级页面）
class PlaylistTab extends ConsumerStatefulWidget {
  const PlaylistTab({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  ConsumerState<PlaylistTab> createState() => _PlaylistTabState();
}

class _PlaylistTabState extends ConsumerState<PlaylistTab>
    with SelectionStateMixin<PlaylistTab, String> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.playlist;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    if (widget.contentTopPadding > 0)
                      SliverToBoxAdapter(
                        child: SizedBox(height: widget.contentTopPadding),
                      ),
                    SliverToBoxAdapter(
                      child: LibraryCategoryHeader(
                        title: l10n.playlist,
                        countLabel: l10n.playlistCount(playlists.length),
                        isWide: !isPortrait,
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
                          IconButton(
                            tooltip: l10n.createPlaylist,
                            icon: const Icon(Icons.add_rounded),
                            onPressed: () => _showCreatePlaylistDialog(context),
                          ),
                          IconButton(
                            tooltip: l10n.importPlaylist,
                            icon: const Icon(Icons.file_download_outlined),
                            onPressed: () => _importM3uPlaylist(context),
                          ),
                          if (playlistService.playlists.any(
                            (p) =>
                                p.id != 'default' &&
                                p.id != PlaylistService.favoritePlaylistId,
                          ))
                            IconButton(
                              tooltip: l10n.multiSelect,
                              icon: const Icon(Icons.checklist_rounded),
                              onPressed: () {
                                final firstCustom = playlistService.playlists
                                    .firstWhereOrNull(
                                      (p) =>
                                          p.id != 'default' &&
                                          p.id !=
                                              PlaylistService
                                                  .favoritePlaylistId,
                                    );
                                if (firstCustom != null) {
                                  enterSelectionMode(firstCustom.id);
                                }
                              },
                            ),
                        ],
                      ),
                    ),
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

                          return SliverPadding(
                            padding: EdgeInsets.only(
                              left: hPad,
                              right: hPad,
                              bottom: MiniPlayerUiTuning.getListBottomPadding(
                                context,
                                hasPlayingMusic: currentMusic != null,
                                isSelectionMode: isSelectionMode,
                              ),
                            ),
                            sliver: SliverGrid(
                              gridDelegate: SliverAnimatedZoomGridDelegate(
                                metrics: metrics,
                              ),
                              delegate: SliverChildBuilderDelegate((
                                context,
                                index,
                              ) {
                                final pl = playlists[index];
                                final isPlSelected = isSelected(pl.id);
                                final selectedPlaylistsList = isSelectionMode
                                    ? playlists
                                          .where((p) => isSelected(p.id))
                                          .toList()
                                    : null;

                                return DraggablePlaylistItem(
                                  playlist: pl,
                                  isSelectionMode: isSelectionMode,
                                  isSelected: isPlSelected,
                                  selectedPlaylists: selectedPlaylistsList,
                                  child: PlaylistZoomItem(
                                    playlist: pl,
                                    metrics: metrics,
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
              onToggleSelectAll: () =>
                  toggleSelectAll(playlists.map((p) => p.id)),
              onCancel: cancelSelection,
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
