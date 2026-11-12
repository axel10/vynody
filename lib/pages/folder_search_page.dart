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
import '../utils/search_selection_utils.dart';
import '../utils/song_context_menu_utils.dart' hide showFolderContextMenu;
import '../utils/song_locator_helper.dart';
import '../widgets/folder_bottom_sheet.dart';
import '../widgets/folder_content_slivers.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/folder_zoom_gesture_layer.dart';
import '../widgets/library_large_title.dart';
import '../widgets/library_search_field.dart';
import '../widgets/library_selection_back_guard.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/playback_ui_tuning.dart';

/// 本地目录独立搜索页。
///
/// 当在具体子目录下点击搜索时，传入 [currentFolder]，搜索结果将自动分为：
/// 1. 当前目录及子目录下的匹配结果；
/// 2. 全局其他本地根目录下的匹配结果。
/// 若在根目录点击搜索（[currentFolder] 为 null），则直接呈现全局匹配的文件夹与歌曲。
///
/// 多选不按分节拆：四段（当前目录文件夹 / 当前目录歌曲 / 全局文件夹 / 全局歌曲）
/// 共用一套选择集，键是 `folder:<path>` 与 `song:<path>`。文件夹按「它包含的
/// 全部歌曲」参与批量动作，因此 Shift 连选与全选都能跨段连起来。
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

class _FolderSearchPageState extends ConsumerState<FolderSearchPage>
    with SelectionStateMixin<FolderSearchPage, String> {
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.folderSearch;

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

  /// 当前选择集展开后的歌曲（文件夹 → 其下全部歌曲）。
  List<MusicFile> _selectedSongs = const [];

  /// 展开结果对应的选择集签名；异步回来时签名不符则丢弃。
  String _expandedSignature = '';

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

  /// 搜索结果会整体换掉，选择集留着旧条目只会让面板统计对不上。
  void _resetSelection() {
    if (isSelectionMode) cancelSelection();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final trimmed = raw.trim();
    if (trimmed == _query) return;

    if (trimmed.isEmpty) {
      _resetSelection();
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

    _resetSelection();
    setState(() {
      _query = trimmed;
      _isSearching = true;
    });

    _debounce = Timer(_debounceDuration, () => _performSearch(trimmed));
  }

  void _onQueryCleared() {
    _debounce?.cancel();
    _controller.clear();
    _resetSelection();
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

  /// 点击 / 长按 / 右键「多选」共用的入口。
  void _enterSelection(String key, int index) {
    lastAnchorIndex = index;
    if (!isSelectionMode) {
      enterSelectionMode(key);
    } else {
      toggleSelection(key);
    }
  }

  void _syncSelectedSongs(List<SearchEntry> entries) {
    final keys = selectedKeys;
    final signature = (keys.toList()..sort()).join('\u0000');
    if (signature == _expandedSignature) return;
    _expandedSignature = signature;

    if (keys.isEmpty) {
      _selectedSongs = const [];
      return;
    }

    final selected = entries
        .where((entry) => keys.contains(entry.key))
        .toList(growable: false);
    unawaited(_expandSelectedSongs(selected, signature));
  }

  Future<void> _expandSelectedSongs(
    List<SearchEntry> entries,
    String signature,
  ) async {
    final scanner = ref.read(scannerServiceProvider);
    try {
      final songs = await expandSearchEntries(
        entries,
        scanner.getSongsForFolder,
      );
      if (!mounted || _expandedSignature != signature) return;
      setState(() => _selectedSongs = songs);
    } catch (error) {
      // 单个目录读不出来（外接盘拔了、权限丢了）不该让整份选择集失去作用，
      // 保留上一次展开结果即可。
      debugPrint('[SearchSelection] expand failed: $error');
    }
  }

  /// 多选态下右键某个条目：动作作用于整个选择集；否则只作用于这一条。
  List<MusicFile> _menuSongsFor(MusicFile song) {
    if (isSelectionMode && _selectedSongs.isNotEmpty) return _selectedSongs;
    return [song];
  }

  void _openSongMenu(
    MusicFile song,
    int index,
    Offset globalPosition,
  ) {
    final key = songSelectionKey(song.path);
    final songs = _menuSongsFor(song);
    showSongContextMenu(
      context,
      globalPosition,
      song: song,
      songs: songs,
      onMultiSelect: isSelectionMode
          ? null
          : () => _enterSelection(key, index),
      onPlayNext: () => ref.read(audioServiceProvider).enqueueNext(songs),
      onAddToQueue: () => ref.read(audioServiceProvider).appendToQueue(songs),
      onAddToPlaylist: () => showAddSongsToPlaylistDialog(
        context,
        ref.read(playlistServiceProvider),
        songs,
      ),
    );
  }

  void _openFolderMenu(MusicFolder folder, int index, Offset globalPosition) {
    showFolderContextMenu(
      context: context,
      globalPosition: globalPosition,
      ref: ref,
      folder: folder,
      isRoot: false,
      onMultiSelect: isSelectionMode
          ? null
          : (path) => _enterSelection(folderSelectionKey(path), index),
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
    final hasCurrentSection = widget.currentFolder != null;
    final selectionActive = isSelectionMode;

    final hasCurrentResults =
        _currentFolderFolders.isNotEmpty || _currentFolderSongs.isNotEmpty;
    final hasGlobalResults =
        _globalFolders.isNotEmpty || _globalSongs.isNotEmpty;
    final hasAnyResults = hasCurrentResults || hasGlobalResults;

    // 页面视觉顺序的扁平条目序列：当前目录文件夹 → 当前目录歌曲 → 全局文件夹
    // → 全局歌曲（根目录模式下前两段长度为 0）。Shift 连选、全选、展开成歌曲
    // 都按这一份算，所以跨段连选天然成立。
    final entries = <SearchEntry>[
      if (hasCurrentSection) ...[
        for (final folder in _currentFolderFolders) SearchEntry.folder(folder),
        for (final song in _currentFolderSongs) SearchEntry.song(song),
      ],
      for (final folder in _globalFolders) SearchEntry.folder(folder),
      for (final song in _globalSongs) SearchEntry.song(song),
    ];
    final entryKeys = [for (final entry in entries) entry.key];
    final curFoldersBase = 0;
    final curSongsBase = hasCurrentSection ? _currentFolderFolders.length : 0;
    final globFoldersBase =
        curSongsBase + (hasCurrentSection ? _currentFolderSongs.length : 0);
    final globSongsBase = globFoldersBase + _globalFolders.length;

    _syncSelectedSongs(entries);
    final allEntriesSelected =
        entries.isNotEmpty && selectedKeys.length == entries.length;

    // FolderSubfoldersSliver / FolderSongsSliver 只认裸路径，选择键带类型前缀，
    // 所以要按类型拆出两份视图集合再传下去。
    final selectedFolderPaths = <String>{
      for (final key in selectedKeys)
        if (key.startsWith('folder:')) key.substring('folder:'.length),
    };
    final selectedSongPaths = <String>{
      for (final key in selectedKeys)
        if (key.startsWith('song:')) key.substring('song:'.length),
    };

    final bottomInset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: selectionActive,
      selectionPanelHeight: 120.0,
    );

    void playFrom(List<MusicFile> songs, int localIndex) {
      ref.read(audioServiceProvider).playPlaylist(
        songs,
        initialIndex: localIndex,
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: 'folder_search',
          name: l10n.search,
        ),
      );
    }

    return LibrarySelectionBackGuard(
      scope: LibrarySelectionScope.folderSearch,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
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
                                    zoomGesturesEnabled: !selectionActive,
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
                                            if (hasCurrentSection &&
                                                hasCurrentResults) ...[
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
                                            ],
                                            if (_currentFolderFolders
                                                .isNotEmpty) ...[
                                              FolderSubfoldersSliver(
                                                folders: _currentFolderFolders,
                                                zoomScale: zoomScale,
                                                scanner: ref.read(
                                                  scannerServiceProvider,
                                                ),
                                                section: 'cur_folders',
                                                crossAxisExtent:
                                                    crossAxisExtent,
                                                bottomPadding: 0.0,
                                                isSelectionMode:
                                                    selectionActive,
                                                selectedFolderPaths:
                                                    selectedFolderPaths,
                                                onNavigateTo: _navigateToFolder,
                                                onFolderTap: (folder, index) =>
                                                    handleItemTap(
                                                  index: curFoldersBase + index,
                                                  itemKey: folderSelectionKey(
                                                    folder.path,
                                                  ),
                                                  allKeys: entryKeys,
                                                  onNormalTap: () =>
                                                      _navigateToFolder(folder),
                                                ),
                                                onFolderLongPress:
                                                    (folder, index) =>
                                                        _enterSelection(
                                                  folderSelectionKey(
                                                    folder.path,
                                                  ),
                                                  curFoldersBase + index,
                                                ),
                                                onToggleFolderSelection: (path) =>
                                                    toggleSelection(
                                                  folderSelectionKey(path),
                                                ),
                                                onShowFolderContextMenu: (
                                                  folder,
                                                  position, {
                                                  required isRoot,
                                                }) =>
                                                    _openFolderMenu(
                                                  folder,
                                                  curFoldersBase +
                                                      _currentFolderFolders
                                                          .indexOf(folder),
                                                  position,
                                                ),
                                              ),
                                              const SliverToBoxAdapter(
                                                child: SizedBox(height: 12),
                                              ),
                                            ],
                                            if (_currentFolderSongs
                                                .isNotEmpty) ...[
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
                                              FolderSongsSliver(
                                                songs: _currentFolderSongs,
                                                zoomScale: zoomScale,
                                                currentSongPath:
                                                    currentMusic?.path,
                                                isPlaying: isAudioPlaying,
                                                section: 'cur_songs',
                                                crossAxisExtent:
                                                    crossAxisExtent,
                                                topPadding: 4.0,
                                                bottomPadding: 0.0,
                                                isSelectionMode:
                                                    selectionActive,
                                                selectedSongPaths:
                                                    selectedSongPaths,
                                                onSongTap: (song, index) =>
                                                    handleItemTap(
                                                  index: curSongsBase + index,
                                                  itemKey: songSelectionKey(
                                                    song.path,
                                                  ),
                                                  allKeys: entryKeys,
                                                  onNormalTap: () => playFrom(
                                                    _currentFolderSongs,
                                                    index,
                                                  ),
                                                ),
                                                onSongLongPress: (song) =>
                                                    _enterSelection(
                                                  songSelectionKey(song.path),
                                                  curSongsBase +
                                                      _currentFolderSongs
                                                          .indexOf(song),
                                                ),
                                                onSongSecondaryTapDown: (
                                                  song,
                                                  details,
                                                ) =>
                                                    _openSongMenu(
                                                  song,
                                                  curSongsBase +
                                                      _currentFolderSongs
                                                          .indexOf(song),
                                                  details.globalPosition,
                                                ),
                                              ),
                                              const SliverToBoxAdapter(
                                                child: SizedBox(height: 12),
                                              ),
                                            ],
                                            if (hasGlobalResults &&
                                                (hasCurrentSection ||
                                                    _globalFolders
                                                        .isNotEmpty)) ...[
                                              SliverToBoxAdapter(
                                                child: SearchSectionHeader(
                                                  title: hasCurrentSection
                                                      ? l10n.searchResultsGlobal
                                                      : '${l10n.searchResultsFolders} (${_globalFolders.length})',
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: sectionHPad,
                                                    vertical: 8.0,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (_globalFolders.isNotEmpty) ...[
                                              FolderSubfoldersSliver(
                                                folders: _globalFolders,
                                                zoomScale: zoomScale,
                                                scanner: ref.read(
                                                  scannerServiceProvider,
                                                ),
                                                section: 'glob_folders',
                                                crossAxisExtent:
                                                    crossAxisExtent,
                                                bottomPadding: 0.0,
                                                isSelectionMode:
                                                    selectionActive,
                                                selectedFolderPaths:
                                                    selectedFolderPaths,
                                                onNavigateTo: _navigateToFolder,
                                                onFolderTap: (folder, index) =>
                                                    handleItemTap(
                                                  index: globFoldersBase + index,
                                                  itemKey: folderSelectionKey(
                                                    folder.path,
                                                  ),
                                                  allKeys: entryKeys,
                                                  onNormalTap: () =>
                                                      _navigateToFolder(folder),
                                                ),
                                                onFolderLongPress:
                                                    (folder, index) =>
                                                        _enterSelection(
                                                  folderSelectionKey(
                                                    folder.path,
                                                  ),
                                                  globFoldersBase + index,
                                                ),
                                                onToggleFolderSelection: (path) =>
                                                    toggleSelection(
                                                  folderSelectionKey(path),
                                                ),
                                                onShowFolderContextMenu: (
                                                  folder,
                                                  position, {
                                                  required isRoot,
                                                }) =>
                                                    _openFolderMenu(
                                                  folder,
                                                  globFoldersBase +
                                                      _globalFolders
                                                          .indexOf(folder),
                                                  position,
                                                ),
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
                                                section: 'glob_songs',
                                                crossAxisExtent:
                                                    crossAxisExtent,
                                                topPadding: 4.0,
                                                bottomPadding: 0.0,
                                                isSelectionMode:
                                                    selectionActive,
                                                selectedSongPaths:
                                                    selectedSongPaths,
                                                onSongTap: (song, index) =>
                                                    handleItemTap(
                                                  index: globSongsBase + index,
                                                  itemKey: songSelectionKey(
                                                    song.path,
                                                  ),
                                                  allKeys: entryKeys,
                                                  onNormalTap: () => playFrom(
                                                    _globalSongs,
                                                    index,
                                                  ),
                                                ),
                                                onSongLongPress: (song) =>
                                                    _enterSelection(
                                                  songSelectionKey(song.path),
                                                  globSongsBase +
                                                      _globalSongs.indexOf(song),
                                                ),
                                                onSongSecondaryTapDown: (
                                                  song,
                                                  details,
                                                ) =>
                                                    _openSongMenu(
                                                  song,
                                                  globSongsBase +
                                                      _globalSongs.indexOf(song),
                                                  details.globalPosition,
                                                ),
                                              ),
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
            AnimatedSelectionPanel(
              isVisible: selectionActive,
              child: LibrarySelectionPanel(
                key: const ValueKey('folder-search-selection-panel'),
                selectedSongs: _selectedSongs,
                title: l10n.selectedItemsCount(selectedCount),
                isSelectionEmpty: selectedKeys.isEmpty,
                isAllSelected: allEntriesSelected,
                onToggleSelectAll: () => toggleSelectAll(entryKeys),
                onCancel: cancelSelection,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
