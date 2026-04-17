import '../models/music_file.dart';

class LyricsTaskQueueSummary {
  const LyricsTaskQueueSummary({required this.taskCount, this.activeSong});

  final int taskCount;
  final MusicFile? activeSong;

  bool get isBusy => taskCount > 0;
  bool get showQueueCount => taskCount > 1;
}
