import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_flow/models/lyric_line.dart';
import 'package:vibe_flow/models/music_lyric.dart';
import 'package:vibe_flow/player/lyrics/lyrics_controller_dependencies.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/lyrics/lyrics_controller.dart';
import 'package:vibe_flow/player/lyrics/lyrics_controller_state.dart';
import 'package:vibe_flow/player/lyrics/lyrics_song_task_state.dart';
import 'package:vibe_flow/player/lyrics/lyrics_ai_service.dart';
import 'package:vibe_flow/player/lyrics/lyrics_service.dart';

final lyricsControllerDependenciesProvider =
    Provider<LyricsControllerDependencies>((ref) {
      final audioService = ref.read(audioServiceProvider);
      return audioService.lyricsControllerDependencies;
    });

final lyricsAiRuntimeConfigProvider = Provider<LyricsAiRuntimeConfig>((ref) {
  return ref.watch(
    settingsServiceProvider.select(
      (settings) => LyricsAiRuntimeConfig(
        generationPrimaryModel: settings.generationPrimaryModel,
        generationFallbackModel: settings.generationFallbackModel,
        translationPrimaryModel: settings.translationPrimaryModel,
        translationFallbackModel: settings.translationFallbackModel,
        geminiApiKey: settings.geminiApiKey,
        openRouterApiKey: settings.openRouterApiKey,
      ),
    ),
  );
});

final lyricsAiServiceProvider = Provider<LyricsAiService>((ref) {
  return LyricsAiService(
    readConfig: () => ref.read(lyricsAiRuntimeConfigProvider),
  );
});

final lyricsServiceProvider = Provider<LyricsService>((ref) {
  return LyricsService();
});

final lyricsTranslationLanguageCodeProvider = Provider<String>((ref) {
  return ref.watch(
    settingsServiceProvider.select(
      (settings) => settings.effectiveLyricsTranslationTargetLanguageCode,
    ),
  );
});

final lyricsControllerProvider =
    NotifierProvider<LyricsController, LyricsControllerState>(
      LyricsController.new,
    );

class _LyricsPanelScrollStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setScrolling(bool value) {
    state = value;
  }
}

class _LyricsLayoutRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }
}

final lyricsPanelScrollAnimatingProvider =
    NotifierProvider<_LyricsPanelScrollStateNotifier, bool>(
      _LyricsPanelScrollStateNotifier.new,
    );

final lyricsLayoutRevisionProvider =
    NotifierProvider<_LyricsLayoutRevisionNotifier, int>(
      _LyricsLayoutRevisionNotifier.new,
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
