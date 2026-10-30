import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_storage_listener/mobile_storage_event.dart';
import 'package:mobile_storage_listener/mobile_storage_listener.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/scanner/scanner_navigation_state.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';
import 'package:vynody/player/scanner/scanner_scan_pipeline.dart';
import 'package:vynody/player/scanner/scanner_scan_coordinator.dart';
import 'package:vynody/player/scanner/scanner_directory_scanner.dart';
import 'package:vynody/player/scanner/scanner_metadata_store.dart';
import 'package:vynody/player/scanner/scanner_repository.dart';
import 'package:vynody/player/scanner/scanner_state.dart';
import 'package:vynody/player/scanner/scanner_tree_builder.dart';
import 'package:vynody/player/scanner/scanner_service_roots.dart';
import 'package:vynody/player/scanner/scanner_scan_support.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/metadata/artwork_constants.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/settings/track_artwork_theme_service.dart';
import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/linux_mount_helper.dart';
import 'package:vynody/player/scanner/folder_cover_resolver.dart';
import 'package:linux_directory_access/linux_directory_access.dart';
import 'package:vynody/player/remote/services/remote_scan_root.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';

export 'package:vynody/player/scanner/scanner_scan_support.dart';

AppLocalizations _l10n() => currentAppL10n;

enum _DirectoryRescanMode { nonRecursive, recursive }

class ScannerService extends ChangeNotifier with WidgetsBindingObserver {
  final ScannerFolderSorter _folderSorter = const ScannerFolderSorter();
  final Duration _directoryRescanBatchWindow;
  final Completer<void> _readyCompleter = Completer<void>();
  AudioCoreController? _playerController;
  void Function(String path, bool isMissing)? _songMissingStateHandler;
  void Function(Iterable<String> paths, Iterable<String> rootPaths)?
      _songsPurgedHandler;
  StreamSubscription? _mediaObserverSubscription;
  bool _mediaObserverPaused = false;
  final MobileStorageListener _mobileStorageListener = MobileStorageListener();
  final LinuxDirectoryAccess _linuxDirectoryAccess = LinuxDirectoryAccess();
  StreamSubscription<MobileStorageEvent>? _mobileStorageSubscription;
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();
  final ScannerNavigationState _navigationState = ScannerNavigationState();
  final List<MusicFolder> _scannedRootFolders = [];
  final List<MusicFolder> _rootFolders = [];
  /// [_rootFolders] 的缓存视图。必须复用同一实例，否则
  /// `select((s) => s.rootFolders)` 会因为每次拿到新的 List 而永不判等，
  /// 退化成「无 select 的全量订阅」。结构变化时由
  /// [_refreshStructureRevision] 置空以重建视图。
  List<MusicFolder>? _rootFoldersView;
  final Map<String, bool> _rootAvailability = {};
  final List<SongMetadata> _pendingStage3IncrementalMetadata = [];
  Timer? _metadataNotifyTimer;
  Timer? _scanNotifyTimer;
  Timer? _rootAvailabilityRefreshTimer;
  Timer? _rootAvailabilityTimer;
  Timer? _directoryRescanTimer;
  bool _scanNotifyPending = false;
  bool _lastNotifiedScanningState = false;
  bool _pendingRootAvailabilityRescan = false;
  bool _directoryRescanInProgress = false;
  bool _isDisposed = false;
  final Set<String> _activeScopedRootPaths = <String>{};
  final Map<String, _DirectoryRescanMode> _pendingDirectoryRescanPaths = {};
  final Set<String> _failedThumbnailPaths = <String>{};
  final Map<String, int> _watchedFileMtimes = {};
  int _lastScanProgressEmitMs = 0;

  MusicFolder? _systemMediaFolder;
  /// 系统媒体元数据后台重读的在途任务。
  ///
  /// 启动期 `scanSystemMedia()` 会被多条入口各触发一次（权限检查、`scan()`、
  /// 媒体观察者），每次扫完都 `unawaited` 地起一场「重读全部条目」的后台任务。
  /// 两场并发时同一路径会在 `processMetadata` 的「读库 → 写库」窗口里撞车
  /// （UNIQUE constraint failed: songs.path），还会把上千个文件的标签读两遍。
  Future<void>? _androidMediaMetadataInFlight;
  /// 在途期间又被请求重读的最新一批条目。
  List<AndroidMediaLibraryEntry>? _pendingAndroidMediaEntries;
  bool _hasPermission = false;
  late final ScannerServiceRoots _roots;
  late final ScannerMetadataStore _metadataStore;
  late final ScannerScanPipeline _scanPipeline;
  late final ScannerRepository _repository;
  late final ScannerScanCoordinator _scanCoordinator;
  late final ScannerTreeBuilder _treeBuilder;
  late final ScannerDirectoryScanner _directoryScanner;
  int _metadataRevision = 0;
  int _albumLibraryRevision = 0;
  /// 「显示树 + 导航历史」的结构版本号。
  ///
  /// 只在根目录增删/替换、系统媒体库切换、导航切换这类真正影响列表结构的事件上递增。
  /// 缩略图路径等纯封面元数据更新不会改变它，因此列表页订阅这个值而不是整个
  /// [ScannerService]，就不会因为一屏缩略图逐张生成而反复整页重建。
  /// 缩略图自身的刷新由 SongThumbnail 内部的 select 负责。
  int _structureRevision = 0;
  int? _lastStructureFingerprint;
  bool _skipShortAudioScanEnabled = false;
  int _skipShortAudioScanThresholdSeconds = _defaultShortAudioThresholdSeconds;
  bool _linuxFlatpak = false;
  final Map<String, String> _linuxDocumentIds = {};
  /// 目录统计的内存镜像，键是归一化目录路径，覆盖所有层级（不只根）。
  ///
  /// 值来自 `folder_entries` 表或本次会话的扫描结果；`MusicFolder` 树里有值时不读它，
  /// 只作为「树还没建好 / 该目录不在当前树里」时的回落，避免目录页先显示 0 首歌。
  final Map<String, int> _folderSongCounts = {};
  final Map<String, int> _folderSongDurations = {};
  final Map<String, SongMetadata?> _folderRepresentativeSongs = {};
  final Map<String, String> _folderRepresentativeSongPaths = {};
  final Set<String> _loadedRootPaths = {};
  Set<String>? _cachedActiveScanRootLookupKeys;

  static const String _keyGlobalSortCriteria = 'folder_sort_global_criteria';
  static const String _keyGlobalSortOrder = 'folder_sort_global_order';
  static const String _keyFolderSortOverrides = 'folder_sort_overrides';

  /// 从未写过排序设置时的默认值：按音轨号升序。
  ///
  /// 不能改 [SortCriteriaX.fromStorageValue] 的兜底值——WebDAV 浏览用的是
  /// 同一个枚举，那边的默认仍是文件名。
  static const SortCriteria _defaultSortCriteria = SortCriteria.trackNumber;
  static const int _defaultShortAudioThresholdSeconds = 30;
  static const bool _scanTimingEnabled = false;
  static const Duration _defaultDirectoryRescanBatchWindow = Duration(
    milliseconds: 900,
  );

  SortCriteria _globalSortCriteria = _defaultSortCriteria;
  SortOrder _globalSortOrder = SortOrder.ascending;
  Map<String, FolderSortSettings> _folderSortOverrides = {};

  SortCriteria get globalSortCriteria => _globalSortCriteria;
  SortOrder get globalSortOrder => _globalSortOrder;
  bool get skipShortAudioScanEnabled => _skipShortAudioScanEnabled;
  int get skipShortAudioScanThresholdSeconds =>
      _skipShortAudioScanThresholdSeconds;
  bool get _supportsPersistentAccess =>
      Platform.isMacOS || Platform.isIOS || _linuxFlatpak;

  List<String> get rootPaths => _roots.rootPaths;
  List<MusicFolder> get rootFolders =>
      _rootFoldersView ??= List.unmodifiable(_rootFolders);
  bool get isScanning => _scanCoordinator.isScanning;
  bool get isBackgroundTaskPaused => _scanCoordinator.isBackgroundPaused;
  ScannerRuntimeState get runtimeState => _scanCoordinator.state;
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  // Navigation state for FoldersPage
  MusicFolder? get navigationCurrentFolder => _navigationState.currentFolder;

  List<MusicFolder> get navigationHistory => _navigationState.history;

  void setNavigationState(MusicFolder? current, List<MusicFolder> history) {
    if (kDebugMode) {
      debugPrint(
        '[ScannerService][timing] setNavigationState current=${current?.path ?? "null"} '
        'history=${history.length}',
      );
    }
    _navigationState.setState(current, history);

    if (current != null) {
      final normalizedPath = _normalizePath(current.path);
      if (normalizedPath != 'system') {
        final rootPath = _roots.rootPaths.firstWhereOrNull(
          (root) =>
              _pathsEqual(root, normalizedPath) ||
              _pathContains(root, normalizedPath),
        );
        if (rootPath != null) {
          unawaited(loadRootFolderSongs(rootPath));
        }
      }
    } else {
      unloadAllRootFolders();
    }
  }

  Future<void> loadRootFolderSongs(String rootPath) async {
    // [ScannerService][timing]：定位「首次进目录卡、之后再进不卡」用的埋点。
    // skip 分支 = 命中缓存（不产生任何重活）；reload 分支 = 又重新读库+建树+排序。
    // 用 !kReleaseMode：debug 的 JIT 会把首次执行放大 5~10 倍，profile 才是可信数字。
    final totalSw = !kReleaseMode ? (Stopwatch()..start()) : null;
    final stepSw = !kReleaseMode ? (Stopwatch()..start()) : null;

    final normalized = _normalizePath(rootPath);
    final alreadyLoaded = _loadedRootPaths.contains(normalized);
    final hasScannedFolder = _scannedRootFolders.any(
      (f) => _pathsEqual(f.path, normalized),
    );
    if (alreadyLoaded && hasScannedFolder) {
      if (!kReleaseMode) {
        debugPrint(
          '[ScannerService][timing] loadRootFolderSongs skip $normalized '
          '(loaded=true scannedTree=true)',
        );
      }
      return;
    }

    final songs = await _repository.getSongsUnderPath(normalized);
    final dbMs = stepSw?.elapsedMilliseconds;
    stepSw?.reset();

    final cachedFolder = _buildCachedFolderTree(
      songs: songs,
      rootPath: normalized,
      rootName: _displayNameForPath(normalized),
    );
    final buildMs = stepSw?.elapsedMilliseconds;
    stepSw?.reset();

    if (cachedFolder == null) {
      if (!kReleaseMode) {
        debugPrint(
          '[ScannerService][timing] loadRootFolderSongs abort $normalized '
          'songs=${songs.length} db=$dbMs ms build=$buildMs ms '
          'total=${totalSw?.elapsedMilliseconds} ms',
        );
      }
      return;
    }

    _folderSorter.sortFolderRecursiveForTree(
      cachedFolder,
      resolveSettings: _resolveSortSettingsForFolder,
    );
    final sortMs = stepSw?.elapsedMilliseconds;
    stepSw?.reset();

    _upsertScannedRootFolder(cachedFolder);
    _seedMetadataCache(songs);
    _loadedRootPaths.add(normalized);
    _rebuildDisplayedRootFolders();
    _syncNavigationStateToLatestTree();
    final applyMs = stepSw?.elapsedMilliseconds;
    stepSw?.reset();

    // notifyListeners() 内部会对全树 folder.invalidateCache()，单列一项看它多贵。
    notifyListeners();
    final notifyMs = stepSw?.elapsedMilliseconds;

    if (!kReleaseMode) {
      debugPrint(
        '[ScannerService][timing] loadRootFolderSongs RELOAD $normalized '
        'songs=${songs.length} db=$dbMs ms build=$buildMs ms sort=$sortMs ms '
        'apply=$applyMs ms notify=$notifyMs ms '
        'total=${totalSw?.elapsedMilliseconds} ms '
        '(loadedBefore=$alreadyLoaded scannedTreeBefore=$hasScannedFolder)',
      );
    }
  }

  void unloadAllRootFolders() {
    // Keep scanned root folders in memory so root directory covers remain stable.
    return;
  }

  int getSongCountForFolder(MusicFolder folder) {
    if (folder.path == 'system') {
      return _systemMediaFolder?.songCount ?? 0;
    }
    final count = folder.songCount;
    if (count > 0) {
      return count;
    }
    final normalized = _normalizePath(folder.path);
    return _folderSongCounts[normalized] ?? 0;
  }

  int getSongDurationForFolder(MusicFolder folder) {
    if (folder.path == 'system') {
      return _systemMediaFolder?.totalDurationMs ?? 0;
    }
    final duration = folder.totalDurationMs;
    if (duration > 0) {
      return duration;
    }
    final normalized = _normalizePath(folder.path);
    return _folderSongDurations[normalized] ?? 0;
  }

  void _updateFolderRepSongCache(MusicFolder folder, String songPath, SongMetadata updated) {
    if (folder.representativeSongCache != null &&
        (_pathsEqual(folder.representativeSongCache!.path, songPath) ||
            _pathsEqual(
              ScannerPathUtils.resolveIosSandboxPath(folder.representativeSongCache!.path),
              ScannerPathUtils.resolveIosSandboxPath(songPath),
            ))) {
      folder.representativeSongCache = _treeBuilder.musicFileFromSongMetadata(updated);
    }
    for (final sub in folder.subFolders) {
      _updateFolderRepSongCache(sub, songPath, updated);
    }
  }

  MusicFile? getRepresentativeSongForFolder(MusicFolder folder) {
    if (folder.representativeSongCache != null) {
      final rep = folder.representativeSongCache!;
      final resolvedRepPath = ScannerPathUtils.resolveIosSandboxPath(rep.path);
      final latestMeta = _metadataStore.getMetadata(rep.path) ?? _metadataStore.getMetadata(resolvedRepPath);
      if (latestMeta != null &&
          (rep.thumbnailPath?.isEmpty ?? true) &&
          (latestMeta.thumbnailPath?.isNotEmpty ?? false)) {
        folder.representativeSongCache = _treeBuilder.musicFileFromSongMetadata(latestMeta);
      }
      return folder.representativeSongCache;
    }

    final normalized = _normalizePath(folder.path);
    final resolvedNormalized = _normalizePath(ScannerPathUtils.resolveIosSandboxPath(folder.path));

    final cachedMeta = _folderRepresentativeSongs[normalized] ?? _folderRepresentativeSongs[resolvedNormalized];
    if (cachedMeta != null) {
      final file = _treeBuilder.musicFileFromSongMetadata(cachedMeta);
      folder.representativeSongCache = file;
      return file;
    }

    final songPath = _folderRepresentativeSongPaths[normalized] ?? _folderRepresentativeSongPaths[resolvedNormalized];
    if (songPath != null) {
      final resolvedSongPath = ScannerPathUtils.resolveIosSandboxPath(songPath);
      final meta = _metadataStore.getMetadata(songPath) ?? _metadataStore.getMetadata(resolvedSongPath);
      if (meta != null) {
        _folderRepresentativeSongs[normalized] = meta;
        final file = _treeBuilder.musicFileFromSongMetadata(meta);
        folder.representativeSongCache = file;
        return file;
      }
      final directSong = folder.files.firstWhereOrNull(
        (f) => _pathsEqual(f.path, songPath) || _pathsEqual(f.path, resolvedSongPath),
      );
      if (directSong != null) {
        folder.representativeSongCache = directSong;
        return directSong;
      }
    }

    // Fallback: evaluate on-the-fly from folder tree so UI always has a cover!
    final direct = FolderCoverResolver.evaluateRepresentativeSongForFolderSync(folder);
    if (direct != null) {
      folder.representativeSongCache = direct;
      return direct;
    }

    return null;
  }

  List<MusicFolder>? _findFolderChainInTree(
    MusicFolder current,
    String targetNormalized,
  ) {
    if (_normalizePath(current.path) == targetNormalized) {
      return [current];
    }
    for (final sub in current.subFolders) {
      final chain = _findFolderChainInTree(sub, targetNormalized);
      if (chain != null) {
        return [current, ...chain];
      }
    }
    return null;
  }

  List<MusicFolder>? findFolderChain(String path) {
    final normalized = _normalizePath(path);
    for (final root in _scannedRootFolders) {
      final chain = _findFolderChainInTree(root, normalized);
      if (chain != null) return chain;
    }
    if (_systemMediaFolder != null) {
      final chain = _findFolderChainInTree(_systemMediaFolder!, normalized);
      if (chain != null) return chain;
    }
    return null;
  }

  Future<void> refreshFolderCoverChain(String folderPath) async {
    final chain = findFolderChain(folderPath);
    if (chain == null || chain.isEmpty) return;

    final updatedCovers = <String, FolderCoverSnapshot>{};
    final removedFolderPaths = <String>[];
    bool hasChanged = false;

    // Traverse upwards from target folder (chain.last) to root (chain.first)
    for (int i = chain.length - 1; i >= 0; i--) {
      final folder = chain[i];
      final normFolder = _normalizePath(folder.path);
      final oldSongPath = _folderRepresentativeSongPaths[normFolder];

      final newRep = await FolderCoverResolver.evaluateRepresentativeSongForFolder(
        folder,
      );
      folder.representativeSongCache = newRep;
      final newSongPath = newRep != null ? _normalizePath(newRep.path) : null;

      // Early-exit check: if representative song did not change and this is an ancestor, stop bubbling up!
      if (newSongPath == oldSongPath && i < chain.length - 1) {
        break;
      }

      if (newSongPath != oldSongPath) {
        hasChanged = true;
      }

      if (newSongPath != null) {
        final rep = newRep!;
        _folderRepresentativeSongPaths[normFolder] = newSongPath;
        final meta = _metadataStore.getMetadata(newSongPath);
        if (meta != null) {
          _folderRepresentativeSongs[normFolder] = meta;
        }
        updatedCovers[normFolder] = FolderCoverSnapshot(
          songPath: newSongPath,
          thumbnailPath: rep.thumbnailPath ?? meta?.thumbnailPath,
          artworkPath: rep.artworkPath ?? meta?.artworkPath,
        );
      } else {
        _folderRepresentativeSongPaths.remove(normFolder);
        _folderRepresentativeSongs.remove(normFolder);
        removedFolderPaths.add(normFolder);
      }
    }

    if (updatedCovers.isNotEmpty) {
      await _repository.batchWriteFolderCovers(updatedCovers);
    }
    if (removedFolderPaths.isNotEmpty) {
      // 只清封面列：这些目录仍然存在于库里，统计不能跟着删。
      await _repository.clearFolderEntryCovers(removedFolderPaths);
    }
    if (hasChanged) {
      notifyListeners();
    }
  }

  final Set<String> _pendingFolderCoverRefreshPaths = <String>{};
  Timer? _folderCoverRefreshTimer;

  /// Enqueues a debounced folder cover refresh.
  /// Deduplicates calls when many song thumbnails or tags update simultaneously in the same directory.
  void enqueueFolderCoverChainRefresh(String folderPath) {
    final norm = _normalizePath(folderPath);
    if (norm.isEmpty) return;
    _pendingFolderCoverRefreshPaths.add(norm);
    _folderCoverRefreshTimer ??= Timer(const Duration(milliseconds: 200), () {
      _folderCoverRefreshTimer = null;
      unawaited(_flushPendingFolderCoverRefreshes());
    });
  }

  Future<void> _flushPendingFolderCoverRefreshes() async {
    if (_pendingFolderCoverRefreshPaths.isEmpty || _isDisposed) return;
    final paths = _pendingFolderCoverRefreshPaths.toList(growable: false);
    _pendingFolderCoverRefreshPaths.clear();
    for (final path in paths) {
      if (_isDisposed) break;
      await refreshFolderCoverChain(path);
    }
  }

  Future<void> updateSongThumbnailPath(
    String path,
    String thumbnailPath,
  ) async {
    final existingMeta = _metadataStore.getMetadata(path);
    if (existingMeta != null) {
      if (existingMeta.thumbnailPath != null &&
          existingMeta.thumbnailPath!.isNotEmpty &&
          File(existingMeta.thumbnailPath!).existsSync()) {
        return;
      }
      final updated = existingMeta.copyWith(thumbnailPath: thumbnailPath);
      _metadataStore.cacheMetadata(updated);
      final normSongPath = _normalizePath(path);
      for (final entry in _folderRepresentativeSongs.entries) {
        if (entry.value != null && _normalizePath(entry.value!.path) == normSongPath) {
          _folderRepresentativeSongs[entry.key] = updated;
        }
      }
      for (final root in _scannedRootFolders) {
        _updateFolderRepSongCache(root, path, updated);
      }
      if (_systemMediaFolder != null) {
        _updateFolderRepSongCache(_systemMediaFolder!, path, updated);
      }
      await MetadataDatabase().insertOrUpdateSong(updated);
      // 缩略图路径只是补全封面，不改变列表结构。走 150ms 节流而非立即全量通知，
      // 否则一屏缩略图逐张生成时会连续触发整页重建。
      // SongThumbnail 自身已通过 setState 立即展示新封面，无需同步广播。
      _scheduleMetadataNotify();
      enqueueFolderCoverChainRefresh(p.dirname(path));
    } else {
      final db = MetadataDatabase();
      final dbMetadata = await db.getSongMetadata(path);
      if (dbMetadata != null) {
        if (dbMetadata.thumbnailPath != null &&
            dbMetadata.thumbnailPath!.isNotEmpty &&
            File(dbMetadata.thumbnailPath!).existsSync()) {
          return;
        }
        final updated = dbMetadata.copyWith(thumbnailPath: thumbnailPath);
        _metadataStore.cacheMetadata(updated);
        final normSongPath = _normalizePath(path);
        for (final entry in _folderRepresentativeSongs.entries) {
          if (entry.value != null && _normalizePath(entry.value!.path) == normSongPath) {
            _folderRepresentativeSongs[entry.key] = updated;
          }
        }
        for (final root in _scannedRootFolders) {
          _updateFolderRepSongCache(root, path, updated);
        }
        if (_systemMediaFolder != null) {
          _updateFolderRepSongCache(_systemMediaFolder!, path, updated);
        }
        await db.insertOrUpdateSong(updated);
        // 同上：缩略图更新走节流通知，避免整页重建。
        _scheduleMetadataNotify();
        enqueueFolderCoverChainRefresh(p.dirname(path));
      }
    }
  }

  Future<List<MusicFile>> getAllRootSongs() async {
    final allSongs = <MusicFile>[];
    final seen = <String>{};
    // 1. Load and traverse root folder trees in natural directory order
    for (final root in _roots.rootPaths) {
      await loadRootFolderSongs(root);
    }
    for (final rootFolder in _rootFolders) {
      for (final song in rootFolder.allSongs) {
        if (seen.add(song.path)) {
          allSongs.add(song);
        }
      }
    }
    // 2. Get system media songs
    if (Platform.isAndroid) {
      if (_systemMediaFolder != null) {
        for (final song in _systemMediaFolder!.allSongs) {
          if (seen.add(song.path)) {
            allSongs.add(song);
          }
        }
      }
    }
    return allSongs;
  }

  MusicFolder? resolveFolderForPath(String path) {
    if (path == 'system') return _systemMediaFolder;
    return _treeBuilder.resolveFolderForPath(
      path,
      _scannedRootFolders,
      _systemMediaFolder,
    );
  }

  Future<List<MusicFile>> getSongsForFolder(MusicFolder folder) async {
    if (folder.path == 'system') {
      return _systemMediaFolder?.allSongs ?? const [];
    }

    if (folder.allSongs.isNotEmpty) {
      return folder.allSongs;
    }

    final normalizedPath = _normalizePath(folder.path);
    final rootPath = _roots.rootPaths.firstWhereOrNull(
      (root) =>
          _pathsEqual(root, normalizedPath) ||
          _pathContains(root, normalizedPath),
    );

    if (rootPath != null) {
      await loadRootFolderSongs(rootPath);
      final resolved = resolveFolderForPath(folder.path);
      if (resolved != null && resolved.allSongs.isNotEmpty) {
        return resolved.allSongs;
      }
    }

    final songsFromRepo = await _repository.getSongsUnderPath(normalizedPath);
    return songsFromRepo.map(_treeBuilder.musicFileFromSongMetadata).toList();
  }

  List<RemoteScanRoot> _remoteRoots = const [];
  List<RemoteScanRoot> get remoteRoots => _remoteRoots;

  void setRemoteRoots(Iterable<RemoteScanRoot> roots) {
    _remoteRoots = List.unmodifiable(roots);
    notifyListeners();
  }

  Future<void> loadRemoteRoots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('remote_scan_roots_list');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _remoteRoots = list
            .whereType<Map<String, dynamic>>()
            .map(RemoteScanRoot.fromJson)
            .toList(growable: false);
      } catch (e) {
        debugPrint('[ScannerService] loadRemoteRoots failed: $e');
      }
    }
    notifyListeners();
  }

  List<String>? _cachedNormalizedActiveRoots;
  String? _cachedNormalizedSystemFolderPath;

  List<String> _getNormalizedActiveRoots() {
    final cached = _cachedNormalizedActiveRoots;
    if (cached != null) return cached;
    final roots = _roots.internalRootPaths;
    final list = roots
        .map(_normalizePath)
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    _cachedNormalizedActiveRoots = list;
    return list;
  }

  bool isPathInActiveRoots(String path) {
    if (path.isEmpty) return false;

    if (RemoteMediaResolver.isRemoteUri(path)) {
      for (final root in _remoteRoots) {
        if (root.containsSong(path)) {
          return true;
        }
      }
      return false;
    }

    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return false;

    final activeRoots = _getNormalizedActiveRoots();
    for (final rootPath in activeRoots) {
      if (ScannerPathUtils.isNormalizedPathWithinOrEqual(rootPath, normalized)) {
        return true;
      }
    }

    final systemFolder = _systemMediaFolder;
    if (systemFolder != null) {
      if (normalized == 'system' ||
          normalized.startsWith('system/') ||
          normalized.startsWith('system\\')) {
        return true;
      }
      final systemPath = _cachedNormalizedSystemFolderPath ??=
          _normalizePath(systemFolder.path);
      if (ScannerPathUtils.isNormalizedPathWithinOrEqual(systemPath, normalized)) {
        return true;
      }
      final lookupKey = _pathLookupKey(normalized);
      if (systemFolder.allSongPaths.contains(lookupKey)) {
        return true;
      }
    }

    return false;
  }

  Future<List<MusicFile>> searchSongs(
    String query, {
    String? folderPath,
  }) async {
    final songs = await _repository.searchSongs(query, folderPath: folderPath);
    final musicFiles = songs
        .map(_treeBuilder.musicFileFromSongMetadata)
        .toList();
    if (folderPath != null && folderPath.isNotEmpty) {
      return musicFiles;
    }
    return musicFiles.where((file) => isPathInActiveRoots(file.path)).toList();
  }

  Future<SongMetadata?> getSongMetadata(String path) =>
      _repository.getSongMetadata(path);

  Future<List<MusicFolder>> searchFolders(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final matchingPaths = await _repository.searchFolderPaths(trimmed);

    final results = <MusicFolder>[];
    final seenPaths = <String>{};

    final lowercaseQuery = trimmed.toLowerCase();
    for (final root in _rootFolders) {
      if (root.name.toLowerCase().contains(lowercaseQuery)) {
        if (seenPaths.add(root.path)) {
          results.add(root);
        }
      }
    }

    final pendingPaths = <String>[];
    for (final path in matchingPaths) {
      if (!isPathInActiveRoots(path)) continue;
      if (seenPaths.add(path)) {
        pendingPaths.add(path);
      }
    }
    if (pendingPaths.isEmpty) return results;

    // 一次 IN 查询拿所有命中目录的统计，换掉「每个命中目录一条全表 COUNT」。
    final statsByPath = await _repository.getFolderStatsForPaths(pendingPaths);

    for (final path in pendingPaths) {
      final normalized = _normalizePath(
        ScannerPathUtils.resolveIosSandboxPath(path),
      );
      final stat = statsByPath[normalized];
      if (stat != null) {
        _folderSongCounts[normalized] = stat.songCount;
        _folderSongDurations[normalized] = stat.totalDurationMs;
      } else {
        // 表里没有（该目录还没落盘过，或上次扫描中断）：退回一次聚合，
        // 宁可慢这一次也不要让搜索结果露出 0 首。
        _folderSongCounts[normalized] =
            await _repository.getSongCountUnderPath(path);
      }

      final sortSettings = _resolveSortSettingsForFolder(path);
      final repSongMeta = await _repository.getRepresentativeSongUnderPath(
        path,
        criteria: sortSettings.criteria,
        order: sortSettings.order,
      );

      if (repSongMeta != null) {
        _folderRepresentativeSongs[normalized] = repSongMeta;
      }

      results.add(MusicFolder(path: path, name: p.basename(path)));
    }

    return results;
  }

  void pushNavigationHistory(MusicFolder folder) {
    _navigationState.pushHistory(folder);
  }

  MusicFolder? popNavigationHistory() {
    return _navigationState.popHistory();
  }

  double getFolderScrollOffset(String? path) {
    return _navigationState.getScrollOffset(path);
  }

  void setFolderScrollOffset(String? path, double offset) {
    _navigationState.setScrollOffset(path, offset);
  }

  void clearFolderScrollOffsets() {
    _navigationState.clearScrollOffsets();
  }

  MusicFolder? get systemMediaFolder => _systemMediaFolder;

  void _setSystemMediaFolder(MusicFolder? folder) {
    _systemMediaFolder = folder;
    _cachedNormalizedSystemFolderPath = null;
  }
  bool get hasPermission => _hasPermission;
  Map<String, SongMetadata> get metadataMap => _metadataStore.metadataMap;
  int get metadataRevision => _metadataRevision;
  int get albumLibraryRevision => _albumLibraryRevision;
  /// 见 [_structureRevision]。列表页应 select 这个值，而不是 watch 整个 ScannerService。
  int get structureRevision => _structureRevision;
  bool isRootPathAvailable(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return true;
    return _rootAvailability[_pathLookupKey(normalizedPath)] ?? true;
  }

  Future<void> get ready => _readyCompleter.future;
  bool get isReady => _readyCompleter.isCompleted;

  String _currentScanStage = 'idle';
  String get currentScanStage => _currentScanStage;

  ScannerService({
    bool autoInitialize = true,
    Duration directoryRescanBatchWindow = _defaultDirectoryRescanBatchWindow,
  }) : _directoryRescanBatchWindow = directoryRescanBatchWindow {
    _roots = ScannerServiceRoots(
      isDisposed: () => _isDisposed,
      onPathChanged: _enqueueWatchedPath,
      onRootsMutated: _invalidateScanRootsCache,
    );
    _metadataStore = ScannerMetadataStore(
      rootFolders: () => _scannedRootFolders,
      systemMediaFolder: () => _systemMediaFolder,
      notifyListeners: notifyListeners,
      scheduleMetadataNotify: _scheduleMetadataNotify,
      onMetadataMutated: _markMetadataMutated,
      notifySongMissingState: _notifySongMissingState,
      normalizePath: _normalizePath,
      pathsEqual: _pathsEqual,
      onAlbumMetadataMutated: _markAlbumLibraryMutated,
      onThumbnailUpdated: (path, thumb) =>
          unawaited(updateSongThumbnailPath(path, thumb)),
      onVisibleTreeSongsRemoved: _scheduleFolderIndexPersistForRemovedSongs,
    );
    _scanPipeline = ScannerScanPipeline(
      normalizePath: _normalizePath,
      pathLookupKey: _pathLookupKey,
      metadataStore: _metadataStore,
    );
    _repository = ScannerRepository();
    _scanCoordinator = ScannerScanCoordinator()
      ..addListener(_handleScanStateChanged);
    _treeBuilder = ScannerTreeBuilder(
      normalizePath: _normalizePath,
      pathsEqual: _pathsEqual,
    );
    _directoryScanner = ScannerDirectoryScanner(
      emitScanProgress: _emitScanProgress,
    );
    _navigationState.addListener(_handleNavigationChanged);
    WidgetsBinding.instance.addObserver(this);
    if (autoInitialize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runInit());
      });
    } else {
      _readyCompleter.complete();
    }
    _setupMediaObserver();
    _setupMobileStorageObserver();
  }

  Future<void> _runInit() async {
    try {
      await _init();
    } finally {
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
    }
  }

  void _markMetadataMutated() {
    _metadataRevision++;
  }

  /// 计算「显示树 + 导航历史」的轻量指纹。
  ///
  /// 只看对象 identity，因此能捕获根目录被替换/增删、系统媒体库切换与导航切换，
  /// 但不被元数据或缩略图路径变化扰动。常驻成本是 O(根目录数)。
  int _computeStructureFingerprint() {
    var hash = Object.hash(
      _rootFolders.length,
      _scannedRootFolders.length,
      _navigationState.currentFolder?.path,
      _navigationState.historyLength,
      // 全库歌曲总数：扫描过程中歌曲逐步入库时，页面上的曲目数/时长统计
      // 需要跟着刷新；而缩略图更新不改变总数，因此不会引起重建。
      _metadataStore.metadataMap.length,
    );
    for (final folder in _rootFolders) {
      hash = Object.hash(hash, identityHashCode(folder));
    }
    for (final folder in _scannedRootFolders) {
      hash = Object.hash(hash, identityHashCode(folder));
    }
    return hash;
  }

  /// 结构确实变了才推进 [_structureRevision]，避免页面级订阅者无谓重建。
  void _refreshStructureRevision() {
    final fingerprint = _computeStructureFingerprint();
    if (fingerprint == _lastStructureFingerprint) return;
    _lastStructureFingerprint = fingerprint;
    _structureRevision++;
    // 元素被替换/增删后必须重建视图，select(rootFolders) 才能感知变化。
    // 元素内部的变动（如 folder.files 增删）通过引用实时可见，无需重建。
    _rootFoldersView = null;
  }

  void _markAlbumLibraryMutated() {
    _albumLibraryRevision++;
  }

  void _handleScanStateChanged() {
    if (_isDisposed) return;
    notifyListeners();
    if (!isScanning &&
        _pendingDirectoryRescanPaths.isNotEmpty &&
        _directoryRescanTimer == null &&
        !_directoryRescanInProgress) {
      _directoryRescanTimer = Timer(
        Duration.zero,
        () => unawaited(_flushPendingDirectoryRescans()),
      );
    }
  }

  void _logInitTiming(String label, Stopwatch stopwatch) {
    if (!kDebugMode) return;
    debugPrint(
      '[ScannerService][init] $label ${stopwatch.elapsedMilliseconds} ms',
    );
  }

  Future<void> _loadScanSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _skipShortAudioScanEnabled =
        prefs.getBool(SettingsService.skipShortAudioScanEnabledStorageKey) ??
        false;
    _skipShortAudioScanThresholdSeconds =
        prefs.getInt(
          SettingsService.skipShortAudioScanMinimumDurationSecondsStorageKey,
        ) ??
        _defaultShortAudioThresholdSeconds;
  }

  bool _shouldSkipShortAudioDuration(int? durationMillis) {
    if (!_skipShortAudioScanEnabled) {
      return false;
    }
    if (durationMillis == null) {
      return false;
    }
    return durationMillis <
        Duration(seconds: _skipShortAudioScanThresholdSeconds).inMilliseconds;
  }

  bool _shouldKeepSongMetadata(SongMetadata song) {
    return !_shouldSkipShortAudioDuration(song.duration);
  }


  @override
  void notifyListeners() {
    if (_isDisposed) return;

    for (final folder in _rootFolders) {
      folder.invalidateCache();
    }
    _systemMediaFolder?.invalidateCache();
    _refreshStructureRevision();

    if (isScanning != _lastNotifiedScanningState) {
      _lastNotifiedScanningState = isScanning;
      _scanNotifyTimer?.cancel();
      _scanNotifyTimer = null;
      _scanNotifyPending = false;
      super.notifyListeners();
      return;
    }

    if (!isScanning) {
      super.notifyListeners();
      return;
    }

    _scanNotifyPending = true;
    if (_scanNotifyTimer?.isActive ?? false) {
      return;
    }

    _scanNotifyTimer = Timer(const Duration(seconds: 1), () {
      _scanNotifyTimer = null;
      if (_isDisposed || !_scanNotifyPending) {
        return;
      }
      _scanNotifyPending = false;
      super.notifyListeners();
    });
  }

  void _flushScanNotifications() {
    _scanNotifyTimer?.cancel();
    _scanNotifyTimer = null;
    _scanNotifyPending = false;
  }

  void setPlayerController(AudioCoreController? controller) {
    final changed = !identical(_playerController, controller);
    _playerController = controller;
    if (!changed || controller == null) {
      return;
    }

    if (Platform.isAndroid) {
      unawaited(checkPermissionStatus());
    } else if (_supportsPersistentAccess && !Platform.isLinux) {
      unawaited(_syncAppleScopedAccessState());
    }
  }

  void setSongMissingStateHandler(
    void Function(String path, bool isMissing)? handler,
  ) {
    _songMissingStateHandler = handler;
  }

  void setSongsPurgedHandler(
    void Function(Iterable<String> paths, Iterable<String> rootPaths)? handler,
  ) {
    _songsPurgedHandler = handler;
  }

  void _notifySongsPurged(
    Iterable<String> paths,
    Iterable<String> rootPaths,
  ) {
    _songsPurgedHandler?.call(paths, rootPaths);
  }

  void _notifySongMissingState(String path, bool isMissing) {
    final handler = _songMissingStateHandler;
    if (handler == null) return;
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return;
    handler(normalized, isMissing);
  }

  /// 修改全局排序。未带目录覆盖的目录都跟随这一份设置。
  void setGlobalSort({SortCriteria? criteria, SortOrder? order}) {
    var changed = false;
    if (criteria != null && criteria != _globalSortCriteria) {
      _globalSortCriteria = criteria;
      changed = true;
    }
    if (order != null && order != _globalSortOrder) {
      _globalSortOrder = order;
      changed = true;
    }
    if (!changed) return;

    unawaited(_saveGlobalSortSettings());
    _sortAndNotify(refreshCovers: false);
  }

  /// 修改 [folderPath] 的目录级排序（必然写入一份覆盖）。
  ///
  /// 调用方需先通过 [setFolderSortLocalized] 把该目录设为「仅此目录」，
  /// 否则这里会凭空造出一份覆盖，让目录脱离全局设置。
  void setFolderSort(
    String folderPath, {
    SortCriteria? criteria,
    SortOrder? order,
  }) {
    assert(
      _folderSortOverrides.containsKey(_sortFolderKey(folderPath)),
      'setFolderSort 要求该目录已开启「仅此目录」',
    );
    if (_writeFolderSortOverride(
      folderPath,
      criteria: criteria,
      order: order,
    )) {
      _sortAndNotify(refreshCovers: false);
    }
  }

  /// 切换「仅此目录」。
  ///
  /// 打开时把当前生效的设置物化成一份覆盖（画面不变，后续改动只影响此目录）；
  /// 关闭时删除覆盖，该目录回到全局设置。
  void setFolderSortLocalized(String folderPath, bool localized) {
    final key = _sortFolderKey(folderPath);
    final hasOverride = _folderSortOverrides.containsKey(key);

    if (localized) {
      if (hasOverride) return;
      _folderSortOverrides = {
        ..._folderSortOverrides,
        key: _resolveSortSettingsForFolder(folderPath),
      };
      unawaited(_saveFolderSortOverrides());
      // 覆盖值与当前生效值一致，列表顺序不变，只需让顶栏等监听者刷新状态。
      _markSortOrderChanged();
      notifyListeners();
      return;
    }

    if (!hasOverride) return;
    final next = Map<String, FolderSortSettings>.from(_folderSortOverrides)
      ..remove(key);
    _folderSortOverrides = next;
    unawaited(_saveFolderSortOverrides());
    _sortAndNotify(refreshCovers: false);
  }

  /// 一次性应用浮层里的选择（浮层点「确定」时调用）。
  ///
  /// [localized] 为真：把 [criteria]/[order] 写成该目录的独立覆盖；
  /// 为假：删除该目录的覆盖（回到全局），并把 [criteria]/[order] 写进全局设置。
  ///
  /// 只在此处收口成一次重排 + 一次通知，避免逐项写入触发多轮全树排序。
  void applySortSettings(
    String folderPath, {
    required bool localized,
    required SortCriteria criteria,
    required SortOrder order,
  }) {
    final key = _sortFolderKey(folderPath);
    var changed = false;

    if (localized) {
      final current = _folderSortOverrides[key];
      if (current == null ||
          current.criteria != criteria ||
          current.order != order) {
        _folderSortOverrides = {
          ..._folderSortOverrides,
          key: FolderSortSettings(criteria: criteria, order: order),
        };
        unawaited(_saveFolderSortOverrides());
        changed = true;
      }
    } else {
      if (_folderSortOverrides.containsKey(key)) {
        final next = Map<String, FolderSortSettings>.from(_folderSortOverrides)
          ..remove(key);
        _folderSortOverrides = next;
        unawaited(_saveFolderSortOverrides());
        changed = true;
      }
      if (_globalSortCriteria != criteria || _globalSortOrder != order) {
        _globalSortCriteria = criteria;
        _globalSortOrder = order;
        unawaited(_saveGlobalSortSettings());
        changed = true;
      }
    }

    if (changed) {
      _sortAndNotify(refreshCovers: false);
    }
  }

  void _sortAndNotify({bool refreshCovers = true}) {
    final totalStopwatch = Stopwatch()..start();
    try {
      _timeScanStepSync('stage sortAndNotify sort scanned root folders', () {
        _folderSorter.sortFoldersForTree(
          _scannedRootFolders,
          resolveSettings: _resolveSortSettingsForFolder,
        );
      });
      if (_systemMediaFolder != null) {
        _timeScanStepSync('stage sortAndNotify sort system media tree', () {
          _folderSorter.sortFolderRecursiveForTree(
            _systemMediaFolder!,
            resolveSettings: _resolveSortSettingsForFolder,
          );
        });
      }
      _timeScanStepSync(
        'stage sortAndNotify rebuild displayed root folders',
        () {
          _rebuildDisplayedRootFolders();
        },
      );
      _timeScanStepSync('stage sortAndNotify sync navigation state', () {
        _syncNavigationStateToLatestTree();
      });
      if (refreshCovers) {
        unawaited(_refreshAllFolderRepresentativeSongs());
      }
      _markSortOrderChanged();
      _timeScanStepSync('stage sortAndNotify notify listeners', () {
        notifyListeners();
      });
    } finally {
      totalStopwatch.stop();
      _logScanTiming('stage sortAndNotify total', totalStopwatch);
    }
  }

  /// 排序结果变了：文件夹是就地重排，对象 identity 与歌曲总数都不变，
  /// [_refreshStructureRevision] 的指纹感知不到，必须显式推进结构版本，
  /// 否则列表停在旧顺序、顶栏的「仅此目录」高亮也不会刷新。
  void _markSortOrderChanged() {
    _structureRevision++;
    _rootFoldersView = null;
  }

  Future<void> _refreshAllFolderRepresentativeSongs() async {
    final allRoots = <String>[];
    if (_systemMediaFolder != null) {
      allRoots.add(_systemMediaFolder!.path);
    }
    for (final root in _scannedRootFolders) {
      allRoots.add(root.path);
    }
    await _refreshFolderCoversForRoots(allRoots);
  }

  Future<void> _refreshFolderCoversForRoots(Iterable<String> rootPaths) async {
    final foldersToProcess = <MusicFolder>[];
    for (final rootPath in rootPaths) {
      if (rootPath == 'system' || rootPath.startsWith('system/')) {
        if (_systemMediaFolder != null && !foldersToProcess.contains(_systemMediaFolder)) {
          foldersToProcess.add(_systemMediaFolder!);
        }
      } else {
        final rootFolder = _scannedRootFolders.firstWhereOrNull(
          (f) => _pathsEqual(f.path, rootPath),
        );
        if (rootFolder != null && !foldersToProcess.contains(rootFolder)) {
          foldersToProcess.add(rootFolder);
        }
      }
    }

    if (foldersToProcess.isEmpty) {
      return;
    }

    final allCovers = await FolderCoverResolver.computeAllFolderCoversInBackground(
      foldersToProcess,
    );

    final staleCovers = <String>[];
    for (final root in foldersToProcess) {
      final normRoot = _normalizePath(root.path);
      for (final folderPath in _folderRepresentativeSongPaths.keys) {
        final isUnderThisRoot = normRoot == 'system'
            ? folderPath == 'system' || folderPath.startsWith('system/')
            : _pathContains(normRoot, folderPath) || _pathsEqual(normRoot, folderPath);
        if (isUnderThisRoot && !allCovers.containsKey(folderPath)) {
          staleCovers.add(folderPath);
        }
      }
    }

    if (staleCovers.isNotEmpty) {
      for (final folder in staleCovers) {
        _folderRepresentativeSongPaths.remove(folder);
        _folderRepresentativeSongs.remove(folder);
      }
      // 只清封面列：目录本身还在，统计必须留住。
      await _repository.clearFolderEntryCovers(staleCovers);
    }

    if (allCovers.isNotEmpty) {
      _folderRepresentativeSongPaths.addAll(allCovers);
      final coverSnapshots = <String, FolderCoverSnapshot>{};
      for (final entry in allCovers.entries) {
        final songMeta = _metadataStore.getMetadata(entry.value);
        if (songMeta != null) {
          _folderRepresentativeSongs[entry.key] = songMeta;
        }
        coverSnapshots[entry.key] = FolderCoverSnapshot(
          songPath: entry.value,
          thumbnailPath: songMeta?.thumbnailPath,
          artworkPath: songMeta?.artworkPath,
        );
      }
      await _repository.batchWriteFolderCovers(coverSnapshots);
    }

    for (final root in foldersToProcess) {
      _syncRepresentativeSongCaches(root, allCovers);
    }

    if (allCovers.isNotEmpty || staleCovers.isNotEmpty) {
      notifyListeners();
    }
  }

  void _syncRepresentativeSongCaches(MusicFolder folder, Map<String, String> covers) {
    final normPath = _normalizePath(folder.path);
    final songPath = covers[normPath];
    if (songPath != null) {
      final meta = _folderRepresentativeSongs[normPath] ?? _metadataStore.getMetadata(songPath);
      if (meta != null) {
        folder.representativeSongCache = _treeBuilder.musicFileFromSongMetadata(meta);
      } else {
        folder.representativeSongCache = folder.files.firstWhereOrNull((f) => _pathsEqual(f.path, songPath));
      }
    } else {
      folder.representativeSongCache = null;
    }
    for (final sub in folder.subFolders) {
      _syncRepresentativeSongCaches(sub, covers);
    }
  }

  Future<void> _loadCachedFolderCoversFromDatabase() async {
    try {
      final covers = await _repository.getAllFolderRepresentativeMetadata();
      debugPrint('[FolderCover] _loadCachedFolderCoversFromDatabase loaded ${covers.length} covers from DB');
      for (final entry in covers.entries) {
        final resolvedFolder = ScannerPathUtils.resolveIosSandboxPath(entry.key);
        final normPath = _normalizePath(resolvedFolder);
        final resolvedSong = entry.value.copyWith(
          path: ScannerPathUtils.resolveIosSandboxPath(entry.value.path),
          thumbnailPath: entry.value.thumbnailPath != null
              ? ScannerPathUtils.resolveIosSandboxPath(entry.value.thumbnailPath!)
              : null,
          artworkPath: entry.value.artworkPath != null
              ? ScannerPathUtils.resolveIosSandboxPath(entry.value.artworkPath!)
              : null,
        );
        _folderRepresentativeSongs[normPath] = resolvedSong;
        _folderRepresentativeSongPaths[normPath] = _normalizePath(resolvedSong.path);
        _metadataStore.cacheMetadata(resolvedSong);
      }
    } catch (e) {
      debugPrint('[ScannerService] Failed to load cached folder covers: $e');
    }
  }

  Future<void> _init() async {
    final totalStopwatch = Stopwatch()..start();
    try {
      if (Platform.isLinux) {
        try {
          _linuxFlatpak = await _linuxDirectoryAccess.isFlatpak;
        } catch (e) {
          debugPrint('[ScannerService] Linux directory access unavailable: $e');
        }
      }
      // Force database open to run path migrations first (critical for iOS sandbox UUID changes)
      await _repository.ensureOpen();

      final canUsePersistentAccess =
          _supportsPersistentAccess &&
          (Platform.isLinux || _playerController != null);
      if (Platform.isLinux) {
        await _timeInitStep('resolve and mount linux roots', () async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final paths = prefs.getStringList('root_paths') ?? [];
            if (paths.isNotEmpty) {
              final updatedPaths = await _resolveAndMigrateLinuxRoots(paths);
              await prefs.setStringList('root_paths', updatedPaths);
            }
          } catch (e, st) {
            debugPrint('Error during pre-initialization linux mount: $e\n$st');
          }
        });
      }
      if (_linuxFlatpak) {
        await _timeInitStep(
          'restore Linux portal roots',
          _restoreLinuxPortalRoots,
        );
      }
      await _timeInitStep('load root paths', () {
        return _roots.loadRootPaths(
          hasPersistentAccess: canUsePersistentAccess
              ? _hasPersistentAccess
              : null,
          forgetPersistentAccess: canUsePersistentAccess
              ? _forgetPersistentAccess
              : null,
        );
      });
      if (canUsePersistentAccess) {
        await _timeInitStep(
          'sync active scoped root access',
          _syncActiveScopedRootAccess,
        );
      }
      await _timeInitStep('check and request permissions', () {
        return checkPermissionStatus();
      });
      await _timeInitStep(
        'sync root availability',
        () => _refreshRootAvailability(shouldNotifyListeners: false),
      );
      await _timeInitStep('load sort settings', _loadSortSettings);
      await _timeInitStep('load scan settings', _loadScanSettings);
      await _timeInitStep('load remote roots', loadRemoteRoots);
      await _timeInitStep(
        'load cached folder covers from database',
        _loadCachedFolderCoversFromDatabase,
      );
      await _timeInitStep(
        'load folder entries from database',
        _loadFolderEntriesFromDatabase,
      );
      final cachedSongs = const <SongMetadata>[];
      await _timeInitStep(
        'load cached root folders from database',
        () => _loadCachedRootFoldersFromDatabase(cachedSongs: cachedSongs),
      );
      await _timeInitStep(
        'load cached system media folder from database',
        () =>
            _loadCachedSystemMediaFolderFromDatabase(cachedSongs: cachedSongs),
      );
      _timeInitStepSync('rebuild displayed root folders', () {
        _rebuildDisplayedRootFolders();
      });
      _timeInitStepSync('notify listeners after init', () {
        notifyListeners();
      });
      // Mark scanner ready as soon as database and root configurations are ready,
      // without blocking callers (like playback restore) on the potentially slow scan().
      if (!_readyCompleter.isCompleted) {
        _readyCompleter.complete();
      }
      // Auto scan on startup: delay slightly so first frame and initial UI animations settle smoothly
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!_isDisposed) {
        await _timeInitStep('startup scan', scan);
      }
      _startRootAvailabilityTimer();
    } finally {
      totalStopwatch.stop();
      _logInitTiming('init total', totalStopwatch);
    }
  }

  void _setupMediaObserver() {
    if (Platform.isAndroid) {
      const mediaObserverChannel = EventChannel(
        'app.vynody.player/media_observer',
      );
      _mediaObserverSubscription = mediaObserverChannel
          .receiveBroadcastStream()
          .listen(
            (event) {
              if (event == 'media_changed' &&
                  !isScanning &&
                  !_mediaObserverPaused) {
                debugPrint(
                  'Media library change detected, re-scanning system media...',
                );
                scanSystemMedia();
              }
            },
            onError: (err) {
              debugPrint('Media observer error: $err');
            },
          );
    }
  }

  void pauseMediaObserver() {
    debugPrint('[ScannerService] Pausing media observer');
    _mediaObserverPaused = true;
  }

  void resumeMediaObserver({bool triggerScan = false}) {
    debugPrint(
      '[ScannerService] Resuming media observer (triggerScan=$triggerScan)',
    );
    _mediaObserverPaused = false;
    if (triggerScan) {
      unawaited(scan(clearScannedRoots: false));
    }
  }

  Future<void> checkAndRequestPermissions() async {
    debugPrint(
      '[ScannerService] checkAndRequestPermissions start '
      'hasPermission=$_hasPermission '
      'playerController=${_playerController != null}',
    );
    _hasPermission = await _checkPermissions(request: true);
    debugPrint(
      '[ScannerService] checkAndRequestPermissions result '
      'hasPermission=$_hasPermission',
    );
    notifyListeners();
    if (_hasPermission) {
      await scanSystemMedia();
    }
  }

  Future<void> checkPermissionStatus() async {
    debugPrint(
      '[ScannerService] checkPermissionStatus start '
      'hasPermission=$_hasPermission '
      'playerController=${_playerController != null}',
    );
    _hasPermission = await _checkPermissions(request: false);
    debugPrint(
      '[ScannerService] checkPermissionStatus result '
      'hasPermission=$_hasPermission',
    );
    notifyListeners();
    if (_hasPermission) {
      unawaited(scanSystemMedia());
    }
  }

  Future<List<String>> _resolveAndMigrateLinuxRoots(List<String> paths) async {
    if (!Platform.isLinux) return paths;
    final updatedPaths = await LinuxMountHelper.resolveAndMountRootPaths(paths);
    for (int i = 0; i < paths.length && i < updatedPaths.length; i++) {
      final oldPath = paths[i];
      final newPath = updatedPaths[i];
      if (oldPath != newPath) {
        await _repository.migrateLinuxRootPath(oldPath, newPath);
      }
    }
    return updatedPaths;
  }

  Future<RootPathAddResult> addRootPath(
    String path, {
    String? persistentDocumentId,
  }) async {
    final normalizedPath = _normalizePath(path);
    debugPrint(
      '[ScannerService] addRootPath: path=$path, normalizedPath=$normalizedPath, persistentDocumentId=$persistentDocumentId, _linuxFlatpak=$_linuxFlatpak',
    );
    if (FileSystemEntity.isFileSync(normalizedPath)) {
      debugPrint(
        '[ScannerService] addRootPath rejected: $normalizedPath is a file, not a directory',
      );
      return RootPathAddResult(
        RootPathAddStatus.failed,
        path: normalizedPath,
      );
    }
    if (Platform.isLinux && _linuxFlatpak && persistentDocumentId != null) {
      _linuxDocumentIds[normalizedPath] = persistentDocumentId;
      await _saveLinuxDocumentIds();
    }
    final existingRoot = _roots.rootPaths.firstWhereOrNull(
      (existing) => _pathsEqual(existing, normalizedPath),
    );

    if (_supportsPersistentAccess) {
      final registered = await _registerPersistentAccess(normalizedPath);
      if (!registered) {
        debugPrint(
          '[ScannerService] persistent access registration returned false for '
          '$normalizedPath; falling back to a readability probe',
        );
      }

      final scopedAccessReady = await _ensureScopedRootAccess(normalizedPath);
      if (!scopedAccessReady) {
        debugPrint(
          '[ScannerService] beginScopedAccess returned false for '
          '$normalizedPath; falling back to a readability probe',
        );
      }

      // The scope flags are advisory: a path can be readable without a
      // security scope (e.g. ~/Music on macOS). Only the filesystem decides.
      // Without this probe an unreadable root is added silently and then shows
      // up as a folder with 0 songs.
      if (!await _isDirectoryReadable(normalizedPath)) {
        debugPrint(
          '[ScannerService] addRootPath rejected: directory is not readable '
          '$normalizedPath',
        );
        return RootPathAddResult(
          RootPathAddStatus.persistentAccessDenied,
          path: normalizedPath,
        );
      }
    }

    if (existingRoot != null) {
      final existingFolder = _rootFolders.firstWhereOrNull(
        (folder) => _pathsEqual(folder.path, existingRoot),
      );
      final isPopulated = existingFolder != null && !existingFolder.isEmpty;
      if (!isPopulated) {
        // The folder is already a root but has never produced any track (for
        // example an iOS folder whose security scope used to fail). Re-picking
        // it is how the user restores access, so rescan instead of silently
        // returning "no music".
        debugPrint(
          '[ScannerService] existing root has no music, rescanning: '
          '$existingRoot',
        );
        _restartFullRootScan();
      }
      return RootPathAddResult(
        isPopulated
            ? RootPathAddStatus.alreadyAdded
            : RootPathAddStatus.noMusic,
        path: existingRoot,
      );
    }

    var updatedRoots = [..._roots.rootPaths, normalizedPath];
    if (Platform.isLinux) {
      try {
        updatedRoots = await _resolveAndMigrateLinuxRoots(updatedRoots);
      } catch (e) {
        debugPrint('Error registering Linux root UUID: $e');
      }
    }
    await _roots.setRootPaths(updatedRoots);
    _rootAvailability[_pathLookupKey(normalizedPath)] = _isRootPathAvailable(
      normalizedPath,
    );
    if (_supportsPersistentAccess) {
      await _syncActiveScopedRootAccess();
    }
    await _loadCachedRootFoldersFromDatabase(rootPaths: updatedRoots);
    _rebuildDisplayedRootFolders();
    notifyListeners();

    if (Platform.isAndroid) {
      try {
        await MediaScanner.loadMedia(path: normalizedPath);
      } catch (e) {
        debugPrint('MediaScanner error: $e');
      }
    }

    _restartFullRootScan();
    return RootPathAddResult(RootPathAddStatus.added, path: normalizedPath);
  }

  Future<void> removeRootPath(String path) async {
    await removeRootPaths([path]);
  }

  Future<void> removeRootPaths(Iterable<String> paths) async {
    final normalizedTargets = _normalizeDeclaredRootPaths(paths);
    if (normalizedTargets.isEmpty) return;
    debugPrint(
      '[ScannerService] removeRootPaths requested=$normalizedTargets '
      'currentRoots=${_roots.rootPaths} isScanning=$isScanning',
    );

    if (_supportsPersistentAccess) {
      for (final path in normalizedTargets) {
        await _forgetPersistentAccess(path);
      }
    }

    var updatedRoots = [..._roots.rootPaths];
    updatedRoots.removeWhere(
      (existing) =>
          normalizedTargets.any((target) => _pathsEqual(existing, target)),
    );
    if (Platform.isLinux) {
      try {
        updatedRoots = await _resolveAndMigrateLinuxRoots(updatedRoots);
      } catch (e) {
        debugPrint('Error updating Linux root UUID mapping: $e');
      }
    }
    await _roots.setRootPaths(updatedRoots);
    _pruneSortOverridesForPaths(normalizedTargets);
    for (final path in normalizedTargets) {
      _rootAvailability.remove(_pathLookupKey(path));
    }
    if (_supportsPersistentAccess) {
      await _syncActiveScopedRootAccess();
    }
    _removeRootsFromScannedTree(normalizedTargets);
    _notifySongsPurged(const <String>[], normalizedTargets);
    await _purgeRemovedRootsFromMetadataCache(normalizedTargets);
    _rebuildDisplayedRootFolders();
    _syncNavigationStateToLatestTree();
    notifyListeners();
    debugPrint(
      '[ScannerService] removeRootPaths applied '
      'remainingRoots=${_roots.rootPaths}',
    );

    _restartFullRootScan();
  }

  Future<void> moveRootPath(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _roots.rootPaths.length) return;
    if (newIndex < 0 || newIndex > _roots.rootPaths.length) return;
    if (oldIndex == newIndex) return;

    final updatedRoots = [..._roots.rootPaths];
    final movedPath = updatedRoots.removeAt(oldIndex);
    updatedRoots.insert(newIndex, movedPath);
    await _roots.setRootPaths(updatedRoots);
    _rebuildDisplayedRootFolders();
    notifyListeners();
    _restartFullRootScan();
  }

  Future<void> reorderRootPaths(List<String> newOrder) async {
    await _roots.setRootPaths(newOrder);
    _rebuildDisplayedRootFolders();
    notifyListeners();
    _restartFullRootScan();
  }

  Future<bool> _registerPersistentAccess(String path) async {
    debugPrint(
      '[ScannerService] _registerPersistentAccess: path=$path, keys=${_linuxDocumentIds.keys.toList()}',
    );
    if (Platform.isLinux && _linuxFlatpak) {
      return _linuxDocumentIds.containsKey(_normalizePath(path));
    }
    final controller = _playerController;
    if (controller == null) return true;
    try {
      final registered = await controller.registerPersistentAccess(path: path);
      debugPrint(
        '[ScannerService] _registerPersistentAccess result=$registered path=$path',
      );
      return registered;
    } catch (e) {
      debugPrint(
        '[ScannerService] registerPersistentAccess failed for $path: $e',
      );
      return false;
    }
  }

  /// Probes whether [path] can actually be listed.
  ///
  /// iOS hands back a security-scoped URL for folders picked in Files; when the
  /// scope never got activated, every listing throws `PathAccessException`
  /// (EPERM). Without this probe such a folder is added silently and then shows
  /// up with 0 songs and no explanation.
  Future<bool> _isDirectoryReadable(String path) async {
    if (path.isEmpty) return false;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        // Missing / unmounted volumes are the availability logic's business;
        // do not report them as a permission problem.
        return true;
      }
      await dir.list(followLinks: false).take(1).toList();
      return true;
    } on FileSystemException catch (e) {
      debugPrint('[ScannerService] directory not readable: $path ($e)');
      return false;
    } catch (e) {
      debugPrint('[ScannerService] directory probe failed: $path ($e)');
      return false;
    }
  }

  Future<void> _forgetPersistentAccess(String path) async {
    if (Platform.isLinux && _linuxFlatpak) {
      final documentId = _linuxDocumentIds.remove(_normalizePath(path));
      await _saveLinuxDocumentIds();
      if (documentId != null) {
        try {
          await _linuxDirectoryAccess.revokeDirectory(documentId);
        } catch (e) {
          debugPrint('[ScannerService] revoke Linux portal access failed: $e');
        }
      }
      return;
    }
    final controller = _playerController;
    if (controller == null) return;
    try {
      await controller.forgetPersistentAccess(path: path);
    } catch (e) {
      debugPrint(
        '[ScannerService] forgetPersistentAccess failed for $path: $e',
      );
    }
  }

  void _setupMobileStorageObserver() {
    if (!(Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isMacOS ||
        Platform.isWindows)) {
      return;
    }

    try {
      _mobileStorageSubscription = _mobileStorageListener.storageEvents.listen(
        (event) {
          if (_isDisposed) return;
          if (event.type == MobileStorageEventType.unknown) return;
          final affectedRoots = _rootsAffectedByStoragePath(event.path);
          if (affectedRoots.isNotEmpty) {
            debugPrint(
              '[ScannerService] mobile storage event=${event.typeName} '
              'path=${event.path ?? "unknown"} affectedRoots=$affectedRoots',
            );
            if (_supportsPersistentAccess) {
              final controller = _playerController;
              if (controller != null) {
                for (final path in affectedRoots) {
                  final normalized = _normalizePath(path);
                  _activeScopedRootPaths.remove(normalized);
                  if (event.type == MobileStorageEventType.unmounted ||
                      event.type == MobileStorageEventType.removed ||
                      event.type == MobileStorageEventType.eject ||
                      event.type == MobileStorageEventType.badRemoval) {
                    try {
                      unawaited(controller.endScopedAccess(path: normalized));
                    } catch (e) {
                      debugPrint(
                        '[ScannerService] endScopedAccess failed for $normalized: $e',
                      );
                    }
                  }
                }
              }
            }
          }
          _pendingRootAvailabilityRescan = true;
          _scheduleRootAvailabilityRefresh();
        },
        onError: (err) {
          debugPrint('Mobile storage observer error: $err');
        },
      );
    } catch (e) {
      debugPrint('Failed to setup mobile storage observer: $e');
    }
  }

  void _scheduleRootAvailabilityRefresh() {
    if (_isDisposed) return;
    if (_rootAvailabilityRefreshTimer?.isActive ?? false) {
      return;
    }

    _rootAvailabilityRefreshTimer = Timer(
      const Duration(milliseconds: 350),
      () {
        _rootAvailabilityRefreshTimer = null;
        if (_isDisposed) return;
        final shouldRescan = _pendingRootAvailabilityRescan;
        _pendingRootAvailabilityRescan = false;
        unawaited(
          _refreshRootAvailability(
            shouldNotifyListeners: true,
            rescanRestoredRoots: shouldRescan,
          ),
        );
      },
    );
  }

  Future<void> _refreshRootAvailability({
    required bool shouldNotifyListeners,
    bool rescanRestoredRoots = false,
  }) async {
    if (_supportsPersistentAccess && _playerController != null) {
      await _syncActiveScopedRootAccess();
    }

    final declaredRoots = _roots.rootPaths.toList(growable: false);
    final declaredKeys = declaredRoots.map(_pathLookupKey).toSet();
    final previousAvailability = Map<String, bool>.from(_rootAvailability);
    final nextAvailability = <String, bool>{};
    final missingRoots = <String>[];
    final restoredRoots = <String>[];

    for (final rootPath in declaredRoots) {
      final normalizedRoot = _normalizePath(rootPath);
      if (normalizedRoot.isEmpty) {
        continue;
      }

      final key = _pathLookupKey(normalizedRoot);
      final available = _isRootPathAvailable(normalizedRoot);
      nextAvailability[key] = available;

      final previous = previousAvailability[key];
      if (previous == null) {
        if (!available) {
          missingRoots.add(normalizedRoot);
        }
        continue;
      }

      if (previous == available) {
        continue;
      }

      if (available) {
        restoredRoots.add(normalizedRoot);
      } else {
        missingRoots.add(normalizedRoot);
      }
    }

    _rootAvailability
      ..clear()
      ..addAll(nextAvailability);
    _rootAvailability.removeWhere((key, _) => !declaredKeys.contains(key));

    final currentFolderPath = _navigationState.currentFolder?.path;
    final shouldReturnToRootList =
        currentFolderPath != null &&
        missingRoots.any((root) => _pathContains(root, currentFolderPath));
    if (shouldReturnToRootList) {
      _navigationState.setState(null, const []);
    }

    if (restoredRoots.isNotEmpty) {
      await _loadCachedRootFoldersFromDatabase(rootPaths: restoredRoots);
    }

    // Keep the last known tree for temporarily missing roots so a brief
    // unplug/replug cycle does not collapse the visible folder structure.
    if (missingRoots.isNotEmpty || restoredRoots.isNotEmpty) {
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      if (shouldNotifyListeners) {
        notifyListeners();
      }
    }

    if (rescanRestoredRoots && restoredRoots.isNotEmpty) {
      _scanCoordinator.requestRescan();
      if (!_scanCoordinator.isScanning) {
        unawaited(
          _scanRootsWithFullFlow(() => restoredRoots, clearScannedRoots: false),
        );
      }
    }
  }

  bool _isRootPathAvailable(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return false;

    if (Platform.isLinux &&
        (normalizedPath.startsWith('/run/media/') ||
            normalizedPath.startsWith('/media/'))) {
      return true;
    }

    if (Platform.isAndroid && !_hasPermission) {
      // On Android without audio permission, Directory.existsSync() on external
      // storage returns false. Preserve configured roots so they don't collapse.
      return true;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      try {
        if (Directory(normalizedPath).existsSync()) {
          return true;
        }
      } catch (_) {}
      final resolved = ScannerPathUtils.resolveIosSandboxPath(normalizedPath);
      try {
        return Directory(resolved).existsSync();
      } catch (e) {
        return false;
      }
    }

    try {
      return Directory(normalizedPath).existsSync();
    } catch (e, st) {
      debugPrint(
        '[ScannerService] root availability check failed path=$normalizedPath: $e\n$st',
      );
      return false;
    }
  }

  List<String> _rootsAffectedByStoragePath(String? storagePath) {
    final normalizedStoragePath = _normalizePath(storagePath ?? '');
    final declaredRoots = _roots.rootPaths.toList(growable: false);
    if (normalizedStoragePath.isEmpty) {
      return declaredRoots;
    }

    final matchingRoots = declaredRoots
        .where((rootPath) => _pathContains(normalizedStoragePath, rootPath))
        .toList(growable: false);
    return matchingRoots.isEmpty ? declaredRoots : matchingRoots;
  }

  Future<bool> _hasPersistentAccess(String path) async {
    if (Platform.isLinux && _linuxFlatpak) {
      return _linuxDocumentIds.containsKey(_normalizePath(path));
    }
    final controller = _playerController;
    if (controller == null) return true;
    try {
      return await controller.hasPersistentAccess(path: path);
    } catch (e) {
      debugPrint('[ScannerService] hasPersistentAccess failed for $path: $e');
      return false;
    }
  }

  Future<void> _saveLinuxDocumentIds() async {
    if (!_linuxFlatpak) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'linux_portal_document_ids',
      jsonEncode(_linuxDocumentIds),
    );
  }

  Future<void> _restoreLinuxPortalRoots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('linux_portal_document_ids');
    if (raw == null || raw.isEmpty) return;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    _linuxDocumentIds
      ..clear()
      ..addAll(
        decoded.map((key, value) => MapEntry(key.toString(), value.toString())),
      );

    final savedRoots = prefs.getStringList('root_paths') ?? <String>[];
    final restoredRoots = <String>[];
    final restoredDocumentIds = <String, String>{};
    for (final savedRoot in savedRoots) {
      final documentId = _linuxDocumentIds[savedRoot];
      if (documentId == null) {
        restoredRoots.add(savedRoot);
        continue;
      }

      try {
        final grant = await _linuxDirectoryAccess.restoreDirectory(documentId);
        if (grant == null) continue;
        final restoredPath = _normalizePath(grant.path);
        if (restoredPath != savedRoot) {
          await _repository.migrateLinuxRootPath(savedRoot, restoredPath);
        }
        restoredRoots.add(restoredPath);
        restoredDocumentIds[restoredPath] = documentId;
      } catch (e) {
        debugPrint(
          '[ScannerService] failed to restore Linux portal root $savedRoot: $e',
        );
      }
    }

    _linuxDocumentIds
      ..clear()
      ..addAll(restoredDocumentIds);
    await prefs.setStringList('root_paths', restoredRoots);
    await _saveLinuxDocumentIds();
  }

  Future<void> _syncAppleScopedAccessState() async {
    if (!_supportsPersistentAccess) return;
    await ready;

    final currentRoots = List<String>.from(_roots.rootPaths);
    for (final path in currentRoots) {
      await _registerPersistentAccess(path);
    }

    await _roots.loadRootPaths(
      hasPersistentAccess: _hasPersistentAccess,
      forgetPersistentAccess: _forgetPersistentAccess,
    );
    await _syncActiveScopedRootAccess();
    _rebuildDisplayedRootFolders();
    notifyListeners();
  }

  Future<bool> _ensureScopedRootAccess(String path) async {
    if (Platform.isLinux && _linuxFlatpak) return true;
    if (!_supportsPersistentAccess) return true;

    final controller = _playerController;
    if (controller == null) return true;

    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return false;
    if (_activeScopedRootPaths.contains(normalizedPath)) {
      return true;
    }

    try {
      final started = await controller.beginScopedAccess(path: normalizedPath);
      if (started) {
        _activeScopedRootPaths.add(normalizedPath);
      }
      return started;
    } catch (e) {
      debugPrint(
        '[ScannerService] beginScopedAccess failed for $normalizedPath: $e',
      );
      return false;
    }
  }

  Future<void> _syncActiveScopedRootAccess() async {
    if (Platform.isLinux && _linuxFlatpak) return;
    if (!_supportsPersistentAccess) return;

    final controller = _playerController;
    if (controller == null) return;

    final desiredRoots = _roots.rootPaths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toSet();

    final staleRoots = _activeScopedRootPaths
        .where((path) => !desiredRoots.contains(path))
        .toList(growable: false);
    for (final path in staleRoots) {
      try {
        await controller.endScopedAccess(path: path);
      } catch (e) {
        debugPrint('[ScannerService] endScopedAccess failed for $path: $e');
      } finally {
        _activeScopedRootPaths.remove(path);
      }
    }

    final missingRoots = desiredRoots
        .where((path) => !_activeScopedRootPaths.contains(path))
        .toList(growable: false);
    for (final path in missingRoots) {
      final started = await _ensureScopedRootAccess(path);
      if (!started) {
        debugPrint(
          '[ScannerService] beginScopedAccess returned false for $path',
        );
      }
    }
  }

  Future<bool> _checkPermissions({bool request = true}) async {
    if (Platform.isAndroid) {
      if (!request) {
        return MetadataHelper.hasAndroidAudioPermission();
      }

      final controller = _playerController;
      if (controller != null) {
        debugPrint(
          '[ScannerService] _checkPermissions via AudioCoreController',
        );
        final granted = await controller.ensureAndroidMediaLibraryPermission();
        debugPrint(
          '[ScannerService] AudioCoreController permission result=$granted',
        );
        MetadataHelper.invalidatePermissionCache();
        return granted;
      }

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      debugPrint(
        '[ScannerService] _checkPermissions fallback '
        'sdkInt=${androidInfo.version.sdkInt}',
      );

      bool granted = false;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ requires Permission.audio
        var status = await Permission.audio.status;
        debugPrint('[ScannerService] Permission.audio initial status=$status');
        if (!status.isGranted) {
          status = await Permission.audio.request();
          debugPrint(
            '[ScannerService] Permission.audio requested status=$status',
          );
        }
        granted = status.isGranted;
      } else {
        // Legacy storage permission
        var status = await Permission.storage.status;
        debugPrint(
          '[ScannerService] Permission.storage initial status=$status',
        );
        if (!status.isGranted) {
          status = await Permission.storage.request();
          debugPrint(
            '[ScannerService] Permission.storage requested status=$status',
          );
        }
        granted = status.isGranted;
      }
      MetadataHelper.invalidatePermissionCache();
      return granted;
    }
    return true; // Assume granted on other platforms for now
  }

  Future<void> scanSystemMedia() async {
    await _loadScanSettings();
    debugPrint(
      '[ScannerService] scanSystemMedia start '
      'platform=${Platform.operatingSystem} '
      'hasPermission=$_hasPermission '
      'playerController=${_playerController != null}',
    );
    if (!Platform.isAndroid) {
      debugPrint('[ScannerService] scanSystemMedia skipped: Android only');
      return;
    }
    if (!_hasPermission) {
      debugPrint('[ScannerService] scanSystemMedia aborted: no permission');
      return;
    }

    try {
      if (Platform.isAndroid) {
        final controller = _playerController;
        if (controller == null) {
          debugPrint(
            'scanSystemMedia skipped: AudioCoreController is not available yet.',
          );
          return;
        }

        final scanResult = await controller.scanAndroidMediaLibrary();
        debugPrint(
          '[ScannerService] Android media scan result '
          'permissionGranted=${scanResult.permissionGranted} '
          'entries=${scanResult.entries.length} '
          'success=${scanResult.isSuccessful} '
          'errorCode=${scanResult.errorCode ?? "-"} '
          'errorMessage=${scanResult.errorMessage ?? "-"}',
        );
        _hasPermission = scanResult.permissionGranted;
        if (!scanResult.permissionGranted) {
          debugPrint(
            '[ScannerService] Android media scan stopped because '
            'permissionGranted=false',
          );
          _setSystemMediaFolder(null);
          notifyListeners();
          return;
        }

        final keptEntries = scanResult.entries
            .where(
              (entry) =>
                  !_shouldSkipShortAudioDuration(entry.duration.inMilliseconds),
            )
            .toList(growable: false);
        final skippedEntryPaths = scanResult.entries
            .where(
              (entry) =>
                  _shouldSkipShortAudioDuration(entry.duration.inMilliseconds),
            )
            .map(_androidEntryFilePath)
            .whereType<String>()
            .toList(growable: false);
        if (skippedEntryPaths.isNotEmpty) {
          _metadataStore.deleteMissingFromCache(skippedEntryPaths);
        }
        if (keptEntries.isEmpty) {
          _setSystemMediaFolder(null);
          await MetadataDatabase().syncSongSourcePresence(
            sourceMask: SongSourceFlags.systemMedia,
            presentPaths: const [],
          );
          notifyListeners();
          return;
        }
        final filePaths = keptEntries
            .map(_androidEntryFilePath)
            .whereType<String>()
            .toList(growable: false);
        final metadataByPath = filePaths.isEmpty
            ? <String, SongMetadata>{}
            : await MetadataDatabase().getSongMetadataByPaths(filePaths);

        _setSystemMediaFolder(
          _treeBuilder.buildAndroidMediaLibrary(
            keptEntries,
            metadataByPath,
            _compareNaturally,
          ),
        );
        debugPrint(
          '[ScannerService] Android system media tree built '
          'hasTree=${_systemMediaFolder != null} '
          'rootFolders=${_systemMediaFolder?.subFolders.length ?? 0} '
          'files=${_systemMediaFolder?.files.length ?? 0}',
        );
        if (_systemMediaFolder != null) {
          _folderSorter.sortFolderRecursiveForTree(
            _systemMediaFolder!,
            resolveSettings: _resolveSortSettingsForFolder,
          );
        }
        await MetadataDatabase().syncSongSourcePresence(
          sourceMask: SongSourceFlags.systemMedia,
          presentPaths: filePaths,
        );
        notifyListeners();

        unawaited(_refreshFolderCoversForRoots(['system']));
        unawaited(_processAndSaveAndroidSongsBackground(keptEntries));
        return;
      }

      if (Platform.isIOS) {
        debugPrint('[ScannerService] iOS media scan start');
        final songs = await OnAudioQuery().querySongs(
          sortType: null,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        );
        final keptSongs = songs
            .where((song) {
              return !_shouldSkipShortAudioDuration(song.duration) &&
                  !MusicFileUtils.isAppleDoubleFilePath(song.data);
            })
            .toList(growable: false);
        final skippedSongPaths = songs
            .where(
              (song) =>
                  _shouldSkipShortAudioDuration(song.duration) ||
                  MusicFileUtils.isAppleDoubleFilePath(song.data),
            )
            .map((song) => _normalizePath(song.data))
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
        if (skippedSongPaths.isNotEmpty) {
          _metadataStore.deleteMissingFromCache(skippedSongPaths);
        }
        if (keptSongs.isEmpty) {
          _setSystemMediaFolder(null);
          await MetadataDatabase().syncSongSourcePresence(
            sourceMask: SongSourceFlags.systemMedia,
            presentPaths: const [],
          );
          notifyListeners();
          return;
        }
        debugPrint(
          '[ScannerService] iOS media scan result count=${songs.length} '
          'kept=${keptSongs.length}',
        );

        final metadataByPath = await _buildScannedMetadataMap(
          keptSongs,
          filePathOf: (song) => song.data,
          songIdOf: (song) => song.id,
          fallbackTitleOf: (song) => song.title,
          fallbackAlbumOf: (song) => song.album ?? '',
          fallbackArtistOf: (song) => song.artist ?? '',
          fallbackDurationOf: (song) => song.duration,
          fallbackTrackNumberOf: (song) => song.track,
          sourceFlags: SongSourceFlags.systemMedia,
        );

        _setSystemMediaFolder(
          _treeBuilder.buildFolderTreeFromMetadata(
            metadataByPath.values,
            _compareNaturally,
            rootPath: 'system',
            rootName: _l10n().systemMediaLibrary,
          ),
        );
        debugPrint(
          '[ScannerService] iOS system media tree built '
          'hasTree=${_systemMediaFolder != null} '
          'rootFolders=${_systemMediaFolder?.subFolders.length ?? 0} '
          'files=${_systemMediaFolder?.files.length ?? 0}',
        );
        if (_systemMediaFolder != null) {
          _folderSorter.sortFolderRecursiveForTree(
            _systemMediaFolder!,
            resolveSettings: _resolveSortSettingsForFolder,
          );
        }
        await MetadataDatabase().syncSongSourcePresence(
          sourceMask: SongSourceFlags.systemMedia,
          presentPaths: keptSongs.map((song) => song.data),
        );
        notifyListeners();

        unawaited(_refreshFolderCoversForRoots(['system']));
        unawaited(_processAndSaveIosSongsBackground(keptSongs));
      }
    } catch (e) {
      debugPrint('[ScannerService] Error scanning system media: $e');
    }
  }

  /// 冷启动把 `folder_entries` 里的目录统计灌进内存镜像。
  ///
  /// 一次全表 SELECT 换掉「每个根两条 LIKE 聚合」。树建好之后由
  /// [_persistFolderIndex] 用精确值覆盖同一批键，因此这里读到的是**上次**的结果，
  /// 只用来让目录页在建树之前也有数字可显示。`statsValid = false` 的行
  /// （上次扫描中断在半路）不采信。
  Future<void> _loadFolderEntriesFromDatabase() async {
    try {
      final rows = await _repository.loadAllFolderEntries();
      for (final row in rows) {
        if (!row.statsValid) continue;
        final normalized = _normalizePath(
          ScannerPathUtils.resolveIosSandboxPath(row.folderPath),
        );
        if (normalized.isEmpty) continue;
        _folderSongCounts[normalized] = row.songCount;
        _folderSongDurations[normalized] = row.totalDurationMs;
      }
      if (kDebugMode) {
        debugPrint(
          '[ScannerService][init] folder_entries seeded ${rows.length} rows',
        );
      }
    } catch (e) {
      debugPrint('[ScannerService] Failed to load folder entries: $e');
    }
  }

  Future<void> _loadCachedRootFoldersFromDatabase({
    Iterable<String>? rootPaths,
    List<SongMetadata>? cachedSongs,
    bool seedMetadataCache = true,
  }) async {
    try {
      final declaredRoots = (rootPaths ?? _roots.rootPaths)
          .map(_normalizePath)
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (declaredRoots.isEmpty) return;
      final availableRoots = declaredRoots
          .where(_isRootPathAvailable)
          .toList(growable: false);
      if (availableRoots.isEmpty) return;

      for (final root in availableRoots) {
        await loadRootFolderSongs(root);
        // loadRootFolderSongs 建完树后统计已经在内存里了，这里不再跑
        // COUNT(*) / SUM(duration) 的 LIKE 聚合——那两条是全表扫。
        final scanned = _scannedRootFolders.firstWhereOrNull(
          (folder) => _pathsEqual(folder.path, root),
        );
        if (scanned != null) {
          _folderSongCounts[root] = scanned.songCount;
          _folderSongDurations[root] = scanned.totalDurationMs;
        }

        final sortSettings = _resolveSortSettingsForFolder(root);
        final repSong = _folderRepresentativeSongs[root] ??
            await _repository.getRepresentativeSongUnderPath(
              root,
              criteria: sortSettings.criteria,
              order: sortSettings.order,
            );

        if (repSong != null) {
          _folderRepresentativeSongs[root] = repSong;
        }

        if (repSong != null && seedMetadataCache) {
          _metadataStore.cacheMetadata(repSong);
        }
      }
    } catch (e) {
      debugPrint('[ScannerService] Failed to load cached root folders: $e');
    }
  }

  Future<void> _loadCachedSystemMediaFolderFromDatabase({
    List<SongMetadata>? cachedSongs,
    bool seedMetadataCache = true,
  }) async {
    if (!Platform.isAndroid) return;

    try {
      final systemSongs =
          cachedSongs ?? await _repository.getSystemMediaSongs();
      if (systemSongs.isNotEmpty) {
        _setSystemMediaFolder(
          _treeBuilder.buildFolderTreeFromMetadata(
            systemSongs,
            _compareNaturally,
            rootPath: 'system',
            rootName: _l10n().systemMediaLibrary,
          ),
        );
        if (_systemMediaFolder != null) {
          _folderSorter.sortFolderRecursiveForTree(
            _systemMediaFolder!,
            resolveSettings: _resolveSortSettingsForFolder,
          );
        }
        if (seedMetadataCache) {
          for (final song in systemSongs) {
            _metadataStore.cacheMetadata(song);
          }
        }
        _loadedRootPaths.add('system');
      }
    } catch (e) {
      debugPrint(
        '[ScannerService] Failed to load cached system media folder: $e',
      );
    }
  }

  void _upsertScannedRootFolder(MusicFolder folder) {
    final index = _scannedRootFolders.indexWhere(
      (existing) => _pathsEqual(existing.path, folder.path),
    );
    if (index >= 0) {
      _scannedRootFolders[index] = folder;
    } else {
      _scannedRootFolders.add(folder);
    }
    final normalized = _normalizePath(folder.path);
    // 用 songCount 而不是 allSongs.length：后者会把整棵树的歌曲摊平成 List
    // 常驻在缓存里，只为拿一个长度不值得。
    _folderSongCounts[normalized] = folder.songCount;
    _folderSongDurations[normalized] = folder.totalDurationMs;
    // 树刚重建完，统计是权威值：落盘供下次冷启动直接读。
    _schedulePersistFolderIndex(normalized, folder);
  }

  final Map<String, Timer> _pendingFolderIndexTimers = {};
  final Map<String, MusicFolder> _pendingFolderIndexRoots = {};

  /// 合并同一根的高频重建。
  ///
  /// 扫描期间 `_upsertScannedRootFolder` 会被反复调用，每次都全量落盘是写放大；
  /// 这里只保留每个根的最新树引用，静默 800ms 后再写一次。
  void _schedulePersistFolderIndex(String rootPath, MusicFolder root) {
    if (_isDisposed) return;
    _pendingFolderIndexRoots[rootPath] = root;
    _pendingFolderIndexTimers[rootPath]?.cancel();
    _pendingFolderIndexTimers[rootPath] = Timer(
      const Duration(milliseconds: 800),
      () {
        _pendingFolderIndexTimers.remove(rootPath);
        final latest = _pendingFolderIndexRoots.remove(rootPath);
        if (latest == null || _isDisposed) return;
        unawaited(_persistFolderIndex(rootPath, latest));
      },
    );
  }

  /// 就地删歌后补一次统计落盘。
  ///
  /// `deleteMissingFromCache` 走的是 `_removeSongsFromFolder`，只改内存树，
  /// 不经过 `_upsertScannedRootFolder`（那是整根重建才走的），所以删歌之后
  /// `folder_entries` 会一直停在旧数字上，直到下一次根重建。
  ///
  /// 这里用「整树重写」而不是「沿父链向上冒泡」：树本来就在内存里，一次 O(N)
  /// 遍历 + 现有防抖，比维护增量路径安全得多，且同一批删除只会写一次。
  void _scheduleFolderIndexPersistForRemovedSongs(List<String> removedPaths) {
    if (_isDisposed || removedPaths.isEmpty) return;

    final affectedRoots = <String>{};
    for (final path in removedPaths) {
      affectedRoots.addAll(_rootPathsForDirectoryPath(path));
    }

    for (final rootPath in affectedRoots) {
      // system 根不落盘，统计直接读 `_systemMediaFolder`。
      final normalized = _normalizePath(rootPath);
      if (normalized == 'system' || normalized.startsWith('system/')) continue;
      final folder = _scannedRootFolders.firstWhereOrNull(
        (existing) => _pathsEqual(existing.path, rootPath),
      );
      if (folder == null) continue;
      // songCount / totalDurationMs 是惰性记忆化字段，文件刚被就地删掉，
      // 不先失效就会把删之前的数字原样写回库。
      folder.invalidateCache();
      _schedulePersistFolderIndex(normalized, folder);
    }
  }

  /// 把一棵完整树的目录统计写入 `folder_entries`。
  ///
  /// 只在根加载成功后调用——此时树是完整的，`statsValid` 才允许置 true。
  /// 写入走 unawaited，不阻塞目录页首帧。
  ///
  /// **只写统计，不写封面。** 封面唯一写入口是 `_refreshFolderCoversForRoots`：
  /// 这里走过的 `representativeSongCache` 会被 `notifyListeners()` 的
  /// `invalidateCache()` 清空，取决于 800ms 防抖窗口内有没有人重建过它，
  /// 采到的是空集或一个不确定的子集——写进去只会制造第二种封面来源。
  ///
  /// 覆盖范围是外部目录根（`_upsertScannedRootFolder` 之后调用）。Android 系统媒体库
  /// 的统计直接读内存树（`getSongCountForFolder` 对 `system` 走 `_systemMediaFolder`），
  /// 不依赖这张表，所以这里不写 system 根。
  Future<void> _persistFolderIndex(String rootPath, MusicFolder root) async {
    final snapshots = <FolderStatsSnapshot>[];

    void walk(MusicFolder folder) {
      final path = _normalizePath(folder.path);
      if (path.isNotEmpty) {
        final count = folder.songCount;
        final duration = folder.totalDurationMs;
        snapshots.add(
          FolderStatsSnapshot(
            folderPath: path,
            rootPath: rootPath,
            songCount: count,
            totalDurationMs: duration,
          ),
        );
        _folderSongCounts[path] = count;
        _folderSongDurations[path] = duration;
      }
      for (final sub in folder.subFolders) {
        walk(sub);
      }
    }

    walk(root);

    try {
      await _repository.batchWriteFolderStats(
        snapshots,
        statsValid: true,
      );
    } catch (e) {
      debugPrint('[ScannerService] Failed to persist folder index for $rootPath: $e');
    }
  }

  MusicFolder? _buildCachedFolderTree({
    required Iterable<SongMetadata> songs,
    required String rootPath,
    required String rootName,
  }) {
    final songList = songs.toList(growable: false);
    if (songList.isEmpty) return null;

    return _treeBuilder.buildFolderTreeFromMetadata(
      songList,
      _compareNaturally,
      rootPath: rootPath,
      rootName: rootName,
    );
  }

  void _seedMetadataCache(Iterable<SongMetadata> songs) {
    for (final song in songs) {
      _metadataStore.cacheMetadata(song);
    }
  }

  bool _songMatchesSource(
    SongMetadata song,
    int sourceMask, {
    bool includeLegacy = false,
  }) {
    final flags = song.sourceFlags;
    if (flags == null) return includeLegacy;
    return (flags & sourceMask) != 0;
  }

  String? _androidEntryFilePath(AndroidMediaLibraryEntry entry) {
    final path = entry.filePath?.trim();
    if (path != null && path.isNotEmpty) return _normalizePath(path);
    final uri = entry.uri.trim();
    if (uri.isNotEmpty) return uri;
    return null;
  }

  void _handleNavigationChanged() {
    if (_isDisposed) return;

    // 导航切换会改变当前文件夹，列表页需要立刻重建。
    _refreshStructureRevision();

    // Navigation changes should feel immediate even while a scan is running.
    // The throttled notifyListeners() path is still used for metadata/scan
    // updates, but folder switches need to repaint right away.
    super.notifyListeners();
  }

  void _syncScannedRootUiFromCache(String rootPath) {
    if (_isDisposed) return;
    _rebuildScannedRootFolderFromCache(rootPath);
    _rebuildDisplayedRootFolders();
    _syncNavigationStateToLatestTree(affectedRootPath: rootPath);
    notifyListeners();
  }

  void _syncScannedRootUiIncrementally(String rootPath) {
    if (_isDisposed) return;
    if (_pendingStage3IncrementalMetadata.isEmpty) return;

    final pending = List<SongMetadata>.from(_pendingStage3IncrementalMetadata);
    _pendingStage3IncrementalMetadata.clear();

    final rootFolder = _scannedRootFolders.firstWhereOrNull(
      (f) => _pathsEqual(f.path, rootPath),
    );

    if (rootFolder == null) {
      _syncScannedRootUiFromCache(rootPath);
      return;
    }

    final modifiedFolders = _treeBuilder.insertSongsToFolderTree(
      rootFolder,
      pending,
      rootPath: rootPath,
    );

    if (modifiedFolders.isNotEmpty) {
      final smallFolders = modifiedFolders.where((f) => f.files.length < 2000);
      if (smallFolders.isNotEmpty) {
        _folderSorter.sortSpecificFolders(
          smallFolders,
          resolveSettings: _resolveSortSettingsForFolder,
        );
      }
      for (final folder in modifiedFolders) {
        enqueueFolderCoverChainRefresh(folder.path);
      }
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree(affectedRootPath: rootPath);
      notifyListeners();
    }
  }

  void pauseBackgroundTasks() {
    if (!_scanCoordinator.isBackgroundPaused) {
      _scanCoordinator.setBackgroundPaused(true);
      debugPrint('ScannerService: Background tasks paused.');
      notifyListeners();
    }
  }

  void resumeBackgroundTasks() {
    if (_scanCoordinator.isBackgroundPaused) {
      _scanCoordinator.setBackgroundPaused(false);
      debugPrint('ScannerService: Background tasks resumed.');
      notifyListeners();
    }
  }

  Future<void> _waitUntilResumed() async {
    while (_scanCoordinator.isBackgroundPaused) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _processAndSaveAndroidSongsBackground(
    List<AndroidMediaLibraryEntry> entries,
  ) async {
    _pendingAndroidMediaEntries = entries;
    if (_androidMediaMetadataInFlight != null) return;

    // 系统媒体元数据重读必须串行（见下方注释）：跑的过程中再来请求，只把最新
    // 列表存下来，等当前这轮跑完再补一遍，保证新发现的文件不会漏。
    while (true) {
      final batch = _pendingAndroidMediaEntries;
      if (batch == null) break;
      _pendingAndroidMediaEntries = null;

      final future = _processEntriesBackground(
        batch,
        filePathOf: _androidEntryFilePath,
        songIdOf: (entry) => int.tryParse(entry.id),
        sourceMask: SongSourceFlags.systemMedia,
      );
      _androidMediaMetadataInFlight = future;
      try {
        await future;
      } finally {
        _androidMediaMetadataInFlight = null;
      }
    }
    unawaited(_refreshFolderCoversForRoots(['system']));
  }

  Future<void> _processAndSaveIosSongsBackground(List<SongModel> songs) async {
    await _processEntriesBackground(
      songs,
      filePathOf: (song) => song.data,
      songIdOf: (song) => song.id,
      sourceMask: SongSourceFlags.systemMedia,
    );
    unawaited(_refreshFolderCoversForRoots(['system']));
  }

  Future<Map<String, SongMetadata>> _buildScannedMetadataMap<T>(
    Iterable<T> entries, {
    required String? Function(T entry) filePathOf,
    required int? Function(T entry) songIdOf,
    required String Function(T entry) fallbackTitleOf,
    required String Function(T entry) fallbackAlbumOf,
    required String Function(T entry) fallbackArtistOf,
    required int? Function(T entry) fallbackDurationOf,
    required int? Function(T entry) fallbackTrackNumberOf,
    int? sourceFlags,
  }) async {
    final metadataByPath = <String, SongMetadata>{};

    final entryByPath = <String, T>{};
    final filePaths = <String>[];
    for (final entry in entries) {
      final filePath = filePathOf(entry);
      if (filePath == null) continue;
      entryByPath[filePath] = entry;
      filePaths.add(filePath);
    }

    final batchResults = await MetadataHelper.readMetadataBatch(
      filePaths,
      getImage: false,
    );
    final db = MetadataDatabase();

    for (final result in batchResults) {
      final filePath = result.path;
      if (filePath.isEmpty) continue;

      final entry = entryByPath[filePath];
      if (entry == null) continue;

      final existing = await db.getSongMetadata(filePath);
      final metadata = _buildScannedMetadataFromBatchResult(
        filePath,
        result,
        existing: existing,
        mediaId: songIdOf(entry),
        fallbackTitle: fallbackTitleOf(entry),
        fallbackAlbum: fallbackAlbumOf(entry),
        fallbackArtist: fallbackArtistOf(entry),
        fallbackDuration: fallbackDurationOf(entry),
        fallbackTrackNumber: fallbackTrackNumberOf(entry),
        sourceFlags: sourceFlags,
      );

      metadataByPath[filePath] = metadata;
      _metadataStore.cacheMetadata(metadata.copyWith(waveformBlob: null));
    }

    return metadataByPath;
  }

  Future<void> _processEntriesBackground<T>(
    Iterable<T> entries, {
    required String? Function(T entry) filePathOf,
    required int? Function(T entry) songIdOf,
    required int sourceMask,
  }) async {
    final player = _playerController;
    if (player == null) {
      debugPrint('Player controller not set for background scanning');
      return;
    }

    try {
      await player.initialize();
    } catch (e) {
      debugPrint(
        'Failed to initialize shared player for background scanning: $e',
      );
      return;
    }

    final scanState = ScanProgressState(
      metadataConcurrency: 4,
      comparePaths: _compareNaturally,
    );

    for (final entry in entries) {
      final currentEntry = entry;
      final path = filePathOf(currentEntry);
      if (path == null) continue;

      scanState.pendingMetadataTasks.add(
        scanState.metadataRunner.run(path, () async {
          await _waitUntilResumed();
          try {
            final processed = await MetadataHelper.processMetadata(
              path,
              songId: songIdOf(currentEntry),
              generateThumbnail: false,
            );
            if (processed == null) return;
            final metadata = processed.$1.copyWith(sourceFlags: sourceMask);
            await MetadataDatabase().insertOrUpdateSong(metadata);
            _metadataStore.cacheMetadata(metadata);
          } catch (e) {
            debugPrint('Background processing error for $path: $e');
          }
        }),
      );
    }

    await Future.wait(scanState.pendingMetadataTasks);
  }

  /// Public entry to trigger a rescan of a specific directory or system media.
  Future<void> rescanDirectory(String directoryPath) async {
    final normalized = _normalizePath(directoryPath);
    if (normalized == 'system' || normalized.startsWith('system/')) {
      await scanSystemMedia();
      return;
    }
    await _rescanDirectory(normalized);
  }

  Future<void> _rescanDirectory(String directoryPath) async {
    final normalizedDirectory = _normalizePath(directoryPath);
    if (normalizedDirectory.isEmpty) {
      return;
    }

    final affectedRoots = _rootPathsForDirectoryPath(normalizedDirectory);
    if (affectedRoots.isEmpty) {
      debugPrint(
        '[ScannerService] Skip rescan for directory outside active roots: '
        '$normalizedDirectory',
      );
      return;
    }

    if (_scanCoordinator.isScanning) {
      _scanCoordinator.requestRescan();
      return;
    }

    _scanCoordinator.beginIncrementalPhase();
    final scanState = ScanProgressState(
      metadataConcurrency: 2,
      comparePaths: _compareNaturally,
    );

    try {
      final directory = Directory(normalizedDirectory);
      if (!await directory.exists()) {
        await _removeDirectoryFromLibrary(normalizedDirectory);
        await _refreshAffectedRootsFromCache(affectedRoots);
        notifyListeners();
        return;
      }

      final discoveredFiles = await _directoryScanner
          .discoverMusicFilesInDirectory(normalizedDirectory, scanState);
      final normalizedDiscoveredPaths = discoveredFiles
          .map((f) => _normalizePath(f.path))
          .where((path) => path.isNotEmpty)
          .toSet();

      final existingPathsInDirectory = _metadataStore.metadataMap.keys
          .where(
            (path) =>
                _isImmediateChildOfDirectory(normalizedDirectory, path) &&
                MusicFileUtils.isMusicFilePath(path),
          )
          .toList(growable: false);

      for (final existingPath in existingPathsInDirectory) {
        if (!normalizedDiscoveredPaths.contains(existingPath)) {
          await _metadataStore.purgeMissingSongPath(existingPath);
        }
      }

      for (final filePath in normalizedDiscoveredPaths) {
        await _upsertIncrementalSongPath(filePath, scanState: scanState);
      }

      await _refreshAffectedRootsFromCache(affectedRoots);
      enqueueFolderCoverChainRefresh(normalizedDirectory);
      notifyListeners();
    } finally {
      _scanCoordinator.completeIncrementalPhase();
    }
  }

  Future<SongMetadata?> _upsertIncrementalSongPath(
    String filePath, {
    required ScanProgressState scanState,
  }) async {
    final normalizedPath = _normalizePath(filePath);
    if (normalizedPath.isEmpty) {
      return null;
    }

    final file = File(normalizedPath);
    if (!await file.exists()) {
      await _metadataStore.purgeMissingSongPath(normalizedPath);
      return null;
    }

    final classification = await _classifyDiscoveredFiles([
      ScanDiscoveredFile(path: normalizedPath),
    ]);
    final existingMetadataByPath = Map<String, SongMetadata>.from(
      classification.existingMetadataByPath,
    );
    final existing = existingMetadataByPath[_pathLookupKey(normalizedPath)];
    if (_shouldSkipShortAudioDuration(existing?.duration)) {
      await _metadataStore.purgeMissingSongPath(normalizedPath);
      return null;
    }

    await _preprocessChangedFiles(
      classification.pathsFor(ScanFileStage.full),
      scanState,
      existingMetadataByPath: existingMetadataByPath,
    );

    if (classification.pathsFor(ScanFileStage.unchanged).isNotEmpty &&
        !_metadataStore.containsPath(normalizedPath)) {
      final dbSong = await _repository.getSongMetadata(normalizedPath);
      if (dbSong != null) {
        _metadataStore.cacheMetadata(dbSong);
      }
    }

    return _metadataStore.getMetadata(normalizedPath) ??
        await _repository.getSongMetadata(normalizedPath);
  }

  Future<void> _removeDirectoryFromLibrary(String directoryPath) async {
    final normalizedPath = _normalizePath(directoryPath);
    if (normalizedPath.isEmpty) {
      return;
    }

    final affectedPaths = _metadataStore.metadataMap.keys
        .where((path) => _pathContains(normalizedPath, path))
        .toList(growable: false);
    if (affectedPaths.isEmpty) return;
    await _metadataStore.purgeMissingSongPaths(affectedPaths);
  }

  void _enqueueWatchedPath(String path) {
    if (_isDisposed || _mediaObserverPaused || isScanning || Platform.isLinux) return;

    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return;
    }

    final matchingRoot = _roots.rootPaths.cast<String?>().firstWhere(
      (root) =>
          _pathContains(root!, normalizedPath) ||
          _pathsEqual(root, normalizedPath),
      orElse: () => null,
    );
    if (matchingRoot == null) {
      return;
    }

    if (ScannerPathUtils.isHiddenOrExcludedPath(
      normalizedPath,
      rootPath: matchingRoot,
    )) {
      return;
    }

    try {
      final stat = FileStat.statSync(normalizedPath);
      if (stat.type == FileSystemEntityType.file ||
          stat.type == FileSystemEntityType.directory) {
        final mtime = stat.modified.millisecondsSinceEpoch;
        final cachedMtime = _watchedFileMtimes[normalizedPath];
        if (cachedMtime == mtime) {
          return;
        }
        _watchedFileMtimes[normalizedPath] = mtime;
      } else if (stat.type == FileSystemEntityType.notFound) {
        _watchedFileMtimes.remove(normalizedPath);
      }
    } catch (_) {
      // If we fail to read stats, let it proceed to rescan
    }

    final rescanMode = _determineRescanMode(normalizedPath);
    if (rescanMode == _DirectoryRescanMode.recursive) {
      _queueDirectoryRescan(normalizedPath, _DirectoryRescanMode.recursive);
      return;
    }

    _queueDirectoryRescan(
      _normalizePath(p.dirname(normalizedPath)),
      _DirectoryRescanMode.nonRecursive,
    );
  }

  Future<void> _populateWatchedMtimesFromLibrary() async {
    for (final entry in _metadataStore.metadataMap.entries) {
      final songPath = entry.key;
      final mtime = entry.value.lastModifiedTime;
      if (mtime != null) {
        _watchedFileMtimes[songPath] = mtime;
      }
    }

    final directoriesToStat = <String>{};
    for (final songPath in _metadataStore.metadataMap.keys) {
      directoriesToStat.add(_normalizePath(p.dirname(songPath)));
    }
    for (final root in _roots.rootPaths) {
      directoriesToStat.add(_normalizePath(root));
    }

    final pathList = directoriesToStat.toList(growable: false);
    const batchSize = 50;
    for (var i = 0; i < pathList.length; i += batchSize) {
      final end = i + batchSize < pathList.length
          ? i + batchSize
          : pathList.length;
      final chunk = pathList.sublist(i, end);
      await Future.wait(
        chunk.map((path) async {
          try {
            final stat = await FileStat.stat(path);
            if (stat.type != FileSystemEntityType.notFound) {
              _watchedFileMtimes[path] = stat.modified.millisecondsSinceEpoch;
            }
          } catch (_) {
            // ignore
          }
        }),
      );
    }
  }

  _DirectoryRescanMode _determineRescanMode(String path) {
    try {
      final entityType = FileSystemEntity.typeSync(path, followLinks: false);
      if (entityType == FileSystemEntityType.directory) {
        return _DirectoryRescanMode.recursive;
      }
      if (entityType == FileSystemEntityType.notFound &&
          _treeBuilder.resolveFolderForPath(
                path,
                _scannedRootFolders,
                _systemMediaFolder,
              ) !=
              null) {
        return _DirectoryRescanMode.recursive;
      }
    } catch (e, st) {
      debugPrint(
        '[ScannerService] directory type check failed path=$path: '
        '$e\n$st',
      );
    }

    return _DirectoryRescanMode.nonRecursive;
  }

  void _queueDirectoryRescan(String directoryPath, _DirectoryRescanMode mode) {
    if (_isDisposed) return;

    final normalizedPath = _normalizePath(directoryPath);
    if (normalizedPath.isEmpty) {
      return;
    }

    final existingMode = _pendingDirectoryRescanPaths[normalizedPath];
    if (existingMode == _DirectoryRescanMode.recursive ||
        mode == _DirectoryRescanMode.nonRecursive) {
      _pendingDirectoryRescanPaths.putIfAbsent(normalizedPath, () => mode);
    } else {
      _pendingDirectoryRescanPaths[normalizedPath] = mode;
    }
    _directoryRescanTimer?.cancel();
    _directoryRescanTimer = Timer(
      _directoryRescanBatchWindow,
      () => unawaited(_flushPendingDirectoryRescans()),
    );
  }

  Future<void> _flushPendingDirectoryRescans() async {
    _directoryRescanTimer = null;
    if (_isDisposed || _directoryRescanInProgress || _mediaObserverPaused) {
      return;
    }
    if (_scanCoordinator.isScanning) {
      return;
    }
    if (_pendingDirectoryRescanPaths.isEmpty) {
      return;
    }

    _directoryRescanInProgress = true;
    final directoryPaths = _pendingDirectoryRescanPaths.entries.toList(
      growable: false,
    );
    _pendingDirectoryRescanPaths.clear();

    try {
      final recursiveRoots = <String>{};
      for (final entry in directoryPaths) {
        if (_isDisposed) {
          return;
        }
        if (entry.value == _DirectoryRescanMode.recursive) {
          recursiveRoots.addAll(_rootPathsForDirectoryPath(entry.key));
        }
      }

      if (recursiveRoots.isNotEmpty) {
        await _scanRootsWithFullFlow(
          () => recursiveRoots,
          clearScannedRoots: false,
        );
      }

      for (final entry in directoryPaths) {
        if (_isDisposed) {
          return;
        }
        if (entry.value == _DirectoryRescanMode.nonRecursive) {
          if (recursiveRoots.any((root) => _pathContains(root, entry.key))) {
            continue;
          }
          await _rescanDirectory(entry.key);
        }
      }
    } finally {
      _directoryRescanInProgress = false;
      if (!_isDisposed &&
          _pendingDirectoryRescanPaths.isNotEmpty &&
          _directoryRescanTimer == null) {
        _directoryRescanTimer = Timer(
          Duration.zero,
          () => unawaited(_flushPendingDirectoryRescans()),
        );
      }
    }
  }

  void cancelScan() {
    _scanCoordinator.cancelActiveScan();
  }

  void _restartFullRootScan() {
    _scanCoordinator.requestRescan();
    if (_scanCoordinator.isScanning) {
      return;
    }
    unawaited(scan(clearScannedRoots: false));
  }

  bool _isScanTokenCurrent(int scanToken) {
    return _scanCoordinator.isSessionCurrent(scanToken);
  }

  Future<ScanFileClassification> _classifyDiscoveredFiles(
    List<ScanDiscoveredFile> discoveredFiles, {
    bool Function()? shouldCancel,
  }) async {
    return _scanPipeline.classifyDiscoveredFiles(
      discoveredFiles,
      shouldCancel: shouldCancel,
    );
  }

  void _seedMetadataFromDatabase(
    Map<String, SongMetadata> existingMetadataByPath,
  ) {
    _scanPipeline.seedMetadataFromDatabase(existingMetadataByPath);
  }

  Future<ScanPreprocessResult> _preprocessChangedFiles(
    List<String> fullPaths,
    ScanProgressState scanState, {
    required Map<String, SongMetadata> existingMetadataByPath,
    int? rootScanSessionId,
    bool Function()? shouldCancel,
  }) async {
    if (fullPaths.isEmpty) {
      return const ScanPreprocessResult(
        keptPaths: <String>[],
        artworkPendingPaths: <String>[],
      );
    }

    final db = MetadataDatabase();
    final sortedPaths = fullPaths.toList()..sort(_compareNaturally);
    final totalStopwatch = Stopwatch()..start();
    final keptPaths = <String>[];
    final artworkPendingPaths = <String>[];
    final skippedPaths = <String>[];

    void flushSkippedPaths() {
      if (skippedPaths.isEmpty) return;
      _metadataStore.deleteMissingFromCache(skippedPaths);
      skippedPaths.clear();
    }

    const batchSize = 200;
    for (var start = 0; start < sortedPaths.length; start += batchSize) {
      if (shouldCancel?.call() ?? false) {
        flushSkippedPaths();
        return ScanPreprocessResult(
          keptPaths: keptPaths,
          artworkPendingPaths: artworkPendingPaths,
        );
      }
      final end = start + batchSize < sortedPaths.length
          ? start + batchSize
          : sortedPaths.length;
      final chunk = sortedPaths.sublist(start, end);
      final batchStopwatch = Stopwatch()..start();

      final readStopwatch = Stopwatch()..start();
      final results = await MetadataHelper.readMetadataBatch(
        chunk,
        getImage: false,
      );
      if (shouldCancel?.call() ?? false) {
        flushSkippedPaths();
        return ScanPreprocessResult(
          keptPaths: keptPaths,
          artworkPendingPaths: artworkPendingPaths,
        );
      }
      readStopwatch.stop();
      _logScanTiming(
        'stage 3 batch ${start + 1}-$end readMetadataBatch',
        readStopwatch,
      );

      final writeStopwatch = Stopwatch()..start();
      final metadataBatch = <SongMetadata>[];
      for (final result in results) {
        if (shouldCancel?.call() ?? false) {
          flushSkippedPaths();
          return ScanPreprocessResult(
            keptPaths: keptPaths,
            artworkPendingPaths: artworkPendingPaths,
          );
        }
        final filePath = result.path;
        if (filePath.isEmpty) continue;

        try {
          final existing =
              existingMetadataByPath[_pathLookupKey(filePath)] ??
              await db.getSongMetadata(filePath);
          var metadata = _buildScannedMetadataFromBatchResult(
            filePath,
            result,
            existing: existing,
            sourceFlags: SongSourceFlags.rootScan,
          );
          if (_shouldSkipShortAudioDuration(metadata.duration)) {
            skippedPaths.add(filePath);
            continue;
          }
          metadataBatch.add(metadata);
          keptPaths.add(filePath);
          _metadataStore.cacheMetadata(metadata);
          _pendingStage3IncrementalMetadata.add(metadata);
          scanState.preprocessedCount++;
          scanState.completedCount++;
        } catch (e) {
          debugPrint('Metadata batch scan error for $filePath: $e');
        } finally {
          _emitScanProgress(scanState, filePath);
        }
      }
      if (metadataBatch.isNotEmpty) {
        await db.insertOrUpdateSongsMerged(
          metadataBatch,
          rootScanSessionId: rootScanSessionId,
        );
      }
      writeStopwatch.stop();
      _logScanTiming(
        'stage 3 batch ${start + 1}-$end db+cache update',
        writeStopwatch,
      );
      batchStopwatch.stop();
      _logScanTiming('stage 3 batch ${start + 1}-$end total', batchStopwatch);
      await Future.delayed(const Duration(milliseconds: 1));
    }

    flushSkippedPaths();
    if (keptPaths.isNotEmpty) {
      _emitScanProgress(scanState, keptPaths.last, force: true);
    }
    totalStopwatch.stop();
    _logScanTiming('stage 3 preprocess text tags total', totalStopwatch);
    return ScanPreprocessResult(
      keptPaths: keptPaths,
      artworkPendingPaths: artworkPendingPaths,
    );
  }


  void _removeRootsFromScannedTree(Iterable<String> roots) {
    final normalizedRoots = _normalizeDeclaredRootPaths(roots);
    if (normalizedRoots.isEmpty) return;
    _scannedRootFolders.removeWhere(
      (folder) => normalizedRoots.any((root) => _pathsEqual(folder.path, root)),
    );
    final separator = Platform.isWindows ? '\\' : '/';
    bool matchesAnyRoot(String path) {
      return normalizedRoots.any((root) {
        if (_pathsEqual(path, root)) return true;
        final prefix = root.endsWith(separator) ? root : '$root$separator';
        return path.startsWith(prefix);
      });
    }
    _folderRepresentativeSongs.removeWhere((path, _) => matchesAnyRoot(path));
    _folderRepresentativeSongPaths.removeWhere((path, _) => matchesAnyRoot(path));
  }

  Future<void> _purgeRemovedRootsFromMetadataCache(
    Iterable<String> roots,
  ) async {
    final normalizedRoots = _normalizeDeclaredRootPaths(roots);
    if (normalizedRoots.isEmpty) return;

    await _repository.unbindRootPaths(normalizedRoots);
    await _repository.removeFolderEntriesUnderRoots(normalizedRoots);
    for (final root in normalizedRoots) {
      _folderSongCounts.removeWhere(
        (path, _) => _pathContains(root, path) || _pathsEqual(root, path),
      );
      _folderSongDurations.removeWhere(
        (path, _) => _pathContains(root, path) || _pathsEqual(root, path),
      );
    }

    final sweepResult = await _repository.sweepOrphanSongs();
    if (sweepResult.deletedPaths.isEmpty) return;

    _notifySongsPurged(sweepResult.deletedPaths, normalizedRoots);

    _metadataStore.deleteMissingFromCache(
      sweepResult.deletedPaths,
      updateVisibleTrees: false,
    );
    for (final path in sweepResult.deletedPaths) {
      _notifySongMissingState(path, true);
    }
  }

  void _invalidateScanRootsCache() {
    _cachedActiveScanRootLookupKeys = null;
    _cachedNormalizedActiveRoots = null;
    _cachedNormalizedSystemFolderPath = null;
  }

  Set<String> _getActiveScanRootLookupKeys() {
    final cached = _cachedActiveScanRootLookupKeys;
    if (cached != null) return cached;
    final roots = _computeScanRoots(_roots.rootPaths);
    final keys = roots.map(_pathLookupKey).toSet();
    _cachedActiveScanRootLookupKeys = keys;
    return keys;
  }

  bool _isScanRootStillActive(String rootPath, {bool checkDisk = false}) {
    final rootKey = _pathLookupKey(rootPath);
    if (!_getActiveScanRootLookupKeys().contains(rootKey)) {
      return false;
    }
    if (!checkDisk) {
      return true;
    }
    try {
      final exists = Directory(rootPath).existsSync();
      if (!exists) {
        debugPrint(
          '[ScannerService] scan root inactive because path no longer exists '
          'path=$rootPath',
        );
      }
      return exists;
    } catch (e, st) {
      debugPrint(
        '[ScannerService] scan root inactive because existsSync failed '
        'path=$rootPath: $e\n$st',
      );
      return false;
    }
  }

  Future<List<ScanDiscoveredFile>> _discoverRootFilePaths(
    String rootPath,
    ScanProgressState scanState,
    int scanToken,
  ) async {
    if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(rootPath)) {
      debugPrint(
        '[ScannerService] skip directory traversal for stale root '
        'path=$rootPath',
      );
      return const <ScanDiscoveredFile>[];
    }
    debugPrint(
      '[ScannerService] begin directory traversal path=$rootPath '
      'scanToken=$scanToken',
    );
    final discoveredFiles = await _directoryScanner.discoverMusicFiles(
      rootPath,
      scanState,
      shouldCancel: () =>
          !_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(rootPath),
    );
    debugPrint(
      '[ScannerService] directory traversal finished path=$rootPath '
      'count=${discoveredFiles.length}',
    );
    if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(rootPath)) {
      _scannedRootFolders.removeWhere(
        (existing) => _pathsEqual(existing.path, rootPath),
      );
      debugPrint(
        '[ScannerService] discard traversal result for stale root '
        'path=$rootPath',
      );
      return const <ScanDiscoveredFile>[];
    }
    if (discoveredFiles.isEmpty) {
      _scannedRootFolders.removeWhere(
        (existing) => _pathsEqual(existing.path, rootPath),
      );
      debugPrint(
        '[ScannerService] traversal found no music files path=$rootPath',
      );
      return const <ScanDiscoveredFile>[];
    }
    return discoveredFiles;
  }

  Future<void> _rebuildScannedRootFolderFromMetadata(
    String rootPath,
    Iterable<String> discoveredPaths,
  ) async {
    final metadataByLookupKey = <String, SongMetadata>{};
    var count = 0;
    for (final path in discoveredPaths) {
      count++;
      if (count % 5000 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final normalizedPath = _normalizePath(path);
      if (normalizedPath.isEmpty) {
        continue;
      }
      final metadata =
          _metadataStore.getMetadata(normalizedPath) ??
          _metadataStore.getMetadata(path);
      if (metadata == null) {
        continue;
      }
      metadataByLookupKey[_pathLookupKey(normalizedPath)] = metadata;
    }

    if (metadataByLookupKey.isEmpty) {
      _scannedRootFolders.removeWhere(
        (existing) => _pathsEqual(existing.path, rootPath),
      );
      return;
    }

    await Future<void>.delayed(Duration.zero);

    final rootFolder = _timeScanStepSync(
      'stage 4.2 build metadata tree for $rootPath',
      () => _treeBuilder.buildFolderTreeFromMetadata(
        metadataByLookupKey.values,
        _compareNaturally,
        rootPath: rootPath,
        rootName: _displayNameForPath(rootPath),
        skipSort: true,
      ),
    );

    await Future<void>.delayed(Duration.zero);

    _folderSorter.sortFolderRecursiveForTree(
      rootFolder,
      resolveSettings: _resolveSortSettingsForFolder,
    );
    _upsertScannedRootFolder(rootFolder);
  }

  void _rebuildScannedRootFolderFromCache(String rootPath) {
    final songs = _metadataStore.metadataMap.values.where(
      (song) =>
          _songMatchesSource(
            song,
            SongSourceFlags.rootScan,
            includeLegacy: true,
          ) &&
          _shouldKeepSongMetadata(song) &&
          _pathContains(rootPath, song.path),
    );
    final rootFolder = _buildCachedFolderTree(
      songs: songs,
      rootPath: rootPath,
      rootName: _displayNameForPath(rootPath),
    );
    if (rootFolder == null) {
      _scannedRootFolders.removeWhere(
        (existing) => _pathsEqual(existing.path, rootPath),
      );
      return;
    }
    _folderSorter.sortFolderRecursiveForTree(
      rootFolder,
      resolveSettings: _resolveSortSettingsForFolder,
    );
    _upsertScannedRootFolder(rootFolder);
  }

  Future<void> _refreshAffectedRootsFromCache(Iterable<String> affectedRoots) async {
    for (final rootPath in affectedRoots) {
      _rebuildScannedRootFolderFromCache(rootPath);
    }
    if (affectedRoots.isNotEmpty) {
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      await _refreshFolderCoversForRoots(affectedRoots);
    }
  }

  Set<String> _rootPathsForDirectoryPath(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return <String>{};
    }
    return _roots.rootPaths
        .where(
          (rootPath) =>
              _pathContains(rootPath, normalizedPath) ||
              _pathContains(normalizedPath, rootPath),
        )
        .toSet();
  }

  Future<void> _processDiscoveredPaths(
    List<ScanDiscoveredFile> discoveredFiles,
    ScanProgressState scanState,
    int scanToken, {
    required String rootPath,
  }) async {
    if (discoveredFiles.isEmpty) {
      return;
    }
    if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(rootPath)) {
      return;
    }

    _currentScanStage = 'stage 2: classify discovered files ($rootPath)';
    final classification = await _timeScanStep(
      'stage 2 classify discovered files batch',
      () => _classifyDiscoveredFiles(
        discoveredFiles,
        shouldCancel: () =>
            !_isScanTokenCurrent(scanToken) ||
            !_isScanRootStillActive(rootPath),
      ),
    );
    if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(rootPath)) {
      return;
    }
    final existingMetadataByPath = Map<String, SongMetadata>.from(
      classification.existingMetadataByPath,
    );
    existingMetadataByPath.removeWhere(
      (path, metadata) => _shouldSkipShortAudioDuration(metadata.duration),
    );
    _currentScanStage = 'stage 2.1: seed metadata from db ($rootPath)';
    _timeScanStepSync('stage 2.1 seed metadata from db batch', () {
      _seedMetadataFromDatabase(existingMetadataByPath);
    });

    final skippedKnownPaths = <String>[];
    final fullPaths = <String>[];
    final imageOnlyPaths = <String>[];
    final unchangedPaths = <String>[];

    for (final entry in classification.stageByPath.entries) {
      final path = entry.key;
      final stage = entry.value;
      final existing =
          classification.existingMetadataByPath[_pathLookupKey(path)];
      if (_shouldSkipShortAudioDuration(existing?.duration)) {
        skippedKnownPaths.add(path);
        continue;
      }
      switch (stage) {
        case ScanFileStage.full:
          fullPaths.add(path);
          break;
        case ScanFileStage.imageOnly:
          imageOnlyPaths.add(path);
          break;
        case ScanFileStage.unchanged:
          unchangedPaths.add(path);
          break;
      }
    }
    if (skippedKnownPaths.isNotEmpty) {
      _metadataStore.deleteMissingFromCache(skippedKnownPaths);
    }
    scanState.completedCount += unchangedPaths.length + imageOnlyPaths.length;

    Timer? stage3UiSyncTimer;
    try {
      _pendingStage3IncrementalMetadata.clear();
      stage3UiSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_isScanTokenCurrent(scanToken) ||
            !_isScanRootStillActive(rootPath)) {
          return;
        }
        _syncScannedRootUiIncrementally(rootPath);
      });

      _currentScanStage = 'stage 3: preprocess text tags (${fullPaths.length} files, $rootPath)';
      final preprocessResult = await _timeScanStep(
        'stage 3 preprocess text tags batch',
        () => _preprocessChangedFiles(
          fullPaths,
          scanState,
          existingMetadataByPath: existingMetadataByPath,
          shouldCancel: () =>
              !_isScanTokenCurrent(scanToken) ||
              !_isScanRootStillActive(rootPath),
        ),
      );
      if (!_isScanTokenCurrent(scanToken) ||
          !_isScanRootStillActive(rootPath)) {
        return;
      }
      final keptFullPaths = preprocessResult.keptPaths;

      final visiblePaths = <String>[
        ...unchangedPaths,
        ...keptFullPaths,
        ...imageOnlyPaths,
      ];

      _currentScanStage = 'stage 3.1: mark root scan token ($rootPath)';
      await _timeScanStep('stage 3.1 mark root scan token batch', () async {
        await MetadataDatabase().markRootScanSeenWithToken(
          visiblePaths,
          scanToken: scanToken,
          sourceMask: SongSourceFlags.rootScan,
        );
        await MetadataDatabase().bindSongsToRootBatch(visiblePaths, rootPath);
      });
      if (!_isScanTokenCurrent(scanToken) ||
          !_isScanRootStillActive(rootPath)) {
        return;
      }

      await Future<void>.delayed(Duration.zero);
      _currentScanStage = 'stage 3.2: rebuild visible root tree ($rootPath)';
      await _timeScanStep('stage 3.2 rebuild visible root tree', () async {
        await _rebuildScannedRootFolderFromMetadata(rootPath, visiblePaths);
        _rebuildDisplayedRootFolders();
        _syncNavigationStateToLatestTree(affectedRootPath: rootPath);
      });
      scanState.pendingMetadataPaths.addAll(visiblePaths);
      notifyListeners();
    } finally {
      stage3UiSyncTimer?.cancel();
      _pendingStage3IncrementalMetadata.clear();
    }
  }


  SongMetadata _buildScannedMetadataFromBatchResult(
    String filePath,
    dynamic result, {
    SongMetadata? existing,
    int? sourceFlags,
    int? mediaId,
    String? fallbackTitle,
    String? fallbackAlbum,
    String? fallbackArtist,
    String? fallbackAlbumArtist,
    int? fallbackDuration,
    int? fallbackTrackNumber,
  }) {
    return _scanPipeline.buildScannedMetadataFromBatchResult(
      filePath,
      result,
      existing: existing,
      sourceFlags: sourceFlags,
      mediaId: mediaId,
      fallbackTitle: fallbackTitle,
      fallbackAlbum: fallbackAlbum,
      fallbackArtist: fallbackArtist,
      fallbackAlbumArtist: fallbackAlbumArtist,
      fallbackDuration: fallbackDuration,
      fallbackTrackNumber: fallbackTrackNumber,
    );
  }

  Future<void> scan({
    bool clearScannedRoots = false,
    bool rescanSystemMedia = false,
  }) async {
    _failedThumbnailPaths.clear();
    _watchedFileMtimes.clear();
    if (rescanSystemMedia && Platform.isAndroid && _hasPermission) {
      unawaited(scanSystemMedia());
    }
    await _scanRootsWithFullFlow(
      () => _roots.rootPaths,
      clearScannedRoots: clearScannedRoots,
    );
  }

  Future<void> rebuildIndex() async {
    final stopwatch = Stopwatch()..start();
    try {
      // 1. Clear songs in database except external
      await _repository.clearSongsExceptExternal();

      // 2. Clear matching in-memory metadata
      _metadataStore.metadataMap.removeWhere((path, metadata) {
        final flags = metadata.sourceFlags ?? 0;
        return (flags & SongSourceFlags.external) == 0;
      });
      _failedThumbnailPaths.clear();
      _watchedFileMtimes.clear();
      _markMetadataMutated();
      _markAlbumLibraryMutated();

      // 3. Clear current folder structure and notify UI
      _scannedRootFolders.clear();
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      notifyListeners();

      // 4. Trigger rescan of all root paths
      await scan(clearScannedRoots: true);
    } finally {
      stopwatch.stop();
      if (kDebugMode) {
        debugPrint(
          '[ScannerService] rebuildIndex completed in ${stopwatch.elapsedMilliseconds} ms',
        );
      }
    }
  }

  Future<void> _scanRootsWithFullFlow(
    Iterable<String> Function() rootsProvider, {
    required bool clearScannedRoots,
  }) async {
    await _loadScanSettings();
    await _scanCoordinator.runFullScan(
      (scanToken) => _runFullScanSession(
        scanToken,
        rootsProvider: rootsProvider,
        clearScannedRoots: clearScannedRoots,
      ),
    );
  }

  Future<void> _runFullScanSession(
    int scanToken, {
    required Iterable<String> Function() rootsProvider,
    required bool clearScannedRoots,
  }) async {
    notifyListeners();

    final totalStopwatch = Stopwatch()..start();
    ScanProgressState? currentScanState;
    _currentScanStage = 'stage 0: permissions';
    final heartbeatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      debugPrint(
        '[ScannerHeartbeat] ${totalStopwatch.elapsed.inSeconds}s | '
        'stage: $_currentScanStage | '
        'activeRoot: ${_scanCoordinator.state.activeRootPath ?? "none"} | '
        'discovered: ${currentScanState?.discoveredCount ?? 0} | '
        'completed: ${currentScanState?.completedCount ?? 0} | '
        'isScanning: $isScanning',
      );
    });

    try {
      final permissionsStopwatch = Stopwatch()..start();
      final hasPermission = await _checkPermissions(request: false);
      permissionsStopwatch.stop();
      _logScanTiming('stage 0 permissions', permissionsStopwatch);

      if (Platform.isAndroid && hasPermission) {
        _hasPermission = true;
        if (_systemMediaFolder == null) {
          unawaited(scanSystemMedia());
        }
      }

      if (Platform.isIOS || Platform.isMacOS) {
        _currentScanStage = 'stage 0.5: healIosSandboxPaths';
        debugPrint('[ScannerService] Starting healIosSandboxPaths...');
        await MetadataDatabase().healIosSandboxPaths();
        debugPrint('[ScannerService] Finished healIosSandboxPaths.');
      }

      _currentScanStage = 'stage 1: root discovery';
      final scanState = ScanProgressState(
        metadataConcurrency: 4,
        comparePaths: _compareNaturally,
      );
      currentScanState = scanState;
      final scanRoots = _timeScanStepSync('stage 1 root discovery', () {
        _invalidateScanRootsCache();
        final requestedRoots = _computeScanRoots(rootsProvider());
        final roots = requestedRoots.toList(growable: false);
        roots.sort(_compareNaturally);
        debugPrint(
          '[ScannerService] scan root discovery requested=$requestedRoots '
          'resolved=$roots currentRoots=${_roots.rootPaths}',
        );
        return roots;
      });

      if (scanRoots.isEmpty) {
        if (clearScannedRoots) {
          _scannedRootFolders.clear();
          _rebuildDisplayedRootFolders();
          _syncNavigationStateToLatestTree();
          notifyListeners();
        }
        return;
      }

      if (clearScannedRoots) {
        _scannedRootFolders.clear();
        _loadedRootPaths.removeWhere((path) => path != 'system');
      }
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      notifyListeners();

      for (final path in scanRoots) {
        if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(path)) {
          debugPrint(
            '[ScannerService] Skipping stale scan root after scan restart: $path',
          );
          continue;
        }
        _scanCoordinator.setActiveRootPath(path);
        debugPrint('Starting scan at: $path');

        _currentScanStage = 'stage 1.1: directory traversal ($path)';
        final discoveredPaths = await _timeScanStep(
          'stage 1.1 directory traversal for $path',
          () => _discoverRootFilePaths(path, scanState, scanToken),
        );
        debugPrint(
          '[ScannerService] traversal stage returned path=$path '
          'count=${discoveredPaths.length}',
        );

        if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(path)) {
          debugPrint(
            '[ScannerService] Discarding stale scan result after scan restart: $path',
          );
          _scannedRootFolders.removeWhere(
            (existing) => _pathsEqual(existing.path, path),
          );
          continue;
        }

        _currentScanStage = 'stage 2: process discovered paths ($path, ${discoveredPaths.length} files)';
        await _processDiscoveredPaths(
          discoveredPaths,
          scanState,
          scanToken,
          rootPath: path,
        );

        if (!_isScanTokenCurrent(scanToken) || !_isScanRootStillActive(path)) {
          debugPrint(
            '[ScannerService] Root scan became stale before tree refresh: $path',
          );
          _scannedRootFolders.removeWhere(
            (existing) => _pathsEqual(existing.path, path),
          );
          continue;
        }
      }

      if (_isScanTokenCurrent(scanToken)) {
        _currentScanStage = 'stage 5: collect present paths';
        final presentPaths = _timeScanStepSync(
          'stage 5 collect present paths',
          () {
            return scanState.pendingMetadataPaths
                .map(_normalizePath)
                .where((path) => path.isNotEmpty)
                .toSet();
          },
        );
        _currentScanStage = 'stage 5.1: sweep root scan state';
        final sweepResult = await _timeScanStep(
          'stage 5.1 sweep root scan state',
          () => _repository.sweepRootScanState(
            scanToken: scanToken,
            sourceMask: SongSourceFlags.rootScan,
            activeRoots: scanRoots,
          ),
        );
        _currentScanStage = 'stage 5.4: notify missing states';
        _timeScanStepSync('stage 5.4 notify missing states', () {
          for (final path in presentPaths) {
            _notifySongMissingState(path, false);
          }
          for (final path in sweepResult.deletedPaths) {
            _notifySongMissingState(path, true);
          }
          for (final path in sweepResult.softDeletedPaths) {
            _notifySongMissingState(path, true);
          }
          if (sweepResult.softDeletedPaths.isNotEmpty) {
            _metadataStore.deleteMissingFromCache(
              sweepResult.softDeletedPaths,
              updateVisibleTrees: true,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      heartbeatTimer.cancel();
      _currentScanStage = 'idle';
      _pendingDirectoryRescanPaths.clear();
      _directoryRescanTimer?.cancel();
      _directoryRescanTimer = null;
      try {
        await _timeScanStep(
          'populate watched mtimes from library',
          () async => _populateWatchedMtimesFromLibrary(),
        );
      } catch (e) {
        debugPrint('[ScannerService] Failed to populate watched mtimes: $e');
      }
      _flushScanNotifications();
      _scanCoordinator.setActiveRootPath(null);
      await _timeScanStep(
        'stage 5.7 final sort and notify',
        () async => _sortAndNotify(),
      );
      totalStopwatch.stop();
      _logScanTiming('scan total', totalStopwatch);
    }
  }

  Future<void> rebuildMetadataDatabase() async {
    if (Platform.isWindows) {
      await MetadataDatabase().clearAll();
      await MetadataHelper.clearThumbnails();
      _metadataStore.clear();
      await scan();
    }
  }

  /// Loads metadata for a single path from the DB (or processes it fresh) and
  /// caches it in [metadataMap]. Safe to call multiple times.
  Future<void> loadMetadataForPath(String path) async {
    await _metadataStore.loadMetadataForPath(path);
  }

  /// Forces a full metadata re-read for the given paths and writes the
  /// refreshed records back into the database and in-memory cache.
  Future<void> refreshMetadataForPaths(Iterable<String> paths) async {
    for (final path in paths) {
      await refreshMetadataForPath(path);
    }
  }

  /// Forces a full metadata re-read for one path.
  Future<void> refreshMetadataForPath(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return;
    }
    _failedThumbnailPaths.remove(normalizedPath);

    final canAccess = await MetadataHelper.canAccessAudioFile(normalizedPath);
    if (!canAccess) {
      debugPrint(
        '[ScannerService] refreshMetadataForPath skipped, cannot access file '
        'path=$normalizedPath',
      );
      return;
    }

    try {
      final processed = await MetadataHelper.processMetadata(
        normalizedPath,
        generateThumbnail: true,
        forceRefresh: true,
      );
      if (processed == null) {
        debugPrint(
          '[ScannerService] refreshMetadataForPath failed to process '
          'path=$normalizedPath',
        );
        return;
      }

      final metadata = processed.$1;
      final artworkBytes = processed.$2;
      _metadataStore.updateMetadataForPath(
        metadata,
        artworkBytes: artworkBytes,
      );
    } catch (e) {
      debugPrint(
        '[ScannerService] refreshMetadataForPath error path=$normalizedPath: '
        '$e',
      );
    }
  }

  Future<void> loadThumbnailForPath(String path) async {
    if (_failedThumbnailPaths.contains(path)) {
      return;
    }
    await _metadataStore.loadThumbnailForPath(path);
    final cached =
        _metadataStore.getMetadata(path) ??
        await MetadataDatabase().getSongMetadata(path);
    if (cached != null && (cached.thumbnailPath?.trim().isNotEmpty ?? false)) {
      if (await File(cached.thumbnailPath!).exists()) {
        return;
      }
    }
    final updated = await _recoverThumbnailCacheWithAudioCore(
      path,
      existingMetadata: cached,
    );
    if (updated == null ||
        updated.thumbnailPath == null ||
        updated.thumbnailPath!.trim().isEmpty) {
      _failedThumbnailPaths.add(path);
    }
  }

  void updateMetadataForPath(
    SongMetadata metadata, {
    Uint8List? artworkBytes,
    bool notify = true,
    bool syncTree = true,
  }) {
    _failedThumbnailPaths.remove(metadata.path);
    if (syncTree) {
      // 用户编辑标签会就地替换 folder.files 里的 MusicFile，顶层目录对象
      // identity 不变，指纹感知不到，这里显式推进结构版本让列表页重建。
      _structureRevision++;
    }
    _metadataStore.updateMetadataForPath(
      metadata,
      artworkBytes: artworkBytes,
      notify: notify,
      syncTree: syncTree,
    );
  }

  void _emitScanProgress(
    ScanProgressState scanState,
    String filePath, {
    bool force = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && (now - _lastScanProgressEmitMs < 1000)) {
      return;
    }
    _lastScanProgressEmitMs = now;
    _scanProgressController.add(
      ScanProgress(
        filePath: filePath,
        discoveredCount: scanState.discoveredCount,
        preprocessedCount: scanState.preprocessedCount,
        completedCount: scanState.completedCount,
      ),
    );
  }

  Future<SongMetadata?> _recoverThumbnailCacheWithAudioCore(
    String path, {
    SongMetadata? existingMetadata,
    bool notifyStore = true,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }

    final hasEmbeddedArtwork = await MetadataHelper.hasEmbeddedArtwork(path);
    if (!hasEmbeddedArtwork) {
      return null;
    }

    try {
      final controller = _playerController ?? AudioCoreController();
      final artwork = await TrackArtworkThemeService(db: MetadataDatabase())
          .getTrackArtworkTheme(
            path,
            controller: controller,
            saveLargeArtwork: false,
            thumbnailSize: vynodyArtworkThumbnailSize,
          );

      if (artwork == null || !artwork.hasThumbnailPath) {
        return null;
      }

      int? resolvedFlags = existingMetadata?.sourceFlags;
      final isInsideRoot = _roots.rootPaths.any(
        (root) => _pathContains(root, path),
      );
      if (isInsideRoot) {
        if (resolvedFlags == null) {
          resolvedFlags = SongSourceFlags.rootScan;
        } else {
          resolvedFlags =
              (resolvedFlags & ~SongSourceFlags.external) |
              SongSourceFlags.rootScan;
        }
      } else {
        resolvedFlags ??= SongSourceFlags.external;
      }

      final lastModified =
          existingMetadata?.lastModifiedTime ??
          (await file.lastModified()).millisecondsSinceEpoch;
      final now = DateTime.now().millisecondsSinceEpoch;
      final updated =
          (existingMetadata ??
                  SongMetadata(
                    path: path,
                    title: p.basenameWithoutExtension(path),
                    album: 'Unknown Album',
                    artist: 'Unknown Artist',
                    lastModifiedTime: lastModified,
                    metadataTextScanned: lastModified,
                    createdAt: now,
                    sourceFlags: resolvedFlags,
                  ))
              .copyWith(
                artworkPath:
                    artwork.artworkPath ?? existingMetadata?.artworkPath,
                thumbnailPath:
                    artwork.thumbnailPath ?? existingMetadata?.thumbnailPath,
                artworkWidth:
                    artwork.artworkWidth ?? existingMetadata?.artworkWidth,
                artworkHeight:
                    artwork.artworkHeight ?? existingMetadata?.artworkHeight,
                themeColorsBlob:
                    artwork.themeColorsBlob ??
                    existingMetadata?.themeColorsBlob,
                lastModifiedTime: lastModified,
                metadataImgScanned: lastModified,
                createdAt: existingMetadata?.createdAt ?? now,
                sourceFlags: resolvedFlags,
              );

      await MetadataDatabase().insertOrUpdateSong(updated);
      _metadataStore.updateMetadataForPath(updated, notify: notifyStore);
      return updated;
    } catch (e) {
      debugPrint('Thumbnail recovery with audio core failed for $path: $e');
      return null;
    }
  }

  int _compareNaturally(String a, String b) {
    if (identical(a, b) || a == b) return 0;
    return compareNatural(a.toLowerCase(), b.toLowerCase());
  }

  FolderSortSettings getGlobalSortSettings() {
    return FolderSortSettings(
      criteria: _globalSortCriteria,
      order: _globalSortOrder,
    );
  }

  /// 返回 [path] 当前**生效**的排序（有目录覆盖则取覆盖，否则取全局）。
  FolderSortSettings getSortSettingsForFolder(String path) {
    return _resolveSortSettingsForFolder(path);
  }

  bool hasSortOverrideForFolder(String path) {
    return _folderSortOverrides.containsKey(_sortFolderKey(path));
  }

  FolderSortSettings _resolveSortSettingsForFolder(String path) {
    final override = _folderSortOverrides[_sortFolderKey(path)];
    if (override != null) {
      return override;
    }
    return FolderSortSettings(
      criteria: _globalSortCriteria,
      order: _globalSortOrder,
    );
  }

  String _sortFolderKey(String path) {
    return _pathLookupKey(path);
  }

  /// 写入（或更新）[folderPath] 的目录级排序，返回值表示设置是否真的变了。
  bool _writeFolderSortOverride(
    String folderPath, {
    SortCriteria? criteria,
    SortOrder? order,
  }) {
    final key = _sortFolderKey(folderPath);
    final currentSettings = _folderSortOverrides[key] ??
        FolderSortSettings(
          criteria: _globalSortCriteria,
          order: _globalSortOrder,
        );
    final nextSettings = currentSettings.copyWith(
      criteria: criteria,
      order: order,
    );

    if (currentSettings.criteria == nextSettings.criteria &&
        currentSettings.order == nextSettings.order) {
      return false;
    }

    _folderSortOverrides = {..._folderSortOverrides, key: nextSettings};
    unawaited(_saveFolderSortOverrides());
    return true;
  }

  /// 根目录被移除后清掉其下所有目录的排序覆盖，避免陈旧路径日后被复用命中。
  void _pruneSortOverridesForPaths(Iterable<String> removedPaths) {
    if (_folderSortOverrides.isEmpty) return;

    final removedKeys = removedPaths
        .map(_pathLookupKey)
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (removedKeys.isEmpty) return;

    final next = <String, FolderSortSettings>{};
    var removed = 0;
    for (final entry in _folderSortOverrides.entries) {
      final key = entry.key;
      final isUnderRemoved = removedKeys.any(
        (removedKey) =>
            key == removedKey ||
            key.startsWith('$removedKey/') ||
            key.startsWith('$removedKey\\'),
      );
      if (isUnderRemoved) {
        removed++;
      } else {
        next[key] = entry.value;
      }
    }
    if (removed == 0) return;

    _folderSortOverrides = next;
    unawaited(_saveFolderSortOverrides());
  }

  Future<void> _loadSortSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storedCriteria = prefs.getString(_keyGlobalSortCriteria);
    // 只有「从未写过」才用新默认值；显式存过 filename 的老用户保持原样
    _globalSortCriteria = storedCriteria == null
        ? _defaultSortCriteria
        : SortCriteriaX.fromStorageValue(storedCriteria);
    _globalSortOrder = SortOrderX.fromStorageValue(
      prefs.getString(_keyGlobalSortOrder),
    );
    _folderSortOverrides = _decodeFolderSortOverrides(
      prefs.getString(_keyFolderSortOverrides),
    );
  }

  Map<String, FolderSortSettings> _decodeFolderSortOverrides(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return {};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return {};
      }

      final result = <String, FolderSortSettings>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map<String, dynamic>) continue;
        result[entry.key] = FolderSortSettings.fromJson(value);
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveGlobalSortSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyGlobalSortCriteria,
      _globalSortCriteria.storageValue,
    );
    await prefs.setString(_keyGlobalSortOrder, _globalSortOrder.storageValue);
  }

  Future<void> _saveFolderSortOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      for (final entry in _folderSortOverrides.entries)
        entry.key: entry.value.toJson(),
    });
    await prefs.setString(_keyFolderSortOverrides, encoded);
  }

  String _normalizePath(String path) {
    return ScannerPathUtils.normalizePath(path);
  }

  String _pathLookupKey(String path) {
    return ScannerPathUtils.pathLookupKey(path);
  }

  List<String> _normalizeDeclaredRootPaths(Iterable<String> paths) {
    return ScannerPathUtils.normalizeDeclaredRootPaths(paths);
  }

  List<String> _computeScanRoots(Iterable<String> paths) {
    return ScannerPathUtils.computeScanRoots(paths);
  }

  void _rebuildDisplayedRootFolders() {
    final displayedRoots = <MusicFolder>[];
    for (final path in _roots.rootPaths) {
      final folder =
          _treeBuilder.resolveFolderForPath(
            path,
            _scannedRootFolders,
            _systemMediaFolder,
          ) ??
          MusicFolder(path: path, name: _displayNameForPath(path));
      displayedRoots.add(folder);
    }
    _rootFolders
      ..clear()
      ..addAll(displayedRoots);
  }

  void _syncNavigationStateToLatestTree({String? affectedRootPath}) {
    final currentFolder = _navigationState.currentFolder;
    if (currentFolder != null && affectedRootPath != null) {
      final normCurrent = _normalizePath(currentFolder.path);
      final normAffected = _normalizePath(affectedRootPath);
      final isAffected =
          normCurrent == normAffected ||
          _pathContains(normAffected, normCurrent) ||
          _pathContains(normCurrent, normAffected);
      if (!isAffected) {
        return;
      }
    }

    MusicFolder? resolveFolder(MusicFolder? folder) {
      if (folder == null) return null;
      if (folder.path == 'system') {
        return _systemMediaFolder;
      }
      return _treeBuilder.resolveFolderForPath(
        folder.path,
        _scannedRootFolders,
        _systemMediaFolder,
      );
    }

    final resolvedCurrentFolder = resolveFolder(currentFolder);

    final resolvedHistory = <MusicFolder>[];
    for (final folder in _navigationState.history) {
      final resolved = resolveFolder(folder);
      if (resolved != null) {
        resolvedHistory.add(resolved);
      }
    }

    if (resolvedCurrentFolder == null && currentFolder != null) {
      final isStillValid =
          currentFolder.path == 'system' ||
          _roots.rootPaths.any(
            (root) =>
                _pathsEqual(root, currentFolder.path) ||
                _pathContains(root, currentFolder.path),
          );
      if (!isStillValid) {
        _navigationState.setState(null, const []);
      }
      return;
    }

    final currentChanged =
        !identical(resolvedCurrentFolder, currentFolder) &&
        resolvedCurrentFolder != null;
    final historyChanged = !const ListEquality<MusicFolder>().equals(
      resolvedHistory,
      _navigationState.history,
    );

    if (currentChanged || historyChanged) {
      _navigationState.setState(resolvedCurrentFolder, resolvedHistory);
    }
  }

  bool _pathsEqual(String left, String right) {
    return ScannerPathUtils.pathsEqual(left, right);
  }

  /// Find the next folder containing music after [currentFolderPath].
  MusicFolder? findNextFolderWithMusic(String currentFolderPath) {
    final list = <MusicFolder>[];
    void traverse(MusicFolder folder) {
      if (folder.files.isNotEmpty) {
        list.add(folder);
      }
      for (final sub in folder.subFolders) {
        traverse(sub);
      }
    }

    if (_systemMediaFolder != null) {
      traverse(_systemMediaFolder!);
    }
    for (final root in _scannedRootFolders) {
      traverse(root);
    }

    if (list.isEmpty) return null;

    final index = list.indexWhere(
      (f) => _pathsEqual(f.path, currentFolderPath),
    );
    if (index == -1) {
      return list.first;
    }

    final nextIndex = (index + 1) % list.length;
    return list[nextIndex];
  }

  /// Find the previous folder containing music before [currentFolderPath].
  MusicFolder? findPreviousFolderWithMusic(String currentFolderPath) {
    final list = <MusicFolder>[];
    void traverse(MusicFolder folder) {
      if (folder.files.isNotEmpty) {
        list.add(folder);
      }
      for (final sub in folder.subFolders) {
        traverse(sub);
      }
    }

    if (_systemMediaFolder != null) {
      traverse(_systemMediaFolder!);
    }
    for (final root in _scannedRootFolders) {
      traverse(root);
    }

    if (list.isEmpty) return null;

    final index = list.indexWhere(
      (f) => _pathsEqual(f.path, currentFolderPath),
    );
    if (index == -1) {
      return list.last;
    }

    final prevIndex = (index - 1 + list.length) % list.length;
    return list[prevIndex];
  }

  bool _pathContains(String parent, String child) {
    return ScannerPathUtils.pathContains(parent, child);
  }

  bool _isImmediateChildOfDirectory(String parent, String child) {
    final normalizedParent = _normalizePath(parent);
    final normalizedChild = _normalizePath(child);
    if (normalizedParent.isEmpty || normalizedChild.isEmpty) {
      return false;
    }
    return _pathsEqual(p.dirname(normalizedChild), normalizedParent);
  }

  String _displayNameForPath(String path) {
    return ScannerPathUtils.displayNameForPath(path);
  }

  void _logScanTiming(String label, Stopwatch stopwatch) {
    if (!_scanTimingEnabled) return;
    debugPrint(
      '[ScannerService][scan] $label took ${stopwatch.elapsedMilliseconds} ms',
    );
  }

  Future<T> _timeInitStep<T>(String label, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      _logInitTiming(label, stopwatch);
    }
  }

  T _timeInitStepSync<T>(String label, T Function() action) {
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      _logInitTiming(label, stopwatch);
    }
  }

  Future<T> _timeScanStep<T>(String label, Future<T> Function() action) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      _logScanTiming(label, stopwatch);
    }
  }

  T _timeScanStepSync<T>(String label, T Function() action) {
    final stopwatch = Stopwatch()..start();
    try {
      return action();
    } finally {
      stopwatch.stop();
      _logScanTiming(label, stopwatch);
    }
  }

  void _scheduleMetadataNotify() {
    if (_metadataNotifyTimer?.isActive ?? false) {
      return;
    }

    _metadataNotifyTimer = Timer(const Duration(milliseconds: 150), () {
      _metadataNotifyTimer = null;
      if (!isScanning) {
        notifyListeners();
      }
    });
  }

  void _startRootAvailabilityTimer() {
    if (_isDisposed) return;
    _rootAvailabilityTimer?.cancel();
    _rootAvailabilityTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _pendingRootAvailabilityRescan = true;
      _scheduleRootAvailabilityRefresh();
    });
  }

  void _stopRootAvailabilityTimer() {
    _rootAvailabilityTimer?.cancel();
    _rootAvailabilityTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _stopRootAvailabilityTimer();
    } else if (state == AppLifecycleState.resumed) {
      _startRootAvailabilityTimer();
      debugPrint(
        '[ScannerService] App resumed, triggering root availability check',
      );
      _pendingRootAvailabilityRescan = true;
      _scheduleRootAvailabilityRefresh();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pendingAndroidMediaEntries = null;
    WidgetsBinding.instance.removeObserver(this);
    _stopRootAvailabilityTimer();
    _navigationState.removeListener(_handleNavigationChanged);
    _navigationState.dispose();
    _roots.dispose();
    _mediaObserverSubscription?.cancel();
    _mobileStorageSubscription?.cancel();
    _metadataNotifyTimer?.cancel();
    _directoryRescanTimer?.cancel();
    _directoryRescanTimer = null;
    _pendingDirectoryRescanPaths.clear();
    _folderCoverRefreshTimer?.cancel();
    _folderCoverRefreshTimer = null;
    _pendingFolderCoverRefreshPaths.clear();
    for (final timer in _pendingFolderIndexTimers.values) {
      timer.cancel();
    }
    _pendingFolderIndexTimers.clear();
    _pendingFolderIndexRoots.clear();
    _scanNotifyTimer?.cancel();
    _rootAvailabilityRefreshTimer?.cancel();
    _scanProgressController.close();
    _scanCoordinator.removeListener(_handleScanStateChanged);
    _scanCoordinator.dispose();
    if (_supportsPersistentAccess && _playerController != null) {
      for (final path in _activeScopedRootPaths.toList(growable: false)) {
        unawaited(_playerController!.endScopedAccess(path: path));
      }
      _activeScopedRootPaths.clear();
    }
    super.dispose();
  }
}

enum RootPathAddStatus {
  added,
  alreadyAdded,
  noMusic,
  persistentAccessDenied,
  failed,
}

class RootPathAddResult {
  const RootPathAddResult(this.status, {this.path});

  final RootPathAddStatus status;
  final String? path;

  bool get hasMusic =>
      status == RootPathAddStatus.added ||
      status == RootPathAddStatus.alreadyAdded;

  bool get accessDenied => status == RootPathAddStatus.persistentAccessDenied;
}

