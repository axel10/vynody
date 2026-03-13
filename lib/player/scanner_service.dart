import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'theme_color_helper.dart';

enum SortCriteria { title, filename, trackNumber }

enum SortOrder { ascending, descending }

class ScannerService extends ChangeNotifier {
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

  ScannerService() {
    _init();
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
    _sortFolders(_rootFolders);
    if (_systemMediaFolder != null) {
      _sortFolderRecursive(_systemMediaFolder!);
    }
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
          (a.title ?? a.name).toLowerCase(),
          (b.title ?? b.name).toLowerCase(),
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
      _sortFolderRecursive(_systemMediaFolder!);
      notifyListeners();

      unawaited(_processAndSaveAndroidSongsBackground(songs));
    } catch (e) {
      debugPrint('Error scanning system media: $e');
    }
  }

  Future<void> _processAndSaveAndroidSongsBackground(
    List<SongModel> songs,
  ) async {
    final db = MetadataDatabase();
    for (var song in songs) {
      try {
        final existing = await db.getSongMetadata(song.data);
        if (existing != null && existing.themeColorsBlob != null) {
          continue;
        }

        Uint8List? themeColorsBlob;
        final artworkBytes = await _audioQuery.queryArtwork(
          song.id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 200,
          quality: 100,
        );

        if (artworkBytes != null) {
          final imageProvider = MemoryImage(artworkBytes);
          final palette = await PaletteGenerator.fromImageProvider(
            imageProvider,
            maximumColorCount: 20,
          );
          themeColorsBlob = ThemeColorHelper.paletteToBlob(palette);
        }

        final songMetadata = SongMetadata(
          path: song.data,
          title: song.title,
          album: song.album ?? '',
          artist: song.artist ?? '',
          duration: song.duration,
          trackNumber: song.track,
          themeColorsBlob: themeColorsBlob,
        );

        await db.insertOrUpdateSong(songMetadata);
      } catch (e) {
        debugPrint('Background processing error for ${song.data}: $e');
      }

      // Yield to event loop to avoid UI jank
      await Future.delayed(const Duration(milliseconds: 100));
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
      subFolders: topFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
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
      subFolders: subFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      files: files
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
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
    }
  }

  /// Loads metadata for a single path from the DB (or processes it fresh) and
  /// caches it in [metadataMap]. Safe to call multiple times — exits early if
  /// the path is already in the map or if the platform is not Windows.
  Future<void> loadMetadataForPath(String path) async {
    if (!Platform.isWindows) return;
    if (_metadataMap.containsKey(path)) return;

    final db = MetadataDatabase();
    // Try DB first (cheapest); fall back to full processing if not found.
    SongMetadata? metadata = await db.getSongMetadata(path);
    metadata ??= await MetadataHelper.processMetadata(path);

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
                trackNumber = metadata.trackNumber;
              }
            }

            files.add(
              MusicFile(
                path: entity.path,
                name: p.basename(entity.path),
                title: title,
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
