import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import 'lyrics_controller_dependencies.dart';
import 'audio_riverpod.dart';
import 'lyrics_controller.dart';
import 'lyrics_controller_state.dart';
import 'gemini_lyrics_service.dart';

final lyricsControllerDependenciesProvider =
    Provider<LyricsControllerDependencies>((ref) {
      final audioService = ref.read(audioServiceProvider);
      return audioService.lyricsControllerDependencies;
    });

final geminiLyricsServiceProvider = Provider<GeminiLyricsService>((ref) {
  return GeminiLyricsService(
    apiKeyService: ref.read(geminiApiKeyServiceProvider),
  );
});

final lyricsControllerProvider =
    NotifierProvider<LyricsController, LyricsControllerState>(
      LyricsController.new,
    );

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
