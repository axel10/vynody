import 'package:flutter/foundation.dart';

import 'lyric_line.dart';
import 'music_lyric_translation.dart';

class MusicLyric {
  final String id;
  final List<LyricLine> syncedLines;
  final String plainText;
  final Map<String, MusicLyricTranslation> translations;

  bool get hasId => id.trim().isNotEmpty;
  bool get isSynced => syncedLines.any((line) => line.isTimed);

  bool get hasTranslatedLyrics =>
      translations.values.any((translation) => translation.hasContent);

  const MusicLyric({
    this.id = '',
    this.syncedLines = const [],
    this.plainText = '',
    this.translations = const {},
  });

  MusicLyricTranslation? translationFor(String languageCode) {
    return translations[languageCode];
  }

  List<String> translatedLinesOf(String languageCode) {
    final translatedLines = translations[languageCode]?.translatedLines;
    if (translatedLines == null || translatedLines.isEmpty) return const [];

    return translatedLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  String translatedTextOf(String languageCode) {
    return translations[languageCode]?.translatedText.trim() ?? '';
  }

  String translatedLineAt(int index, String languageCode) {
    return translations[languageCode]?.translatedLineAt(index) ?? '';
  }

  MusicLyric copyWith({
    String? id,
    List<LyricLine>? syncedLines,
    String? plainText,
    Map<String, MusicLyricTranslation>? translations,
  }) {
    return MusicLyric(
      id: id ?? this.id,
      syncedLines: syncedLines ?? this.syncedLines,
      plainText: plainText ?? this.plainText,
      translations: translations ?? this.translations,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MusicLyric &&
        other.id == id &&
        listEquals(other.syncedLines, syncedLines) &&
        other.plainText == plainText &&
        mapEquals(other.translations, translations);
  }

  @override
  int get hashCode => Object.hash(
    id,
    Object.hashAll(syncedLines),
    plainText,
    Object.hashAllUnordered(
      translations.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}
