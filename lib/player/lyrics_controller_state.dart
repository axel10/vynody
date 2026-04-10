import 'package:freezed_annotation/freezed_annotation.dart';

import '../models/lyric_line.dart';

part 'lyrics_controller_state.freezed.dart';

@freezed
abstract class LyricsControllerState with _$LyricsControllerState {
  const LyricsControllerState._();

  const factory LyricsControllerState({
    @Default(false) bool isLyricsLoading,
    @Default(false) bool isLyricsTranslating,
    @Default('') String lyricsTranslationStatus,
    @Default(false) bool hasLyrics,
    @Default(false) bool lyricsSearchAttempted,
    @Default(false) bool isLyricsSynced,
    @Default(<LyricLine>[]) List<LyricLine> currentLyricsLines,
    @Default('') String currentLyricsText,
    String? currentLyricsTitle,
    @Default('zh') String lyricsTranslationLanguageCode,
  }) = _LyricsControllerState;
}
