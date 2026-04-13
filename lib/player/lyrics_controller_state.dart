import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/lyric_line.dart';
import '../utils/language_code_utils.dart';
import 'lyrics_generation_phase.dart';

part 'lyrics_controller_state.freezed.dart';

@freezed
abstract class LyricsControllerState with _$LyricsControllerState {
  const LyricsControllerState._();

  const factory LyricsControllerState({
    @Default(false) bool isLyricsLoading,
    @Default(false) bool isLyricsTranslating,
    @Default('') String lyricsTranslationStatus,
    @Default('') String lyricsGenerationStatus,
    @Default(false) bool hasLyrics,
    @Default(false) bool lyricsSearchAttempted,
    @Default(<LyricLine>[]) List<LyricLine> currentLyricsLines,
    @Default('') String currentLyricsText,
    @Default(false) bool isLyricsGenerating,
    @Default(LyricsGenerationPhase.idle)
    LyricsGenerationPhase lyricsGenerationPhase,
    @Default(0.0) double lyricsGenerationProgress,
    @Default(LanguageCodeUtils.fallbackLanguageCode)
    String lyricsTranslationLanguageCode,
    @Default(0) int revision,
  }) = _LyricsControllerState;
}
