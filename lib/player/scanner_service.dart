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
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:collection/collection.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'music_file_utils.dart';
import 'scanner_navigation_state.dart';
import 'scanner_path_utils.dart';
import 'scanner_sorting.dart';
import 'scanner_scan_pipeline.dart';
import 'scanner_directory_scanner.dart';
import 'scanner_metadata_store.dart';
import 'scanner_tree_builder.dart';
import 'scanner_service_roots.dart';
import 'scanner_scan_support.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

export 'scanner_scan_support.dart';

class ScannerService extends ChangeNotifier {
  final ScannerFolderSorter _folderSorter = const ScannerFolderSorter();
  AudioCoreController? _playerController;
  void Function(String path, bool isMissing)? _songMissingStateHandler;
  StreamSubscription? _mediaObserverSubscription;
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();
  final ScannerNavigationState _navigationState = ScannerNavigationState();
  final List<MusicFolder> _scannedRootFolders = [];
  final List<MusicFolder> _rootFolders = [];
  bool _isScanning = false;
  bool _isBackgroundTaskPaused = false;
  Timer? _metadataNotifyTimer;
  Timer? _scanNotifyTimer;
  bool _scanNotifyPending = false;
  bool _lastNotifiedScanningState = false;
  bool _isDisposed = false;
  Future<void> _incrementalEventQueue = Future<void>.value();
  final List<FileSystemEvent> _pendingIncrementalEvents = [];

  MusicFolder? _systemMediaFolder;
  bool _hasPermission = false;
  late final ScannerServiceRoots _roots;
  late final ScannerMetadataStore _metadataStore;
  late final ScannerScanPipeline _scanPipeline;
  late final ScannerTreeBuilder _treeBuilder;
  late final ScannerDirectoryScanner _directoryScanner;

  static const String _keyGlobalSortCriteria = 'folder_sort_global_criteria';
  static const String _keyGlobalSortOrder = 'folder_sort_global_order';
  static const String _keyFolderSortOverrides = 'folder_sort_overrides';
  static const bool _scanTimingEnabled = kDebugMode;

  SortCriteria _globalSortCriteria = SortCriteria.filename;
  SortOrder _globalSortOrder = SortOrder.ascending;
  Map<String, FolderSortSettings> _folderSortOverrides = {};

  SortCriteria get sortCriteria => _currentSortSettings.criteria;
  SortOrder get sortOrder => _currentSortSettings.order;
  SortCriteria get globalSortCriteria => _globalSortCriteria;
  SortOrder get globalSortOrder => _globalSortOrder;

  List<String> get rootPaths => _roots.rootPaths;
  List<MusicFolder> get rootFolders => List.unmodifiable(_rootFolders);
  bool get isScanning => _isScanning;
  bool get isBackgroundTaskPaused => _isBackgroundTaskPaused;
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  // Navigation state for FoldersPage
  MusicFolder? get navigationCurrentFolder => _navigationState.currentFolder;

  List<MusicFolder> get navigationHistory => _navigationState.history;

  void setNavigationState(MusicFolder? current, List<MusicFolder> history) {
    _navigationState.setState(current, history);
  }

  void pushNavigationHistory(MusicFolder folder) {
    _navigationState.pushHistory(folder);
  }

  MusicFolder? popNavigationHistory() {
    return _navigationState.popHistory();
  }

  MusicFolder? get systemMediaFolder => _systemMediaFolder;
  bool get hasPermission => _hasPermission;
  Map<String, SongMetadata> get metadataMap => _metadataStore.metadataMap;

  ScannerService() {
    _roots = ScannerServiceRoots(
      isDisposed: () => _isDisposed,
      onFileEvent: _enqueueIncrementalFileEvent,
      notifySongMissingState: _notifySongMissingState,
    );
    _metadataStore = ScannerMetadataStore(
      rootFolders: () => _scannedRootFolders,
      systemMediaFolder: () => _systemMediaFolder,
      notifyListeners: notifyListeners,
      scheduleMetadataNotify: _scheduleMetadataNotify,
      notifySongMissingState: _notifySongMissingState,
      normalizePath: _normalizePath,
      pathsEqual: _pathsEqual,
    );
    _scanPipeline = ScannerScanPipeline(
      normalizePath: _normalizePath,
      pathLookupKey: _pathLookupKey,
      metadataStore: _metadataStore,
    );
    _treeBuilder = ScannerTreeBuilder(
      normalizePath: _normalizePath,
      pathsEqual: _pathsEqual,
    );
    _directoryScanner = ScannerDirectoryScanner(
      displayNameForPath: _displayNameForPath,
      pathsEqual: _pathsEqual,
      compareNaturally: _compareNaturally,
      emitScanProgress: _emitScanProgress,
    );
    _navigationState.addListener(_handleNavigationChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_init());
    });
    _setupMediaObserver();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;

    if (_isScanning != _lastNotifiedScanningState) {
      _lastNotifiedScanningState = _isScanning;
      _scanNotifyTimer?.cancel();
      _scanNotifyTimer = null;
      _scanNotifyPending = false;
      super.notifyListeners();
      return;
    }

    if (!_isScanning) {
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
    if (changed && controller != null && Platform.isAndroid) {
      unawaited(checkAndRequestPermissions());
    }
  }

  void setSongMissingStateHandler(
    void Function(String path, bool isMissing)? handler,
  ) {
    _songMissingStateHandler = handler;
  }

  void _notifySongMissingState(String path, bool isMissing) {
    final handler = _songMissingStateHandler;
    if (handler == null) return;
    final normalized = _normalizePath(path);
    if (normalized.isEmpty) return;
    handler(normalized, isMissing);
  }

  void setSortCriteria(
    SortCriteria criteria, {
    SortScope scope = SortScope.global,
    String? folderPath,
  }) {
    if (scope == SortScope.currentFolder &&
        _updateFolderSortSettings(folderPath: folderPath, criteria: criteria)) {
      _sortAndNotify();
      return;
    }

    if (_globalSortCriteria == criteria) {
      return;
    }

    _globalSortCriteria = criteria;
    unawaited(_saveGlobalSortSettings());
    _sortAndNotify();
  }

  void setSortOrder(
    SortOrder order, {
    SortScope scope = SortScope.global,
    String? folderPath,
  }) {
    if (scope == SortScope.currentFolder &&
        _updateFolderSortSettings(folderPath: folderPath, order: order)) {
      _sortAndNotify();
      return;
    }

    if (_globalSortOrder == order) {
      return;
    }

    _globalSortOrder = order;
    unawaited(_saveGlobalSortSettings());
    _sortAndNotify();
  }

  void _sortAndNotify() {
    _folderSorter.sortFoldersForTree(
      _scannedRootFolders,
      resolveSettings: _resolveSortSettingsForFolder,
    );
    if (_systemMediaFolder != null) {
      _folderSorter.sortFolderRecursiveForTree(
        _systemMediaFolder!,
        resolveSettings: _resolveSortSettingsForFolder,
      );
    }
    _rebuildDisplayedRootFolders();
    _syncNavigationStateToLatestTree();
    notifyListeners();
  }

  Future<void> _init() async {
    await _roots.loadRootPaths();
    await _loadSortSettings();
    await _loadCachedRootFoldersFromDatabase();
    _rebuildDisplayedRootFolders();
    notifyListeners();
    await checkAndRequestPermissions();
    // Auto scan on startup
    await scan();
  }

  void _setupMediaObserver() {
    if (Platform.isAndroid) {
      const mediaObserverChannel = EventChannel(
        'com.example.pure_player/media_observer',
      );
      _mediaObserverSubscription = mediaObserverChannel
          .receiveBroadcastStream()
          .listen(
            (event) {
              if (event == 'media_changed' && !_isScanning) {
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

  Future<void> checkAndRequestPermissions() async {
    debugPrint(
      '[ScannerService] checkAndRequestPermissions start '
      'hasPermission=$_hasPermission '
      'playerController=${_playerController != null}',
    );
    _hasPermission = await _checkPermissions();
    debugPrint(
      '[ScannerService] checkAndRequestPermissions result '
      'hasPermission=$_hasPermission',
    );
    notifyListeners();
    if (_hasPermission) {
      // 系统媒体库扫描可能比本地目录扫描慢很多，启动时不要把
      // 根目录初始化卡在这里。
      unawaited(scanSystemMedia());
    }
  }

  Future<bool> addRootPath(String path) async {
    final normalizedPath = _normalizePath(path);
    final existingRoot = _roots.rootPaths.firstWhereOrNull(
      (existing) => _pathsEqual(existing, normalizedPath),
    );
    if (existingRoot != null) {
      final existingFolder = _rootFolders.firstWhereOrNull(
        (folder) => _pathsEqual(folder.path, existingRoot),
      );
      return existingFolder != null && !existingFolder.isEmpty;
    }

    final updatedRoots = [..._roots.rootPaths, normalizedPath];
    await _roots.setRootPaths(updatedRoots);
    await _loadCachedRootFoldersFromDatabase(rootPaths: [normalizedPath]);
    _rebuildDisplayedRootFolders();
    notifyListeners();

    if (Platform.isAndroid) {
      try {
        await MediaScanner.loadMedia(path: normalizedPath);
      } catch (e) {
        debugPrint('MediaScanner error: $e');
      }
    }

    await scan();

    final addedFolder = _rootFolders.firstWhereOrNull(
      (folder) => _pathsEqual(folder.path, normalizedPath),
    );
    return addedFolder != null && !addedFolder.isEmpty;
  }

  Future<void> removeRootPath(String path) async {
    await removeRootPaths([path]);
  }

  Future<void> removeRootPaths(Iterable<String> paths) async {
    final normalizedTargets = _normalizeDeclaredRootPaths(paths);
    if (normalizedTargets.isEmpty) return;

    final updatedRoots = [..._roots.rootPaths];
    updatedRoots.removeWhere(
      (existing) =>
          normalizedTargets.any((target) => _pathsEqual(existing, target)),
    );
    await _roots.setRootPaths(updatedRoots);
    _rebuildDisplayedRootFolders();
    notifyListeners();
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
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
      final controller = _playerController;
      if (controller != null) {
        debugPrint(
          '[ScannerService] _checkPermissions via AudioCoreController',
        );
        final granted = await controller.ensureAndroidMediaLibraryPermission();
        debugPrint(
          '[ScannerService] AudioCoreController permission result=$granted',
        );
        return granted;
      }

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      debugPrint(
        '[ScannerService] _checkPermissions fallback '
        'sdkInt=${androidInfo.version.sdkInt}',
      );

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
        return status.isGranted;
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
        return status.isGranted;
      }
    }
    return true; // Assume granted on other platforms for now
  }

  Future<void> scanSystemMedia() async {
    debugPrint(
      '[ScannerService] scanSystemMedia start '
      'platform=${Platform.operatingSystem} '
      'hasPermission=$_hasPermission '
      'playerController=${_playerController != null}',
    );
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
          _systemMediaFolder = null;
          notifyListeners();
          return;
        }

        final metadataByPath = await _buildScannedMetadataMap(
          scanResult.entries,
          filePathOf: _androidEntryFilePath,
          songIdOf: (entry) => int.tryParse(entry.id),
          fallbackTitleOf: (entry) => entry.label,
          fallbackAlbumOf: (entry) => entry.album ?? '',
          fallbackArtistOf: (entry) => entry.artist ?? '',
          fallbackDurationOf: (entry) => entry.duration.inMilliseconds,
          fallbackTrackNumberOf: (_) => null,
        );

        _systemMediaFolder = _treeBuilder.buildAndroidMediaLibrary(
          scanResult.entries,
          metadataByPath,
          _compareNaturally,
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
        notifyListeners();

        unawaited(_processAndSaveAndroidSongsBackground(scanResult.entries));
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
        debugPrint(
          '[ScannerService] iOS media scan result count=${songs.length}',
        );

        final metadataByPath = await _buildScannedMetadataMap(
          songs,
          filePathOf: (song) => song.data,
          songIdOf: (song) => song.id,
          fallbackTitleOf: (song) => song.title,
          fallbackAlbumOf: (song) => song.album ?? '',
          fallbackArtistOf: (song) => song.artist ?? '',
          fallbackDurationOf: (song) => song.duration,
          fallbackTrackNumberOf: (song) => song.track,
        );

        _systemMediaFolder = _treeBuilder.buildSongsIntoFolders(
          songs,
          metadataByPath,
          _compareNaturally,
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
        notifyListeners();

        unawaited(_processAndSaveIosSongsBackground(songs));
      }
    } catch (e) {
      debugPrint('[ScannerService] Error scanning system media: $e');
    }
  }

  Future<void> _loadCachedRootFoldersFromDatabase({
    Iterable<String>? rootPaths,
  }) async {
    try {
      final declaredRoots = (rootPaths ?? _roots.rootPaths)
          .map(_normalizePath)
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (declaredRoots.isEmpty) return;
      declaredRoots.sort((a, b) {
        final lengthCompare = b.length.compareTo(a.length);
        if (lengthCompare != 0) return lengthCompare;
        return _compareNaturally(a, b);
      });

      final cachedSongs = await MetadataDatabase().getAllSongMetadata();
      final cachedSongGroups = <String, List<SongMetadata>>{
        for (final root in declaredRoots) root: <SongMetadata>[],
      };

      for (final song in cachedSongs) {
        final normalizedPath = _normalizePath(song.path);
        if (normalizedPath.isEmpty) continue;

        for (final root in declaredRoots) {
          if (_pathContains(root, normalizedPath)) {
            cachedSongGroups[root]!.add(song);
            break;
          }
        }
      }

      var loadedCount = 0;
      for (final root in declaredRoots) {
        final songs = cachedSongGroups[root]!;
        if (songs.isEmpty) continue;

        final cachedFolder = _treeBuilder.buildFolderTreeFromMetadata(
          songs,
          _compareNaturally,
          rootPath: root,
          rootName: _displayNameForPath(root),
        );
        _upsertScannedRootFolder(cachedFolder);
        for (final song in songs) {
          _metadataStore.cacheMetadata(song);
        }
        loadedCount += songs.length;
      }

      if (loadedCount > 0) {
        debugPrint(
          '[ScannerService] Loaded cached root folders from songs table '
          'entries=$loadedCount roots=${declaredRoots.length}',
        );
      }
    } catch (e) {
      debugPrint('[ScannerService] Failed to load cached root folders: $e');
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
  }

  String? _androidEntryFilePath(AndroidMediaLibraryEntry entry) {
    final path = entry.filePath?.trim();
    if (path != null && path.isNotEmpty) return _normalizePath(path);
    final uri = entry.uri.trim();
    if (uri.isNotEmpty) return uri;
    return null;
  }

  void _handleNavigationChanged() {
    notifyListeners();
  }

  void pauseBackgroundTasks() {
    if (!_isBackgroundTaskPaused) {
      _isBackgroundTaskPaused = true;
      debugPrint('ScannerService: Background tasks paused.');
      notifyListeners();
    }
  }

  void resumeBackgroundTasks() {
    if (_isBackgroundTaskPaused) {
      _isBackgroundTaskPaused = false;
      debugPrint('ScannerService: Background tasks resumed.');
      notifyListeners();
    }
  }

  Future<void> _waitUntilResumed() async {
    while (_isBackgroundTaskPaused) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<void> _processAndSaveAndroidSongsBackground(
    List<AndroidMediaLibraryEntry> entries,
  ) async {
    await _processEntriesBackground(
      entries,
      filePathOf: _androidEntryFilePath,
      songIdOf: (entry) => int.tryParse(entry.id),
    );
  }

  Future<void> _processAndSaveIosSongsBackground(List<SongModel> songs) async {
    await _processEntriesBackground(
      songs,
      filePathOf: (song) => song.data,
      songIdOf: (song) => song.id,
    );
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
      final filePath = result['path'] as String? ?? '';
      if (filePath.isEmpty) continue;

      final entry = entryByPath[filePath];
      if (entry == null) continue;

      final existing = await db.getSongMetadata(filePath);
      final metadata = _buildScannedMetadataFromBatchResult(
        filePath,
        result,
        existing: existing,
        fallbackTitle: fallbackTitleOf(entry),
        fallbackAlbum: fallbackAlbumOf(entry),
        fallbackArtist: fallbackArtistOf(entry),
        fallbackDuration: fallbackDurationOf(entry),
        fallbackTrackNumber: fallbackTrackNumberOf(entry),
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
            await MetadataHelper.processMetadata(
              path,
              songId: songIdOf(currentEntry),
              generateThumbnail: false,
            );
          } catch (e) {
            debugPrint('Background processing error for $path: $e');
          }
        }),
      );
    }

    await Future.wait(scanState.pendingMetadataTasks);
  }

  void _enqueueIncrementalFileEvent(FileSystemEvent event) {
    if (_isDisposed) return;

    if (_isScanning) {
      _pendingIncrementalEvents.add(event);
      return;
    }

    _incrementalEventQueue = _incrementalEventQueue.then((_) async {
      await _processIncrementalFileEvent(event);
    }).catchError((e, st) {
      debugPrint('[ScannerService] Incremental file event error: $e');
    });
  }

  Future<void> _drainPendingIncrementalFileEvents() async {
    if (_pendingIncrementalEvents.isEmpty) return;

    final pendingEvents = List<FileSystemEvent>.from(_pendingIncrementalEvents);
    _pendingIncrementalEvents.clear();

    _incrementalEventQueue = _incrementalEventQueue.then((_) async {
      for (final event in pendingEvents) {
        await _processIncrementalFileEvent(event, notify: false);
      }
    }).catchError((e, st) {
      debugPrint('[ScannerService] Pending incremental event error: $e');
    });

    await _incrementalEventQueue;
  }

  Future<void> _processIncrementalFileEvent(
    FileSystemEvent event, {
    bool notify = true,
  }) async {
    if (_isDisposed) return;

    final normalizedPath = _normalizePath(event.path);
    if (normalizedPath.isEmpty) return;
    if (event.isDirectory) {
      if ((event.type & FileSystemEvent.delete) != 0 ||
          (event.type & FileSystemEvent.move) != 0) {
        await _removeIncrementalDirectory(normalizedPath, notify: notify);
      }
      return;
    }
    if (!MusicFileUtils.isMusicFilePath(normalizedPath)) return;
    if (!_roots.rootPaths.any((root) => _pathContains(root, normalizedPath))) {
      return;
    }

    final exists = await File(normalizedPath).exists();
    if (!exists) {
      await _removeIncrementalSong(normalizedPath, notify: notify);
      return;
    }

    final processed = await MetadataHelper.processMetadata(
      normalizedPath,
      generateThumbnail: true,
    );
    if (processed == null) return;

    final metadata = processed.$1;
    final artworkBytes = processed.$2;

    _metadataStore.updateMetadataForPath(
      metadata,
      artworkBytes: artworkBytes,
      notify: false,
    );
    _insertOrUpdateSongInLibrary(
      metadata,
      artworkBytes: artworkBytes,
      sort: notify,
    );
    if (notify) {
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      _scheduleMetadataNotify();
    }
  }

  Future<void> _removeIncrementalDirectory(
    String directoryPath, {
    required bool notify,
  }) async {
    final normalizedDirectory = _normalizePath(directoryPath);
    if (normalizedDirectory.isEmpty) return;

    final pathsToRemove = _metadataStore.metadataMap.keys
        .where((path) => _pathContains(normalizedDirectory, path))
        .toList(growable: false);
    if (pathsToRemove.isEmpty) {
      return;
    }

    for (final path in pathsToRemove) {
      _metadataStore.removeMetadataForPath(path);
      final matchedRoot = _findScanRootForPath(path);
      if (matchedRoot != null) {
        final rootFolder = _findScannedRootFolder(matchedRoot);
        if (rootFolder != null) {
          _treeBuilder.removeSongFromFolder(rootFolder, path);
          if (rootFolder.isEmpty) {
            _scannedRootFolders.removeWhere(
              (existing) => _pathsEqual(existing.path, rootFolder.path),
            );
          }
        }
      }

      if (_systemMediaFolder != null) {
        _treeBuilder.removeSongFromFolder(_systemMediaFolder!, path);
        if (_systemMediaFolder!.isEmpty) {
          _systemMediaFolder = null;
        }
      }

      await MetadataDatabase().deleteSongByPath(path);
      _notifySongMissingState(path, true);
    }

    if (notify) {
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      _scheduleMetadataNotify();
    }
  }

  void _insertOrUpdateSongInLibrary(
    SongMetadata metadata, {
    Uint8List? artworkBytes,
    bool sort = true,
  }) {
    final rootPath = _findScanRootForPath(metadata.path);
    if (rootPath == null) return;

    final rootFolder = _findScannedRootFolder(rootPath) ??
        MusicFolder(path: rootPath, name: _displayNameForPath(rootPath));
    _upsertScannedRootFolder(rootFolder);

    final targetFolder = _ensureFolderChain(
      rootFolder,
      metadata.path,
    );
    final musicFile = MusicFile(
      path: metadata.path,
      name: p.basename(metadata.path),
      title: metadata.title,
      artist: metadata.artist,
      album: metadata.album,
      trackNumber: metadata.trackNumber,
      durationMillis: metadata.duration,
      thumbnailPath: metadata.thumbnailPath,
      artworkPath: metadata.artworkPath,
      artworkWidth: metadata.artworkWidth,
      artworkHeight: metadata.artworkHeight,
      themeColorsBlob: metadata.themeColorsBlob,
      artworkBytes: artworkBytes,
      lastModifiedTime: metadata.lastModifiedTime,
    );
    _upsertMusicFile(targetFolder, musicFile);
    if (sort) {
      _folderSorter.sortFolderRecursiveForTree(
        rootFolder,
        resolveSettings: _resolveSortSettingsForFolder,
      );
    }
  }

  Future<void> _removeIncrementalSong(
    String path, {
    required bool notify,
  }) async {
    _metadataStore.removeMetadataForPath(path);

    final matchedRoot = _findScanRootForPath(path);
    if (matchedRoot != null) {
      final rootFolder = _findScannedRootFolder(matchedRoot);
      if (rootFolder != null) {
        _treeBuilder.removeSongFromFolder(rootFolder, path);
        if (rootFolder.isEmpty) {
          _scannedRootFolders.removeWhere(
            (existing) => _pathsEqual(existing.path, rootFolder.path),
          );
        }
      }
    }

    if (_systemMediaFolder != null) {
      _treeBuilder.removeSongFromFolder(_systemMediaFolder!, path);
      if (_systemMediaFolder!.isEmpty) {
        _systemMediaFolder = null;
      }
    }

    await MetadataDatabase().deleteSongByPath(path);
    _notifySongMissingState(path, true);
    if (notify) {
      _rebuildDisplayedRootFolders();
      _syncNavigationStateToLatestTree();
      _scheduleMetadataNotify();
    }
  }

  String? _findScanRootForPath(String path) {
    String? bestMatch;
    for (final root in _computeScanRoots(_roots.rootPaths)) {
      if (!_pathContains(root, path)) continue;
      if (bestMatch == null || root.length > bestMatch.length) {
        bestMatch = root;
      }
    }
    return bestMatch;
  }

  MusicFolder? _findScannedRootFolder(String rootPath) {
    for (final root in _scannedRootFolders) {
      if (_pathsEqual(root.path, rootPath)) {
        return root;
      }
    }
    return null;
  }

  MusicFolder _ensureFolderChain(MusicFolder root, String filePath) {
    final normalizedRoot = _normalizePath(root.path);
    final normalizedFile = _normalizePath(filePath);
    final relative = p.relative(normalizedFile, from: normalizedRoot);
    final parts = p.split(relative);
    if (parts.isEmpty || (parts.length == 1 && parts.first == p.basename(normalizedFile))) {
      return root;
    }

    var currentFolder = root;
    var currentPath = normalizedRoot;
    for (var i = 0; i < parts.length - 1; i++) {
      final segment = parts[i];
      if (segment.trim().isEmpty || segment == '.') continue;
      currentPath = p.join(currentPath, segment);
      final existing = currentFolder.subFolders.firstWhereOrNull(
        (folder) => _pathsEqual(folder.path, currentPath),
      );
      if (existing != null) {
        currentFolder = existing;
        continue;
      }

      final created = MusicFolder(
        path: currentPath,
        name: _displayNameForPath(currentPath),
      );
      currentFolder.subFolders.add(created);
      currentFolder = created;
    }

    return currentFolder;
  }

  void _upsertMusicFile(MusicFolder folder, MusicFile file) {
    final index = folder.files.indexWhere(
      (existing) => _pathsEqual(existing.path, file.path),
    );
    if (index >= 0) {
      folder.files[index] = file;
    } else {
      folder.files.add(file);
    }
  }

  Future<ScanFileClassification> _classifyDiscoveredFiles(
    List<String> filePaths,
  ) async {
    return _scanPipeline.classifyDiscoveredFiles(filePaths);
  }

  void _seedMetadataFromDatabase(
    Map<String, SongMetadata> existingMetadataByPath,
  ) {
    _scanPipeline.seedMetadataFromDatabase(existingMetadataByPath);
  }

  Future<void> _preprocessChangedFiles(
    List<String> fullPaths,
    ScanProgressState scanState, {
    required Map<String, SongMetadata> existingMetadataByPath,
  }) async {
    if (fullPaths.isEmpty) return;

    final db = MetadataDatabase();
    final sortedPaths = fullPaths.toList()..sort(_compareNaturally);
    final totalStopwatch = Stopwatch()..start();

    const batchSize = 200;
    for (var start = 0; start < sortedPaths.length; start += batchSize) {
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
      readStopwatch.stop();
      _logScanTiming(
        'stage 3 batch ${start + 1}-$end readMetadataBatch',
        readStopwatch,
      );

      final writeStopwatch = Stopwatch()..start();
      for (final result in results) {
        final filePath = result['path'] as String? ?? '';
        if (filePath.isEmpty) continue;

        try {
          final existing =
              existingMetadataByPath[_pathLookupKey(filePath)] ??
              await db.getSongMetadata(filePath);
          final metadata = _buildScannedMetadataFromBatchResult(
            filePath,
            result,
            existing: existing,
          );
          await db.insertOrUpdateSong(metadata);
          _metadataStore.updateMetadataForPath(metadata, notify: false);
          scanState.preprocessedCount++;
        } catch (e) {
          debugPrint('Metadata batch scan error for $filePath: $e');
        } finally {
          _emitScanProgress(scanState, filePath);
        }
      }
      writeStopwatch.stop();
      _logScanTiming(
        'stage 3 batch ${start + 1}-$end db+store update',
        writeStopwatch,
      );
      batchStopwatch.stop();
      _logScanTiming(
        'stage 3 batch ${start + 1}-$end total',
        batchStopwatch,
      );
    }

    totalStopwatch.stop();
    _logScanTiming('stage 3 preprocess text tags total', totalStopwatch);
  }

  Future<void> _applyArtworkAndThemeToChangedFiles(
    List<String> imageOnlyPaths,
    ScanProgressState scanState,
  ) async {
    if (imageOnlyPaths.isEmpty) return;

    final sortedPaths = imageOnlyPaths.toList()..sort(_compareNaturally);
    final totalStopwatch = Stopwatch()..start();

    try {
      final supportDir = await getApplicationSupportDirectory();
      const batchSize = 6;
      for (var start = 0; start < sortedPaths.length; start += batchSize) {
        final end = start + batchSize < sortedPaths.length
            ? start + batchSize
            : sortedPaths.length;
        final batch = sortedPaths.sublist(start, end);
        final batchStopwatch = Stopwatch()..start();

        await Future.wait(
          batch.map(
            (filePath) => _processArtworkAndThemeWithWorker(
              filePath: filePath,
              supportDirPath: supportDir.path,
              scanState: scanState,
            ),
          ),
        );
        batchStopwatch.stop();
        _logScanTiming(
          'stage 4 batch ${start + 1}-$end total',
          batchStopwatch,
        );
      }
    } catch (e) {
      debugPrint('Worker artwork scan failed, falling back to serial mode: $e');
      final db = MetadataDatabase();
      final fallbackStopwatch = Stopwatch()..start();
      for (final filePath in sortedPaths) {
        try {
          final baseMetadata =
              _metadataStore.getMetadata(filePath) ??
              await db.getSongMetadata(filePath);
          if (baseMetadata == null) {
            continue;
          }

          final artworkBytes = await MetadataHelper.decodeEmbeddedArtwork(
            filePath,
          );
          final updatedMetadata =
              await MetadataHelper.applyArtworkAndThemeToMetadata(
                metadata: baseMetadata,
                artworkBytes: artworkBytes,
                saveLarge: !Platform.isWindows,
              );

          if (updatedMetadata != null) {
            _metadataStore.updateMetadataForPath(
              updatedMetadata,
              notify: false,
            );
          }
          scanState.completedCount++;
        } catch (inner) {
          debugPrint('Artwork/theme scan error for $filePath: $inner');
        } finally {
          _emitScanProgress(scanState, filePath);
        }
      }
      fallbackStopwatch.stop();
      _logScanTiming('stage 4 fallback serial total', fallbackStopwatch);
    }

    totalStopwatch.stop();
    _logScanTiming('stage 4 preprocess artwork/theme total', totalStopwatch);
  }

  Future<void> _processArtworkAndThemeWithWorker({
    required String filePath,
    required String supportDirPath,
    required ScanProgressState scanState,
  }) async {
    final db = MetadataDatabase();
    final totalStopwatch = Stopwatch()..start();

    try {
      final baseMetadata =
          _metadataStore.getMetadata(filePath) ??
          await db.getSongMetadata(filePath);
      if (baseMetadata == null) {
        return;
      }

      final workerStopwatch = Stopwatch()..start();
      final result = await workerManager.execute<Map<String, dynamic>?>(
        () => processArtworkThumbnailWorkerTask({
          'filePath': filePath,
          'supportDirPath': supportDirPath,
          'saveLarge': !Platform.isWindows,
          'baseMetadata': baseMetadata.toMap(),
        }),
        priority: WorkPriority.immediately,
      );
      workerStopwatch.stop();
      _logScanTiming('stage 4 worker $filePath', workerStopwatch);

      if (result == null) {
        return;
      }

      final metadataMap = result['metadata'] as Map<String, dynamic>?;
      if (metadataMap == null) {
        return;
      }

      var updatedMetadata = SongMetadata.fromMap(metadataMap);

      await db.insertOrUpdateSong(updatedMetadata);
      _metadataStore.updateMetadataForPath(updatedMetadata, notify: false);
      scanState.completedCount++;
    } catch (e) {
      debugPrint('Worker artwork/theme scan error for $filePath: $e');
    } finally {
      totalStopwatch.stop();
      _logScanTiming('stage 4 item $filePath total', totalStopwatch);
      _emitScanProgress(scanState, filePath);
    }
  }

  SongMetadata _buildScannedMetadataFromBatchResult(
    String filePath,
    Map<String, dynamic> result, {
    SongMetadata? existing,
    String? fallbackTitle,
    String? fallbackAlbum,
    String? fallbackArtist,
    int? fallbackDuration,
    int? fallbackTrackNumber,
  }) {
    return _scanPipeline.buildScannedMetadataFromBatchResult(
      filePath,
      result,
      existing: existing,
      fallbackTitle: fallbackTitle,
      fallbackAlbum: fallbackAlbum,
      fallbackArtist: fallbackArtist,
      fallbackDuration: fallbackDuration,
      fallbackTrackNumber: fallbackTrackNumber,
    );
  }

  Future<void> scan() async {
    if (_roots.rootPaths.isEmpty) return;
    if (_isScanning) {
      return;
    }

    _isScanning = true;
    notifyListeners();

    final totalStopwatch = Stopwatch()..start();
    try {
      final permissionsStopwatch = Stopwatch()..start();
      final hasPermission = await _checkPermissions();
      permissionsStopwatch.stop();
      _logScanTiming('stage 0 permissions', permissionsStopwatch);

      if (hasPermission) {
        final scanState = ScanProgressState(
          metadataConcurrency: 4,
          comparePaths: _compareNaturally,
        );
        final scanRoots = _timeScanStepSync('stage 1 root discovery', () {
          final roots = _computeScanRoots(_roots.rootPaths);
          roots.sort(_compareNaturally);
          return roots;
        });

        for (final path in scanRoots) {
          debugPrint('Starting scan at: $path');

          final rootFolder = MusicFolder(
            path: path,
            name: _displayNameForPath(path),
          );

          if (Platform.isAndroid) {
            await _timeScanStep(
              'stage 1.1 MediaScanner.loadMedia for $path',
              () async {
                try {
                  await MediaScanner.loadMedia(path: path);
                } catch (e) {
                  debugPrint('MediaScanner startup scan error: $e');
                }
              },
            );
          }

          await _timeScanStep(
            'stage 1.2 directory traversal for $path',
            () => _directoryScanner.scanDirectoryInto(
              rootFolder,
              path,
              scanState,
              notifyListeners: notifyListeners,
            ),
          );

          _upsertScannedRootFolder(rootFolder);
          _rebuildDisplayedRootFolders();
          notifyListeners();
        }

        final discoveredPaths = _timeScanStepSync(
          'stage 1.3 collect discovered paths',
          () => scanState.pendingMetadataPaths.toList(growable: false),
        );
        final classification = await _timeScanStep(
          'stage 2 classify discovered files',
          () => _classifyDiscoveredFiles(discoveredPaths),
        );
        _timeScanStepSync('stage 2.1 seed metadata from db', () {
          _seedMetadataFromDatabase(classification.existingMetadataByPath);
        });

        final fullPaths = classification.pathsFor(ScanFileStage.full);
        final imageOnlyPaths = classification.pathsFor(ScanFileStage.imageOnly);

        await _timeScanStep(
          'stage 3 preprocess text tags',
          () => _preprocessChangedFiles(
            fullPaths,
            scanState,
            existingMetadataByPath: classification.existingMetadataByPath,
          ),
        );

        await _timeScanStep(
          'stage 4 preprocess artwork/theme',
          () => _applyArtworkAndThemeToChangedFiles([
            ...fullPaths,
            ...imageOnlyPaths,
          ], scanState),
        );

        final presentPaths = _timeScanStepSync('stage 5 collect present paths', () {
          final result = <String>{};
          for (final root in _scannedRootFolders) {
            _treeBuilder.collectFilePaths(root, result);
          }
          return result;
        });
        final normalizedPresentPaths = _timeScanStepSync(
          'stage 5.1 normalize present paths',
          () => presentPaths
              .map(_normalizePath)
              .where((path) => path.isNotEmpty)
              .toSet(),
        );
        final presentPathIndex = _timeScanStepSync(
          'stage 5.2 build present index',
          () => Platform.isWindows
              ? normalizedPresentPaths.map((path) => path.toLowerCase()).toSet()
              : normalizedPresentPaths,
        );
        final missingPaths = _timeScanStepSync('stage 5.3 detect missing paths', () {
          final result = <String>[];
          for (final path in _metadataStore.metadataMap.keys) {
            final normalizedPath = _normalizePath(path);
            if (!_roots.rootPaths.any(
              (root) => _pathContains(root, normalizedPath),
            )) {
              continue;
            }
            final lookupKey = Platform.isWindows
                ? normalizedPath.toLowerCase()
                : normalizedPath;
            if (!presentPathIndex.contains(lookupKey)) {
              result.add(normalizedPath);
            }
          }
          return result;
        });
        _timeScanStepSync('stage 5.4 notify missing states', () {
          for (final path in normalizedPresentPaths) {
            _notifySongMissingState(path, false);
          }
          for (final path in missingPaths) {
            _notifySongMissingState(path, true);
          }
        });
        await _timeScanStep(
          'stage 5.5 delete missing db rows',
          () => MetadataDatabase().deleteSongsMissingFromPaths(
            scopeRoots: _roots.rootPaths,
            presentPaths: presentPaths,
          ),
        );
      } else {
        debugPrint('Scan aborted: Permission not granted.');
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      totalStopwatch.stop();
      _logScanTiming('scan total', totalStopwatch);
      _isScanning = false;
      _flushScanNotifications();
      await _drainPendingIncrementalFileEvents();
      _sortAndNotify();
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

  Future<void> loadThumbnailForPath(String path) async {
    await _metadataStore.loadThumbnailForPath(path);
  }

  void updateMetadataForPath(SongMetadata metadata, {Uint8List? artworkBytes}) {
    _metadataStore.updateMetadataForPath(metadata, artworkBytes: artworkBytes);
  }

  void _emitScanProgress(ScanProgressState scanState, String filePath) {
    _scanProgressController.add(
      ScanProgress(
        filePath: filePath,
        discoveredCount: scanState.discoveredCount,
        preprocessedCount: scanState.preprocessedCount,
        completedCount: scanState.completedCount,
      ),
    );
  }

  int _compareNaturally(String a, String b) {
    return compareNatural(a.toLowerCase(), b.toLowerCase());
  }

  FolderSortSettings get _currentSortSettings {
    final currentFolder = _navigationState.currentFolder;
    if (currentFolder == null) {
      return FolderSortSettings(
        criteria: _globalSortCriteria,
        order: _globalSortOrder,
      );
    }
    return _resolveSortSettingsForFolder(currentFolder.path);
  }

  FolderSortSettings getGlobalSortSettings() {
    return FolderSortSettings(
      criteria: _globalSortCriteria,
      order: _globalSortOrder,
    );
  }

  FolderSortSettings getSortSettingsForFolder(String path) {
    return _resolveSortSettingsForFolder(path);
  }

  bool hasSortOverrideForFolder(String path) {
    return _folderSortOverrides.containsKey(_sortFolderKey(path));
  }

  SortScope get sortScopeForCurrentView {
    final currentFolder = _navigationState.currentFolder;
    if (currentFolder == null) {
      return SortScope.global;
    }
    return hasSortOverrideForFolder(currentFolder.path)
        ? SortScope.currentFolder
        : SortScope.global;
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

  bool _updateFolderSortSettings({
    String? folderPath,
    SortCriteria? criteria,
    SortOrder? order,
  }) {
    final targetPath = folderPath ?? _navigationState.currentFolder?.path;
    if (targetPath == null) {
      return false;
    }

    final key = _sortFolderKey(targetPath);
    final currentSettings =
        _folderSortOverrides[key] ??
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
      return true;
    }

    _folderSortOverrides = {..._folderSortOverrides, key: nextSettings};
    unawaited(_saveFolderSortOverrides());
    return true;
  }

  Future<void> _loadSortSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _globalSortCriteria = SortCriteriaX.fromStorageValue(
      prefs.getString(_keyGlobalSortCriteria),
    );
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

  void _syncNavigationStateToLatestTree() {
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

    final currentFolder = _navigationState.currentFolder;
    final resolvedCurrentFolder = resolveFolder(currentFolder);

    final resolvedHistory = <MusicFolder>[];
    for (final folder in _navigationState.history) {
      final resolved = resolveFolder(folder);
      if (resolved != null) {
        resolvedHistory.add(resolved);
      }
    }

    if (resolvedCurrentFolder == null && currentFolder != null) {
      _navigationState.setState(null, const []);
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

  bool _pathContains(String parent, String child) {
    return ScannerPathUtils.pathContains(parent, child);
  }

  bool isShortcutRoot(String path) {
    return _treeBuilder.isShortcutRoot(
      path: path,
      declaredRootPaths: _roots.rootPaths,
    );
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

  Future<T> _timeScanStep<T>(
    String label,
    Future<T> Function() action,
  ) async {
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
      if (!_isScanning) {
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _navigationState.removeListener(_handleNavigationChanged);
    _navigationState.dispose();
    _roots.dispose();
    _mediaObserverSubscription?.cancel();
    _metadataNotifyTimer?.cancel();
    _scanNotifyTimer?.cancel();
    _scanProgressController.close();
    super.dispose();
  }
}
