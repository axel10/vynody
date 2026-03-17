import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import 'package:flutter/material.dart';

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, "0")}';
}

IconData getPlaylistModeIcon(PlaylistMode mode) {
  switch (mode) {
    case PlaylistMode.single:
      return Icons.looks_one_outlined;
    case PlaylistMode.singleLoop:
      return Icons.repeat_one_rounded;
    case PlaylistMode.queue:
      return Icons.reorder_rounded;
    case PlaylistMode.queueLoop:
      return Icons.repeat_rounded;
    case PlaylistMode.autoQueueLoop:
      return Icons.all_inclusive_rounded;
  }
}

String getPlaylistModeName(PlaylistMode mode) {
  switch (mode) {
    case PlaylistMode.single:
      return 'Single';
    case PlaylistMode.singleLoop:
      return 'Single Loop';
    case PlaylistMode.queue:
      return 'Queue';
    case PlaylistMode.queueLoop:
      return 'Queue Loop';
    case PlaylistMode.autoQueueLoop:
      return 'Auto Queue Loop';
  }
}

IconData getVolumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_mute;
  if (volume < 75) return Icons.volume_down;
  return Icons.volume_up;
}