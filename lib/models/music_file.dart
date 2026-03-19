import 'package:path/path.dart' as p;

class MusicFile {
  final String path;
  final String name;
  final String? title;
  final int? trackNumber;
  final int? id; // System Media Library ID

  MusicFile({
    required this.path,
    required this.name,
    this.title,
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
}
