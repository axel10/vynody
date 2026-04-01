import 'package:path/path.dart' as p;

class MusicFile {
  final String path;
  final String name;
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? id; // System Media Library ID

  MusicFile({
    required this.path,
    required this.name,
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.id,
  });

  String get displayName {
    if (title != null && title!.trim().isNotEmpty) {
      return title!;
    }
    // Remove extension from name using path package
    return p.basenameWithoutExtension(path);
  }

  MusicFile copyWith({
    String? path,
    String? name,
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    int? id,
  }) {
    return MusicFile(
      path: path ?? this.path,
      name: name ?? this.name,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      trackNumber: trackNumber ?? this.trackNumber,
      id: id ?? this.id,
    );
  }
}
