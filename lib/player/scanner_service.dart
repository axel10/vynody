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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import '../utils/music_sorter.dart';


class ScannerService extends ChangeNotifier {
  final SettingsService? _settingsService;
  AudioCoreController? _playerController;
  final List<String> _rootPaths = [];
  final List<MusicFolder> _rootFolders = [];
  bool _isScanning = false;

  MusicFolder? _systemMediaFolder;
  bool _hasPermission = false;
  final OnAudioQuery _audioQuery = OnAudioQuery();

  SortCriteria _sortCriteria = SortCriteria.filename;
  SortOrder _sortOrder = SortOrder.ascending;

  SortCriteria get sortCriteria => _sortCriteria;
  SortOrder get sortOrder => _sortOrder;

  List<String> get rootPaths => List.unmodifiable(_rootPaths);
  List<MusicFolder> get rootFolders => List.unmodifiable(_rootFolders);
  bool get isScanning => _isScanning;

  MusicFolder? get systemMediaFolder => _systemMediaFolder;
  bool get hasPermission => _hasPermission;
  final Map<String, int> _pathIdMap = {};
  final Map<String, SongMetadata> _metadataMap = {};

  Map<String, SongMetadata> get metadataMap => _metadataMap;

  final List<String> _audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  ScannerService([this._settingsService]) {
    _init();
    _setupMediaObserver();
  }

  void setPlayerController(AudioCoreController controller) {
    _playerController = controller;
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
    MusicSorter.sortFolders(_rootFolders, criteria: _sortCriteria, order: _sortOrder);
    if (_systemMediaFolder != null) {
      MusicSorter.sortFolderRecursive(_systemMediaFolder!, criteria: _sortCriteria, order: _sortOrder);
    }
    notifyListeners();
  }

  Future<void> _init() async {
    await _loadRootPaths();
    await checkAndRequestPermissions();
    // Auto scan on startup
    await scan();
  }

  void _setupMediaObserver() {
    if (Platform.isAndroid) {
      const mediaObserverChannel =
          EventChannel('com.example.pure_player/media_observer');
      mediaObserverChannel.receiveBroadcastStream().listen((event) {
        if (event == 'media_changed' && !_isScanning) {
          debugPrint('Media library change detected, re-scanning system media...');
          scanSystemMedia();
        }
      }, onError: (err) {
        debugPrint('Media observer error: $err');
      });
    }
  }

  Future<void> _loadRootPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('root_paths') ?? [];
    final normalizedPaths = paths.map(_normalizePath).toSet().toList();
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
    if (_rootPaths.any((existing) => _pathsEqual(existing, normalizedPath))) {
      final existingFolder = _rootFolders.firstWhereOrNull(
        (folder) => _pathsEqual(folder.path, normalizedPath),
      );
      return existingFolder != null && !existingFolder.isEmpty;
    }

    _rootPaths.add(normalizedPath);
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
    await _saveRootPaths();
    _rootFolders.removeWhere((f) => _pathsEqual(f.path, normalizedPath));
    notifyListeners();
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
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
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final List<SongModel> songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      _pathIdMap.clear();
      _metadataMap.clear();
      for (var song in songs) {
        _pathIdMap[song.data] = song.id;
        _metadataMap[song.data] = SongMetadata(
          path: song.data,
          title: song.title,
          album: song.album ?? '',
          artist: song.artist ?? '',
          duration: song.duration,
          trackNumber: song.track,
        );
      }

      _systemMediaFolder = _organizeSongsIntoFolders(songs);
      _sortAndNotify();

      unawaited(_processAndSaveAndroidSongsBackground(songs));
    } catch (e) {
      debugPrint('Error scanning system media: $e');
    }
  }

  Future<void> _processAndSaveAndroidSongsBackground(
    List<SongModel> songs,
  ) async {
    final player = _playerController;
    if (player == null) {
      debugPrint('Player controller not set for background scanning');
      return;
    }

    try {
      // Ensure the shared player is initialized (idempotent)
      await player.initialize();
    } catch (e) {
      debugPrint('Failed to initialize shared player for background scanning: $e');
      return;
    }

    try {
      for (var song in songs) {
        try {
          // Use the unified MetadataHelper to process metadata.
          // This will extract tags, save thumbnails, and generate theme colors.
          final result = await MetadataHelper.processMetadata(
            song.data,
            songId: song.id,
          );
          final metadata = result?.$1;

          if (metadata != null) {
            // After common metadata is processed, check if waveform is needed.
            if (metadata.waveformBlob == null) {
              try {
                final waveform = await player.getWaveform(
                  expectedChunks: _settingsService?.waveformChunks ?? 80,
                  sampleStride: _settingsService?.sampleStride ?? 4,
                  filePath: song.data,
                );
                if (waveform.isNotEmpty) {
                  final float32List = Float32List.fromList(
                    waveform.map((e) => e.toDouble()).toList(),
                  );
                  final waveformBlob = float32List.buffer.asUint8List();

                  // Update the DB with the waveform
                  final updatedMetadata = SongMetadata(
                    id: metadata.id,
                    path: metadata.path,
                    title: metadata.title,
                    album: metadata.album,
                    artist: metadata.artist,
                    duration: metadata.duration,
                    artworkPath: metadata.artworkPath,
                    artworkWidth: metadata.artworkWidth,
                    artworkHeight: metadata.artworkHeight,
                    trackNumber: metadata.trackNumber,
                    themeColorsBlob: metadata.themeColorsBlob,
                    waveformBlob: waveformBlob,
                  );
                  await MetadataDatabase().insertOrUpdateSong(updatedMetadata);
                }
              } catch (e) {
                debugPrint('Waveform extraction failed for scan: $e');
              }
            }
          }
        } catch (e) {
          debugPrint('Background processing error for ${song.data}: $e');
        }

        // Yield to event loop to avoid UI jank
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      // We no longer dispose the shared player here
    }
  }

  MusicFolder _organizeSongsIntoFolders(List<SongModel> songs) {
    // Map to keep track of folder paths to MusicFolder objects
    final Map<String, List<MusicFile>> folderFiles = {};
    final Set<String> allPaths = {};

    for (var song in songs) {
      final path = song.data;
      final file = MusicFile(
        path: path,
        name: p.basename(path),
        title: song.title,
        artist: song.artist,
        album: song.album,
        trackNumber: song.track,
        id: song.id,
      );
      final dirPath = p.dirname(path);

      folderFiles.putIfAbsent(dirPath, () => []).add(file);

      // Collect all parent directories
      String current = dirPath;
      while (current.isNotEmpty && current != '/' && current != '.') {
        allPaths.add(current);
        final parent = p.dirname(current);
        if (parent == current) break;
        current = parent;
      }
    }

    // Now build the tree. We need a root. For system media, we can use a virtual root.
    // Or find the common ancestor. Let's just create a virtual root "系统媒体库"

    // Refined tree building:
    // 1. Identify all directories that contain songs.
    // 2. Identify all intermediate directories.
    // 3. Find the entry points (directories whose parents are not in the set).

    final List<String> entryPoints = allPaths.where((path) {
      final parent = p.dirname(path);
      return !allPaths.contains(parent);
    }).toList();

    if (entryPoints.isEmpty && songs.isEmpty) {
      return MusicFolder(path: 'system', name: '系统媒体库');
    }

    // If there's only one entry point and no files in higher levels, we could collapse it,
    // but usually there are multiple entry points (SD card vs Internal).

    final List<MusicFolder> topFolders = entryPoints
        .map((path) => _recursiveBuild(path, allPaths, folderFiles))
        .toList();

    return MusicFolder(
      path: 'system',
      name: '系统媒体库',
      subFolders: topFolders,
      files: [], // Usually songs are in subfolders
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
      subFolders: subFolders,
      files: files,
    );
  }

  Future<void> scan() async {
    if (_rootPaths.isEmpty) return;

    if (_pathIdMap.isEmpty && _hasPermission) {
      await scanSystemMedia();
    }

    _isScanning = true;
    _rootFolders.clear();
    notifyListeners();

    try {
      if (await _checkPermissions()) {
        for (final path in _rootPaths) {
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
          _rootFolders.add(
            folder ?? MusicFolder(path: path, name: _displayNameForPath(path)),
          );
        }
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

    for (final root in _rootFolders) {
      collectFiles(root);
    }

    if (allFilePaths.isEmpty) return;

    debugPrint(
      'Starting background metadata rebuild for ${allFilePaths.length} files',
    );

    // Process in batches or one by one
    for (final path in allFilePaths) {
      try {
        final result = await MetadataHelper.processMetadata(path);
        SongMetadata? metadata = result?.$1;

        // Extract waveform if missing
        if (metadata != null && metadata.waveformBlob == null && _playerController != null) {
          try {
            final waveform = await _playerController!.getWaveform(
              expectedChunks: _settingsService?.waveformChunks ?? 80,
              sampleStride: _settingsService?.sampleStride ?? 4,
              filePath: path,
            );
            if (waveform.isNotEmpty) {
              final float32List = Float32List.fromList(
                waveform.map((e) => e.toDouble()).toList(),
              );
              final waveformBlob = float32List.buffer.asUint8List();

              metadata = SongMetadata(
                id: metadata.id,
                path: metadata.path,
                title: metadata.title,
                album: metadata.album,
                artist: metadata.artist,
                duration: metadata.duration,
                artworkPath: metadata.artworkPath,
                artworkWidth: metadata.artworkWidth,
                artworkHeight: metadata.artworkHeight,
                trackNumber: metadata.trackNumber,
                themeColorsBlob: metadata.themeColorsBlob,
                waveformBlob: waveformBlob,
              );
              await MetadataDatabase().insertOrUpdateSong(metadata);
            }
          } catch (e) {
            debugPrint('Waveform extraction failed for background rebuild: $e');
          }
        }

        // To update UI immediately if user is looking at it:
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

  /// Loads metadata for a single path from the DB (or processes it fresh) and
  /// caches it in [metadataMap]. Safe to call multiple times — exits early if
  /// the path is already in the map or if the platform is not Windows.
  Future<void> loadMetadataForPath(String path) async {
    if (_metadataMap.containsKey(path)) return;

    final db = MetadataDatabase();
    // Try DB first (cheapest); fall back to full processing if not found.
    SongMetadata? metadata = await db.getSongMetadata(path);
    final result = metadata == null ? await MetadataHelper.processMetadata(path) : null;
    metadata ??= result?.$1;

    if (metadata != null) {
      _metadataMap[path] = metadata;
      notifyListeners();
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
            final id = _pathIdMap[entity.path];

            String? title;
            String? artist;
            String? album;
            int? trackNumber;

            if (Platform.isWindows) {
              // Avoid expensive per-file parsing during directory crawl.
              // Thumbnail/title metadata is loaded lazily when list items build.
              final metadata = await MetadataDatabase().getSongMetadata(
                entity.path,
              );
              if (metadata != null) {
                _metadataMap[entity.path] = metadata;
                title = metadata.title;
                artist = metadata.artist;
                album = metadata.album;
                trackNumber = metadata.trackNumber;
              }
            }

            files.add(
              MusicFile(
                path: entity.path,
                name: p.basename(entity.path),
                title: title,
                artist: artist,
                album: album,
                trackNumber: trackNumber,
                id: id,
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
      subFolders: subFolders,
      files: files,
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

  bool _pathsEqual(String left, String right) {
    final normalizedLeft = _normalizePath(left);
    final normalizedRight = _normalizePath(right);
    if (Platform.isWindows) {
      return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    }
    return normalizedLeft == normalizedRight;
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
}
