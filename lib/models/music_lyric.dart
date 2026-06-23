import 'package:freezed_annotation/freezed_annotation.dart';

import 'lyric_line.dart';
import 'lyrics_json_converters.dart';
import 'music_lyric_translation.dart';

part 'music_lyric.freezed.dart';
part 'music_lyric.g.dart';

@freezed
abstract class MusicLyric with _$MusicLyric {
  const MusicLyric._();

  const factory MusicLyric({
    @Default('') String id,
    @Default(<LyricLine>[]) List<LyricLine> syncedLines,
    @Default('') String plainText,
    @Default(<String, MusicLyricTranslation>{})
    Map<String, MusicLyricTranslation> translations,
    @Default('') String source,
    @JsonKey(
      fromJson: durationFromMilliseconds,
      toJson: durationToMilliseconds,
    )
    @Default(Duration.zero) Duration timelineOffset,
  }) = _MusicLyric;

  factory MusicLyric.fromJson(Map<String, dynamic> json) =>
      _$MusicLyricFromJson(json);

  bool get hasId => id.trim().isNotEmpty;
  bool get isSynced => syncedLines.any((line) => line.isTimed);
  bool get hasTranslatedLyrics =>
      translations.values.any((translation) => translation.hasContent);

  MusicLyricTranslation? translationFor(String languageCode) {
    return translations[languageCode];
  }

  List<String> translatedLinesOf(String languageCode) {
    final translatedLines = translations[languageCode]?.translatedLines;
    if (translatedLines == null || translatedLines.isEmpty) {
      return const [];
    }

    return translatedLines
        .map((line) => line.trim())
        .toList(growable: false);
  }

  String translatedTextOf(String languageCode) {
    return translations[languageCode]?.translatedText ?? '';
  }

  String translatedLineAt(int index, String languageCode) {
    return translations[languageCode]?.translatedLineAt(index) ?? '';
  }

  String getEffectiveTranslationLanguage(String targetLanguageCode) {
    if (translations.isEmpty) {
      return targetLanguageCode;
    }
    final targetTranslation = translations[targetLanguageCode];
    if (targetTranslation != null && targetTranslation.hasContent) {
      return targetLanguageCode;
    }
    final validTranslations = translations.values
        .where((t) => t.hasContent)
        .toList();
    if (validTranslations.isEmpty) {
      return targetLanguageCode;
    }
    validTranslations.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return validTranslations.first.languageCode;
  }
}
