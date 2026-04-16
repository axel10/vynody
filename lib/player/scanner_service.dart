import 'dart:io';
import 'dart:async';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import 'package:worker_manager/worker_manager.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

enum SortCriteria { title, filename, trackNumber }

enum SortOrder { ascending, descending }

class ScanProgress {
  final String filePath;
  final int discoveredCount;
  final int preprocessedCount;
  final int completedCount;

  const ScanProgress({
    required this.filePath,
    required this.discoveredCount,
    required this.preprocessedCount,
    required this.completedCount,
  });
}

class _ScanProgressState {
  _ScanProgressState({
    int metadataConcurrency = 4,
    required int Function(String a, String b) comparePaths,
  }) : metadataRunner = _PriorityTaskRunner(
         metadataConcurrency,
         comparePaths: comparePaths,
       );

  int discoveredCount = 0;
  int preprocessedCount = 0;
  int completedCount = 0;
  final _PriorityTaskRunner metadataRunner;
  final List<Future<void>> pendingMetadataTasks = [];
  final List<String> pendingMetadataPaths = [];
}

class _PriorityTaskRunner {
  _PriorityTaskRunner(int maxConcurrent, {required this.comparePaths})
    : maxConcurrent = maxConcurrent < 1 ? 1 : maxConcurrent;

  final int maxConcurrent;
  final int Function(String a, String b) comparePaths;
  int _running = 0;
  int _sequence = 0;
  final List<_QueuedTask<dynamic>> _queue = [];

  Future<T> run<T>(String path, Future<T> Function() task) {
    final completer = Completer<T>();
    _queue.add(
      _QueuedTask<T>(
        path: path,
        sequence: _sequence++,
        completer: completer,
        task: task,
      ),
    );
    _pump();
    return completer.future;
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final nextIndex = _selectNextIndex();
      final next = _queue.removeAt(nextIndex);
      _running++;
      unawaited(_execute(next));
    }
  }

  int _selectNextIndex() {
    var bestIndex = 0;
    for (var i = 1; i < _queue.length; i++) {
      final candidate = _queue[i];
      final best = _queue[bestIndex];
      final pathCompare = comparePaths(candidate.path, best.path);
      if (pathCompare < 0 ||
          (pathCompare == 0 && candidate.sequence < best.sequence)) {
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  Future<void> _execute<T>(_QueuedTask<T> entry) async {
    try {
      final result = await entry.task();
      if (!entry.completer.isCompleted) {
        entry.completer.complete(result);
      }
    } catch (e, st) {
      if (!entry.completer.isCompleted) {
        entry.completer.completeError(e, st);
      }
    } finally {
      _running--;
      _pump();
    }
  }
}

class _QueuedTask<T> {
  _QueuedTask({
    required this.path,
    required this.sequence,
    required this.completer,
    required this.task,
  });

  final String path;
  final int sequence;
  final Completer<T> completer;
  final Future<T> Function() task;
}

enum _ScanFileStage { full, imageOnly, unchanged }

class _ScanFileClassification {
  _ScanFileClassification({
    required this.existingMetadataByPath,
    required this.stageByPath,
  });

  final Map<String, SongMetadata> existingMetadataByPath;
  final Map<String, _ScanFileStage> stageByPath;

  List<String> pathsFor(_ScanFileStage stage) {
    return stageByPath.entries
        .where((entry) => entry.value == stage)
        .map((entry) => entry.key)
        .toList(growable: false);
  }
}

class ScannerService extends ChangeNotifier {
  AudioCoreController? _playerController;
  StreamSubscription? _mediaObserverSubscription;
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();
  final List<String> _rootPaths = [];
  final List<MusicFolder> _scannedRootFolders = [];
  final List<MusicFolder> _rootFolders = [];
  bool _isScanning = false;
  bool _isBackgroundTaskPaused = false;
  Timer? _metadataNotifyTimer;
  Timer? _scanNotifyTimer;
  bool _scanNotifyPending = false;
  bool _isDisposed = false;

  MusicFolder? _systemMediaFolder;
  bool _hasPermission = false;

  SortCriteria _sortCriteria = SortCriteria.filename;
  SortOrder _sortOrder = SortOrder.ascending;

  SortCriteria get sortCriteria => _sortCriteria;
  SortOrder get sortOrder => _sortOrder;

  List<String> get rootPaths => List.unmodifiable(_rootPaths);
  List<MusicFolder> get rootFolders => List.unmodifiable(_rootFolders);
  bool get isScanning => _isScanning;
  bool get isBackgroundTaskPaused => _isBackgroundTaskPaused;
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  // Navigation state for FoldersPage
  MusicFolder? _navigationCurrentFolder;
  final List<MusicFolder> _navigationHistory = [];

  MusicFolder? get navigationCurrentFolder => _navigationCurrentFolder;
  List<MusicFolder> get navigationHistory =>
      List.unmodifiable(_navigationHistory);

  void setNavigationState(MusicFolder? current, List<MusicFolder> history) {
    _navigationCurrentFolder = current;
    _navigationHistory.clear();
    _navigationHistory.addAll(history);
    notifyListeners();
  }

  void pushNavigationHistory(MusicFolder folder) {
    _navigationHistory.add(folder);
    notifyListeners();
  }

  MusicFolder? popNavigationHistory() {
    if (_navigationHistory.isEmpty) return null;
    final folder = _navigationHistory.removeLast();
    notifyListeners();
    return folder;
  }

  MusicFolder? get systemMediaFolder => _systemMediaFolder;
  bool get hasPermission => _hasPermission;
  final Map<String, SongMetadata> _metadataMap = {};

  Map<String, SongMetadata> get metadataMap => _metadataMap;

  final List<String> _audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  ScannerService() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_init());
    });
    _setupMediaObserver();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;

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

  void setSortCriteria(SortCriteria criteria) {
    _sortCriteria = criteria;
    _sortAndNotify();
  }

  void setSortOrder(SortOrder order) {
    _sortOrder = order;
    _sortAndNotify();
  }

  void _sortAndNotify() {
    _sortFolders(_scannedRootFolders);
    if (_systemMediaFolder != null) {
      _sortFolderRecursive(_systemMediaFolder!);
    }
    _rebuildDisplayedRootFolders();
    notifyListeners();
  }

  void _sortFolders(List<MusicFolder> folders) {
    folders.sort(
      (a, b) => compareNatural(a.name.toLowerCase(), b.name.toLowerCase()),
    );
    for (var folder in folders) {
      _sortFolderRecursive(folder);
    }
  }

  void _sortFolderRecursive(MusicFolder folder) {
    folder.subFolders.sort(
      (a, b) => compareNatural(a.name.toLowerCase(), b.name.toLowerCase()),
    );

    int Function(MusicFile, MusicFile) comparator;

    switch (_sortCriteria) {
      case SortCriteria.title:
        comparator = (a, b) => compareNatural(
          a.displayName.toLowerCase(),
          b.displayName.toLowerCase(),
        );
        break;
      case SortCriteria.filename:
        comparator = (a, b) =>
            compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
        break;
      case SortCriteria.trackNumber:
        comparator = (a, b) {
          if (a.trackNumber != null && b.trackNumber != null) {
            return a.trackNumber!.compareTo(b.trackNumber!);
          }
          if (a.trackNumber != null) return -1;
          if (b.trackNumber != null) return 1;
          return compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
        };
        break;
    }

    if (_sortOrder == SortOrder.descending) {
      final baseComparator = comparator;
      comparator = (a, b) => baseComparator(b, a);
    }

    folder.files.sort(comparator);

    for (var sub in folder.subFolders) {
      _sortFolderRecursive(sub);
    }
  }

  Future<void> _init() async {
    await _loadRootPaths();
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

  Future<void> _loadRootPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('root_paths') ?? [];
    final normalizedPaths = _normalizeDeclaredRootPaths(paths);
    _rootPaths.clear();
    _rootPaths.addAll(normalizedPaths);
    notifyListeners();
  }

  Future<void> _saveRootPaths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('root_paths', _rootPaths);
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
    final existingRoot = _rootPaths.firstWhereOrNull(
      (existing) => _pathsEqual(existing, normalizedPath),
    );
    if (existingRoot != null) {
      final existingFolder = _rootFolders.firstWhereOrNull(
        (folder) => _pathsEqual(folder.path, existingRoot),
      );
      return existingFolder != null && !existingFolder.isEmpty;
    }

    _rootPaths.add(normalizedPath);
    final normalizedRoots = _normalizeDeclaredRootPaths(_rootPaths);
    _rootPaths
      ..clear()
      ..addAll(normalizedRoots);
    await _saveRootPaths();
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

    _rootPaths.removeWhere(
      (existing) =>
          normalizedTargets.any((target) => _pathsEqual(existing, target)),
    );
    _rebuildDisplayedRootFolders();
    await _saveRootPaths();
    notifyListeners();
  }

  Future<void> moveRootPath(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _rootPaths.length) return;
    if (newIndex < 0 || newIndex > _rootPaths.length) return;
    if (oldIndex == newIndex) return;

    final movedPath = _rootPaths.removeAt(oldIndex);
    _rootPaths.insert(newIndex, movedPath);
    _rebuildDisplayedRootFolders();
    await _saveRootPaths();
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

        _systemMediaFolder = _organizeAndroidMediaLibrary(
          scanResult.entries,
          metadataByPath,
        );
        if (_systemMediaFolder != null) {
          _sortFolderRecursive(_systemMediaFolder!);
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

        _systemMediaFolder = _organizeSongsIntoFolders(songs, metadataByPath);
        if (_systemMediaFolder != null) {
          _sortFolderRecursive(_systemMediaFolder!);
        }
        notifyListeners();

        unawaited(_processAndSaveIosSongsBackground(songs));
      }
    } catch (e) {
      debugPrint('Error scanning system media: $e');
    }
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
    _metadataMap.clear();
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
      _metadataMap[filePath] = metadata.copyWith(waveformBlob: null);
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

    final scanState = _ScanProgressState(
      metadataConcurrency: 4,
      comparePaths: _compareScanFilePriority,
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

  Future<Map<String, int?>> _loadLastModifiedTimes(
    Iterable<String> filePaths,
  ) async {
    final normalizedPaths = <String>[];
    final seen = <String>{};

    for (final path in filePaths) {
      final normalized = _normalizePath(path);
      if (normalized.isEmpty) continue;

      final lookupKey = _pathLookupKey(normalized);
      if (seen.add(lookupKey)) {
        normalizedPaths.add(normalized);
      }
    }

    final lastModifiedByPath = <String, int?>{};
    if (normalizedPaths.isEmpty) {
      return lastModifiedByPath;
    }

    const batchSize = 128;
    for (var start = 0; start < normalizedPaths.length; start += batchSize) {
      final end = start + batchSize < normalizedPaths.length
          ? start + batchSize
          : normalizedPaths.length;
      final chunk = normalizedPaths.sublist(start, end);

      final results = await Future.wait(
        chunk.map((path) async {
          try {
            final lastModified = await File(path).lastModified();
            return MapEntry(
              _pathLookupKey(path),
              lastModified.millisecondsSinceEpoch,
            );
          } catch (_) {
            return MapEntry<String, int?>(_pathLookupKey(path), null);
          }
        }),
      );

      for (final entry in results) {
        lastModifiedByPath[entry.key] = entry.value;
      }
    }

    return lastModifiedByPath;
  }

  Future<_ScanFileClassification> _classifyDiscoveredFiles(
    List<String> filePaths,
  ) async {
    if (filePaths.isEmpty) {
      return _ScanFileClassification(
        existingMetadataByPath: const {},
        stageByPath: const {},
      );
    }

    final existingMetadataByPath = await MetadataDatabase()
        .getSongMetadataByPaths(filePaths);
    final lastModifiedByPath = await _loadLastModifiedTimes(filePaths);

    final stageByPath = <String, _ScanFileStage>{};
    final seen = <String>{};

    for (final path in filePaths) {
      final lookupKey = _pathLookupKey(path);
      if (!seen.add(lookupKey)) {
        continue;
      }

      final existing = existingMetadataByPath[lookupKey];
      final currentLastModified = lastModifiedByPath[lookupKey];
      final textScanned = existing?.metadataTextScanned;
      final imgScanned = existing?.metadataImgScanned;

      if (existing != null &&
          currentLastModified != null &&
          textScanned == currentLastModified &&
          imgScanned == currentLastModified) {
        stageByPath[path] = _ScanFileStage.unchanged;
      } else if (existing != null &&
          currentLastModified != null &&
          textScanned == currentLastModified &&
          imgScanned != currentLastModified) {
        stageByPath[path] = _ScanFileStage.imageOnly;
      } else {
        stageByPath[path] = _ScanFileStage.full;
      }
    }

    return _ScanFileClassification(
      existingMetadataByPath: existingMetadataByPath,
      stageByPath: stageByPath,
    );
  }

  void _seedMetadataFromDatabase(
    Map<String, SongMetadata> existingMetadataByPath,
  ) {
    for (final metadata in existingMetadataByPath.values) {
      _updateMetadataForPath(metadata, notify: false);
    }
  }

  Future<void> _preprocessChangedFiles(
    List<String> fullPaths,
    _ScanProgressState scanState, {
    required Map<String, SongMetadata> existingMetadataByPath,
  }) async {
    if (fullPaths.isEmpty) return;

    final db = MetadataDatabase();
    final sortedPaths = fullPaths.toList()..sort(_compareScanFilePriority);

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
          _updateMetadataForPath(metadata, notify: false);
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
    _ScanProgressState scanState,
  ) async {
    if (imageOnlyPaths.isEmpty) return;

    final sortedPaths = imageOnlyPaths.toList()..sort(_compareScanFilePriority);

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
              _metadataMap[filePath] ?? await db.getSongMetadata(filePath);
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
            _updateMetadataForPath(updatedMetadata, notify: false);
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
    required _ScanProgressState scanState,
  }) async {
    final db = MetadataDatabase();

    try {
      final baseMetadata =
          _metadataMap[filePath] ?? await db.getSongMetadata(filePath);
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
      _updateMetadataForPath(updatedMetadata, notify: false);
      scanState.completedCount++;
    } catch (e) {
      debugPrint('Worker artwork/theme scan error for $filePath: $e');
    } finally {
      _emitScanProgress(scanState, filePath);
    }
  }

  MusicFolder _organizeAndroidMediaLibrary(
    List<AndroidMediaLibraryEntry> entries,
    Map<String, SongMetadata> metadataByPath,
  ) {
    final root = MusicFolder(path: 'system', name: '系统媒体库');
    final nodes = <String, MusicFolder>{'': root};

    for (final entry in entries) {
      final filePath = _androidEntryFilePath(entry);
      if (filePath == null) continue;

      final file = _musicFileFromAndroidEntry(
        entry,
        path: filePath,
        metadata: metadataByPath[filePath],
      );
      final folderPath = _normalizeAndroidFolderPath(entry.folderPath);
      if (folderPath.isEmpty) {
        root.files.add(file);
        continue;
      }

      var currentPath = '';
      var currentFolder = root;
      for (final segment in folderPath.split('/').where((s) => s.isNotEmpty)) {
        currentPath = currentPath.isEmpty ? segment : '$currentPath/$segment';
        final nextFolder = nodes.putIfAbsent(
          currentPath,
          () => MusicFolder(path: currentPath, name: segment),
        );
        if (!currentFolder.subFolders.contains(nextFolder)) {
          currentFolder.subFolders.add(nextFolder);
        }
        currentFolder = nextFolder;
      }

      currentFolder.files.add(file);
    }

    _sortFolderRecursive(root);
    return root;
  }

  MusicFolder _organizeSongsIntoFolders(
    List<SongModel> songs,
    Map<String, SongMetadata> metadataByPath,
  ) {
    final Map<String, List<MusicFile>> folderFiles = {};
    final Set<String> allPaths = {};

    for (final song in songs) {
      final path = song.data;
      final metadata = metadataByPath[path];
      final file = _musicFileFromSongModel(song, metadata: metadata);
      final dirPath = p.dirname(path);

      folderFiles.putIfAbsent(dirPath, () => []).add(file);

      var current = dirPath;
      while (current.isNotEmpty && current != '/' && current != '.') {
        allPaths.add(current);
        final parent = p.dirname(current);
        if (parent == current) break;
        current = parent;
      }
    }

    final List<String> entryPoints = allPaths.where((path) {
      final parent = p.dirname(path);
      return !allPaths.contains(parent);
    }).toList();

    if (entryPoints.isEmpty && songs.isEmpty) {
      return MusicFolder(path: 'system', name: '系统媒体库');
    }

    final List<MusicFolder> topFolders = entryPoints
        .map((path) => _recursiveBuild(path, allPaths, folderFiles))
        .toList();

    return MusicFolder(
      path: 'system',
      name: '系统媒体库',
      subFolders: topFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      files: [],
    );
  }

  MusicFolder _recursiveBuild(
    String currentPath,
    Set<String> allPaths,
    Map<String, List<MusicFile>> folderFiles,
  ) {
    final subFolderPaths = allPaths
        .where((path) => p.dirname(path) == currentPath)
        .toList();
    final subFolders = subFolderPaths
        .map((path) => _recursiveBuild(path, allPaths, folderFiles))
        .toList();
    final files = folderFiles[currentPath] ?? [];

    return MusicFolder(
      path: currentPath,
      name: p.basename(currentPath).isEmpty
          ? currentPath
          : p.basename(currentPath),
      subFolders: subFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      files: files
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  MusicFile _musicFileFromAndroidEntry(
    AndroidMediaLibraryEntry entry, {
    required String path,
    SongMetadata? metadata,
  }) {
    final parsedId = int.tryParse(entry.id);
    final displayName = entry.displayName?.trim();
    final resolvedMetadata = metadata;
    return MusicFile(
      path: path,
      name: displayName != null && displayName.isNotEmpty
          ? displayName
          : p.basename(path),
      title: _cleanText(resolvedMetadata?.title ?? entry.title),
      artist: _cleanText(resolvedMetadata?.artist ?? entry.artist),
      album: _cleanText(resolvedMetadata?.album ?? entry.album),
      trackNumber: resolvedMetadata?.trackNumber,
      durationMillis:
          resolvedMetadata?.duration ?? entry.duration.inMilliseconds,
      id: parsedId,
      mediaUri: entry.uri,
      thumbnailPath: resolvedMetadata?.thumbnailPath,
      artworkPath: resolvedMetadata?.artworkPath,
      artworkWidth: resolvedMetadata?.artworkWidth,
      artworkHeight: resolvedMetadata?.artworkHeight,
      themeColorsBlob: resolvedMetadata?.themeColorsBlob,
      lastModifiedTime: resolvedMetadata?.lastModifiedTime,
    );
  }

  MusicFile _musicFileFromSongModel(SongModel song, {SongMetadata? metadata}) {
    return MusicFile(
      path: song.data,
      name: p.basename(song.data),
      title: _cleanText(metadata?.title ?? song.title),
      artist: _cleanText(metadata?.artist ?? song.artist),
      album: _cleanText(metadata?.album ?? song.album),
      trackNumber: metadata?.trackNumber ?? song.track,
      durationMillis: metadata?.duration ?? song.duration,
      id: song.id,
      thumbnailPath: metadata?.thumbnailPath,
      artworkPath: metadata?.artworkPath,
      artworkWidth: metadata?.artworkWidth,
      artworkHeight: metadata?.artworkHeight,
      themeColorsBlob: metadata?.themeColorsBlob,
      lastModifiedTime: metadata?.lastModifiedTime,
    );
  }

  String? _androidEntryFilePath(AndroidMediaLibraryEntry entry) {
    final path = entry.filePath?.trim();
    if (path != null && path.isNotEmpty) return _normalizePath(path);
    final uri = entry.uri.trim();
    if (uri.isNotEmpty) return uri;
    return null;
  }

  String _normalizeAndroidFolderPath(String path) {
    final cleaned = path.replaceAll('\\', '/').trim();
    if (cleaned.isEmpty) return '';
    return cleaned.endsWith('/')
        ? cleaned.substring(0, cleaned.length - 1)
        : cleaned;
  }

  String? _cleanText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastModified =
        result['lastModifiedTime'] as int? ?? existing?.lastModifiedTime ?? now;
    final resolvedFallbackTitle =
        _cleanText(fallbackTitle) ?? p.basenameWithoutExtension(filePath);

    final song = SongMetadata(
      path: filePath,
      title:
          _cleanText(result['title'] as String?) ??
          _cleanText(existing?.title) ??
          resolvedFallbackTitle,
      album:
          _cleanText(result['album'] as String?) ??
          _cleanText(existing?.album) ??
          _cleanText(fallbackAlbum) ??
          'Unknown Album',
      artist:
          _cleanText(result['artist'] as String?) ??
          _cleanText(existing?.artist) ??
          _cleanText(fallbackArtist) ??
          'Unknown Artist',
      duration:
          result['duration'] as int? ?? existing?.duration ?? fallbackDuration,
      trackNumber:
          result['trackNumber'] as int? ??
          existing?.trackNumber ??
          fallbackTrackNumber,
      artworkPath: existing?.artworkPath,
      thumbnailPath: existing?.thumbnailPath,
      artworkWidth: existing?.artworkWidth,
      artworkHeight: existing?.artworkHeight,
      themeColorsBlob: existing?.themeColorsBlob,
      waveformBlob: existing?.waveformBlob,
      lastModifiedTime: lastModified,
      metadataTextScanned: lastModified,
      metadataImgScanned: existing?.metadataImgScanned,
      createdAt: existing?.createdAt ?? now,
      genres: existing?.genres,
    );

    return song;
  }

  Future<void> scan() async {
    if (_rootPaths.isEmpty) return;

    _isScanning = true;
    _scannedRootFolders.clear();
    _rootFolders.clear();
    notifyListeners();

    try {
      if (await _checkPermissions()) {
        final scanState = _ScanProgressState(
          metadataConcurrency: 4,
          comparePaths: _compareScanFilePriority,
        );
        final scanRoots = _computeScanRoots(_rootPaths);
        scanRoots.sort(_compareScanPathPriority);
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

          await _scanDirectoryInto(rootFolder, path, scanState);
        }

        final discoveredPaths = scanState.pendingMetadataPaths.toList(
          growable: false,
        );
        final classification = await _classifyDiscoveredFiles(discoveredPaths);
        _seedMetadataFromDatabase(classification.existingMetadataByPath);

        final fullPaths = classification.pathsFor(_ScanFileStage.full);
        final imageOnlyPaths = classification.pathsFor(
          _ScanFileStage.imageOnly,
        );

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
          _collectFilePaths(root, presentPaths);
        }
        final normalizedPresentPaths = presentPaths
            .map(_normalizePath)
            .where((path) => path.isNotEmpty)
            .toSet();
        final presentPathIndex = Platform.isWindows
            ? normalizedPresentPaths.map((path) => path.toLowerCase()).toSet()
            : normalizedPresentPaths;
        _metadataMap.removeWhere((path, _) {
          final normalizedPath = _normalizePath(path);
          return _rootPaths.any(
                (root) => _pathContains(root, normalizedPath),
              ) &&
              !presentPathIndex.contains(
                Platform.isWindows
                    ? normalizedPath.toLowerCase()
                    : normalizedPath,
              );
        });
        await MetadataDatabase().deleteSongsMissingFromPaths(
          scopeRoots: _rootPaths,
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
    }
  }

  Future<void> rebuildMetadataDatabase() async {
    if (Platform.isWindows) {
      await MetadataDatabase().clearAll();
      await MetadataHelper.clearThumbnails();
      _metadataMap.clear();
      await scan();
    }
  }

  void _collectFilePaths(MusicFolder folder, Set<String> out) {
    for (final file in folder.files) {
      out.add(_normalizePath(file.path));
    }
    for (final subFolder in folder.subFolders) {
      _collectFilePaths(subFolder, out);
    }
  }

  /// Loads metadata for a single path from the DB (or processes it fresh) and
  /// caches it in [metadataMap]. Safe to call multiple times.
  Future<void> loadMetadataForPath(String path) async {
    if (!await File(path).exists()) {
      await _purgeMissingSongPath(path);
      return;
    }

    final cached = _metadataMap[path];
    if (cached != null) {
      return;
    }

    final db = MetadataDatabase();
    // Try DB first (cheapest); fall back to full processing if not found.
    SongMetadata? metadata = await db.getSongMetadata(path);
    final result = metadata == null
        ? await MetadataHelper.processMetadata(path, generateThumbnail: false)
        : null;
    metadata ??= result?.$1;

    if (metadata != null) {
      _metadataMap[path] = metadata;
      notifyListeners();
    }
  }

  Future<void> loadThumbnailForPath(String path) async {
    if (!await File(path).exists()) {
      await _purgeMissingSongPath(path);
      return;
    }

    final cached = _metadataMap[path];
    if (cached != null && (cached.thumbnailPath?.isNotEmpty ?? false)) {
      return;
    }

    final db = MetadataDatabase();
    SongMetadata? metadata = await db.getSongMetadata(path);
    if (metadata != null && (metadata.thumbnailPath?.isNotEmpty ?? false)) {
      _metadataMap[path] = metadata;
      notifyListeners();
      return;
    }

    final result = await MetadataHelper.processMetadata(
      path,
      generateThumbnail: true,
    );
    metadata = result?.$1 ?? metadata;

    if (metadata != null) {
      _metadataMap[path] = metadata;
      notifyListeners();
    }
  }

  Future<void> _purgeMissingSongPath(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return;

    _metadataMap.removeWhere(
      (existingPath, _) => _pathsEqual(existingPath, normalizedPath),
    );

    for (final root in _scannedRootFolders) {
      _removeSongFromFolder(root, normalizedPath);
    }
    if (_systemMediaFolder != null) {
      _removeSongFromFolder(_systemMediaFolder!, normalizedPath);
    }

    _rebuildDisplayedRootFolders();
    await MetadataDatabase().deleteSongByPath(normalizedPath);
    notifyListeners();
  }

  bool _removeSongFromFolder(MusicFolder folder, String path) {
    folder.files.removeWhere((file) => _pathsEqual(file.path, path));

    folder.subFolders.removeWhere((subFolder) {
      final shouldRemove = _removeSongFromFolder(subFolder, path);
      return shouldRemove;
    });

    return folder.isEmpty;
  }

  void updateMetadataForPath(SongMetadata metadata, {Uint8List? artworkBytes}) {
    _updateMetadataForPath(metadata, artworkBytes: artworkBytes);
  }

  void _updateMetadataForPath(
    SongMetadata metadata, {
    Uint8List? artworkBytes,
    bool notify = true,
  }) {
    final existing = _metadataMap[metadata.path];
    final mergedMetadata = metadata.copyWith(
      thumbnailPath: metadata.thumbnailPath ?? existing?.thumbnailPath,
      artworkPath: metadata.artworkPath ?? existing?.artworkPath,
      artworkWidth: metadata.artworkWidth ?? existing?.artworkWidth,
      artworkHeight: metadata.artworkHeight ?? existing?.artworkHeight,
      themeColorsBlob: metadata.themeColorsBlob ?? existing?.themeColorsBlob,
      waveformBlob: null,
    );
    _metadataMap[metadata.path] = mergedMetadata;

    for (final root in _scannedRootFolders) {
      _updateMusicFileInFolder(
        root,
        mergedMetadata,
        artworkBytes: artworkBytes,
      );
    }
    if (_systemMediaFolder != null) {
      _updateMusicFileInFolder(
        _systemMediaFolder!,
        mergedMetadata,
        artworkBytes: artworkBytes,
      );
    }

    if (notify) {
      notifyListeners();
    } else {
      _scheduleMetadataNotify();
    }
  }

  void _updateMusicFileInFolder(
    MusicFolder folder,
    SongMetadata metadata, {
    Uint8List? artworkBytes,
  }) {
    for (var i = 0; i < folder.files.length; i++) {
      final file = folder.files[i];
      if (file.path == metadata.path) {
        folder.files[i] = file.copyWith(
          title: metadata.title,
          artist: metadata.artist,
          album: metadata.album,
          trackNumber: metadata.trackNumber,
          thumbnailPath: metadata.thumbnailPath ?? file.thumbnailPath,
          artworkPath: metadata.artworkPath ?? file.artworkPath,
          artworkWidth: metadata.artworkWidth ?? file.artworkWidth,
          artworkHeight: metadata.artworkHeight ?? file.artworkHeight,
          themeColorsBlob: metadata.themeColorsBlob ?? file.themeColorsBlob,
          waveformBlob: null,
          artworkBytes: artworkBytes,
          lastModifiedTime: metadata.lastModifiedTime,
        );
      }
    }
    for (final subFolder in folder.subFolders) {
      _updateMusicFileInFolder(subFolder, metadata, artworkBytes: artworkBytes);
    }
  }

  Future<bool> _scanDirectoryInto(
    MusicFolder folder,
    String path,
    _ScanProgressState scanState,
  ) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('Directory does not exist: $path');
      return false;
    }

    bool hasContent = false;

    try {
      final List<FileSystemEntity> entities = await dir
          .list(followLinks: false)
          .toList();
      debugPrint('Scanning $path: Found ${entities.length} entities');

      final directories = <Directory>[];
      final audioFiles = <File>[];

      for (var entity in entities) {
        if (entity is Directory) {
          // Avoid hidden directories/system folders
          if (p.basename(entity.path).startsWith('.')) continue;
          directories.add(entity);
        } else if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_audioExtensions.contains(ext)) {
            audioFiles.add(entity);
          }
        }
      }

      directories.sort((a, b) => _compareScanPathPriority(a.path, b.path));
      audioFiles.sort((a, b) => _compareScanFilePriority(a.path, b.path));

      for (final entity in audioFiles) {
        final filePath = entity.path;
        folder.files.add(
          MusicFile(path: filePath, name: p.basename(filePath), id: null),
        );
        scanState.discoveredCount++;
        _emitScanProgress(scanState, filePath);
        hasContent = true;

        scanState.pendingMetadataPaths.add(filePath);
      }

      for (final entity in directories) {
        final subFolder = MusicFolder(
          path: entity.path,
          name: _displayNameForPath(entity.path),
        );
        folder.subFolders.add(subFolder);
        final subFolderHasContent = await _scanDirectoryInto(
          subFolder,
          entity.path,
          scanState,
        );
        if (subFolderHasContent) {
          hasContent = true;
        } else {
          folder.subFolders.removeWhere(
            (existing) => _pathsEqual(existing.path, subFolder.path),
          );
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error listing directory $path: $e');
    }

    _sortFolderRecursive(folder);
    return hasContent;
  }

  void _emitScanProgress(_ScanProgressState scanState, String filePath) {
    _scanProgressController.add(
      ScanProgress(
        filePath: filePath,
        discoveredCount: scanState.discoveredCount,
        preprocessedCount: scanState.preprocessedCount,
        completedCount: scanState.completedCount,
      ),
    );
  }

  int _compareScanPathPriority(String a, String b) {
    final currentPath = _navigationCurrentFolder?.path;
    if (currentPath != null) {
      final aPriority = _pathContains(a, currentPath) ? 0 : 1;
      final bPriority = _pathContains(b, currentPath) ? 0 : 1;
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
    }

    return compareNatural(a.toLowerCase(), b.toLowerCase());
  }

  int _compareScanFilePriority(String a, String b) {
    final currentPath = _navigationCurrentFolder?.path;
    if (currentPath != null) {
      final aPriority = _pathContains(currentPath, p.dirname(a)) ? 0 : 1;
      final bPriority = _pathContains(currentPath, p.dirname(b)) ? 0 : 1;
      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }
    }

    return compareNatural(a.toLowerCase(), b.toLowerCase());
  }

  String _normalizePath(String path) {
    var normalized = p.normalize(path.trim());
    if (Platform.isWindows) {
      normalized = normalized.replaceAll('/', r'\');
      if (normalized.length > 3 && normalized.endsWith(r'\')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
    } else if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _pathLookupKey(String path) {
    final normalized = _normalizePath(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  List<String> _normalizeDeclaredRootPaths(Iterable<String> paths) {
    final normalizedPaths = paths
        .map(_normalizePath)
        .where((path) => path.isNotEmpty)
        .toList();

    final result = <String>[];
    for (final path in normalizedPaths) {
      if (result.any((existing) => _pathsEqual(existing, path))) {
        continue;
      }
      result.add(path);
    }

    return result;
  }

  List<String> _computeScanRoots(Iterable<String> paths) {
    final normalizedPaths = _normalizeDeclaredRootPaths(paths);
    normalizedPaths.sort((a, b) => a.length.compareTo(b.length));

    final result = <String>[];
    for (final path in normalizedPaths) {
      if (result.any((existing) => _pathContains(existing, path))) {
        continue;
      }
      result.add(path);
    }

    return result;
  }

  void _rebuildDisplayedRootFolders() {
    final displayedRoots = <MusicFolder>[];
    for (final path in _rootPaths) {
      final folder =
          _resolveFolderForPath(path) ??
          MusicFolder(path: path, name: _displayNameForPath(path));
      displayedRoots.add(folder);
    }
    _rootFolders
      ..clear()
      ..addAll(displayedRoots);
  }

  MusicFolder? _resolveFolderForPath(String path) {
    final normalizedPath = _normalizePath(path);

    for (final root in _scannedRootFolders) {
      final resolved = _findFolderInTree(root, normalizedPath);
      if (resolved != null) return resolved;
    }

    if (_systemMediaFolder != null) {
      final resolved = _findFolderInTree(_systemMediaFolder!, normalizedPath);
      if (resolved != null) return resolved;
    }

    return null;
  }

  MusicFolder? _findFolderInTree(MusicFolder folder, String path) {
    if (_pathsEqual(folder.path, path)) return folder;

    for (final subFolder in folder.subFolders) {
      final resolved = _findFolderInTree(subFolder, path);
      if (resolved != null) return resolved;
    }

    return null;
  }

  bool _pathsEqual(String left, String right) {
    final normalizedLeft = _normalizePath(left);
    final normalizedRight = _normalizePath(right);
    if (Platform.isWindows) {
      return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    }
    return normalizedLeft == normalizedRight;
  }

  bool _pathContains(String parent, String child) {
    final normalizedParent = _normalizePath(parent);
    final normalizedChild = _normalizePath(child);

    if (_pathsEqual(normalizedParent, normalizedChild)) {
      return true;
    }

    if (Platform.isWindows) {
      return p.isWithin(
        normalizedParent.toLowerCase(),
        normalizedChild.toLowerCase(),
      );
    }

    return p.isWithin(normalizedParent, normalizedChild);
  }

  bool isShortcutRoot(String path) {
    final normalizedPath = _normalizePath(path);
    final declaredMatch = _rootPaths.any(
      (existing) => _pathsEqual(existing, normalizedPath),
    );
    if (!declaredMatch) return false;

    final scanRoots = _computeScanRoots(_rootPaths);
    return !scanRoots.any((existing) => _pathsEqual(existing, normalizedPath));
  }

  String _displayNameForPath(String path) {
    final normalizedPath = _normalizePath(path);
    final basename = p.basename(normalizedPath);
    if (basename.isNotEmpty) return basename;

    if (Platform.isWindows) {
      var drive = p.rootPrefix(normalizedPath);
      if (drive.endsWith(r'\') || drive.endsWith('/')) {
        drive = drive.substring(0, drive.length - 1);
      }
      if (drive.isNotEmpty) return drive;
    }

    return normalizedPath;
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
    _mediaObserverSubscription?.cancel();
    _metadataNotifyTimer?.cancel();
    _scanNotifyTimer?.cancel();
    _scanProgressController.close();
    super.dispose();
  }
}
