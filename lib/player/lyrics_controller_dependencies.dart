import '../models/music_file.dart';
import 'metadata_database.dart';

class LyricsControllerDependencies {
  const LyricsControllerDependencies({
    required this.db,
    required this.currentMusic,
    required this.queue,
    required this.currentIndex,
    required this.playerDuration,
    required this.isLyricsActive,
    required this.cacheSongDuration,
  });

  final MetadataDatabase db;
  final MusicFile? Function() currentMusic;
  final List<MusicFile> Function() queue;
  final int Function() currentIndex;
  final Duration Function() playerDuration;
  final bool Function() isLyricsActive;
  final void Function(String path, int durationMillis) cacheSongDuration;
}
