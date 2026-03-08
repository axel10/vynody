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
}
