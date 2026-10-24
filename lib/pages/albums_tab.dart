import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'cover_flow/album_3d_cover_flow_view.dart';
import 'cover_flow/floating_cover_flow_toolbar.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import '../widgets/album_zoom_item.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/library_zoom_popover.dart';
import 'album_detail_page.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_selection_panel.dart';
import '../models/music_file.dart';
import '../dialogs/sort_options_dialog.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'main_layout_riverpod.dart';
import '../utils/app_log.dart';
import '../widgets/draggable_album_item.dart';
import '../widgets/album_context_menu.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/library_category_header.dart';

class AlbumsTab extends ConsumerStatefulWidget {
  const AlbumsTab({
    super.key,
    this.initial3DView = false,
    this.initial3DIndex = 0,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  final bool initial3DView;
  final int initial3DIndex;
  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  ConsumerState<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends ConsumerState<AlbumsTab>
    with SelectionStateMixin<AlbumsTab, String> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.album;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  AlbumSortField _sortField = AlbumSortField.artist;
  bool _sortAscending = true;
  late bool _is3DView;
  bool _isShuffledMode = false;
  List<AlbumSummary>? _shuffledAlbums;
  final GlobalKey<Album3DCoverFlowViewState> _coverFlowKey = GlobalKey();

  List<AlbumSummary>? _lastRawAlbums;
  String? _lastSearchQuery;
  AlbumSortField? _lastSortField;
  bool? _lastSortAscending;
  bool? _lastIsShuffledMode;
  List<AlbumSummary>? _cachedFilteredAlbums;
  List<AlbumSummary>? _cachedKnownAlbums;
  List<AlbumSummary>? _cachedUnknownAlbums;
  late final IsAlbum3DViewActiveNotifier _isAlbum3DNotifier;

  @override
  void initState() {
    super.initState();
    _isAlbum3DNotifier = ref.read(isAlbum3DViewActiveProvider.notifier);
    _is3DView = widget.initial3DView;
    final settings = ref.read(settingsServiceProvider);
    _sortField = settings.albumSortField;
    _sortAscending = settings.albumSortAscending;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _isAlbum3DNotifier.set(_is3DView);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _isAlbum3DNotifier.set(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isAlbum3DViewActiveProvider, (prev, next) {
      if (_is3DView != next) {
        setState(() {
          _is3DView = next;
        });
      }
    });

    final albumsAsync = ref.watch(albumLibraryProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    // 只认专辑自己的档位：目录页调大卡片不应该连带改变这里。
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );
    final l10n = AppLocalizations.of(context)!;

    final albums = albumsAsync.value ?? _lastRawAlbums;
    if (albums == null) {
      if (albumsAsync.isLoading) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      }
      if (albumsAsync.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              albumsAsync.error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
        if (!identical(_lastRawAlbums, albums) ||
            _lastSearchQuery != _searchQuery ||
            _lastSortField != _sortField ||
            _lastSortAscending != _sortAscending ||
            _lastIsShuffledMode != _isShuffledMode) {
          if (_lastSortField != _sortField || _lastSortAscending != _sortAscending) {
            _isShuffledMode = false;
            _shuffledAlbums = null;
          }
          _lastRawAlbums = albums;
          _lastSearchQuery = _searchQuery;
          _lastSortField = _sortField;
          _lastSortAscending = _sortAscending;
          _lastIsShuffledMode = _isShuffledMode;
          _cachedFilteredAlbums = _filterAndSortAlbums(albums);
          _cachedKnownAlbums = _cachedFilteredAlbums!
              .where((album) => !album.isUnknownAlbum)
              .toList(growable: false);
          _cachedUnknownAlbums = _cachedFilteredAlbums!
              .where((album) => album.isUnknownAlbum)
              .toList(growable: false);
        }
        final visibleAlbums = _cachedFilteredAlbums!;
        final knownAlbums = _cachedKnownAlbums!;
        final unknownAlbums = _cachedUnknownAlbums!;

        final List<MusicFile> selectedSongs;
        final List<MusicFile> allSongs;

        if (isSelectionMode) {
          selectedSongs = <MusicFile>[];
          final seenSelectedPaths = <String>{};
          for (final album in visibleAlbums) {
            if (isSelected(album.id)) {
              for (final song in album.songs) {
                if (seenSelectedPaths.add(song.path)) {
                  selectedSongs.add(song);
                }
              }
            }
          }

          allSongs = <MusicFile>[];
          final seenAllPaths = <String>{};
          for (final album in visibleAlbums) {
            for (final song in album.songs) {
              if (seenAllPaths.add(song.path)) {
                allSongs.add(song);
              }
            }
          }
        } else {
          selectedSongs = const [];
          allSongs = const [];
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 780;
            final availableWidth = math.max(0.0, constraints.maxWidth - widget.contentLeftPadding);
            final contentWidth = math.min(availableWidth, kFolderPageMaxWidth);

            final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
            final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
            final bool isCoverFlowImmersive = isLandscape && _is3DView;

                // 多选面板高度：3D cover flow 用单行精简版，普通网格列表用完整版
                final selectionPanelHeight = _is3DView ? 120.0 : 220.0;
                final bottomPadding =
                    120.0 + (isSelectionMode ? selectionPanelHeight : 0.0);
                final bottomOffset = isCoverFlowImmersive
                    ? (isSelectionMode ? 100.0 : 0.0)
                    : MiniPlayerUiTuning.getListBottomPadding(
                        context,
                        hasPlayingMusic: currentMusic != null,
                        isSelectionMode: isSelectionMode,
                        selectionPanelHeight: selectionPanelHeight,
                      );

                final toolbar = LibraryCategoryHeader(
                  title: l10n.albums,
                  countLabel: l10n.albumCount(visibleAlbums.length),
                  isWide: isWide,
                  searchController: _searchController,
                  searchQuery: _searchQuery,
                  searchHintText: l10n.searchAlbums,
                  onSearchChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim();
                    });
                  },
                  onSearchCleared: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  onPlayAll: () => _playAllVisible(visibleAlbums, shuffle: false),
                  onShufflePlay: () => _playAllVisible(visibleAlbums, shuffle: true),
                  onSortPressed: () => _openSortDialog(context, l10n),
                  extraActions: [
                    if (_is3DView)
                      IconButton(
                        tooltip: l10n.shuffleAlbumOrder,
                        onPressed: () => _onShufflePressed(albums),
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                    if (!_is3DView) const LibraryZoomButton(scope: LibraryZoomScope.album),
                    IconButton(
                      tooltip: _is3DView ? l10n.gridView : l10n.threeDView,
                      onPressed: () {
                        setState(() {
                          _is3DView = !_is3DView;
                        });
                        ref.read(isAlbum3DViewActiveProvider.notifier).set(_is3DView);
                      },
                      icon: Icon(
                        _is3DView ? Icons.grid_view_rounded : Icons.view_carousel_rounded,
                      ),
                    ),
                  ],
                  backgroundColor: _is3DView ? Colors.transparent : null,
                  hasBorder: !_is3DView,
                );

                final Widget mainContent = AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  layoutBuilder: (currentChild, previousChildren) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ...previousChildren,
                        ?currentChild,
                      ],
                    );
                  },
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _is3DView
                      ? KeyedSubtree(
                          key: const ValueKey('album_3d_cover_flow_view'),
                          child: isCoverFlowImmersive
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fill(
                                      child: visibleAlbums.isEmpty
                                          ? Center(
                                              child: Text(
                                                l10n.noAlbums,
                                                style: Theme.of(context).textTheme.titleMedium,
                                              ),
                                            )
                                          : Album3DCoverFlowView(
                                              key: _coverFlowKey,
                                              albums: visibleAlbums,
                                              initialIndex: widget.initial3DIndex,
                                              isSelectionMode: isSelectionMode,
                                              selectedAlbumIds: selectedKeys,
                                              bottomOffset: bottomOffset,
                                              isHeroEnabled: _is3DView,
                                              onToggleSelection: toggleSelection,
                                              onEnterSelectionMode: enterSelectionMode,
                                              onExit3DView: () {
                                                setState(() {
                                                  _is3DView = false;
                                                });
                                                ref.read(isAlbum3DViewActiveProvider.notifier).set(false);
                                              },
                                            ),
                                    ),
                                    Positioned(
                                      top: getTitleBarTopPadding(
                                        context,
                                        defaultWindowPadding: 36.0,
                                        statusBarOffset: 8.0,
                                      ),
                                      left: isDesktop ? 80 : 16,
                                      right: isDesktop ? 80 : 16,
                                      child: FloatingCoverFlowToolbar(
                                        albumCount: visibleAlbums.length,
                                        sortField: _sortField,
                                        sortAscending: _sortAscending,
                                        searchController: _searchController,
                                        searchQuery: _searchQuery,
                                        isDesktop: isDesktop,
                                        onSearchChanged: (value) {
                                          setState(() {
                                            _searchQuery = value.trim();
                                          });
                                        },
                                        onSearchCleared: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                        onViewModeToggled: () {
                                          setState(() {
                                            _is3DView = !_is3DView;
                                          });
                                          ref.read(isAlbum3DViewActiveProvider.notifier).set(_is3DView);
                                        },
                                        onShufflePressed: () => _onShufflePressed(albums),
                                        onSortChanged: (field, sortAscending) {
                                          setState(() {
                                            _sortField = field;
                                            _sortAscending = sortAscending;
                                            _isShuffledMode = false;
                                            _shuffledAlbums = null;
                                          });
                                          final settings = ref.read(settingsServiceProvider);
                                          settings.albumSortField = field;
                                          settings.albumSortAscending = sortAscending;
                                        },
                                      ),
                                    ),
                                  ],
                                )
                              : Padding(
                                  padding: EdgeInsets.only(
                                    top: widget.contentTopPadding,
                                    left: widget.contentLeftPadding,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: kFolderPageMaxWidth),
                                      child: Column(
                                    children: [
                                      toolbar,
                                      Expanded(
                                        child: visibleAlbums.isEmpty
                                            ? Center(
                                                child: Text(
                                                  l10n.noAlbums,
                                                  style: Theme.of(context).textTheme.titleMedium,
                                                ),
                                              )
                                            : Album3DCoverFlowView(
                                                key: _coverFlowKey,
                                                albums: visibleAlbums,
                                                initialIndex: widget.initial3DIndex,
                                                isSelectionMode: isSelectionMode,
                                                selectedAlbumIds: selectedKeys,
                                                bottomOffset: bottomOffset,
                                                isHeroEnabled: _is3DView,
                                                onToggleSelection: toggleSelection,
                                                onEnterSelectionMode: enterSelectionMode,
                                                onAlbumContextMenu: (album, position) =>
                                                    showAlbumContextMenu(
                                                      context: context,
                                                      globalPosition: position,
                                                      ref: ref,
                                                      album: album,
                                                      onMultiSelect: (id) => enterSelectionMode(id),
                                                    ),
                                                onExit3DView: () {
                                                  setState(() {
                                                    _is3DView = false;
                                                  });
                                                  ref.read(isAlbum3DViewActiveProvider.notifier).set(false);
                                                },
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        )
                      : Padding(
                          padding: EdgeInsets.only(
                            left: widget.contentLeftPadding,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: kFolderPageMaxWidth),
                              child: FolderZoomGestureLayer(
                                scope: LibraryZoomScope.album,
                                child: CustomScrollView(
                                  key: const ValueKey('album_grid_view'),
                                  controller: _scrollController,
                                  // 预构建范围只留约半屏：更大的 cacheExtent 会让
                                  // 几十张卡片在滚动中成批 initState（同步 stat +
                                  // 缩略图解析排队），收益只是少一点占位图，不值。
                                  scrollCacheExtent:
                                      const ScrollCacheExtent.viewport(0.4),
                                  slivers: [
                                      if (widget.contentTopPadding > 0)
                                        SliverToBoxAdapter(
                                          child: SizedBox(
                                            height: widget.contentTopPadding,
                                          ),
                                        ),
                                      SliverToBoxAdapter(child: toolbar),
                                      if (visibleAlbums.isEmpty)
                                        SliverFillRemaining(
                                          hasScrollBody: false,
                                          child: Center(
                                            child: Text(
                                              l10n.noAlbums,
                                              style: Theme.of(context).textTheme.titleMedium,
                                            ),
                                          ),
                                        )
                                      else ...[
                                        if (knownAlbums.isNotEmpty) ...[
                                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                                          ..._albumSectionSlivers(
                                            albums: knownAlbums,
                                            zoomScale: albumZoomScale,
                                            width: contentWidth,
                                            isSelectionMode: isSelectionMode,
                                            isHeroEnabled: !_is3DView,
                                          ),
                                        ],
                                        if (knownAlbums.isNotEmpty && unknownAlbums.isNotEmpty)
                                          const SliverToBoxAdapter(child: SizedBox(height: 24)),
                                        if (unknownAlbums.isNotEmpty)
                                          ..._albumSectionSlivers(
                                            albums: unknownAlbums,
                                            zoomScale: albumZoomScale,
                                            width: contentWidth,
                                            isSelectionMode: isSelectionMode,
                                            isHeroEnabled: !_is3DView,
                                          ),
                                        SliverToBoxAdapter(child: SizedBox(height: bottomPadding)),
                                      ],
                                    ],
                                  ),
                              ),
                              ),
                            ),
                          ),
                  );

                return Stack(
                  children: [
                    Positioned.fill(child: mainContent),
                    AnimatedSelectionPanel(
                      isVisible: isSelectionMode,
                      child: LibrarySelectionPanel(
                        key: const ValueKey('album-selection-panel'),
                        selectedSongs: selectedSongs,
                        allSongs: allSongs,
                        title: l10n.selectedAlbumsCount(selectedCount),
                        hideSecondaryActions: _is3DView,
                        onToggleSelectAll: () =>
                            toggleSelectAll(visibleAlbums.map((a) => a.id)),
                        onCancel: cancelSelection,
                      ),
                    ),
                  ],
                );
              },
            );
  }

  void _playAllVisible(List<AlbumSummary> visibleAlbums, {bool shuffle = false}) {
    final songs = <MusicFile>[];
    final seen = <String>{};
    for (final album in visibleAlbums) {
      for (final song in album.songs) {
        if (seen.add(song.path)) {
          songs.add(song);
        }
      }
    }
    if (songs.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final playlist = shuffle ? (List<MusicFile>.of(songs)..shuffle()) : songs;
    ref.read(audioServiceProvider).playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.album,
        id: shuffle ? 'all_albums_shuffled' : 'all_albums',
        name: l10n.albums,
      ),
    );
  }

  Future<void> _openSortDialog(BuildContext context, AppLocalizations l10n) async {
    final result = await showDialog<SortResult<AlbumSortField>>(
      context: context,
      builder: (context) => SortOptionsDialog<AlbumSortField>(
        title: l10n.albumSort,
        currentField: _sortField,
        sortAscending: _sortAscending,
        options: [
          SortOptionItem(
            value: AlbumSortField.artist,
            label: l10n.sortArtistAsc,
            icon: Icons.mic_rounded,
          ),
          SortOptionItem(
            value: AlbumSortField.title,
            label: l10n.sortTitleAsc,
            icon: Icons.album_rounded,
          ),
          SortOptionItem(
            value: AlbumSortField.trackCount,
            label: l10n.sortTrackCount,
            icon: Icons.format_list_numbered_rounded,
          ),
          SortOptionItem(
            value: AlbumSortField.duration,
            label: l10n.sortDuration,
            icon: Icons.access_time_rounded,
          ),
          SortOptionItem(
            value: AlbumSortField.recentAdded,
            label: l10n.sortRecentAdded,
            icon: Icons.add_circle_outline_rounded,
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() {
        _sortField = result.field;
        _sortAscending = result.sortAscending;
        _isShuffledMode = false;
        _shuffledAlbums = null;
      });
      final settings = ref.read(settingsServiceProvider);
      settings.albumSortField = result.field;
      settings.albumSortAscending = result.sortAscending;
    }
  }

  void _onShufflePressed(List<AlbumSummary> albums) {
    final coverFlowState = _coverFlowKey.currentState;
    void doShuffle() {
      setState(() {
        _isShuffledMode = true;
        _lastIsShuffledMode = true;
        final baseFiltered = _filterAndSortAlbums(albums, ignoreShuffle: true);
        _shuffledAlbums = List<AlbumSummary>.from(baseFiltered)..shuffle();
        _cachedFilteredAlbums = _shuffledAlbums;
        _cachedKnownAlbums = _cachedFilteredAlbums!
            .where((album) => !album.isUnknownAlbum)
            .toList(growable: false);
        _cachedUnknownAlbums = _cachedFilteredAlbums!
            .where((album) => album.isUnknownAlbum)
            .toList(growable: false);
      });
    }

    if (coverFlowState != null) {
      coverFlowState.animateShuffle(doShuffle);
    } else {
      doShuffle();
    }
  }

  List<AlbumSummary> _filterAndSortAlbums(
    List<AlbumSummary> albums, {
    bool ignoreShuffle = false,
  }) {
    if (_isShuffledMode && !ignoreShuffle && _shuffledAlbums != null) {
      if (_searchQuery.isEmpty) {
        return _shuffledAlbums!;
      } else {
        final query = _searchQuery.toLowerCase();
        return _shuffledAlbums!.where((album) {
          return album.title.toLowerCase().contains(query) ||
              album.artist.toLowerCase().contains(query);
        }).toList();
      }
    }

    final query = _searchQuery.toLowerCase();
    final filtered = albums.where((album) {
      if (query.isEmpty) return true;
      return album.title.toLowerCase().contains(query) ||
          album.artist.toLowerCase().contains(query);
    }).toList();

    filtered.sort((a, b) {
      final compare = switch (_sortField) {
        AlbumSortField.artist => a.artist.toLowerCase().compareTo(
          b.artist.toLowerCase(),
        ),
        AlbumSortField.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        AlbumSortField.trackCount => a.trackCount.compareTo(b.trackCount),
        AlbumSortField.duration => a.totalDurationMillis.compareTo(
          b.totalDurationMillis,
        ),
        AlbumSortField.recentAdded => a.latestTimestampMillis.compareTo(
          b.latestTimestampMillis,
        ),
      };
      if (compare != 0) {
        return _sortAscending ? compare : -compare;
      }
      final fallback = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return _sortAscending ? fallback : -fallback;
    });
    return filtered;
  }

  /// 一屏专辑按当前档位渲染：列表档位是「封面在左 + 标题/艺人」，网格档位按档位
  /// 决定列数与卡片宽度，两者之间的过渡动画由 [FolderZoomSliverBuilder] 负责。
  ///
  /// [width] 是 sliver 实际拿到的外层宽度（已扣掉 `contentLeftPadding` 与
  /// `kFolderPageMaxWidth` 的钳制），内边距由 [folderContentHorizontalPadding] 内部扣除。
  List<Widget> _albumSectionSlivers({
    required List<AlbumSummary> albums,
    required double zoomScale,
    required double width,
    required bool isSelectionMode,
    bool isHeroEnabled = true,
  }) {
    final audio = ref.read(audioServiceProvider);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return [
      FolderZoomSliverBuilder(
        zoomScale: snapFolderZoomScale(zoomScale),
        width: width,
        builder: (context, metrics) {
          final hPad = folderContentHorizontalPadding(
            isPortrait: isPortrait,
            gridMorph: metrics.gridMorph,
          );

          return SliverPadding(
            padding: EdgeInsets.only(left: hPad, right: hPad),
            sliver: SliverGrid(
              gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final album = albums[index];
                  final isSelected = this.isSelected(album.id);

                  return DraggableAlbumItem(
                    album: album,
                    enabled: !isSelectionMode,
                    child: AlbumZoomItem(
                      album: album,
                      metrics: metrics,
                      isSelected: isSelected,
                      isSelectionMode: isSelectionMode,
                      enableHero: isHeroEnabled,
                      onTap: () {
                        handleItemTap(
                          index: index,
                          itemKey: album.id,
                          allKeys: albums.map((a) => a.id).toList(),
                          onNormalTap: () => _openAlbumDetail(album),
                        );
                      },
                      onLongPress: () {
                        lastAnchorIndex = index;
                        if (isSelectionMode) {
                          toggleSelection(album.id);
                        } else {
                          enterSelectionMode(album.id);
                        }
                      },
                      onSecondaryTapDown: (details) {
                        if (!isSelectionMode) {
                          showAlbumContextMenu(
                            context: context,
                            globalPosition: details.globalPosition,
                            ref: ref,
                            album: album,
                            onMultiSelect: (id) => enterSelectionMode(id),
                          );
                        }
                      },
                      onPlay: () => audio.playPlaylist(
                        album.songs,
                        source: PlaybackSource(
                          type: PlaybackSourceType.album,
                          id: album.id,
                          name: album.title,
                        ),
                      ),
                    ),
                  );
                },
                childCount: albums.length,
              ),
            ),
          );
        },
      ),
    ];
  }

  void _openAlbumDetail(AlbumSummary album) {
    AppLog.log(
      '[NavTrace] AlbumsTab _openAlbumDetail: pushing AlbumDetailPage for album="${album.title}" (id=${album.id})',
      mirrorToConsole: true,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: 'album_detail_${album.id}'),
        builder: (_) => AlbumDetailPage(album: album),
      ),
    );
  }
}


