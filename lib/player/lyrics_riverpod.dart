import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'lyrics_controller.dart';
import 'lyrics_controller_state.dart';

typedef LyricsControllerBuilder = LyricsController Function();

final lyricsControllerBuilderProvider =
    Provider<LyricsControllerBuilder>((ref) {
      throw UnimplementedError(
        'lyricsControllerBuilderProvider must be overridden before use',
      );
    });

final lyricsControllerProvider = ChangeNotifierProvider<LyricsController>((
  ref,
) {
  final builder = ref.watch(lyricsControllerBuilderProvider);
  final controller = builder();
  ref.onDispose(controller.dispose);
  return controller;
});

final lyricsControllerStateProvider = Provider<LyricsControllerState>((ref) {
  final controller = ref.watch(lyricsControllerProvider);
  return LyricsControllerState(
    isLyricsLoading: controller.isLyricsLoading,
    isLyricsTranslating: controller.isLyricsTranslating,
    lyricsTranslationStatus: controller.lyricsTranslationStatus,
    hasLyrics: controller.hasLyrics,
    lyricsSearchAttempted: controller.lyricsSearchAttempted,
    isLyricsSynced: controller.isLyricsSynced,
    currentLyricsLines: controller.currentLyricsLines,
    currentLyricsText: controller.currentLyricsText,
    currentLyricsTitle: controller.currentLyricsTitle,
    lyricsTranslationLanguageCode: controller.lyricsTranslationLanguageCode,
  );
});
