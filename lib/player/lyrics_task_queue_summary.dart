import '../models/music_file.dart';

class LyricsTaskQueueSummary {
  const LyricsTaskQueueSummary({
    required this.taskCount,
    this.activeSong,
    this.activeStatusLabel,
    this.activeModelLabel,
  });

  final int taskCount;
  final MusicFile? activeSong;
  final String? activeStatusLabel;
  final String? activeModelLabel;

  bool get isBusy => taskCount > 0;
  bool get showQueueCount => taskCount > 1;
}
