import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_service.dart';

MusicFile? findRepresentativeSong(MusicFolder folder) {
  for (final file in folder.files) {
    if (file.thumbnailPath != null || file.id != null) {
      return file;
    }
  }
  for (final song in folder.allSongs) {
    if (song.thumbnailPath != null || song.id != null) {
      return song;
    }
  }
  if (folder.files.isNotEmpty) {
    return folder.files.first;
  }
  if (folder.allSongs.isNotEmpty) {
    return folder.allSongs.first;
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
