import 'package:collection/collection.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'layout_constants.dart';

import 'package:vynody/player/metadata/metadata_database.dart';

const double folderPageMaxWidth = kFolderPageMaxWidth;

bool hasSongArtwork(MusicFile? file) =>
    file != null &&
    ((file.artworkPath != null && file.artworkPath!.isNotEmpty) ||
        (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) ||
        (file.artworkBytes != null && file.artworkBytes!.isNotEmpty));

/// Evaluates representative song for a single folder [folder].
/// Priority 1: Direct file with artwork
/// Priority 2: Direct subfolder representative with artwork
/// Returns null if neither direct files nor subfolders have artwork,
/// ensuring only folders with actual artwork are recorded in FolderCovers.
MusicFile? evaluateRepresentativeSongForFolder(
  MusicFolder folder, {
  Map<String, SongMetadata>? metadataByPath,
  String Function(String path)? normalizePath,
}) {
  bool hasArtwork(MusicFile file) {
    if (hasSongArtwork(file)) return true;
    if (metadataByPath != null) {
      final key = normalizePath != null ? normalizePath(file.path) : file.path;
      final meta = metadataByPath[key] ?? metadataByPath[file.path];
      if (meta != null) {
        return (meta.artworkPath != null && meta.artworkPath!.isNotEmpty) ||
            (meta.thumbnailPath != null && meta.thumbnailPath!.isNotEmpty);
      }
    }
    return false;
  }

  // Priority 1: Direct file with artwork
  MusicFile? selected = folder.files.firstWhereOrNull(hasArtwork);

  // Priority 2: Subfolder representative with artwork
  if (selected == null) {
    for (final sub in folder.subFolders) {
      final subRep = sub.representativeSongCache;
      if (subRep != null && hasArtwork(subRep)) {
        selected = subRep;
        break;
      }
    }
  }

  // Priority 3: Fallback to direct file (preferring formats likely to have embedded art, e.g. flac/mp3/m4a/ogg/opus)
  if (selected == null && folder.files.isNotEmpty) {
    selected = folder.files.firstWhereOrNull((f) {
      final dotIdx = f.path.lastIndexOf('.');
      if (dotIdx < 0) return false;
      final ext = f.path.substring(dotIdx + 1).toLowerCase();
      return ext == 'flac' || ext == 'mp3' || ext == 'm4a' || ext == 'ogg' || ext == 'opus';
    }) ?? folder.files.firstOrNull;
  }

  // Priority 4: Fallback to first subfolder representative
  if (selected == null) {
    for (final sub in folder.subFolders) {
      final subRep = sub.representativeSongCache;
      if (subRep != null) {
        selected = subRep;
        break;
      }
    }
  }

  return selected;
}

/// Computes representative songs for all folders in the subtree rooted at [root]
/// using a bottom-up (post-order DFS) traversal.
/// Returns a map of `normalizedFolderPath -> normalizedSongPath`.
Map<String, String> computeFolderCoversBottomUp(
  MusicFolder root, {
  Map<String, SongMetadata>? metadataByPath,
  String Function(String path)? normalizePath,
}) {
  final result = <String, String>{};
  final normalize = normalizePath ?? (p) => p;

  void postOrder(MusicFolder folder) {
    // 1. Recurse into all subfolders first (bottom-up)
    for (final sub in folder.subFolders) {
      postOrder(sub);
    }

    // 2. Select representative song for this folder
    final selected = evaluateRepresentativeSongForFolder(
      folder,
      metadataByPath: metadataByPath,
      normalizePath: normalizePath,
    );

    if (selected != null) {
      final normFolder = normalize(folder.path);
      final normSong = normalize(selected.path);
      result[normFolder] = normSong;
      folder.representativeSongCache = selected;
    } else {
      folder.representativeSongCache = null;
    }
  }

  postOrder(root);
  return result;
}

MusicFile? findRepresentativeSong(
  MusicFolder folder, {
  Map<String, SongMetadata>? metadataByPath,
  String Function(String path)? normalizePath,
}) {
  if (folder.representativeSongCache != null &&
      hasSongArtwork(folder.representativeSongCache)) {
    return folder.representativeSongCache;
  }
  if (folder.isEmpty) return null;

  computeFolderCoversBottomUp(
    folder,
    metadataByPath: metadataByPath,
    normalizePath: normalizePath,
  );
  return folder.representativeSongCache;
}


bool isUserRootSelectionContext(
  ScannerService scanner,
  MusicFolder? currentFolder,
  List<MusicFolder> navigationHistory,
) {
  if (currentFolder == null) return false;

  final rootPaths = scanner.rootFolders.map((folder) => folder.path).toSet();
  rootPaths.add('system');
  if (rootPaths.contains(currentFolder.path)) {
    return true;
  }

  if (navigationHistory.isNotEmpty) {
    final rootFolder = navigationHistory.first;
    if (rootPaths.contains(rootFolder.path)) {
      return true;
    }
  }

  return false;
}

String formatDurationMs(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '0:00';
  final duration = Duration(milliseconds: durationMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

