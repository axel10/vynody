import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class MusicFile {
  final String path;
  final String name;

  MusicFile({required this.path, required this.name});
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

  List<String> get rootPaths => List.unmodifiable(_rootPaths);
  List<MusicFolder> get rootFolders => List.unmodifiable(_rootFolders);
  bool get isScanning => _isScanning;

  final List<String> _audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  Future<void> addRootPath(String path) async {
    if (_rootPaths.contains(path)) return;
    _rootPaths.add(path);
    notifyListeners();
    await scan();
  }

  Future<void> removeRootPath(String path) async {
    _rootPaths.remove(path);
    _rootFolders.removeWhere((f) => f.path == path);
    notifyListeners();
  }

  Future<bool> _checkPermissions() async {
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ requires Permission.audio
        final status = await Permission.audio.request();
        if (!status.isGranted) {
          debugPrint('Audio permission denied');
          return false;
        }
      } else {
        // Legacy storage permission
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          debugPrint('Storage permission denied');
          return false;
        }
      }
    }
    return true;
  }

  Future<void> scan() async {
    if (_rootPaths.isEmpty) return;

    _isScanning = true;
    _rootFolders.clear();
    notifyListeners();

    try {
      if (await _checkPermissions()) {
        for (final path in _rootPaths) {
          debugPrint('Starting scan at: $path');
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
            files.add(
              MusicFile(path: entity.path, name: p.basename(entity.path)),
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
