import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../models/music_file.dart';
import 'lyrics_controller_dependencies.dart';
import 'audio_riverpod.dart';
import 'lyrics_controller.dart';
import 'lyrics_generation_display_state.dart';
import 'lyrics_controller_state.dart';
import 'lyrics_song_task_state.dart';
import 'lyrics_task_queue_summary.dart';
import 'lyrics_ai_service.dart';

final lyricsControllerDependenciesProvider =
    Provider<LyricsControllerDependencies>((ref) {
      final audioService = ref.read(audioServiceProvider);
      return audioService.lyricsControllerDependencies;
    });

final lyricsAiServiceProvider = Provider<LyricsAiService>((ref) {
  return LyricsAiService(settingsService: ref.read(settingsServiceProvider));
});

final lyricsControllerProvider =
    NotifierProvider<LyricsController, LyricsControllerState>(
      LyricsController.new,
    );

final lyricsSongTaskStateProvider =
    Provider.family<LyricsSongTaskState, String>((ref, songPath) {
      ref.watch(lyricsControllerProvider.select((state) => state.revision));
      return ref
          .read(lyricsControllerProvider.notifier)
          .taskStateForSong(songPath);
    });

final lyricsCurrentSongTaskStateProvider = Provider<LyricsSongTaskState>((ref) {
  final currentMusic = ref.watch(audioCurrentMusicProvider);
  final songPath = currentMusic?.path;
  if (songPath == null || songPath.isEmpty) {
    return const LyricsSongTaskState();
  }

  return ref.watch(lyricsSongTaskStateProvider(songPath));
});

final lyricsTaskQueueSummaryProvider = Provider<LyricsTaskQueueSummary>((ref) {
  ref.watch(lyricsControllerProvider.select((state) => state.revision));
  final queue = ref.watch(audioPlaybackQueueProvider);
  final controller = ref.read(lyricsControllerProvider.notifier);

  var taskCount = 0;
  MusicFile? activeSong;

  for (final song in queue) {
    final taskState = controller.taskStateForSong(song.path);
    final songTaskCount =
        (taskState.isGenerationQueued ? 1 : 0) +
        (taskState.isGenerationRunning ? 1 : 0) +
        (taskState.isTranslationQueued ? 1 : 0) +
        (taskState.isTranslationRunning ? 1 : 0);
    if (songTaskCount == 0) continue;

    taskCount += songTaskCount;
    if (activeSong == null ||
        taskState.isGenerationRunning ||
        taskState.isTranslationRunning) {
      activeSong = song;
    }
  }

  return LyricsTaskQueueSummary(taskCount: taskCount, activeSong: activeSong);
});

final lyricsGenerationDisplayStateProvider =
    Provider<LyricsGenerationDisplayState>((ref) {
      ref.watch(lyricsControllerProvider.select((state) => state.revision));
      return ref
          .read(lyricsControllerProvider.notifier)
          .activeLyricsGenerationDisplayState;
    });

final lyricsDisplayLinesProvider =
    Provider.family<List<LyricLine>, MusicLyric?>((ref, baseLyrics) {
      final liveLines = ref.watch(
        lyricsControllerProvider.select((state) => state.currentLyricsLines),
      );
      if (liveLines.isNotEmpty) {
        return liveLines;
      }
      return baseLyrics?.syncedLines ?? const [];
    });

final lyricsDisplayPlainTextProvider = Provider.family<String, MusicLyric?>((
  ref,
  baseLyrics,
) {
  final liveText = ref.watch(
    lyricsControllerProvider.select((state) => state.currentLyricsText),
  );
  final normalizedLiveText = liveText.trim();
  if (normalizedLiveText.isNotEmpty) {
    return normalizedLiveText;
  }
  return baseLyrics?.plainText.trim() ?? '';
});

final lyricsDisplayLyricsProvider = Provider.family<MusicLyric?, MusicLyric?>((
  ref,
  baseLyrics,
) {
  final liveText = ref.watch(
    lyricsControllerProvider.select((state) => state.currentLyricsText),
  );
  final normalizedLiveText = liveText.trim();
  if (normalizedLiveText.isEmpty) {
    return baseLyrics;
  }

  final displayLines = ref.watch(lyricsDisplayLinesProvider(baseLyrics));
  return baseLyrics?.copyWith(
    syncedLines: displayLines,
    plainText: normalizedLiveText,
  );
});

final lyricsHasRenderableContentProvider = Provider.family<bool, MusicLyric?>((
  ref,
  baseLyrics,
) {
  final hasLyrics = ref.watch(
    lyricsControllerProvider.select((state) => state.hasLyrics),
  );
  if (!hasLyrics) {
    return false;
  }

  final displayLines = ref.watch(lyricsDisplayLinesProvider(baseLyrics));
  if (displayLines.isNotEmpty) {
    return true;
  }

  final displayText = ref.watch(lyricsDisplayPlainTextProvider(baseLyrics));
  return displayText.isNotEmpty;
});
