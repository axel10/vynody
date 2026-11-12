import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/platform/right_queue_drawer_controller.dart';
import '../player/scanner/scanner_path_utils.dart';
import '../utils/folder_helpers.dart';
import '../utils/song_context_menu_utils.dart';
import '../utils/song_locator_helper.dart';
import '../widgets/folder_content_slivers.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/library_large_title.dart';
import '../widgets/library_search_field.dart';
import '../widgets/playback_ui_tuning.dart';

/// 本地目录独立搜索页。
///
/// 当在具体子目录下点击搜索时，传入 [currentFolder]，搜索结果将自动分为：
/// 1. 当前目录及子目录下的匹配结果；
/// 2. 全局其他本地根目录下的匹配结果。
/// 若在根目录点击搜索（[currentFolder] 为 null），则直接呈现全局匹配的文件夹与歌曲。
class FolderSearchPage extends ConsumerStatefulWidget {
  const FolderSearchPage({
    super.key,
    this.currentFolder,
    this.contentTopPadding,
    this.contentLeftPadding,
  });

  final MusicFolder? currentFolder;
  final double? contentTopPadding;
  final double? contentLeftPadding;

  @override
  ConsumerState<FolderSearchPage> createState() => _FolderSearchPageState();
}

class _FolderSearchPageState extends ConsumerState<FolderSearchPage> {
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  String _query = '';
  bool _isSearching = false;

  // 搜索结果分类存储
  List<MusicFolder> _currentFolderFolders = const [];
  List<MusicFile> _currentFolderSongs = const [];

  List<MusicFolder> _globalFolders = const [];
  List<MusicFile> _globalSongs = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final trimmed = raw.trim();
    if (trimmed == _query) return;

    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _isSearching = false;
        _currentFolderFolders = const [];
        _currentFolderSongs = const [];
        _globalFolders = const [];
        _globalSongs = const [];
      });
      return;
    }

    setState(() {
      _query = trimmed;
      _isSearching = true;
    });

    _debounce = Timer(_debounceDuration, () => _performSearch(trimmed));
  }

  void _onQueryCleared() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _isSearching = false;
      _currentFolderFolders = const [];
      _currentFolderSongs = const [];
      _globalFolders = const [];
      _globalSongs = const [];
    });
  }

  Future<void> _performSearch(String query) async {
    final scanner = ref.read(scannerServiceProvider);
    final targetFolder = widget.currentFolder;

    try {
      if (targetFolder != null) {
        // 子目录模式：同时拉取当前目录下的歌曲、全局歌曲与文件夹
        final currentSongsFuture = scanner.searchSongs(
          query,
          folderPath: targetFolder.path,
        );
        final allSongsFuture = scanner.searchSongs(query);
        final allFoldersFuture = scanner.searchFolders(query);

        final currentSongs = await currentSongsFuture;
        final allSongs = await allSongsFuture;
        final allFolders = await allFoldersFuture;

        if (!mounted || query != _query) return;

        final targetPath = targetFolder.path;
        final globalSongs = allSongs
            .where((s) => !ScannerPathUtils.pathContains(targetPath, s.path))
            .toList(growable: false);

        final curFolders = allFolders
            .where((f) =>
                ScannerPathUtils.pathContains(targetPath, f.path) &&
                !ScannerPathUtils.pathsEqual(targetPath, f.path))
            .toList(growable: false);

        final globFolders = allFolders
            .where((f) => !ScannerPathUtils.pathContains(targetPath, f.path))
            .toList(growable: false);

        setState(() {
          _isSearching = false;
          _currentFolderSongs = currentSongs;
          _currentFolderFolders = curFolders;
          _globalSongs = globalSongs;
          _globalFolders = globFolders;
        });
      } else {
        // 根目录模式：直接进行全量检索
        final allSongsFuture = scanner.searchSongs(query);
        final allFoldersFuture = scanner.searchFolders(query);

        final allSongs = await allSongsFuture;
        final allFolders = await allFoldersFuture;

        if (!mounted || query != _query) return;

        setState(() {
          _isSearching = false;
          _currentFolderSongs = const [];
          _currentFolderFolders = const [];
          _globalSongs = allSongs;
          _globalFolders = allFolders;
        });
      }
    } catch (_) {
      if (mounted && query == _query) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _navigateToFolder(MusicFolder folder) async {
    final scanner = ref.read(scannerServiceProvider);
    final rootPath = scanner.rootPaths.firstWhereOrNull(
      (root) => ScannerPathUtils.pathContains(root, folder.path),
    );

    if (rootPath != null) {
      await scanner.loadRootFolderSongs(rootPath);
      final rootFolder = scanner.rootFolders.firstWhereOrNull(
        (r) => ScannerPathUtils.pathsEqual(r.path, rootPath),
      );
      if (rootFolder != null) {
        final foundHistory = SongLocatorHelper.findFolderHistoryByFolderPath(
          rootFolder,
          folder.path,
        );
        if (foundHistory != null && foundHistory.isNotEmpty) {
          final target = foundHistory.last;
          final history = foundHistory.sublist(0, foundHistory.length - 1);
          scanner.setNavigationState(target, history);
          if (mounted) Navigator.of(context).pop();
          return;
        }
      }
    } else if (folder.path == 'system' ||
        ScannerPathUtils.pathContains('system', folder.path)) {
      if (scanner.systemMediaFolder != null) {
        final foundHistory = SongLocatorHelper.findFolderHistoryByFolderPath(
          scanner.systemMediaFolder!,
          folder.path,
        );
        if (foundHistory != null && foundHistory.isNotEmpty) {
          final target = foundHistory.last;
          final history = foundHistory.sublist(0, foundHistory.length - 1);
          scanner.setNavigationState(target, history);
          if (mounted) Navigator.of(context).pop();
          return;
        }
      }
    }

    final history = List<MusicFolder>.from(scanner.navigationHistory);
    if (scanner.navigationCurrentFolder != null) {
      history.add(scanner.navigationCurrentFolder!);
    }
    scanner.setNavigationState(folder, history);
    if (mounted) Navigator.of(context).pop();
  }

  void _openSongMenu(MusicFile song, {Offset? globalPosition}) {
    void onPlayNext() => ref.read(audioServiceProvider).enqueueNext([song]);
    void onAddToQueue() =>
        ref.read(audioServiceProvider).appendToQueue([song]);
    Future<void> addToPlaylist() => showAddSongsToPlaylistDialog(
      context,
      ref.read(playlistServiceProvider),
      [song],
    );

    if (globalPosition == null) {
      showSongBottomSheet(
        context,
        song: song,
        songs: [song],
        onPlayNext: onPlayNext,
        onAddToQueue: onAddToQueue,
        onAddToPlaylist: addToPlaylist,
      );
      return;
    }
    showSongContextMenu(
      context,
      globalPosition,
      song: song,
      songs: [song],
      onPlayNext: onPlayNext,
      onAddToQueue: onAddToQueue,
      onAddToPlaylist: addToPlaylist,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.sizeOf(context);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final isLandscape = ref.watch(isEffectiveLandscapeProvider(size));
    final double safeTop = getTitleBarTopPadding(
      context,
      defaultWindowPadding: isLandscape ? 32.0 : 36.0,
    );
    final double topPadding = widget.contentTopPadding ??
        (isLandscape ? (safeTop + 8.0) : safeTop);
    final double leftPadding = widget.contentLeftPadding ?? 0.0;
    final horizontalPadding = folderContentHorizontalPadding(
      isPortrait: isPortrait,
      gridMorph: 0.0,
    );
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isAudioPlaying = ref.watch(audioIsPlayingProvider);
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;
    final bottomInset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
    );

    final hasCurrentResults =
        _currentFolderFolders.isNotEmpty || _currentFolderSongs.isNotEmpty;
    final hasGlobalResults =
        _globalFolders.isNotEmpty || _globalSongs.isNotEmpty;
    final hasAnyResults = hasCurrentResults || hasGlobalResults;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(left: leftPadding),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: folderPageMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding + 16,
                    horizontalPadding,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LibraryLargeTitle(title: l10n.search),
                      const SizedBox(height: 10),
                      LibrarySearchField(
                        controller: _controller,
                        focusNode: _focusNode,
                        query: _query,
                        hintText: widget.currentFolder != null
                            ? l10n.searchInFolderAndSubfolders
                            : l10n.searchFolderHint,
                        onChanged: _onQueryChanged,
                        onClear: _onQueryCleared,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !hasAnyResults
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? l10n.typeToSearch
                                : _isSearching
                                    ? l10n.searching
                                    : l10n.noMatchingResults,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisExtent = constraints.maxWidth;
                            return FolderZoomGestureLayer(
                              child: FolderZoomSliverBuilder(
                                zoomScale: snapFolderZoomScale(zoomScale),
                                width: crossAxisExtent,
                                controller: _scrollController,
                                builder: (context, metrics) {
                                  final sectionHPad =
                                      folderContentHorizontalPadding(
                                    isPortrait: isPortrait,
                                    gridMorph: metrics.gridMorph,
                                  );

                                  return CustomScrollView(
                                    controller: _scrollController,
                                    slivers: [
                                      const SliverPadding(
                                        padding: EdgeInsets.only(top: 4),
                                      ),
                                      if (widget.currentFolder != null) ...[
                                        if (hasCurrentResults) ...[
                                          SliverToBoxAdapter(
                                            child: SearchSectionHeader(
                                              title:
                                                  '${l10n.searchResultsCurrentFolder} (${widget.currentFolder!.name})',
                                              padding: EdgeInsets.symmetric(
                                                horizontal: sectionHPad,
                                                vertical: 8.0,
                                              ),
                                            ),
                                          ),
                                          if (_currentFolderFolders.isNotEmpty)
                                            FolderSubfoldersSliver(
                                              folders: _currentFolderFolders,
                                              zoomScale: zoomScale,
                                              scanner: ref.read(
                                                scannerServiceProvider,
                                              ),
                                              section: 'cur_folders',
                                              crossAxisExtent: crossAxisExtent,
                                              bottomPadding: 0.0,
                                              onNavigateTo: _navigateToFolder,
                                            ),
                                          if (_currentFolderFolders.isNotEmpty &&
                                              _currentFolderSongs.isNotEmpty) ...[
                                            const SliverToBoxAdapter(
                                              child: SizedBox(height: 12),
                                            ),
                                            SliverToBoxAdapter(
                                              child: SearchSectionHeader(
                                                title:
                                                    '${l10n.searchResultsSongs} (${_currentFolderSongs.length})',
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: sectionHPad,
                                                  vertical: 8.0,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (_currentFolderSongs.isNotEmpty)
                                            FolderSongsSliver(
                                              songs: _currentFolderSongs,
                                              zoomScale: zoomScale,
                                              currentSongPath:
                                                  currentMusic?.path,
                                              isPlaying: isAudioPlaying,
                                              section: 'cur_songs',
                                              crossAxisExtent: crossAxisExtent,
                                              topPadding: 4.0,
                                              bottomPadding: 0.0,
                                              onSongTap: (song, index) {
                                                ref
                                                    .read(audioServiceProvider)
                                                    .playPlaylist(
                                                      _currentFolderSongs,
                                                      initialIndex: index,
                                                      source: PlaybackSource(
                                                        type: PlaybackSourceType
                                                            .folder,
                                                        id: 'folder_search',
                                                        name: l10n.search,
                                                      ),
                                                    );
                                              },
                                              onSongLongPress: (song) =>
                                                  _openSongMenu(song),
                                              onSongSecondaryTapDown: (
                                                song,
                                                details,
                                              ) => _openSongMenu(
                                                song,
                                                globalPosition:
                                                    details.globalPosition,
                                              ),
                                            ),
                                          const SliverToBoxAdapter(
                                            child: SizedBox(height: 12),
                                          ),
                                        ],
                                        if (hasGlobalResults) ...[
                                          SliverToBoxAdapter(
                                            child: SearchSectionHeader(
                                              title: l10n.searchResultsGlobal,
                                              padding: EdgeInsets.symmetric(
                                                horizontal: sectionHPad,
                                                vertical: 8.0,
                                              ),
                                            ),
                                          ),
                                          if (_globalFolders.isNotEmpty)
                                            FolderSubfoldersSliver(
                                              folders: _globalFolders,
                                              zoomScale: zoomScale,
                                              scanner: ref.read(
                                                scannerServiceProvider,
                                              ),
                                              section: 'glob_folders',
                                              crossAxisExtent: crossAxisExtent,
                                              bottomPadding: 0.0,
                                              onNavigateTo: _navigateToFolder,
                                            ),
                                          if (_globalFolders.isNotEmpty &&
                                              _globalSongs.isNotEmpty) ...[
                                            const SliverToBoxAdapter(
                                              child: SizedBox(height: 12),
                                            ),
                                            SliverToBoxAdapter(
                                              child: SearchSectionHeader(
                                                title:
                                                    '${l10n.searchResultsSongs} (${_globalSongs.length})',
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: sectionHPad,
                                                  vertical: 8.0,
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (_globalSongs.isNotEmpty)
                                            FolderSongsSliver(
                                              songs: _globalSongs,
                                              zoomScale: zoomScale,
                                              currentSongPath:
                                                  currentMusic?.path,
                                              isPlaying: isAudioPlaying,
                                              section: 'glob_songs',
                                              crossAxisExtent: crossAxisExtent,
                                              topPadding: 4.0,
                                              bottomPadding: 0.0,
                                              onSongTap: (song, index) {
                                                ref
                                                    .read(audioServiceProvider)
                                                    .playPlaylist(
                                                      _globalSongs,
                                                      initialIndex: index,
                                                      source: PlaybackSource(
                                                        type: PlaybackSourceType
                                                            .folder,
                                                        id: 'folder_search',
                                                        name: l10n.search,
                                                      ),
                                                    );
                                              },
                                              onSongLongPress: (song) =>
                                                  _openSongMenu(song),
                                              onSongSecondaryTapDown: (
                                                song,
                                                details,
                                              ) => _openSongMenu(
                                                song,
                                                globalPosition:
                                                    details.globalPosition,
                                              ),
                                            ),
                                        ],
                                      ] else ...[
                                        if (_globalFolders.isNotEmpty) ...[
                                          SliverToBoxAdapter(
                                            child: SearchSectionHeader(
                                              title:
                                                  '${l10n.searchResultsFolders} (${_globalFolders.length})',
                                              padding: EdgeInsets.symmetric(
                                                horizontal: sectionHPad,
                                                vertical: 8.0,
                                              ),
                                            ),
                                          ),
                                          FolderSubfoldersSliver(
                                            folders: _globalFolders,
                                            zoomScale: zoomScale,
                                            scanner: ref.read(
                                              scannerServiceProvider,
                                            ),
                                            section: 'root_folders',
                                            crossAxisExtent: crossAxisExtent,
                                            bottomPadding: 0.0,
                                            onNavigateTo: _navigateToFolder,
                                          ),
                                          const SliverToBoxAdapter(
                                            child: SizedBox(height: 12),
                                          ),
                                        ],
                                        if (_globalSongs.isNotEmpty) ...[
                                          SliverToBoxAdapter(
                                            child: SearchSectionHeader(
                                              title:
                                                  '${l10n.searchResultsSongs} (${_globalSongs.length})',
                                              padding: EdgeInsets.symmetric(
                                                horizontal: sectionHPad,
                                                vertical: 8.0,
                                              ),
                                            ),
                                          ),
                                          FolderSongsSliver(
                                            songs: _globalSongs,
                                            zoomScale: zoomScale,
                                            currentSongPath:
                                                currentMusic?.path,
                                            isPlaying: isAudioPlaying,
                                            section: 'root_songs',
                                            crossAxisExtent: crossAxisExtent,
                                            topPadding: 4.0,
                                            bottomPadding: 0.0,
                                            onSongTap: (song, index) {
                                              ref
                                                  .read(audioServiceProvider)
                                                  .playPlaylist(
                                                    _globalSongs,
                                                    initialIndex: index,
                                                    source: PlaybackSource(
                                                      type: PlaybackSourceType
                                                          .folder,
                                                      id: 'folder_search',
                                                      name: l10n.search,
                                                    ),
                                                  );
                                            },
                                            onSongLongPress: (song) =>
                                                _openSongMenu(song),
                                            onSongSecondaryTapDown: (
                                              song,
                                              details,
                                            ) => _openSongMenu(
                                              song,
                                              globalPosition:
                                                  details.globalPosition,
                                            ),
                                          ),
                                        ],
                                      ],
                                      SliverPadding(
                                        padding: EdgeInsets.only(
                                          bottom: bottomInset,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
