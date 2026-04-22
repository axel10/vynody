import 'music_file.dart';

class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.title,
    required this.artist,
    required this.songs,
    required this.representativeSong,
    required this.totalDurationMillis,
  });

  final String id;
  final String title;
  final String artist;
  final List<MusicFile> songs;
  final MusicFile representativeSong;
  final int totalDurationMillis;

  int get trackCount => songs.length;
  bool get isUnknownAlbum => title.trim().toLowerCase() == 'unknown album';

  int get latestTimestampMillis => songs.fold<int>(
    0,
    (latest, song) =>
        song.lastModifiedTime != null && song.lastModifiedTime! > latest
        ? song.lastModifiedTime!
        : latest,
  );
}
