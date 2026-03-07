import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

class MusicFile {
  final String path;
  final String name;
  final int? id; // System Media Library ID

  MusicFile({required this.path, required this.name, this.id});
}

class MusicFolder {
  final String path;
  final String name;
  final List<MusicFolder> subFolders;
  final List<MusicFile> files;

  MusicFolder({
    required this.path,
    required this.name,
    this.subFolders = const [],
    this.files = const [],
  });

  bool get isEmpty => subFolders.isEmpty && files.isEmpty;
}

class ScannerService extends ChangeNotifier {
  final List<String> _rootPaths = [];
  final List<MusicFolder> _rootFolders = [];
  bool _isScanning = false;

  MusicFolder? _systemMediaFolder;
  bool _hasPermission = false;
  final OnAudioQuery _audioQuery = OnAudioQuery();

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

  Future<void> _init() async {
    await _loadRootPaths();
    await checkAndRequestPermissions();
    // Auto scan on startup
    await scan();
  }

  Future<void> _loadRootPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList('root_paths') ?? [];
    _rootPaths.clear();
    _rootPaths.addAll(paths);
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

  Future<void> addRootPath(String path) async {
    if (_rootPaths.contains(path)) return;
    _rootPaths.add(path);
    await _saveRootPaths();
    notifyListeners();

    if (Platform.isAndroid) {
      try {
        await MediaScanner.loadMedia(path: path);
      } catch (e) {
        debugPrint('MediaScanner error: $e');
      }
    }

    await scan();
  }

  Future<void> removeRootPath(String path) async {
    _rootPaths.remove(path);
    await _saveRootPaths();
    _rootFolders.removeWhere((f) => f.path == path);
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
      for (var song in songs) {
        _pathIdMap[song.data] = song.id;
      }

      _systemMediaFolder = _organizeSongsIntoFolders(songs);
      notifyListeners();
    } catch (e) {
      debugPrint('Error scanning system media: $e');
    }
  }

  MusicFolder _organizeSongsIntoFolders(List<SongModel> songs) {
    // Map to keep track of folder paths to MusicFolder objects
    final Map<String, List<MusicFile>> folderFiles = {};
    final Set<String> allPaths = {};

    for (var song in songs) {
      final path = song.data;
      final file = MusicFile(path: path, name: p.basename(path), id: song.id);
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
          if (folder != null) {
            _rootFolders.add(folder);
          }
        }
      } else {
        debugPrint('Scan aborted: Permission not granted.');
      }
    } catch (e) {
      debugPrint('Scan error: $e');
    } finally {
      _isScanning = false;
      _rootFolders.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      notifyListeners();
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

  Future<MusicFolder?> _scanDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      debugPrint('Directory does not exist: $path');
      return null;
    }

    final List<MusicFolder> subFolders = [];
    final List<MusicFile> files = [];

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
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

            if (Platform.isWindows) {
              final metadata = await MetadataHelper.processMetadata(
                entity.path,
              );
              if (metadata != null) {
                _metadataMap[entity.path] = metadata;
              }
            }

            files.add(
              MusicFile(
                path: entity.path,
                name: p.basename(entity.path),
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
      name: p.basename(path),
      subFolders: subFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      files: files
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }
}
