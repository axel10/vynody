import 'package:freezed_annotation/freezed_annotation.dart';

import 'lyrics_json_converters.dart';

part 'music_lyric_translation.freezed.dart';
part 'music_lyric_translation.g.dart';

@freezed
abstract class MusicLyricTranslation with _$MusicLyricTranslation {
  const MusicLyricTranslation._();

  const factory MusicLyricTranslation({
    @Default('zh') String languageCode,
    @Default('') String translatedText,
    @JsonKey(
      fromJson: stringListFromJson,
      toJson: stringListToJson,
    )
    @Default(<String>[]) List<String> translatedLines,
    String? provider,
    DateTime? updatedAt,
  }) = _MusicLyricTranslation;

  factory MusicLyricTranslation.fromJson(Map<String, dynamic> json) =>
      _$MusicLyricTranslationFromJson(json);

  bool get hasContent =>
      translatedText.trim().isNotEmpty ||
      translatedLines.any((line) => line.trim().isNotEmpty);

  String translatedLineAt(int index) {
    if (index < 0) return '';
    if (index >= translatedLines.length) return '';
    return translatedLines[index].trim();
  }
}
