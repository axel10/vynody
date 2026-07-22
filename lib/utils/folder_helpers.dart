import 'package:collection/collection.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_service.dart';

const double folderPageMaxWidth = 1700.0;

MusicFile? findRepresentativeSong(MusicFolder folder) {
  final fileWithArtwork = folder.files.firstWhereOrNull(
    (s) =>
        (s.artworkPath != null && s.artworkPath!.isNotEmpty) ||
        (s.thumbnailPath != null && s.thumbnailPath!.isNotEmpty) ||
        (s.artworkBytes != null && s.artworkBytes!.isNotEmpty),
  );
  if (fileWithArtwork != null) return fileWithArtwork;

  final allSongWithArtwork = folder.allSongs.firstWhereOrNull(
    (s) =>
        (s.artworkPath != null && s.artworkPath!.isNotEmpty) ||
        (s.thumbnailPath != null && s.thumbnailPath!.isNotEmpty) ||
        (s.artworkBytes != null && s.artworkBytes!.isNotEmpty),
  );
  if (allSongWithArtwork != null) return allSongWithArtwork;

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
