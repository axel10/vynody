import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/remote_server_riverpod.dart';
import '../../player/remote/clients/webdav_client.dart';
import '../../player/remote/clients/smb_client.dart';
import '../../player/remote/proxy/remote_media_resolver.dart';
import '../../l10n/app_localizations.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../player/remote/services/remote_folder_cover_service.dart';
import '../../player/remote/services/webdav_metadata_helper.dart';
import '../../player/remote/services/remote_scan_root.dart';
import '../../player/remote/services/remote_directory_scanner.dart';
import '../../player/remote/services/remote_metadata_scan_state.dart';
import '../../player/library/playlist_service.dart';
import '../../player/metadata/metadata_database.dart';
import '../../player/scanner/scanner_sorting.dart';
import '../../player/settings/settings_service.dart';
import '../../dialogs/transcode_dialog.dart';
import '../../utils/app_snack_bar.dart';
import '../../utils/folder_helpers.dart';
import '../../utils/remote_context_menu_utils.dart';
import '../../utils/remote_download_feedback.dart';
import '../../utils/song_context_menu_utils.dart';
import '../../widgets/library_selection_panel.dart';
import '../../widgets/library_selection_scope.dart';
import '../../widgets/folder_header_banner.dart';
import 'remote_folder_search_page.dart';
import '../../widgets/folder_layout_utils.dart';
import '../../widgets/folder_content_slivers.dart';
import '../../widgets/folder_zoom_gesture_layer.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../widgets/song_thumbnail.dart';
import '../../widgets/default_cover_art.dart';
import '../../widgets/locate_song_button.dart';
import 'remote_download_manager_page.dart';
import 'widgets/webdav_content_slivers.dart';
import '../../utils/selection_utils.dart';
import '../../utils/song_locator_helper.dart';
import '../../widgets/folder_header_nav_bar.dart';
import '../../widgets/folder_scan_widgets.dart';
import '../../widgets/auto_hide_header.dart';
import '../../widgets/folder_floating_action_button.dart';
import '../../utils/app_icons.dart';

/// 同一页里两段网格各自的身份（与 `SliverAnimatedZoomGridDelegate.section` 对齐）。
///
/// 子目录段和文件段的条目索引都从 0 开始，靠它区分。换档时上段（子目录）的高度
/// 变化要算进下段（文件）的位移里，两段必须由页面统一提供的那一个
/// `FolderZoomSliverBuilder` 结算 —— 各段自建 builder 时上段在下段的 tracker 里
/// 根本不存在，换档瞬间下段会被顶走一个 `ΔH`。
const Object _kRemoteFolderSection = 'remote-browser.folders';
const Object _kRemoteFileSection = 'remote-browser.files';

class RemoteFolderBrowserPage extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String? initialPath;
  final String? rootPath;
  final bool wrapWithMiniPlayer;
  final String? highlightedSongPath;

  const RemoteFolderBrowserPage({
    super.key,
    required this.server,
    required this.password,
    this.initialPath,
    this.rootPath,
    this.wrapWithMiniPlayer = false,
    this.highlightedSongPath,
  });

  @override
  ConsumerState<RemoteFolderBrowserPage> createState() =>
      _RemoteFolderBrowserPageState();
}

class _RemoteFolderBrowserPageState
    extends ConsumerState<RemoteFolderBrowserPage> {
  late final RemoteDirectoryClient _client;
  late String _rootPath;
  late String _currentPath;
  bool _isLoading = false;
  String? _error;
  List<WebDavFile> _items = [];
  final Map<String, SongMetadata> _metadataMap = {};
  int _loadEpoch = 0;

  /// 当前层每个子目录的代表封面（键 = 目录 virtualUri）。
  ///
  /// 封面是逐步补齐的，走 [ValueNotifier] 只通知目录网格那一层重建，
  /// 不用整页 `setState`（整页 build 里要跑元数据聚合和全部音频行的构造）。
  final ValueNotifier<Map<String, MusicFile>> _folderCoverSongs =
      ValueNotifier<Map<String, MusicFile>>(const {});

  // Selection states
  bool _isSelectionMode = false;
  final Set<String> _selectedSongPaths = {};
  final Set<String> _selectedFolderPaths = {};
  int? _lastSongAnchorIndex;
  int? _lastFolderAnchorIndex;

  // Scroll states
  late final LibrarySelectionScopeController _selectionScopeNotifier;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _breadcrumbsScrollController = ScrollController();

  /// `LayoutBuilder` 给的列表内容宽度（已扣除最大宽度约束）。
  /// 「定位当前播放」用它估算偏移，避免用 `MediaQuery` 宽度高估卡片行高。
  double? _contentCrossAxisExtent;

  /// 挂在标题横幅上：定位当前播放时实测横幅高度，不再靠 `190.0` 估算。
  final GlobalKey _bannerMeasureKey = GlobalKey();
  final ValueNotifier<double> _scrollProgress = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _isCoverVisible = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _showFloatingActions = ValueNotifier<bool>(false);
  String? _highlightedSongPath;
  Timer? _highlightTimer;
  late final double _initialZoomScale;

  void _openSearchPage() {
    Navigator.of(context).push(
      (Platform.isIOS || Platform.isMacOS)
          ? CupertinoPageRoute<void>(
              settings: const RouteSettings(name: 'remote_folder_search'),
              builder: (_) => RemoteFolderSearchPage(
                server: widget.server,
                password: widget.password,
                currentPath: _currentPath,
                rootPath: _rootPath,
              ),
            )
          : MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'remote_folder_search'),
              builder: (_) => RemoteFolderSearchPage(
                server: widget.server,
                password: widget.password,
                currentPath: _currentPath,
                rootPath: _rootPath,
              ),
            ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initialZoomScale = ref.read(settingsServiceProvider).folderZoomScale;
    _selectionScopeNotifier =
        ref.read(librarySelectionScopeProvider.notifier);
    if (widget.server.type == RemoteServerType.smb) {
      _client = SmbClient(
        server: widget.server,
        password: widget.password,
      );
    } else {
      _client = WebDavClient(
        server: widget.server,
        password: widget.password,
      );
    }

    if (widget.highlightedSongPath != null) {
      _highlightedSongPath = widget.highlightedSongPath;
    }

    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    if (isSameServer && session.webDavMetadataCache.isNotEmpty) {
      _metadataMap.addAll(session.webDavMetadataCache);
    }

    _rootPath = normalizeRemotePath(
      widget.rootPath ??
          (isSameServer && session.rootPath != null ? session.rootPath! : null) ??
          widget.server.customPath,
    );

    _currentPath = normalizeRemotePath(
      widget.initialPath ??
          (isSameServer && session.initialPath != null
              ? session.initialPath!
              : null) ??
          _rootPath,
    );

    if (isSameServer &&
        session.webDavDirectoryCache.containsKey(_currentPath)) {
      _items = List.of(session.webDavDirectoryCache[_currentPath]!);
      _sortItems(_items);
      _isLoading = false;
      _startMetadataExtraction(_items, _loadEpoch);
      _kickFolderCovers(_items, _loadEpoch);
      if (_highlightedSongPath != null) {
        final target = _highlightedSongPath!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToSong(target);
        });
      }
    } else {
      _loadDirectory(_currentPath);
    }
  }

  @override
  void didUpdateWidget(RemoteFolderBrowserPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedSongPath != null &&
        widget.highlightedSongPath != oldWidget.highlightedSongPath) {
      _highlightedSongPath = widget.highlightedSongPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSong(widget.highlightedSongPath!);
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth == 0) {
      final offset = notification.metrics.pixels;
      final isVisible = offset < 160.0;
      final progress = (offset / 160.0).clamp(0.0, 1.0);
      _scrollProgress.value = progress;
      if (isVisible != _isCoverVisible.value) {
        _isCoverVisible.value = isVisible;
      }
      final shouldShowFab = offset > 70.0;
      if (shouldShowFab != _showFloatingActions.value) {
        _showFloatingActions.value = shouldShowFab;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    _breadcrumbsScrollController.dispose();
    _scrollProgress.dispose();
    _isCoverVisible.dispose();
    _showFloatingActions.dispose();
    _folderCoverSongs.dispose();
    Future.microtask(() {
      _selectionScopeNotifier.clear();
    });
    super.dispose();
  }

  bool get _isAtRoot {
    final cleanCurrent = normalizeRemotePath(_currentPath);
    final cleanRoot = normalizeRemotePath(_rootPath);
    return cleanCurrent == cleanRoot;
  }

  /// 目录页只呈现「子目录 + 可播放音频」。
  ///
  /// 远程目录里常混着封面图、`.cue` / `.nfo` / `.log` / `.txt` 以及 `.DS_Store`
  /// 这类系统文件。它们在这个页面上既不能播放也没有任何可用的操作：点击无响应，
  /// 长按能进多选但 `_getAudioFiles` 又会把它们过滤掉（已选数量对不上），
  /// 还会把「歌曲数」和专辑曲序带偏。所以在拿到底层列表的这一层就统一剔除，
  /// 后续排序、计数、全选、选择面板都只面对干净列表。
  ///
  /// 注意这里不动图片的用途：子目录封面由 [RemoteFolderCoverService] 自己
  /// 走 `client.listFiles` 去找 `cover.jpg`，不依赖本页的列表。
  static List<WebDavFile> _visibleDirectoryItems(Iterable<WebDavFile> items) =>
      items.where((i) => i.isDirectory || i.isAudio).toList();

  Future<void> _loadDirectory(String path, {bool forceRefresh = false}) async {
    _clearAllSelection();
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    _loadEpoch++;
    final currentEpoch = _loadEpoch;

    if (!forceRefresh &&
        isSameServer &&
        session.webDavDirectoryCache.containsKey(path)) {
      final cachedList =
          _visibleDirectoryItems(session.webDavDirectoryCache[path]!);
      _sortItems(cachedList);
      setState(() {
        _currentPath = path;
        _items = cachedList;
        _isLoading = false;
        _error = null;
      });
      _scrollToTop();
      _startMetadataExtraction(_items, currentEpoch);
      _kickFolderCovers(_items, currentEpoch);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(activeRemoteSessionProvider.notifier).updateWebDavState(
              currentPath: path,
              rootPath: _rootPath,
            );
        if (_breadcrumbsScrollController.hasClients) {
          _breadcrumbsScrollController.animateTo(
            _breadcrumbsScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _currentPath = path;
    });
    _scrollToTop();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_breadcrumbsScrollController.hasClients) {
        _breadcrumbsScrollController.animateTo(
          _breadcrumbsScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      // `/dav` 前缀探测要用原始列表：万一根目录下只剩非音频文件，过滤后的
      // 列表是空的，探测会失效。
      final remoteItems = await _client.listFiles(path);

      var effectivePath = path;
      if (path == '/' &&
          remoteItems.isNotEmpty &&
          remoteItems.first.path.startsWith('/dav')) {
        effectivePath = '/dav';
        if (_rootPath == '/') {
          _rootPath = '/dav';
        }
      }

      final list = _visibleDirectoryItems(remoteItems);
      _sortItems(list);

      if (mounted && _loadEpoch == currentEpoch) {
        setState(() {
          _items = list;
          _currentPath = effectivePath;
          _isLoading = false;
        });
        _startMetadataExtraction(list, currentEpoch);
        _kickFolderCovers(list, currentEpoch, forceRefresh: forceRefresh);
        if (_highlightedSongPath != null) {
          final target = _highlightedSongPath!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToSong(target);
          });
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(activeRemoteSessionProvider.notifier).updateWebDavState(
                currentPath: effectivePath,
                rootPath: _rootPath,
                items: list,
              );
        });
      }
    } catch (e) {
      if (mounted && _loadEpoch == currentEpoch) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _scrollProgress.value = 0.0;
    _isCoverVisible.value = true;
  }

  Future<void> _startMetadataExtraction(List<WebDavFile> files, int epoch) async {
    final audioFiles = files.where((f) => f.isAudio).toList();
    if (audioFiles.isEmpty) return;

    // 1. Check local SQLite metadata database first for instant cache hits
    final db = MetadataDatabase();
    final Map<String, SongMetadata> dbHits = {};
    // 命中了库但没读全（负数标记）的曲目：先按旧值显示，同时重新入队解析。
    final Set<String> staleUris = {};
    for (final file in audioFiles) {
      final virtualUri = RemoteMediaResolver.buildRemoteUri(widget.server, file.path);
      final inMemory = _metadataMap[virtualUri];
      final cached = inMemory ?? await db.getSongMetadata(virtualUri);
      if (cached == null) continue;
      _metadataMap[virtualUri] = cached;
      if (remoteMetadataNeedsParse(cached.metadataTextScanned)) {
        staleUris.add(virtualUri);
      } else if (inMemory == null) {
        // 只有这次才从库里捞出来的才回推给扫描器；内存里已有的上一轮推过。
        dbHits[virtualUri] = cached;
      }
    }

    if (dbHits.isNotEmpty && mounted && _loadEpoch == epoch) {
      final criteria = ref.read(settingsServiceProvider).webDavSortCriteria;
      if (criteria == SortCriteria.title || criteria == SortCriteria.trackNumber) {
        _sortItems(_items);
      }
      setState(() {});
      for (final meta in dbHits.values) {
        ref.read(scannerServiceProvider).updateMetadataForPath(meta);
      }
      ref.read(activeRemoteSessionProvider.notifier).updateWebDavState(
            currentPath: _currentPath,
            rootPath: _rootPath,
            metadataMap: dbHits,
          );
    }

    // 2. Identify unparsed files that need HTTP Range tag extraction
    final unparsedFiles = audioFiles.where((f) {
      final virtualUri = RemoteMediaResolver.buildRemoteUri(widget.server, f.path);
      return staleUris.contains(virtualUri) || !_metadataMap.containsKey(virtualUri);
    }).toList();

    if (unparsedFiles.isEmpty) return;

    // 3. Concurrently extract metadata with pool of 3
    final Map<String, SongMetadata> newMetas = {};
    DateTime lastUiUpdate = DateTime.now();
    await WebDavMetadataHelper.processBatchMetadata(
      files: unparsedFiles,
      server: widget.server,
      password: widget.password,
      concurrency: 3,
      isCancelled: () => !mounted || _loadEpoch != epoch,
      onMetadataLoaded: (virtualUri, meta, file) {
        if (!mounted || _loadEpoch != epoch) return;
        _metadataMap[virtualUri] = meta;
        newMetas[virtualUri] = meta;
        ref.read(scannerServiceProvider).updateMetadataForPath(
          meta,
          notify: false,
          syncTree: false,
        );
        final now = DateTime.now();
        if (now.difference(lastUiUpdate).inMilliseconds > 150) {
          lastUiUpdate = now;
          final criteria = ref.read(settingsServiceProvider).webDavSortCriteria;
          if (criteria == SortCriteria.title || criteria == SortCriteria.trackNumber) {
            _sortItems(_items);
          }
          setState(() {});
        }
      },
    );

    if (mounted && _loadEpoch == epoch) {
      final criteria = ref.read(settingsServiceProvider).webDavSortCriteria;
      if (criteria == SortCriteria.title || criteria == SortCriteria.trackNumber) {
        _sortItems(_items);
      }
      setState(() {});
    }

    if (newMetas.isNotEmpty && mounted && _loadEpoch == epoch) {
      ref.read(activeRemoteSessionProvider.notifier).updateWebDavState(
            currentPath: _currentPath,
            rootPath: _rootPath,
            metadataMap: newMetas,
          );
    }
  }

  /// 触发封面补全但不等待：目录本身先渲染，封面补到一张就画一张。
  /// 失败只记日志，不影响目录浏览。
  void _kickFolderCovers(
    List<WebDavFile> items,
    int epoch, {
    bool forceRefresh = false,
  }) {
    unawaited(
      _startFolderCoverExtraction(
        items,
        epoch,
        forceRefresh: forceRefresh,
      ).catchError((Object error) {
        debugPrint('[RemoteFolderBrowser] 子目录封面补全失败: $error');
      }),
    );
  }

  /// 给当前层可见的子目录补「代表封面」。
  ///
  /// 顺序是「缓存 → 已索引目录 → 网络」，结果由
  /// [RemoteFolderCoverService] 写回 `folder_entries`，所以同一层目录只会
  /// 为网络付一次代价。这里只负责把结果塞进 [_folderCoverSongs]。
  Future<void> _startFolderCoverExtraction(
    List<WebDavFile> folders,
    int epoch, {
    bool forceRefresh = false,
  }) async {
    final dirs = folders.where((f) => f.isDirectory).toList(growable: false);
    final dirByUri = <String, WebDavFile>{
      for (final dir in dirs)
        RemoteMediaResolver.buildRemoteUri(widget.server, dir.path): dir,
    };
    final uriByDir = <String, String>{
      for (final entry in dirByUri.entries) entry.key: entry.value.name,
    };

    // 换层时丢掉不属于这一层的旧封面，Map 不会随浏览历史一直膨胀。
    final previous = _folderCoverSongs.value;
    final pruned = <String, MusicFile>{
      for (final entry in previous.entries)
        if (uriByDir.containsKey(entry.key)) entry.key: entry.value,
    };
    if (pruned.length != previous.length) {
      _folderCoverSongs.value = pruned;
    }
    if (dirs.isEmpty) return;

    final service = RemoteFolderCoverService();

    // 已查过的目录（含确认没封面的负缓存），避免每次进同一层都重新走网络。
    final settled = <String>{};
    if (!forceRefresh) {
      final cached = await service.loadCachedCovers(uriByDir.keys);
      if (!mounted || _loadEpoch != epoch) return;
      settled.addAll(cached.settled);
      if (cached.covers.isNotEmpty) {
        final next = <String, MusicFile>{..._folderCoverSongs.value};
        cached.covers.forEach((uri, thumbnailPath) {
          next[uri] = MusicFile(
            path: uri,
            name: uriByDir[uri] ?? '',
            thumbnailPath: thumbnailPath,
          );
        });
        _folderCoverSongs.value = next;
      }
    }

    final missing = [
      for (final entry in uriByDir.entries)
        if (!settled.contains(entry.key)) entry.key,
    ];
    if (missing.isEmpty) return;

    // 远端并发压到 2：再高容易把家用 NAS 或公网 WebDAV 打到限流。
    const concurrency = 2;
    var cursor = 0;
    Future<void> worker() async {
      while (true) {
        if (!mounted || _loadEpoch != epoch) return;
        final index = cursor++;
        if (index >= missing.length) return;
        final uri = missing[index];
        final dir = dirByUri[uri];
        if (dir == null) continue;
        final thumbnailPath = await service.resolveCover(
          server: widget.server,
          password: widget.password,
          client: _client,
          folderPath: dir.path,
          forceRefresh: forceRefresh,
        );
        if (!mounted || _loadEpoch != epoch) return;
        if (thumbnailPath == null || thumbnailPath.isEmpty) continue;
        _folderCoverSongs.value = {
          ..._folderCoverSongs.value,
          uri: MusicFile(
            path: uri,
            name: uriByDir[uri] ?? '',
            thumbnailPath: thumbnailPath,
          ),
        };
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  }

  List<MusicFile> _getAudioFiles({List<WebDavFile>? sourceList}) {
    final scanner = ref.read(scannerServiceProvider);
    final list = sourceList ?? _items;
    return list
        .where((item) => item.isAudio)
        .map((item) {
          final virtualUri = RemoteMediaResolver.buildRemoteUri(widget.server, item.path);
          final meta = _metadataMap[virtualUri] ?? scanner.metadataMap[virtualUri];
          return RemoteMediaResolver.buildMusicFile(
            item,
            widget.server,
            metadata: meta,
          );
        })
        .toList();
  }

  Future<void> _playFolder({bool shuffle = false}) async {
    final audioFiles = _getAudioFiles();
    if (audioFiles.isEmpty) {
      showToast('No audio files in this folder');
      return;
    }

    final audioService = ref.read(audioServiceProvider);
    final playlist = List<MusicFile>.from(audioFiles);
    if (shuffle) {
      playlist.shuffle();
    }
    final folderName = _isAtRoot ? widget.server.name : p.basename(_currentPath);
    await audioService.playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.folder,
        id: 'webdav-${widget.server.id}-$_currentPath',
        name: folderName,
      ),
    );
    showToast('Playing ${playlist.length} songs');
  }


  Future<void> _downloadSingleAudio(WebDavFile item) async {
    await ref.read(remoteDownloadTasksProvider.notifier).enqueueWebDavFile(
          server: widget.server,
          password: widget.password,
          file: item,
        );

    showRemoteDownloadQueuedFeedback(context, ref, 1);
  }

  void _clearAllSelection() {
    final shouldClearSelection = _isSelectionMode ||
        _selectedSongPaths.isNotEmpty ||
        _selectedFolderPaths.isNotEmpty;
    final currentScope = ref.read(librarySelectionScopeProvider);
    final isWebDavScope = currentScope == LibrarySelectionScope.webdav ||
        currentScope == LibrarySelectionScope.folder;
    if (!shouldClearSelection && !isWebDavScope) return;

    if (isWebDavScope) {
      _selectionScopeNotifier.clear();
    }
    if (shouldClearSelection) {
      if (mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedSongPaths.clear();
          _selectedFolderPaths.clear();
          _lastSongAnchorIndex = null;
          _lastFolderAnchorIndex = null;
        });
      } else {
        _isSelectionMode = false;
        _selectedSongPaths.clear();
        _selectedFolderPaths.clear();
        _lastSongAnchorIndex = null;
        _lastFolderAnchorIndex = null;
      }
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSongPaths.clear();
        _selectedFolderPaths.clear();
        _selectionScopeNotifier.clear();
      } else {
        _selectionScopeNotifier.setScope(LibrarySelectionScope.webdav);
      }
    });
  }

  void _toggleSongSelection(String virtualUri) {
    setState(() {
      if (_selectedSongPaths.contains(virtualUri)) {
        _selectedSongPaths.remove(virtualUri);
      } else {
        _selectedSongPaths.add(virtualUri);
      }
      if (_selectedSongPaths.isEmpty && _selectedFolderPaths.isEmpty) {
        _isSelectionMode = false;
        _selectionScopeNotifier.clear();
      } else {
        _selectionScopeNotifier.setScope(LibrarySelectionScope.webdav);
      }
    });
  }

  void _toggleFolderSelection(String folderPath) {
    setState(() {
      if (_selectedFolderPaths.contains(folderPath)) {
        _selectedFolderPaths.remove(folderPath);
      } else {
        _selectedFolderPaths.add(folderPath);
      }
      if (_selectedSongPaths.isEmpty && _selectedFolderPaths.isEmpty) {
        _isSelectionMode = false;
        _selectionScopeNotifier.clear();
      } else {
        _selectionScopeNotifier.setScope(LibrarySelectionScope.webdav);
      }
    });
  }

  void _selectAllVisible(List<WebDavFile> displayedItems) {
    _selectionScopeNotifier.setScope(LibrarySelectionScope.webdav);
    setState(() {
      _isSelectionMode = true;
      for (final item in displayedItems) {
        if (item.isDirectory) {
          _selectedFolderPaths.add(item.path);
        } else if (item.isAudio) {
          final uri =
              RemoteMediaResolver.buildRemoteUri(widget.server, item.path);
          _selectedSongPaths.add(uri);
        }
      }
    });
  }

  List<MusicFile> _getSelectedSongs({List<WebDavFile>? sourceList}) {
    final allAudio = _getAudioFiles(sourceList: sourceList);
    final songs = <MusicFile>[];
    for (final song in allAudio) {
      if (_selectedSongPaths.contains(song.path)) {
        songs.add(song);
      }
    }
    final seen = <String>{};
    return songs.where((s) => seen.add(s.path)).toList(growable: false);
  }

  Future<List<MusicFile>> _resolveAllSelectedSongs({
    List<WebDavFile>? sourceList,
  }) async {
    final songs = <MusicFile>[];
    songs.addAll(_getSelectedSongs(sourceList: sourceList));

    if (_selectedFolderPaths.isNotEmpty) {
      showToast('Loading selected folders...');
      for (final folderPath in _selectedFolderPaths) {
        final folderAudios = await fetchWebDavFolderAudioFiles(
          _client,
          widget.server,
          folderPath,
        );
        songs.addAll(folderAudios);
      }
    }

    final seen = <String>{};
    return songs.where((s) => seen.add(s.path)).toList(growable: false);
  }

  void _handleSongTap(
    WebDavFile file,
    int index,
    List<MusicFile> allAudio,
    List<WebDavFile> displayedFiles,
  ) async {
    final uri = RemoteMediaResolver.buildRemoteUri(widget.server, file.path);
    SelectionActionHelper.handleItemTap(
      index: index,
      itemKey: uri,
      items: displayedFiles,
      keySelector: (f) =>
          RemoteMediaResolver.buildRemoteUri(widget.server, f.path),
      isSelectionMode: _isSelectionMode,
      selectedKeys: _selectedSongPaths,
      lastAnchorIndex: _lastSongAnchorIndex,
      onUpdateAnchor: (a) => setState(() => _lastSongAnchorIndex = a),
      onSetSelection: (keys) {
        _selectionScopeNotifier.setScope(LibrarySelectionScope.webdav);
        setState(() {
          _isSelectionMode = true;
          _selectedSongPaths.addAll(keys);
        });
      },
      onToggleSelection: (key) => _toggleSongSelection(key),
      onEnterSelectionMode: () {
        _selectionScopeNotifier.setScope(LibrarySelectionScope.webdav);
        setState(() => _isSelectionMode = true);
      },
      onNormalTap: () async {
        if (file.isAudio) {
          final target = RemoteMediaResolver.buildMusicFile(
            file,
            widget.server,
            metadata: _metadataMap[uri] ??
                ref.read(scannerServiceProvider).metadataMap[uri],
          );
          final initialIndex = allAudio.indexWhere((s) => s.path == target.path);
          final audioService = ref.read(audioServiceProvider);
          await audioService.playPlaylist(
            allAudio.isNotEmpty ? allAudio : [target],
            initialIndex: initialIndex >= 0 ? initialIndex : 0,
            source: PlaybackSource(
              type: PlaybackSourceType.folder,
              id: 'remote-${widget.server.id}-$_currentPath',
              name: _isAtRoot ? widget.server.name : p.basename(_currentPath),
            ),
          );
        }
      },
    );
  }

  void _handleSongLongPress(WebDavFile file, int index) {
    final uri = RemoteMediaResolver.buildRemoteUri(widget.server, file.path);
    _lastSongAnchorIndex = index;
    if (!_isSelectionMode) {
      _toggleSelectionMode();
      _toggleSongSelection(uri);
    } else {
      _toggleSongSelection(uri);
    }
  }

  void _handleSongContextMenu(
    WebDavFile file,
    Offset globalPosition,
    List<MusicFile> allAudio,
    List<WebDavFile> displayedItems,
  ) {
    final uri = RemoteMediaResolver.buildRemoteUri(widget.server, file.path);
    final target = RemoteMediaResolver.buildMusicFile(
      file,
      widget.server,
      metadata: _metadataMap[uri] ??
          ref.read(scannerServiceProvider).metadataMap[uri],
    );
    final selectedSongs = _getSelectedSongs(sourceList: displayedItems);
    final songsToAdd =
        (_selectedSongPaths.isNotEmpty || _selectedFolderPaths.isNotEmpty) &&
                selectedSongs.isNotEmpty
            ? selectedSongs
            : [target];

    showSongContextMenu(
      context,
      globalPosition,
      song: target,
      songs: songsToAdd,
      mode: SongContextMenuMode.full,
      // 长按与右键共用同一入口：锚点必须按整个音频列表算，不能用显示顺序。
      onMultiSelect: _isSelectionMode
          ? null
          : () {
              final fileIndex =
                  allAudio.indexWhere((s) => s.path == target.path);
              if (fileIndex >= 0) {
                _handleSongLongPress(file, fileIndex);
              }
            },
      onAddToPlaylist: () => showAddSongsToPlaylistDialog(
        context,
        ref.read(playlistServiceProvider),
        songsToAdd,
      ),
      onPlayNext: () =>
          ref.read(audioServiceProvider).enqueueNext(songsToAdd),
      onAddToQueue: () =>
          ref.read(audioServiceProvider).appendToQueue(songsToAdd),
      onDownload: () {
        if (songsToAdd.length > 1) {
          final notifier = ref.read(remoteDownloadTasksProvider.notifier);
          final webDavFiles = <WebDavFile>[];
          for (final song in songsToAdd) {
            final uriInfo = RemoteMediaResolver.parseUri(song.path);
            final remotePath = (uriInfo != null &&
                    (uriInfo.type == RemoteServerType.webdav ||
                        uriInfo.type == RemoteServerType.smb))
                ? uriInfo.trackIdOrPath
                : null;
            if (remotePath != null) {
              webDavFiles.add(WebDavFile(
                path: remotePath,
                name: p.basename(remotePath),
                isDirectory: false,
                contentLength: 0,
              ));
            }
          }
          if (webDavFiles.isNotEmpty && mounted) {
            notifier.enqueueWebDavFiles(
              server: widget.server,
              password: widget.password,
              files: webDavFiles,
            );
            showRemoteDownloadQueuedFeedback(
              context,
              ref,
              webDavFiles.length,
            );
          }
        } else {
          _downloadSingleAudio(file);
        }
      },
    );
  }

  void _handleShowFolderBottomSheet(WebDavFile folder) {
    showWebDavFolderBottomSheet(
      context: context,
      ref: ref,
      server: widget.server,
      password: widget.password,
      folder: folder,
      onOpen: () => _openFolder(folder),
      onMultiSelect: (folderPath) {
        if (!_isSelectionMode) _toggleSelectionMode();
        _toggleFolderSelection(folderPath);
      },
    );
  }

  void _openFolder(WebDavFile folder) {
    _clearAllSelection();
    ref.read(activeRemoteSessionProvider.notifier).pushWebDavPath(folder.path);
  }

  void _handleGoBack() {
    if (_isSelectionMode) {
      _clearAllSelection();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _navigateToBreadcrumb(int index) {
    _clearAllSelection();
    if (index < 0) {
      ref
          .read(activeRemoteSessionProvider.notifier)
          .setWebDavPathStack(const []);
      return;
    }
    final targetStack = <String>[];
    for (int i = 0; i <= index; i++) {
      targetStack.add(_buildSegmentPath(i));
    }
    ref
        .read(activeRemoteSessionProvider.notifier)
        .setWebDavPathStack(targetStack);
  }

  List<String> get _pathSegments {
    if (_isAtRoot) return [];
    final cleanCurrent = normalizeRemotePath(_currentPath);
    final cleanRoot = normalizeRemotePath(_rootPath);
    var relative = cleanCurrent;
    if (cleanRoot != '/' && relative.startsWith(cleanRoot)) {
      relative = relative.substring(cleanRoot.length);
    }
    final segments = relative
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return segments;
  }

  String _buildSegmentPath(int index) {
    final segments = _pathSegments;
    final sub = segments.sublist(0, index + 1).join('/');
    final cleanRoot = normalizeRemotePath(_rootPath);
    if (cleanRoot == '/' || cleanRoot.isEmpty) {
      return '/$sub';
    }
    return '$cleanRoot/$sub';
  }

  void _sortItems(List<WebDavFile> items, {SortCriteria? criteria, SortOrder? order}) {
    final effectiveCriteria =
        criteria ?? ref.read(settingsServiceProvider).webDavSortCriteria;
    final effectiveOrder =
        order ?? ref.read(settingsServiceProvider).webDavSortOrder;

    items.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      if (a.isDirectory && b.isDirectory) {
        final res = compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
        return effectiveOrder == SortOrder.descending ? -res : res;
      }

      // Both are files
      int comp = 0;
      final virtualUriA =
          RemoteMediaResolver.buildRemoteUri(widget.server, a.path);
      final virtualUriB =
          RemoteMediaResolver.buildRemoteUri(widget.server, b.path);
      final metaA = _metadataMap[virtualUriA] ??
          ref.read(scannerServiceProvider).metadataMap[virtualUriA];
      final metaB = _metadataMap[virtualUriB] ??
          ref.read(scannerServiceProvider).metadataMap[virtualUriB];

      switch (effectiveCriteria) {
        case SortCriteria.title:
          final titleA =
              (metaA?.title.isNotEmpty == true) ? metaA!.title : a.name;
          final titleB =
              (metaB?.title.isNotEmpty == true) ? metaB!.title : b.name;
          comp = compareNatural(titleA.toLowerCase(), titleB.toLowerCase());
          if (comp == 0) {
            comp = compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
          }
          break;
        case SortCriteria.filename:
          comp = compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
          break;
        case SortCriteria.trackNumber:
          final trackA = metaA?.trackNumber;
          final trackB = metaB?.trackNumber;
          if (trackA != null && trackB != null) {
            comp = trackA.compareTo(trackB);
          } else if (trackA != null) {
            comp = -1;
          } else if (trackB != null) {
            comp = 1;
          }
          if (comp == 0) {
            comp = compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
          }
          break;
      }

      return effectiveOrder == SortOrder.descending ? -comp : comp;
    });
  }

  void _showSortDialog(BuildContext context) {
    final settings = ref.read(settingsServiceProvider);
    var selectedCriteria = settings.webDavSortCriteria;
    var selectedOrder = settings.webDavSortOrder;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final l10n = AppLocalizations.of(context)!;
            return AlertDialog(
              title: Text(l10n.sortBy),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.sortBy,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortCriteria>(
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selectedCriteria = v;
                      });
                      settings.webDavSortCriteria = v;
                      setState(() {
                        _sortItems(_items);
                      });
                    },
                    groupValue: selectedCriteria,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(l10n.fileName),
                          leading: const Radio(value: SortCriteria.filename),
                          onTap: () {
                            setDialogState(() {
                              selectedCriteria = SortCriteria.filename;
                            });
                            settings.webDavSortCriteria = SortCriteria.filename;
                            setState(() {
                              _sortItems(_items);
                            });
                          },
                        ),
                        ListTile(
                          title: Text(l10n.title),
                          leading: const Radio(value: SortCriteria.title),
                          onTap: () {
                            setDialogState(() {
                              selectedCriteria = SortCriteria.title;
                            });
                            settings.webDavSortCriteria = SortCriteria.title;
                            setState(() {
                              _sortItems(_items);
                            });
                          },
                        ),
                        ListTile(
                          title: Text(l10n.trackNumber),
                          leading: const Radio(value: SortCriteria.trackNumber),
                          onTap: () {
                            setDialogState(() {
                              selectedCriteria = SortCriteria.trackNumber;
                            });
                            settings.webDavSortCriteria =
                                SortCriteria.trackNumber;
                            setState(() {
                              _sortItems(_items);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.sortOrder,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortOrder>(
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selectedOrder = v;
                      });
                      settings.webDavSortOrder = v;
                      setState(() {
                        _sortItems(_items);
                      });
                    },
                    groupValue: selectedOrder,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(l10n.ascending),
                          leading: const Radio(value: SortOrder.ascending),
                          onTap: () {
                            setDialogState(() {
                              selectedOrder = SortOrder.ascending;
                            });
                            settings.webDavSortOrder = SortOrder.ascending;
                            setState(() {
                              _sortItems(_items);
                            });
                          },
                        ),
                        ListTile(
                          title: Text(l10n.descending),
                          leading: const Radio(value: SortOrder.descending),
                          onTap: () {
                            setDialogState(() {
                              selectedOrder = SortOrder.descending;
                            });
                            settings.webDavSortOrder = SortOrder.descending;
                            setState(() {
                              _sortItems(_items);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.confirm),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _locateCurrentSong() async {
    final currentMusic = ref.read(audioCurrentMusicProvider);
    if (currentMusic == null) return;

    final info = RemoteMediaResolver.parseUri(currentMusic.path);
    if (info != null &&
        (info.type == RemoteServerType.webdav ||
            info.type == RemoteServerType.smb) &&
        info.serverId == widget.server.id) {
      final songFullPath = info.trackIdOrPath;
      final parentDir = p.posix.dirname(songFullPath);

      final cleanCurrent = _currentPath.endsWith('/') && _currentPath.length > 1
          ? _currentPath.substring(0, _currentPath.length - 1)
          : _currentPath;
      final cleanParent = parentDir.endsWith('/') && parentDir.length > 1
          ? parentDir.substring(0, parentDir.length - 1)
          : parentDir;

      if (cleanCurrent == cleanParent) {
        final scrolled = _scrollToSong(currentMusic.path);
        if (scrolled) return;
      }
    }

    await SongLocatorHelper.locateCurrentPlayingSong(ref, context);
  }

  bool _scrollToSong(String songPath) {
    if (!mounted || _items.isEmpty) return false;
    final info = RemoteMediaResolver.parseUri(songPath);
    final songFullPath = info?.trackIdOrPath ?? songPath;

    final displayedItems = _items;
    final matchedFolders = displayedItems.where((i) => i.isDirectory).toList();
    final matchedFiles = displayedItems.where((i) => !i.isDirectory).toList();

    final fileIndex = matchedFiles.indexWhere((f) {
      final uri = RemoteMediaResolver.buildRemoteUri(widget.server, f.path);
      return uri == songPath || f.path == songFullPath;
    });

    if (fileIndex == -1) {
      return false;
    }

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
      final settings = ref.read(settingsServiceProvider);
      final outerWidth =
          _contentCrossAxisExtent ?? MediaQuery.sizeOf(context).width;
      final policy = FolderZoomPolicy.resolve(
        context: context,
        outerWidth: outerWidth,
        zoomScale: settings.folderZoomScale,
      );

      double fileOffset = folderContentTopOffset(
        context: context,
        isPortrait: MediaQuery.of(context).orientation == Orientation.portrait,
        bannerKey: _bannerMeasureKey,
      );
      fileOffset += policy.calculateScrollOffset(
        folderCount: matchedFolders.length,
        songIndex: fileIndex,
      );

      final targetOffset = policy.centerInViewport(
        itemOffset: fileOffset,
        viewportDimension: _scrollController.position.viewportDimension,
        maxScrollExtent: _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isAudioPlaying = ref.watch(audioIsPlayingProvider);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final double headerHeight = FolderNavBarScaffold.getBarHeight(context);
    final bottomOffset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
    );

    // Current directory audio stats
    final audioItems = _items.where((i) => i.isAudio).toList();
    final audioCount = audioItems.length;
    int totalDurationMs = 0;
    for (final item in audioItems) {
      final virtualUri =
          RemoteMediaResolver.buildRemoteUri(widget.server, item.path);
      final meta = _metadataMap[virtualUri] ??
          ref.watch(
            scannerServiceProvider.select((s) => s.metadataMap[virtualUri]),
          );
      if (meta?.duration != null) {
        totalDurationMs += meta!.duration!;
      }
    }

    // Banner cover finding logic:
    // Only search in current directory audio files for an existing thumbnail file. No deep recursive search.
    String? bannerCoverThumbnailPath;
    String? bannerCoverVirtualUri;
    for (final item in audioItems) {
      final virtualUri =
          RemoteMediaResolver.buildRemoteUri(widget.server, item.path);
      final meta = _metadataMap[virtualUri] ??
          ref.watch(
            scannerServiceProvider.select((s) => s.metadataMap[virtualUri]),
          );
      if (meta?.thumbnailPath != null &&
          File(meta!.thumbnailPath!).existsSync()) {
        bannerCoverThumbnailPath = meta.thumbnailPath;
        bannerCoverVirtualUri = virtualUri;
        break;
      }
    }

    // Current folder display name & subtitle
    final folderDisplayName =
        _isAtRoot ? widget.server.name : p.basename(_currentPath);
    final String folderDisplaySubtitle;
    if (_isAtRoot) {
      folderDisplaySubtitle = '';
    } else {
      final segments = _pathSegments;
      if (segments.length > 1) {
        folderDisplaySubtitle = segments[segments.length - 2];
      } else {
        folderDisplaySubtitle = widget.server.name;
      }
    }

    // Search filtering within current directory
    final displayedItems = _items;
    final matchedFolders = displayedItems.where((i) => i.isDirectory).toList();
    final matchedFiles = displayedItems.where((i) => !i.isDirectory).toList();

    // 主体内容现在挂在 `FolderZoomSliverBuilder.builder` 里，换档动画期间每帧都会
    // 重新执行一次 —— 这份列表必须先算好，不能留在闭包里按帧重建
    // （每条都要构造 `MusicFile` 并查元数据）。
    final displayedAudio = _getAudioFiles(sourceList: displayedItems);

    final Widget bannerCoverWidget = bannerCoverThumbnailPath != null
        ? SongThumbnail(
            path: bannerCoverVirtualUri!,
            thumbnailPath: bannerCoverThumbnailPath,
            size: 100,
            width: 100,
            height: 100,
            borderRadius: BorderRadius.zero,
          )
        : const SizedBox(
            width: 100,
            height: 100,
            child: DefaultCoverArt.cloudFolder(
              iconSize: 42,
            ),
          );

    /// 主体滚动区。
    ///
    /// [crossAxisExtent] 必须是这一层 `LayoutBuilder` 给出的宽度（内容区扣掉
    /// rail 与最大宽度约束之后的真实宽度）。不能让缩放网格退回 `MediaQuery` 的
    /// 窗口宽度：`FolderZoomSliverBuilder.width` 是横向坐标系的 `outerWidth`，
    /// 与网格真实的 `crossAxisExtent` 不等时，delegate 会按「内容在窗口里居中」
    /// 折算原点偏移。左侧让出了 rail 的窗口里那个折算结果是负值，整段条目就被
    /// 推到 rail 底下去。
    Widget buildMainContent(double crossAxisExtent) {
      Widget mainContent;
      if (_isLoading) {
        mainContent = CustomScrollView(
          key: ValueKey<String>(
              'webdav-browser-${widget.server.id}-$_currentPath'),
          controller: _scrollController,
          cacheExtent: 1000.0,
          slivers: [
            if (!isPortrait)
              SliverToBoxAdapter(
                child: SizedBox(height: headerHeight),
              ),
            SliverToBoxAdapter(
              child: _buildBanner(
                theme: theme,
                l10n: l10n,
                title: folderDisplayName,
                subtitle: folderDisplaySubtitle,
                audioCount: audioCount,
                totalDurationMs: totalDurationMs,
                bannerCoverThumbnailPath: bannerCoverThumbnailPath,
                bannerCoverVirtualUri: bannerCoverVirtualUri,
                bannerCoverWidget: bannerCoverWidget,
                topHeader: isPortrait
                    ? _buildBannerBreadcrumbs(context, headerHeight)
                    : null,
              ),
            ),
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          ],
        );
      } else if (_error != null) {
        mainContent = CustomScrollView(
          key: ValueKey<String>(
              'webdav-browser-${widget.server.id}-$_currentPath'),
          controller: _scrollController,
          cacheExtent: 1000.0,
          slivers: [
            if (!isPortrait)
              SliverToBoxAdapter(
                child: SizedBox(height: headerHeight),
              ),
            SliverToBoxAdapter(
              child: _buildBanner(
                theme: theme,
                l10n: l10n,
                title: folderDisplayName,
                subtitle: folderDisplaySubtitle,
                audioCount: audioCount,
                totalDurationMs: totalDurationMs,
                bannerCoverThumbnailPath: bannerCoverThumbnailPath,
                bannerCoverVirtualUri: bannerCoverVirtualUri,
                bannerCoverWidget: bannerCoverWidget,
                topHeader: isPortrait
                    ? _buildBannerBreadcrumbs(context, headerHeight)
                    : null,
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Error: $_error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () =>
                            _loadDirectory(_currentPath, forceRefresh: true),
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      } else if (_items.isEmpty) {
        mainContent = RefreshIndicator(
          onRefresh: () => _loadDirectory(_currentPath, forceRefresh: true),
          child: CustomScrollView(
            key: ValueKey<String>(
                'webdav-browser-${widget.server.id}-$_currentPath'),
            controller: _scrollController,
            cacheExtent: 1000.0,
            slivers: [
              if (!isPortrait)
                SliverToBoxAdapter(
                  child: SizedBox(height: headerHeight),
                ),
              SliverToBoxAdapter(
                child: _buildBanner(
                  theme: theme,
                  l10n: l10n,
                  title: folderDisplayName,
                  subtitle: folderDisplaySubtitle,
                  audioCount: audioCount,
                  totalDurationMs: totalDurationMs,
                  bannerCoverThumbnailPath: bannerCoverThumbnailPath,
                  bannerCoverVirtualUri: bannerCoverVirtualUri,
                  bannerCoverWidget: bannerCoverWidget,
                  topHeader: isPortrait
                    ? _buildBannerBreadcrumbs(context, headerHeight)
                    : null,
                ),
              ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(l10n.folderIsEmpty)),
              ),
            ],
          ),
        );
      } else {
        mainContent = RefreshIndicator(
          onRefresh: () => _loadDirectory(_currentPath, forceRefresh: true),
          child: CustomScrollView(
            key: ValueKey<String>(
                'webdav-browser-${widget.server.id}-$_currentPath'),
            controller: _scrollController,
            cacheExtent: 1000.0,
            slivers: [
              if (!isPortrait)
                SliverToBoxAdapter(
                  child: SizedBox(height: headerHeight),
                ),
              SliverToBoxAdapter(
                child: _buildBanner(
                  theme: theme,
                  l10n: l10n,
                  title: folderDisplayName,
                  subtitle: folderDisplaySubtitle,
                  audioCount: audioCount,
                  totalDurationMs: totalDurationMs,
                  bannerCoverThumbnailPath: bannerCoverThumbnailPath,
                  bannerCoverVirtualUri: bannerCoverVirtualUri,
                  bannerCoverWidget: bannerCoverWidget,
                  topHeader: isPortrait
                    ? _buildBannerBreadcrumbs(context, headerHeight)
                    : null,
                ),
              ),
              // 1. Subfolders Sliver (Grid or List according to zoomScale)
              if (matchedFolders.isNotEmpty)
                WebDavSubfoldersSliver(
                    folders: matchedFolders,
                    zoomScale: zoomScale,
                    crossAxisExtent: crossAxisExtent,
                    section: _kRemoteFolderSection,
                    server: widget.server,
                    password: widget.password,
                    isSelectionMode: _isSelectionMode,
                    selectedFolderPaths: _selectedFolderPaths,
                    onOpenFolder: (folder) => _openFolder(folder),
                    onFolderTap: (folder, index) {
                      SelectionActionHelper.handleItemTap(
                        index: index,
                        itemKey: folder.path,
                        items: matchedFolders,
                        keySelector: (f) => f.path,
                        isSelectionMode: _isSelectionMode,
                        selectedKeys: _selectedFolderPaths,
                        lastAnchorIndex: _lastFolderAnchorIndex,
                        onUpdateAnchor: (a) =>
                            setState(() => _lastFolderAnchorIndex = a),
                        onSetSelection: (keys) {
                          _selectionScopeNotifier
                              .setScope(LibrarySelectionScope.webdav);
                          setState(() {
                            _isSelectionMode = true;
                            _selectedFolderPaths.addAll(keys);
                          });
                        },
                        onToggleSelection: (key) => _toggleFolderSelection(key),
                        onEnterSelectionMode: () {
                          _selectionScopeNotifier
                              .setScope(LibrarySelectionScope.webdav);
                          setState(() => _isSelectionMode = true);
                        },
                        onNormalTap: () => _openFolder(folder),
                      );
                    },
                    onFolderLongPress: (folder, index) {
                      _lastFolderAnchorIndex = index;
                      if (!_isSelectionMode) {
                        _toggleSelectionMode();
                      }
                      _toggleFolderSelection(folder.path);
                    },
                    onToggleFolderSelection: _toggleFolderSelection,
                    onToggleSelectionMode: _toggleSelectionMode,
                    onShowFolderBottomSheet: _handleShowFolderBottomSheet,
                    folderCoverSongs: _folderCoverSongs,
                  ),

                // 2. Section divider if both folders and files exist
                if (matchedFolders.isNotEmpty && matchedFiles.isNotEmpty)
                  FolderSectionHeaderSliver(
                    title: l10n.songsCountFormat(matchedFiles.length),
                  ),

                // 3. Files/Songs Sliver (Grid or List according to zoomScale)
                if (matchedFiles.isNotEmpty)
                  WebDavSongsSliver(
                    files: matchedFiles,
                    zoomScale: zoomScale,
                    crossAxisExtent: crossAxisExtent,
                    section: _kRemoteFileSection,
                    server: widget.server,
                    password: widget.password,
                    metadataMap: _metadataMap,
                    currentMusicPath: currentMusic?.path,
                    highlightedSongPath: _highlightedSongPath,
                    isAudioPlaying: isAudioPlaying,
                    allAudioFiles: displayedAudio,
                    isSelectionMode: _isSelectionMode,
                    selectedSongPaths: _selectedSongPaths,
                    onSongTap: (file, index) => _handleSongTap(
                      file,
                      index,
                      displayedAudio,
                      matchedFiles,
                    ),
                    onSongLongPress: (file) => _handleSongLongPress(
                      file,
                      matchedFiles.indexOf(file),
                    ),
                    onSongSecondaryTapDown: (file, details) =>
                        _handleSongContextMenu(
                      file,
                      details.globalPosition,
                      displayedAudio,
                      displayedItems,
                    ),
                    bottomPadding: 0,
                  ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: bottomOffset,
                ),
              ),
            ],
          ),
        );
      }

      return mainContent;
    }

    final selectedSongs = _getSelectedSongs(sourceList: displayedItems);

    final selectedFoldersCount = _selectedFolderPaths.length;
    final selectedSongsCount = _selectedSongPaths.length;
    final totalSelectedCount = selectedFoldersCount + selectedSongsCount;
    final isSelectionEmpty = totalSelectedCount == 0;

    final allVisibleFoldersCount =
        displayedItems.where((i) => i.isDirectory).length;
    final allVisibleAudioCount =
        displayedItems.where((i) => !i.isDirectory && i.isAudio).length;
    final isAllSelected = (allVisibleFoldersCount + allVisibleAudioCount > 0) &&
        selectedFoldersCount == allVisibleFoldersCount &&
        selectedSongsCount == allVisibleAudioCount;

    final String selectionTitle;
    if (selectedFoldersCount > 0 && selectedSongsCount > 0) {
      selectionTitle =
          '${l10n.selectedFolders(selectedFoldersCount)}, ${l10n.selectedSongs(selectedSongsCount)}';
    } else if (selectedFoldersCount > 0) {
      selectionTitle = l10n.selectedFolders(selectedFoldersCount);
    } else {
      selectionTitle = l10n.selectedSongs(selectedSongsCount);
    }

    final page = AutoHideHeaderScope(
      enabled: false,
      forceVisible: _isSelectionMode,
      builder: (context, isHeaderVisible) {
        final scaffold = Scaffold(
      body: Stack(
        children: [
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: folderPageMaxWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _contentCrossAxisExtent = constraints.maxWidth;
                    return NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: FolderZoomGestureLayer(
                        child: FolderZoomSliverBuilder(
                          zoomScale: snapFolderZoomScale(zoomScale),
                          width: constraints.maxWidth,
                          // 这里**不能**传 `controller: _scrollController`。
                          // 本页按 `_isLoading` / `_error` / 空目录 / 有内容分成四个
                          // 分支，loading/error 是裸 `CustomScrollView`，另外两支套了
                          // `RefreshIndicator`。从 loading 切到有内容时 `RefreshIndicator`
                          // 插进来，整个 `ScrollView` 子树换了父级 → 新元素重建，而旧的
                          // `ScrollPosition` 要到本帧 `finalizeTree` 才 detach。若传了
                          // controller，`_FolderZoomSliverBuilderState._scrollPosition()`
                          // 在这中间的那次布局里读 `controller.position`，读到
                          // `_positions.length == 2` → 断言炸在 sliver 布局里，整页空白。
                          // 不传时走渲染树里"按布局校验挑一个 viewport"的路径，
                          // 自带对齐校验、能容忍这种一帧的重叠。
                          builder: (context, metrics) =>
                              buildMainContent(constraints.maxWidth),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (!isPortrait)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AutoHideHeader(
                  isVisible: isHeaderVisible,
                  child: _buildHeaderNavBar(context, isOverlay: true),
                ),
              ),
            if (isPortrait)
              FolderFloatingHeaderBar(
                visibleListenable: _showFloatingActions,
                isSelectionMode: _isSelectionMode,
                showBack: _pathSegments.isNotEmpty,
                onBack: _handleGoBack,
                backTooltip: l10n.goBack,
                contentMaxWidth: folderPageMaxWidth,
                trailingAction: PopupMenuButton<String>(
                  tooltip: l10n.more,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: theme.colorScheme.onSurface,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                    onSelected: (val) {
                      switch (val) {
                        case 'locate':
                          _locateCurrentSong();
                          break;
                        case 'sort':
                          _showSortDialog(context);
                          break;
                        case 'view_mode':
                          showFolderZoomPopover(context);
                          break;
                        case 'refresh':
                          _loadDirectory(_currentPath, forceRefresh: true);
                          break;
                        case 'downloads':
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const RemoteDownloadManagerPage(),
                            ),
                          );
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (currentMusic != null)
                        PopupMenuItem(
                          value: 'locate',
                          child: Row(
                            children: [
                              const Icon(Icons.my_location_rounded, size: 20),
                              const SizedBox(width: 12),
                              Text(l10n.locateCurrentSong),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'sort',
                        child: Row(
                          children: [
                            const Icon(Icons.sort_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.sortBy),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'view_mode',
                        child: Row(
                          children: [
                            ZoomTierIcon(
                              zoomScale: settings.folderZoomScale,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isFolderZoomGrid(settings.folderZoomScale)
                                  ? l10n.gridView
                                  : l10n.listView,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'refresh',
                        child: Row(
                          children: [
                            const Icon(Icons.refresh_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.refresh),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'downloads',
                        child: Row(
                          children: [
                            const Icon(Icons.download_rounded, size: 20),
                            const SizedBox(width: 12),
                            Text(l10n.downloadManager),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                reverseDuration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, 1.0),
                    end: Offset.zero,
                  ).animate(animation);
                  return SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  );
                },
                child: _isSelectionMode
                    ? LibrarySelectionPanel(
                        key: const ValueKey('webdav-selection-panel'),
                        selectedSongs: selectedSongs,
                        allSongs: displayedAudio,
                        title: selectionTitle,
                        isSelectionEmpty: isSelectionEmpty,
                        isAllSelected: isAllSelected,
                        hideSongProperties:
                            selectedFoldersCount > 0 || selectedSongsCount != 1,
                        onToggleSelectAll: () {
                          if (isAllSelected) {
                            _clearAllSelection();
                          } else {
                            _selectAllVisible(displayedItems);
                          }
                        },
                        onCancel: _clearAllSelection,
                        onPlayNext: () async {
                          final songs = await _resolveAllSelectedSongs(
                            sourceList: displayedItems,
                          );
                          if (songs.isNotEmpty) {
                            await ref.read(audioServiceProvider).enqueueNext(songs);
                            showToast(l10n.addedToQueue);
                          } else {
                            showToast('No audio files in selected items');
                          }
                          _clearAllSelection();
                        },
                        onAddToQueue: () async {
                          final songs = await _resolveAllSelectedSongs(
                            sourceList: displayedItems,
                          );
                          if (songs.isNotEmpty) {
                            await ref.read(audioServiceProvider).appendToQueue(songs);
                            showToast(l10n.addedToQueue);
                          } else {
                            showToast('No audio files in selected items');
                          }
                          _clearAllSelection();
                        },
                        onAddToPlaylist: () async {
                          final songs = await _resolveAllSelectedSongs(
                            sourceList: displayedItems,
                          );
                          if (songs.isNotEmpty && mounted) {
                            final playlistService =
                                ref.read(playlistServiceProvider);
                            await showAddSongsToPlaylistDialog(
                              context,
                              playlistService,
                              songs,
                            );
                          } else if (mounted) {
                            showToast('No audio files in selected items');
                          }
                          _clearAllSelection();
                        },
                        onAddToFavorites: () async {
                          final songs = await _resolveAllSelectedSongs(
                            sourceList: displayedItems,
                          );
                          if (songs.isNotEmpty && mounted) {
                            final playlistService =
                                ref.read(playlistServiceProvider);
                            await playlistService.addSongsToPlaylist(
                              PlaylistService.favoritePlaylistId,
                              songs,
                            );
                            AppSnackBar.show(
                              context,
                              ref,
                              SnackBar(
                                content: Text(
                                  l10n.addedToPlaylist(
                                    songs.length,
                                    l10n.favorites,
                                  ),
                                ),
                              ),
                            );
                          } else if (mounted) {
                            showToast('No audio files in selected items');
                          }
                          _clearAllSelection();
                        },
                        onDownload: () async {
                          final songs = await _resolveAllSelectedSongs(
                            sourceList: displayedItems,
                          );
                          if (songs.isEmpty) {
                            showToast(l10n.noActiveDownloads);
                            return;
                          }
                          final notifier =
                              ref.read(remoteDownloadTasksProvider.notifier);
                          final webDavFiles = <WebDavFile>[];
                          for (final song in songs) {
                            final uriInfo =
                                RemoteMediaResolver.parseUri(song.path);
                            final remotePath = (uriInfo != null &&
                                    (uriInfo.type == RemoteServerType.webdav ||
                                        uriInfo.type ==
                                            RemoteServerType.smb))
                                ? uriInfo.trackIdOrPath
                                : null;
                            if (remotePath != null) {
                              webDavFiles.add(WebDavFile(
                                path: remotePath,
                                name: p.basename(remotePath),
                                isDirectory: false,
                                contentLength: 0,
                              ));
                            }
                          }
                          if (webDavFiles.isNotEmpty && mounted) {
                            await notifier.enqueueWebDavFiles(
                              server: widget.server,
                              password: widget.password,
                              files: webDavFiles,
                            );
                            showRemoteDownloadQueuedFeedback(
                              context,
                              ref,
                              webDavFiles.length,
                            );
                          }
                          _clearAllSelection();
                        },
                        onTranscode: () async {
                          final songs = await _resolveAllSelectedSongs(
                            sourceList: displayedItems,
                          );
                          if (songs.isNotEmpty && mounted) {
                            await showTranscodeDialog(
                              context,
                              songs: songs,
                            );
                          } else if (mounted) {
                            showToast('No audio files in selected items');
                          }
                          _clearAllSelection();
                        },
                        onAddToMediaLibrary: _selectedFolderPaths.isEmpty
                            ? null
                            : () async {
                                final folderPaths =
                                    List<String>.from(_selectedFolderPaths);
                                _clearAllSelection();
                                int addedCount = 0;
                                final rootsNotifier =
                                    ref.read(remoteScanRootsProvider.notifier);
                                final scanner =
                                    ref.read(remoteDirectoryScannerProvider);
                                for (final folderPath in folderPaths) {
                                  final scanRoot = RemoteScanRoot(
                                    id: RemoteScanRoot.generateId(
                                      widget.server.id,
                                      folderPath,
                                    ),
                                    serverId: widget.server.id,
                                    serverType: widget.server.type,
                                    serverName: widget.server.name,
                                    remotePath: folderPath,
                                    virtualUri:
                                        RemoteScanRoot.generateVirtualUri(
                                      widget.server,
                                      folderPath,
                                    ),
                                    addedAt:
                                        DateTime.now().millisecondsSinceEpoch,
                                  );
                                  final added =
                                      await rootsNotifier.addRoot(scanRoot);
                                  if (added) {
                                    addedCount++;
                                    unawaited(scanner.scanRoot(
                                      server: widget.server,
                                      password: widget.password,
                                      root: scanRoot,
                                    ));
                                  }
                                }
                                if (addedCount > 0) {
                                  final currentRoots = ref
                                          .read(remoteScanRootsProvider)
                                          .asData
                                          ?.value ??
                                      [];
                                  ref
                                      .read(scannerServiceProvider)
                                      .setRemoteRoots(currentRoots);
                                  showToast(l10n.addedToMediaLibrary);
                                } else {
                                  showToast(l10n.remoteFolderAlreadyIndexed);
                                }
                              },
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('webdav-selection-panel-hidden'),
                      ),
              ),
            ),
          ],
        ),
      );

        final content = PopScope(
          canPop: !_isSelectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _clearAllSelection();
          },
          child: scaffold,
        );

        if (widget.wrapWithMiniPlayer) {
          return MiniPlayerWrapper(child: content);
        }
        return content;
      },
    );

    return page;
  }

  Widget _buildBanner({
    required ThemeData theme,
    required AppLocalizations l10n,
    required String title,
    required String subtitle,
    required int audioCount,
    required int totalDurationMs,
    required String? bannerCoverThumbnailPath,
    String? bannerCoverVirtualUri,
    required Widget bannerCoverWidget,
    Widget? topHeader,
  }) {
    return KeyedSubtree(
      key: _bannerMeasureKey,
      child: ValueListenableBuilder<bool>(
        valueListenable: _isCoverVisible,
        builder: (context, isCoverVisible, _) {
          return FolderHeaderBanner(
            title: title,
            subtitle: subtitle,
            songsCount: audioCount,
            totalDuration: Duration(milliseconds: totalDurationMs),
            songPath: bannerCoverVirtualUri,
            coverImagePath: bannerCoverThumbnailPath,
            coverWidget: bannerCoverWidget,
            topHeader: topHeader,
            heroTag: 'webdav-cover-$_currentPath',
            isHeroModeEnabled: isCoverVisible &&
                (ref.watch(settingsServiceProvider).folderZoomScale -
                            _initialZoomScale)
                        .abs() <=
                    1e-4,
            actionButtons: [
              FolderPlayActionButtons(
                totalSongsCount: audioCount,
                onPlayAll: audioCount > 0 ? () => _playFolder(shuffle: false) : () {},
                onShufflePlay:
                    audioCount > 0 ? () => _playFolder(shuffle: true) : () {},
              ),
            ],
            actionButtonsScrollable: false,
            onSearch: _openSearchPage,
          );
        },
      ),
    );
  }

  Widget _buildBannerBreadcrumbs(BuildContext context, double headerHeight) {
    final style = FolderNavBarStyle.overlay(context);
    final l10n = AppLocalizations.of(context)!;
    final breadcrumbItems = _buildBreadcrumbItems(style);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final settings = ref.watch(settingsServiceProvider);
    final activeDownloadsCount = ref.watch(activeDownloadsCountProvider);
    final actions = _buildHeaderActions(
      context,
      style,
      l10n,
      currentMusic,
      settings,
      activeDownloadsCount,
    );
    final canGoBack = _pathSegments.isNotEmpty;

    const bannerHorizontalInsetCompensation = -8.0;

    return SizedBox(
      height: headerHeight,
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: EdgeInsets.only(
            top: FolderNavBarScaffold.getContentTopInset(context),
          ),
          child: Transform.translate(
            offset: const Offset(bannerHorizontalInsetCompensation, 0),
            child: Row(
              children: [
                if (canGoBack) ...[
                  FolderBreadcrumbItem(
                    style: style,
                    icon: kAppBackIcon,
                    iconSize: 22,
                    tooltip: l10n.goBack,
                    onTap: _handleGoBack,
                  ),
                  FolderBreadcrumbSeparator(style: style),
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        controller: _breadcrumbsScrollController,
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(children: breadcrumbItems),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                actions,
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBreadcrumbItems(FolderNavBarStyle style) {
    final List<Widget> items = [];
    final segments = _pathSegments;

    // Server root (Icon + Name)
    final rootContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_queue_rounded,
          size: 18,
          color: style.iconColor,
          shadows: style.shadows,
        ),
        const SizedBox(width: 6),
        Text(
          widget.server.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: style.folderTextColor,
            shadows: style.shadows,
          ),
        ),
      ],
    );

    items.add(
      FolderBreadcrumbItem(
        style: style,
        onTap: segments.isEmpty ? null : () => _navigateToBreadcrumb(-1),
        child: rootContent,
      ),
    );

    for (int i = 0; i < segments.length; i++) {
      final isLast = i == segments.length - 1;
      items.add(FolderBreadcrumbSeparator(style: style));
      items.add(
        FolderBreadcrumbItem(
          style: style,
          label: segments[i],
          onTap: isLast ? null : () => _navigateToBreadcrumb(i),
        ),
      );
    }

    return items;
  }

  Widget _buildHeaderActions(
    BuildContext context,
    FolderNavBarStyle style,
    AppLocalizations l10n,
    MusicFile? currentMusic,
    SettingsService settings,
    int activeDownloadsCount,
  ) {
    if (style.isPortrait) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FolderScanSpinner(style: style),
          FolderNavActionMenu<String>(
            style: style,
            onSelected: (value) {
              if (value == 'search') {
                _openSearchPage();
              } else if (value == 'locate') {
                _locateCurrentSong();
              } else if (value == 'sort') {
                _showSortDialog(context);
              } else if (value == 'view_mode') {
                showFolderZoomPopover(context);
              } else if (value == 'refresh') {
                _loadDirectory(_currentPath, forceRefresh: true);
              } else if (value == 'downloads') {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => const RemoteDownloadManagerPage(),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'search',
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.search),
                  ],
                ),
              ),
              if (currentMusic != null)
                PopupMenuItem(
                  value: 'locate',
                  child: Row(
                    children: [
                      const Icon(Icons.my_location_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.locateCurrentSong),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'sort',
                child: Row(
                  children: [
                    const Icon(Icons.sort_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.sortBy),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'view_mode',
                child: Row(
                  children: [
                    ZoomTierIcon(
                      zoomScale: settings.folderZoomScale,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isFolderZoomGrid(settings.folderZoomScale)
                          ? l10n.gridView
                          : l10n.listView,
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh_rounded, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.refreshResults),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'downloads',
                child: Row(
                  children: [
                    Badge(
                      isLabelVisible: activeDownloadsCount > 0,
                      label: Text('$activeDownloadsCount'),
                      child: const Icon(Icons.download_rounded, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(l10n.downloadManager),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FolderScanSpinner(style: style),
          FolderNavIconButton(
            style: style,
            tooltip: l10n.search,
            icon: Icon(
              Icons.search_rounded,
              size: 20,
              color: style.iconColor,
              shadows: style.shadows,
            ),
            onPressed: _openSearchPage,
          ),
          if (currentMusic != null) ...[
            LocateSongNavButton(
              style: style,
              tooltip: l10n.locateCurrentSong,
              onPressed: _locateCurrentSong,
            ),
          ],
          FolderNavIconButton(
            style: style,
            tooltip: l10n.sortBy,
            icon: Icon(
              Icons.sort_rounded,
              size: 20,
              color: style.iconColor,
              shadows: style.shadows,
            ),
            onPressed: () => _showSortDialog(context),
          ),
          FolderZoomNavButton(style: style),
          FolderNavIconButton(
            style: style,
            tooltip: l10n.refreshResults,
            icon: Icon(
              Icons.refresh_rounded,
              size: 20,
              color: style.iconColor,
              shadows: style.shadows,
            ),
            onPressed: () =>
                _loadDirectory(_currentPath, forceRefresh: true),
          ),
          FolderNavIconButton(
            style: style,
            tooltip: l10n.downloadManager,
            badge: activeDownloadsCount > 0
                ? Text('$activeDownloadsCount')
                : null,
            icon: Icon(
              Icons.download_rounded,
              size: 20,
              color: style.iconColor,
              shadows: style.shadows,
            ),
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => const RemoteDownloadManagerPage(),
                ),
              );
            },
          ),
        ],
      );
    }
  }

  void _handleGoToFoldersRoot() {
    _clearAllSelection();
    final hasActiveSession = ref.read(activeRemoteSessionProvider) != null;
    if (hasActiveSession) {
      ref.read(activeRemoteSessionProvider.notifier).clear();
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Widget _buildPinnedLeading(
    BuildContext context,
    FolderNavBarStyle style,
    AppLocalizations l10n,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FolderBreadcrumbItem(
          style: style,
          icon: Icons.home_rounded,
          tooltip: l10n.backToRootDirectory,
          onTap: _handleGoToFoldersRoot,
        ),
        FolderBreadcrumbSeparator(style: style),
      ],
    );
  }

  Widget _buildHeaderNavBar(BuildContext context, {bool isOverlay = true}) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final settings = ref.watch(settingsServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final activeDownloadsCount = ref.watch(activeDownloadsCountProvider);

    return FolderNavBarScaffold(
      isOverlay: isOverlay,
      scrollProgress: _scrollProgress,
      onGoBack: _handleGoBack,
      scrollController: _breadcrumbsScrollController,
      pinnedLeadingBuilder: (context, style) =>
          _buildPinnedLeading(context, style, l10n),
      breadcrumbItemsBuilder: (context, style) =>
          _buildBreadcrumbItems(style),
      actionsBuilder: (context, style) => _buildHeaderActions(
        context,
        style,
        l10n,
        currentMusic,
        settings,
        activeDownloadsCount,
      ),
    );
  }
}
