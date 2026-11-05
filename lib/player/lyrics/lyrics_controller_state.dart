import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/player/lyrics/lyrics_generation_phase.dart';

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

    /// 当前这首歌**展示**哪一种译文（per-song，来自 `lyrics_cache.selectedTranslationLanguage`）。
    ///
    /// 空串 = 跟随 [lyricsTranslationLanguageCode]（全局默认目标语言）。
    /// 与 [lyricsTranslationLanguageCode] 不是同一件事：后者是"要翻译成什么"，
    /// 前者是"已经在看什么"。展示侧只允许通过
    /// `LyricsController.effectiveTranslationLanguageFor()` 读取。
    @Default('') String translationDisplayLanguageCode,

    @Default(0) int revision,
  }) = _LyricsControllerState;
}
