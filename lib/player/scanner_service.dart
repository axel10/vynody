import 'dart:io';
import 'dart:async';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

enum SortCriteria { title, filename, trackNumber }

enum SortOrder { ascending, descending }

class ScannerService extends ChangeNotifier {
  AudioCoreController? _playerController;
  StreamSubscription? _mediaObserverSubscription;
  final List<String> _rootPaths = [];
  final List<MusicFolder> _scannedRootFolders = [];
  final List<MusicFolder> _rootFolders = [];
  bool _isScanning = false;
  bool _isBackgroundTaskPaused = false;

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
    _init();
    _setupMediaObserver();
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
    final normalizedPath = _normalizePath(path);
    _rootPaths.removeWhere((existing) => _pathsEqual(existing, normalizedPath));
    final normalizedRoots = _normalizeDeclaredRootPaths(_rootPaths);
    _rootPaths
      ..clear()
      ..addAll(normalizedRoots);
    await _saveRootPaths();
    _rootFolders.removeWhere((f) => _pathsEqual(f.path, normalizedPath));
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

    for (final entry in entries) {
      final filePath = filePathOf(entry);
      if (filePath == null) continue;

      final metadata = await _resolveScannedMetadata(
        filePath,
        songId: songIdOf(entry),
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

    for (final entry in entries) {
      await _waitUntilResumed();
      final path = filePathOf(entry);
      if (path == null) continue;
      try {
        await MetadataHelper.processMetadata(
          path,
          songId: songIdOf(entry),
          generateThumbnail: false,
        );
      } catch (e) {
        debugPrint('Background processing error for $path: $e');
      }

      await Future.delayed(const Duration(milliseconds: 100));
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

  Future<SongMetadata> _resolveScannedMetadata(
    String filePath, {
    int? songId,
    required String fallbackTitle,
    required String fallbackAlbum,
    required String fallbackArtist,
    required int? fallbackDuration,
    int? fallbackTrackNumber,
  }) async {
    final db = MetadataDatabase();
    final existing = await db.getSongMetadata(filePath);
    if (existing != null) {
      try {
        final lastModified = (await File(
          filePath,
        ).lastModified()).millisecondsSinceEpoch;
        if (existing.lastModifiedTime == lastModified) {
          return existing;
        }
      } catch (e) {
        debugPrint('Failed to read last modified time for $filePath: $e');
        return existing;
      }
    }

    final result = await MetadataHelper.processMetadata(
      filePath,
      songId: songId,
      generateThumbnail: false,
    );
    if (result != null) {
      return result.$1;
    }

    return existing ??
        SongMetadata(
          path: filePath,
          title:
              _cleanText(fallbackTitle) ?? p.basenameWithoutExtension(filePath),
          album: _cleanText(fallbackAlbum) ?? 'Unknown Album',
          artist: _cleanText(fallbackArtist) ?? 'Unknown Artist',
          duration: fallbackDuration,
          trackNumber: fallbackTrackNumber,
        );
  }

  Future<void> scan() async {
    if (_rootPaths.isEmpty) return;

    _isScanning = true;
    _scannedRootFolders.clear();
    _rootFolders.clear();
    notifyListeners();

    try {
      if (await _checkPermissions()) {
        final scanRoots = _computeScanRoots(_rootPaths);
        for (final path in scanRoots) {
          debugPrint('Starting scan at: $path');

          if (Platform.isAndroid) {
            // Trigger media scanner for each root path on startup
            try {
              await MediaScanner.loadMedia(path: path);
            } catch (e) {
              debugPrint('MediaScanner startup scan error: $e');
            }
          }

          final folder = await _scanDirectory(path);
          _scannedRootFolders.add(
            folder ?? MusicFolder(path: path, name: _displayNameForPath(path)),
          );
        }

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
      _sortAndNotify();
    }
  }

  Future<void> rebuildMetadataDatabase() async {
    if (Platform.isWindows) {
      await MetadataDatabase().clearAll();
      await MetadataHelper.clearThumbnails();
      _metadataMap.clear();
      await scan();

      // Background process to collect all files and update metadata
      unawaited(_backgroundMetadataRebuild());
    }
  }

  Future<void> _backgroundMetadataRebuild() async {
    final List<String> allFilePaths = [];

    void collectFiles(MusicFolder folder) {
      for (final file in folder.files) {
        allFilePaths.add(file.path);
      }
      for (final subFolder in folder.subFolders) {
        collectFiles(subFolder);
      }
    }

    for (final root in _scannedRootFolders) {
      collectFiles(root);
    }

    if (allFilePaths.isEmpty) return;

    debugPrint(
      'Starting background metadata rebuild for ${allFilePaths.length} files',
    );

    // Process in batches or one by one
    for (final path in allFilePaths) {
      await _waitUntilResumed();
      try {
        final result = await MetadataHelper.processMetadata(path);
        SongMetadata? metadata = result?.$1;

        // Metadata update (to update UI metadataMap)
        if (metadata != null) {
          _metadataMap[path] = metadata;
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Error in background metadata rebuild for $path: $e');
      }
    }
    debugPrint('Background metadata rebuild completed');
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
  /// caches it in [metadataMap]. Safe to call multiple times — exits early if
  /// the path is already in the map or if the platform is not Windows.
  Future<void> loadMetadataForPath(String path) async {
    final cached = _metadataMap[path];
    if (cached != null && (cached.thumbnailPath?.isNotEmpty ?? false)) {
      return;
    }

    final db = MetadataDatabase();
    // Try DB first (cheapest); fall back to full processing if not found.
    SongMetadata? metadata = await db.getSongMetadata(path);
    final result = metadata == null
        ? await MetadataHelper.processMetadata(path, generateThumbnail: true)
        : null;
    metadata ??= result?.$1;

    if (metadata != null && !(metadata.thumbnailPath?.isNotEmpty ?? false)) {
      final refreshed = await MetadataHelper.processMetadata(
        path,
        generateThumbnail: true,
      );
      metadata = refreshed?.$1 ?? metadata;
    }

    if (metadata != null) {
      _metadataMap[path] = metadata;
      notifyListeners();
    }
  }

  void updateMetadataForPath(SongMetadata metadata, {Uint8List? artworkBytes}) {
    _metadataMap[metadata.path] = metadata.copyWith(waveformBlob: null);

    // Update MusicFile objects in the tree if they exist
    for (final root in _scannedRootFolders) {
      _updateMusicFileInFolder(root, metadata, artworkBytes: artworkBytes);
    }
    if (_systemMediaFolder != null) {
      _updateMusicFileInFolder(
        _systemMediaFolder!,
        metadata,
        artworkBytes: artworkBytes,
      );
    }

    notifyListeners();
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
          thumbnailPath: metadata.thumbnailPath,
          artworkPath: metadata.artworkPath,
          artworkWidth: metadata.artworkWidth,
          artworkHeight: metadata.artworkHeight,
          themeColorsBlob: metadata.themeColorsBlob,
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

  Future<MusicFolder?> _scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('Directory does not exist: $path');
      return null;
    }

    final List<MusicFolder> subFolders = [];
    final List<MusicFile> files = [];

    try {
      final List<FileSystemEntity> entities = await dir
          .list(followLinks: false)
          .toList();
      debugPrint('Scanning $path: Found ${entities.length} entities');

      for (var entity in entities) {
        if (entity is Directory) {
          // Avoid hidden directories/system folders
          if (p.basename(entity.path).startsWith('.')) continue;

          final subFolder = await _scanDirectory(entity.path);
          if (subFolder != null && !subFolder.isEmpty) {
            subFolders.add(subFolder);
          }
        } else if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_audioExtensions.contains(ext)) {
            String? title;
            String? artist;
            String? album;
            int? trackNumber;
            String? thumbnailPath;
            String? artworkPath;
            int? artworkWidth;
            int? artworkHeight;
            Uint8List? themeColorsBlob;
            int? lastModifiedTime;

            if (Platform.isWindows) {
              final metadata = await _resolveScannedMetadata(
                entity.path,
                fallbackTitle: p.basenameWithoutExtension(entity.path),
                fallbackAlbum: '',
                fallbackArtist: '',
                fallbackDuration: null,
              );
              _metadataMap[entity.path] = metadata.copyWith(waveformBlob: null);
              title = metadata.title;
              artist = metadata.artist;
              album = metadata.album;
              trackNumber = metadata.trackNumber;
              thumbnailPath = metadata.thumbnailPath;
              artworkPath = metadata.artworkPath;
              artworkWidth = metadata.artworkWidth;
              artworkHeight = metadata.artworkHeight;
              themeColorsBlob = metadata.themeColorsBlob;
              lastModifiedTime = metadata.lastModifiedTime;
            }

            files.add(
              MusicFile(
                path: entity.path,
                name: p.basename(entity.path),
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                thumbnailPath: thumbnailPath,
                artworkPath: artworkPath,
                artworkWidth: artworkWidth,
                artworkHeight: artworkHeight,
                themeColorsBlob: themeColorsBlob,
                lastModifiedTime: lastModifiedTime,
                id: null,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing directory $path: $e');
    }

    if (subFolders.isEmpty && files.isEmpty) return null;

    return MusicFolder(
      path: path,
      name: _displayNameForPath(path),
      subFolders: subFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      files: files
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
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
    _rootFolders.sort(
      (a, b) => compareNatural(a.name.toLowerCase(), b.name.toLowerCase()),
    );
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

  @override
  void dispose() {
    _mediaObserverSubscription?.cancel();
    super.dispose();
  }
}
