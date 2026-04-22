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
}
