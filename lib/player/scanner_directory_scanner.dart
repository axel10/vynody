import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'music_file_utils.dart';
import 'scanner_scan_support.dart';

class ScannerDirectoryScanner {
  ScannerDirectoryScanner({
    required String Function(String path) displayNameForPath,
    required bool Function(String left, String right) pathsEqual,
    required int Function(String a, String b) compareNaturally,
    required void Function(ScanProgressState scanState, String filePath)
    emitScanProgress,
  }) : _displayNameForPath = displayNameForPath,
       _pathsEqual = pathsEqual,
       _compareNaturally = compareNaturally,
       _emitScanProgress = emitScanProgress;

  final String Function(String path) _displayNameForPath;
  final bool Function(String left, String right) _pathsEqual;
  final int Function(String a, String b) _compareNaturally;
  final void Function(ScanProgressState scanState, String filePath)
  _emitScanProgress;

  Future<bool> scanDirectoryInto(
    MusicFolder folder,
    String path,
    ScanProgressState scanState, {
    required void Function() notifyListeners,
  }) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      return false;
    }

    bool hasContent = false;

    try {
      final List<FileSystemEntity> entities = await dir
          .list(followLinks: false)
          .toList();

      final directories = <Directory>[];
      final audioFiles = <File>[];

      for (var entity in entities) {
        if (entity is Directory) {
          if (p.basename(entity.path).startsWith('.')) continue;
          directories.add(entity);
        } else if (entity is File) {
          if (MusicFileUtils.isMusicFilePath(entity.path)) {
            audioFiles.add(entity);
          }
        }
      }

      directories.sort((a, b) => _compareNaturally(a.path, b.path));
      audioFiles.sort((a, b) => _compareNaturally(a.path, b.path));

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
        final subFolderHasContent = await scanDirectoryInto(
          subFolder,
          entity.path,
          scanState,
          notifyListeners: notifyListeners,
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
    } catch (_) {
      // Swallow and continue scanning sibling paths; caller handles logging.
    }

    _sortFolderRecursive(folder);
    return hasContent;
  }

  void _sortFolderRecursive(MusicFolder folder) {
    folder.subFolders.sort((a, b) => _compareNaturally(a.name, b.name));
    folder.files.sort((a, b) => _compareNaturally(a.name, b.name));
    for (final sub in folder.subFolders) {
      _sortFolderRecursive(sub);
    }
  }
}
