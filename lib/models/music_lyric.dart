import 'package:flutter/foundation.dart';
import 'lyric_line.dart';

class MusicLyric {
  final List<LyricLine> syncedLines;
  final String plainText;
  final List<String> translatedLines;

  bool get isSynced => syncedLines.isNotEmpty;
  bool get hasTranslatedLyrics =>
      translatedLines.any((line) => line.trim().isNotEmpty);
  String get translatedText => translatedLines.join('\n').trim();

  const MusicLyric({
    this.syncedLines = const [],
    this.plainText = '',
    this.translatedLines = const [],
  });

  MusicLyric copyWith({
    List<LyricLine>? syncedLines,
    String? plainText,
    List<String>? translatedLines,
  }) {
    return MusicLyric(
      syncedLines: syncedLines ?? this.syncedLines,
      plainText: plainText ?? this.plainText,
      translatedLines: translatedLines ?? this.translatedLines,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MusicLyric &&
        listEquals(other.syncedLines, syncedLines) &&
        other.plainText == plainText &&
        listEquals(other.translatedLines, translatedLines);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(syncedLines),
    plainText,
    Object.hashAll(translatedLines),
  );
}
