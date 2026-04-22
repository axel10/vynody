import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/music_folder.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

class ScannerMetadataStore {
  ScannerMetadataStore({
    required Iterable<MusicFolder> Function() rootFolders,
    required MusicFolder? Function() systemMediaFolder,
    required void Function() notifyListeners,
    required void Function() scheduleMetadataNotify,
    required void Function() onMetadataMutated,
    required void Function(String path, bool isMissing) notifySongMissingState,
    required String Function(String path) normalizePath,
    required bool Function(String left, String right) pathsEqual,
  }) : _rootFolders = rootFolders,
       _systemMediaFolder = systemMediaFolder,
       _notifyListeners = notifyListeners,
       _scheduleMetadataNotify = scheduleMetadataNotify,
       _onMetadataMutated = onMetadataMutated,
       _notifySongMissingState = notifySongMissingState,
       _normalizePath = normalizePath,
       _pathsEqual = pathsEqual;

  final Iterable<MusicFolder> Function() _rootFolders;
  final MusicFolder? Function() _systemMediaFolder;
  final void Function() _notifyListeners;
  final void Function() _scheduleMetadataNotify;
  final void Function() _onMetadataMutated;
  final void Function(String path, bool isMissing) _notifySongMissingState;
  final String Function(String path) _normalizePath;
  final bool Function(String left, String right) _pathsEqual;

  final Map<String, SongMetadata> _metadataMap = {};

  Map<String, SongMetadata> get metadataMap => _metadataMap;

  SongMetadata? getMetadata(String path) => _metadataMap[path];

  void _logTiming(String label, Stopwatch stopwatch) {
    if (!kDebugMode) return;
    // debugPrint(
    //   '[ScannerMetadataStore][timing] $label ${stopwatch.elapsedMilliseconds} ms',
    // );
  }

  void cacheMetadata(SongMetadata metadata) {
    _metadataMap[metadata.path] = metadata.copyWith(waveformBlob: null);
    _onMetadataMutated();
  }

  void clear() {
    _metadataMap.clear();
    _onMetadataMutated();
  }

  Future<void> loadMetadataForPath(String path) async {
    final stopwatch = Stopwatch()..start();
    if (!await File(path).exists()) {
      await purgeMissingSongPath(path);
      stopwatch.stop();
      _logTiming('loadMetadataForPath missing($path)', stopwatch);
      return;
    }

    final cached = _metadataMap[path];
    if (cached != null) {
      return;
    }

    final db = MetadataDatabase();
    SongMetadata? metadata = await db.getSongMetadata(path);
    final result = metadata == null
        ? await MetadataHelper.processMetadata(path, generateThumbnail: false)
        : null;
    metadata ??= result?.$1;

    if (metadata != null) {
      _metadataMap[path] = metadata;
      _onMetadataMutated();
      _notifyListeners();
    }
    stopwatch.stop();
    _logTiming('loadMetadataForPath($path)', stopwatch);
  }

  Future<void> loadThumbnailForPath(String path) async {
    final stopwatch = Stopwatch()..start();
    if (!await File(path).exists()) {
      await purgeMissingSongPath(path);
      stopwatch.stop();
      _logTiming('loadThumbnailForPath missing($path)', stopwatch);
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
      _onMetadataMutated();
      _notifyListeners();
      return;
    }

    final result = await MetadataHelper.processMetadata(
      path,
      generateThumbnail: true,
    );
    metadata = result?.$1 ?? metadata;

    if (metadata != null) {
      _metadataMap[path] = metadata;
      _onMetadataMutated();
      _notifyListeners();
    }
    stopwatch.stop();
    _logTiming('loadThumbnailForPath($path)', stopwatch);
  }

  void updateMetadataForPath(
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
    _onMetadataMutated();

    for (final root in _rootFolders()) {
      _updateMusicFileInFolder(
        root,
        mergedMetadata,
        artworkBytes: artworkBytes,
      );
    }
    final systemFolder = _systemMediaFolder();
    if (systemFolder != null) {
      _updateMusicFileInFolder(
        systemFolder,
        mergedMetadata,
        artworkBytes: artworkBytes,
      );
    }

    if (notify) {
      _notifyListeners();
    } else {
      _scheduleMetadataNotify();
    }
  }

  Future<void> purgeMissingSongPath(String path) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return;

    _notifySongMissingState(normalizedPath, true);

    for (final root in _rootFolders()) {
      _removeSongFromFolder(root, normalizedPath);
    }
    final systemFolder = _systemMediaFolder();
    if (systemFolder != null) {
      _removeSongFromFolder(systemFolder, normalizedPath);
    }

    await MetadataDatabase().deleteSongByPath(normalizedPath);
    _onMetadataMutated();
    _notifyListeners();
  }

  void deleteMissingFromCache(Iterable<String> paths) {
    var changed = false;
    for (final path in paths) {
      changed = _metadataMap.remove(path) != null || changed;
    }
    if (changed) {
      _onMetadataMutated();
    }
  }

  void removeMetadataForPath(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) return;
    final beforeLength = _metadataMap.length;
    _metadataMap.removeWhere((key, _) => _pathsEqual(key, normalizedPath));
    if (_metadataMap.length != beforeLength) {
      _onMetadataMutated();
    }
  }

  void clearWaveformForPath(String path) {
    final existing = _metadataMap[path];
    if (existing == null) return;
    _metadataMap[path] = existing.copyWith(waveformBlob: null);
    _onMetadataMutated();
  }

  bool containsPath(String path) {
    return _metadataMap.containsKey(path);
  }

  void _updateMusicFileInFolder(
    MusicFolder folder,
    SongMetadata metadata, {
    Uint8List? artworkBytes,
  }) {
    for (var i = 0; i < folder.files.length; i++) {
      final file = folder.files[i];
      if (_pathsEqual(file.path, metadata.path)) {
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

  bool _removeSongFromFolder(MusicFolder folder, String path) {
    folder.files.removeWhere((file) => _pathsEqual(file.path, path));

    folder.subFolders.removeWhere((subFolder) {
      final shouldRemove = _removeSongFromFolder(subFolder, path);
      return shouldRemove;
    });

    return folder.isEmpty;
  }
}
