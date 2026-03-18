import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

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

String getPlaylistModeName(PlaylistMode mode, AppLocalizations l10n) {
  switch (mode) {
    case PlaylistMode.single:
      return l10n.playlistModeSingle;
    case PlaylistMode.singleLoop:
      return l10n.playlistModeSingleLoop;
    case PlaylistMode.queue:
      return l10n.playlistModeQueue;
    case PlaylistMode.queueLoop:
      return l10n.playlistModeQueueLoop;
    case PlaylistMode.autoQueueLoop:
      return l10n.playlistModeAutoQueueLoop;
  }
}

IconData getVolumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_mute;
  if (volume < 75) return Icons.volume_down;
  return Icons.volume_up;
}