import 'package:path/path.dart' as p;

import 'package:audio_core/audio_core.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../models/music_file.dart';
import '../models/music_folder.dart';
import 'metadata_database.dart';
import 'scanner_path_utils.dart';

class ScannerTreeBuilder {
  ScannerTreeBuilder({
    required String Function(String path) normalizePath,
    required bool Function(String left, String right) pathsEqual,
  }) : _normalizePath = normalizePath,
       _pathsEqual = pathsEqual;

  final String Function(String path) _normalizePath;
  final bool Function(String left, String right) _pathsEqual;

  MusicFolder buildAndroidMediaLibrary(
    List<AndroidMediaLibraryEntry> entries,
    Map<String, SongMetadata> metadataByPath,
    int Function(String a, String b) compareNaturally,
  ) {
    final items = <_FolderItem>[];
    for (final entry in entries) {
      final filePath = _androidEntryFilePath(entry);
      if (filePath == null) continue;
      items.add(
        _FolderItem(
          file: _musicFileFromAndroidEntry(
            entry,
            path: filePath,
            metadata: metadataByPath[filePath],
          ),
          folderPath: _normalizeAndroidFolderPath(entry.folderPath),
        ),
      );
    }

    return _buildFolderTree(
      items,
      compareNaturally,
      rootPath: 'system',
      rootName: '系统媒体库',
    );
  }

  MusicFolder buildSongsIntoFoldersFromMetadata(
    Iterable<SongMetadata> songs,
    int Function(String a, String b) compareNaturally,
  ) {
    return buildFolderTreeFromMetadata(
      songs,
      compareNaturally,
      rootPath: 'system',
      rootName: '系统媒体库',
    );
  }

  MusicFolder buildFolderTreeFromMetadata(
    Iterable<SongMetadata> songs,
    int Function(String a, String b) compareNaturally, {
    required String rootPath,
    required String rootName,
  }) {
    final items = <_FolderItem>[];
    for (final song in songs) {
      final normalizedPath = _normalizePath(song.path);
      if (normalizedPath.isEmpty) continue;
      items.add(
        _FolderItem(
          file: _musicFileFromSongMetadata(song.copyWith(path: normalizedPath)),
          folderPath: p.dirname(normalizedPath),
        ),
      );
    }

    return _buildFolderTree(
      items,
      compareNaturally,
      rootPath: rootPath,
      rootName: rootName,
    );
  }

  MusicFolder buildSongsIntoFolders(
    List<SongModel> songs,
    Map<String, SongMetadata> metadataByPath,
    int Function(String a, String b) compareNaturally,
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
        .map(
          (path) =>
              _recursiveBuild(path, allPaths, folderFiles, compareNaturally),
        )
        .toList();

    return MusicFolder(
      path: 'system',
      name: '系统媒体库',
      subFolders: topFolders
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      files: [],
    );
  }

  void collectFilePaths(MusicFolder folder, Set<String> out) {
    for (final file in folder.files) {
      out.add(_normalizePath(file.path));
    }
    for (final subFolder in folder.subFolders) {
      collectFilePaths(subFolder, out);
    }
  }

  bool removeSongFromFolder(MusicFolder folder, String path) {
    folder.files.removeWhere((file) => _pathsEqual(file.path, path));

    folder.subFolders.removeWhere((subFolder) {
      final shouldRemove = removeSongFromFolder(subFolder, path);
      return shouldRemove;
    });

    return folder.isEmpty;
  }

  MusicFolder? resolveFolderForPath(
    String path,
    Iterable<MusicFolder> scannedRootFolders,
    MusicFolder? systemMediaFolder,
  ) {
    final normalizedPath = _normalizePath(path);

    for (final root in scannedRootFolders) {
      final resolved = _findFolderInTree(root, normalizedPath);
      if (resolved != null) return resolved;
    }

    if (systemMediaFolder != null) {
      final resolved = _findFolderInTree(systemMediaFolder, normalizedPath);
      if (resolved != null) return resolved;
    }

    return null;
  }

  bool isShortcutRoot({
    required String path,
    required Iterable<String> declaredRootPaths,
  }) {
    return ScannerPathUtils.isShortcutRoot(
      path: path,
      declaredRootPaths: declaredRootPaths,
    );
  }

  MusicFile musicFileFromAndroidEntry(
    AndroidMediaLibraryEntry entry, {
    required String path,
    SongMetadata? metadata,
  }) {
    return _musicFileFromAndroidEntry(entry, path: path, metadata: metadata);
  }

  MusicFile musicFileFromSongModel(SongModel song, {SongMetadata? metadata}) {
    return _musicFileFromSongModel(song, metadata: metadata);
  }

  MusicFile _musicFileFromSongMetadata(SongMetadata song) {
    return MusicFile(
      path: song.path,
      name: p.basename(song.path),
      title: _cleanText(song.title),
      artist: _cleanText(song.artist),
      album: _cleanText(song.album),
      trackNumber: song.trackNumber,
      durationMillis: song.duration,
      thumbnailPath: song.thumbnailPath,
      artworkPath: song.artworkPath,
      artworkWidth: song.artworkWidth,
      artworkHeight: song.artworkHeight,
      themeColorsBlob: song.themeColorsBlob,
      waveformBlob: song.waveformBlob,
      lastModifiedTime: song.lastModifiedTime,
    );
  }

  MusicFolder _buildFolderTree(
    List<_FolderItem> items,
    int Function(String a, String b) compareNaturally, {
    required String rootPath,
    required String rootName,
  }) {
    final root = MusicFolder(path: rootPath, name: rootName);
    final nodes = <String, MusicFolder>{'': root};

    for (final item in items) {
      final folderPath = item.folderPath;
      if (folderPath.isEmpty) {
        root.files.add(item.file);
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

      currentFolder.files.add(item.file);
    }

    _sortFolderRecursive(root, compareNaturally);
    return root;
  }

  MusicFolder _recursiveBuild(
    String currentPath,
    Set<String> allPaths,
    Map<String, List<MusicFile>> folderFiles,
    int Function(String a, String b) compareNaturally,
  ) {
    final subFolderPaths = allPaths
        .where((path) => p.dirname(path) == currentPath)
        .toList();
    final subFolders = subFolderPaths
        .map(
          (path) =>
              _recursiveBuild(path, allPaths, folderFiles, compareNaturally),
        )
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
        ..sort(
          (a, b) =>
              compareNaturally(a.name.toLowerCase(), b.name.toLowerCase()),
        ),
    );
  }

  MusicFolder? _findFolderInTree(MusicFolder folder, String path) {
    if (_pathsEqual(folder.path, path)) return folder;

    for (final subFolder in folder.subFolders) {
      final resolved = _findFolderInTree(subFolder, path);
      if (resolved != null) return resolved;
    }

    return null;
  }

  void _sortFolderRecursive(
    MusicFolder folder,
    int Function(String a, String b) compareNaturally,
  ) {
    folder.subFolders.sort((a, b) => compareNaturally(a.name, b.name));
    folder.files.sort((a, b) => compareNaturally(a.name, b.name));
    for (final sub in folder.subFolders) {
      _sortFolderRecursive(sub, compareNaturally);
    }
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

  String? _cleanText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

class _FolderItem {
  final MusicFile file;
  final String folderPath;

  const _FolderItem({required this.file, required this.folderPath});
}
