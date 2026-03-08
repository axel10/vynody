import 'music_file.dart';

class MusicFolder {
  final String path;
  final String name;
  final List<MusicFolder> subFolders;
  final List<MusicFile> files;

  MusicFolder({
    required this.path,
    required this.name,
    List<MusicFolder> subFolders = const [],
    List<MusicFile> files = const [],
  }) : subFolders = List.from(subFolders),
       files = List.from(files);

  bool get isEmpty => subFolders.isEmpty && files.isEmpty;
}
