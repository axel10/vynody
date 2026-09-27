import 'package:collection/collection.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'layout_constants.dart';

const double folderPageMaxWidth = kFolderPageMaxWidth;

bool hasSongArtwork(MusicFile? file) =>
    file != null &&
    ((file.artworkPath != null && file.artworkPath!.isNotEmpty) ||
        (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) ||
        (file.artworkBytes != null && file.artworkBytes!.isNotEmpty));

MusicFile? findRepresentativeSong(MusicFolder folder) {
  if (folder.representativeSongCache != null &&
      hasSongArtwork(folder.representativeSongCache)) {
    return folder.representativeSongCache;
  }
  if (folder.isEmpty) return null;

  final fileWithArtwork = folder.files.firstWhereOrNull(hasSongArtwork);
  if (fileWithArtwork != null) {
    folder.representativeSongCache = fileWithArtwork;
    return fileWithArtwork;
  }

  for (final sub in folder.subFolders) {
    final subRep = findRepresentativeSong(sub);
    if (subRep != null && hasSongArtwork(subRep)) {
      folder.representativeSongCache = subRep;
      return subRep;
    }
  }

  // 3. Fallback when thumbnails have not been generated yet (e.g. freshly scanned):
  // Pick the first candidate song (direct files first, then subfolders) in current sort order
  // so SongThumbnail can trigger lazy thumbnail extraction without requiring user to drill down.
  // Note: we intentionally do not cache unparsed fallback songs in representativeSongCache.
  if (folder.files.isNotEmpty) {
    return folder.files.first;
  }

  for (final sub in folder.subFolders) {
    final subRep = findRepresentativeSong(sub);
    if (subRep != null) {
      return subRep;
    }
  }

  return null;
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

