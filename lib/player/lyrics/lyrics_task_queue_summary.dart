import 'package:vynody/models/music_file.dart';

class LyricsTaskQueueSummary {
  const LyricsTaskQueueSummary({
    required this.taskCount,
    this.activeSong,
    this.activeStatusLabel = '',
  });

  final int taskCount;
  final MusicFile? activeSong;
  final String activeStatusLabel;

  bool get isBusy => taskCount > 0;
  bool get showQueueCount => taskCount > 1;
}
