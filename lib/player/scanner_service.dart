import 'dart:io';
import 'dart:async';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:collection/collection.dart';
import 'package:worker_manager/worker_manager.dart';
import '../models/music_folder.dart';
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

  MusicFolder? _systemMediaFolder;
  bool _hasPermission = false;
  late final ScannerServiceRoots _roots;
  late final ScannerMetadataStore _metadataStore;
  late final ScannerScanPipeline _scanPipeline;
  late final ScannerTreeBuilder _treeBuilder;
  late final ScannerDirectoryScanner _directoryScanner;

  SortCriteria _sortCriteria = SortCriteria.filename;
  SortOrder _sortOrder = SortOrder.ascending;

  SortCriteria get sortCriteria => _sortCriteria;
  SortOrder get sortOrder => _sortOrder;

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
      isScanning: () => _isScanning,
      isDisposed: () => _isDisposed,
      requestScan: () => scan(),
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

  void setSortCriteria(SortCriteria criteria) {
    _sortCriteria = criteria;
    _sortAndNotify();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    _sortAndNotify();
  }

  void _sortAndNotify() {
    _folderSorter.sortFolders(
      _scannedRootFolders,
      criteria: _sortCriteria,
      order: _sortOrder,
    );
    if (_systemMediaFolder != null) {
      _folderSorter.sortFolderRecursive(
        _systemMediaFolder!,
        criteria: _sortCriteria,
        order: _sortOrder,
      );
    }
    _rebuildDisplayedRootFolders();
    _syncNavigationStateToLatestTree();
    notifyListeners();
  }

  Future<void> _init() async {
    await _roots.loadRootPaths();
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
    _hasPermission = await _checkPermissions();
    notifyListeners();
    if (_hasPermission) {
      await scanSystemMedia();
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
        return await controller.ensureAndroidMediaLibraryPermission();
      }

      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ requires Permission.audio
        var status = await Permission.audio.status;
        if (!status.isGranted) {
          status = await Permission.audio.request();
        }
        return status.isGranted;
      } else {
        // Legacy storage permission
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    }
    return true; // Assume granted on other platforms for now
  }

  Future<void> scanSystemMedia() async {
    if (!_hasPermission) return;

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
        _hasPermission = scanResult.permissionGranted;
        if (!scanResult.permissionGranted) {
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
        if (_systemMediaFolder != null) {
          _folderSorter.sortFolderRecursive(
            _systemMediaFolder!,
            criteria: _sortCriteria,
            order: _sortOrder,
          );
        }
        notifyListeners();

        unawaited(_processAndSaveAndroidSongsBackground(scanResult.entries));
        return;
      }

      if (Platform.isIOS) {
        final songs = await OnAudioQuery().querySongs(
          sortType: null,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
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
        if (_systemMediaFolder != null) {
          _folderSorter.sortFolderRecursive(
            _systemMediaFolder!,
            criteria: _sortCriteria,
            order: _sortOrder,
          );
        }
        notifyListeners();

        unawaited(_processAndSaveIosSongsBackground(songs));
      }
    } catch (e) {
      debugPrint('Error scanning system media: $e');
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

    const batchSize = 200;
    for (var start = 0; start < sortedPaths.length; start += batchSize) {
      final end = start + batchSize < sortedPaths.length
          ? start + batchSize
          : sortedPaths.length;
      final chunk = sortedPaths.sublist(start, end);

      final results = await MetadataHelper.readMetadataBatch(
        chunk,
        getImage: false,
      );

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
    }
  }

  Future<void> _applyArtworkAndThemeToChangedFiles(
    List<String> imageOnlyPaths,
    ScanProgressState scanState,
  ) async {
    if (imageOnlyPaths.isEmpty) return;

    final sortedPaths = imageOnlyPaths.toList()..sort(_compareNaturally);

    try {
      final supportDir = await getApplicationSupportDirectory();
      const batchSize = 6;
      for (var start = 0; start < sortedPaths.length; start += batchSize) {
        final end = start + batchSize < sortedPaths.length
            ? start + batchSize
            : sortedPaths.length;
        final batch = sortedPaths.sublist(start, end);

        await Future.wait(
          batch.map(
            (filePath) => _processArtworkAndThemeWithWorker(
              filePath: filePath,
              supportDirPath: supportDir.path,
              scanState: scanState,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Worker artwork scan failed, falling back to serial mode: $e');
      final db = MetadataDatabase();
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
    }
  }

  Future<void> _processArtworkAndThemeWithWorker({
    required String filePath,
    required String supportDirPath,
    required ScanProgressState scanState,
  }) async {
    final db = MetadataDatabase();

    try {
      final baseMetadata =
          _metadataStore.getMetadata(filePath) ??
          await db.getSongMetadata(filePath);
      if (baseMetadata == null) {
        return;
      }

      final result = await workerManager.execute<Map<String, dynamic>?>(
        () => processArtworkThumbnailWorkerTask({
          'filePath': filePath,
          'supportDirPath': supportDirPath,
          'saveLarge': !Platform.isWindows,
          'baseMetadata': baseMetadata.toMap(),
        }),
        priority: WorkPriority.immediately,
      );

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
      _roots.requestRootRescan();
      return;
    }

    _isScanning = true;
    _scannedRootFolders.clear();
    _rootFolders.clear();
    notifyListeners();

    try {
      if (await _checkPermissions()) {
        final scanState = ScanProgressState(
          metadataConcurrency: 4,
          comparePaths: _compareNaturally,
        );
        final scanRoots = _computeScanRoots(_roots.rootPaths);
        scanRoots.sort(_compareNaturally);
        for (final path in scanRoots) {
          debugPrint('Starting scan at: $path');

          final rootFolder = MusicFolder(
            path: path,
            name: _displayNameForPath(path),
          );
          _scannedRootFolders.add(rootFolder);
          _rebuildDisplayedRootFolders();
          notifyListeners();

          if (Platform.isAndroid) {
            // Trigger media scanner for each root path on startup
            try {
              await MediaScanner.loadMedia(path: path);
            } catch (e) {
              debugPrint('MediaScanner startup scan error: $e');
            }
          }

          await _directoryScanner.scanDirectoryInto(
            rootFolder,
            path,
            scanState,
            notifyListeners: notifyListeners,
          );
        }

        final discoveredPaths = scanState.pendingMetadataPaths.toList(
          growable: false,
        );
        final classification = await _classifyDiscoveredFiles(discoveredPaths);
        _seedMetadataFromDatabase(classification.existingMetadataByPath);

        final fullPaths = classification.pathsFor(ScanFileStage.full);
        final imageOnlyPaths = classification.pathsFor(ScanFileStage.imageOnly);

        await _preprocessChangedFiles(
          fullPaths,
          scanState,
          existingMetadataByPath: classification.existingMetadataByPath,
        );

        await _applyArtworkAndThemeToChangedFiles([
          ...fullPaths,
          ...imageOnlyPaths,
        ], scanState);

        final presentPaths = <String>{};
        for (final root in _scannedRootFolders) {
          _treeBuilder.collectFilePaths(root, presentPaths);
        }
        final normalizedPresentPaths = presentPaths
            .map(_normalizePath)
            .where((path) => path.isNotEmpty)
            .toSet();
        final presentPathIndex = Platform.isWindows
            ? normalizedPresentPaths.map((path) => path.toLowerCase()).toSet()
            : normalizedPresentPaths;
        final missingPaths = <String>[];
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
            missingPaths.add(normalizedPath);
          }
        }
        for (final path in normalizedPresentPaths) {
          _notifySongMissingState(path, false);
        }
        for (final path in missingPaths) {
          _notifySongMissingState(path, true);
        }
        await MetadataDatabase().deleteSongsMissingFromPaths(
          scopeRoots: _roots.rootPaths,
          presentPaths: presentPaths,
        );
      } else {
        debugPrint('Scan aborted: Permission not granted.');
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      _isScanning = false;
      _flushScanNotifications();
      _sortAndNotify();
      _roots.schedulePendingRootRescan();
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
