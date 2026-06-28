import 'package:audio_core/audio_core.dart';

enum AppPlaybackMode {
  single,
  singleLoop,
  queue,
  queueLoop,
  autoQueueLoop;

  PlaylistMode toCoreMode() {
    switch (this) {
      case AppPlaybackMode.single:
        return PlaylistMode.single;
      case AppPlaybackMode.singleLoop:
        return PlaylistMode.singleLoop;
      case AppPlaybackMode.queue:
      case AppPlaybackMode.autoQueueLoop:
        return PlaylistMode.queue;
      case AppPlaybackMode.queueLoop:
        return PlaylistMode.queueLoop;
    }
  }
}
