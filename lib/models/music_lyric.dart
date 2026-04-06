import 'package:flutter/foundation.dart';
import 'lyric_line.dart';

class MusicLyric {
  final List<LyricLine> syncedLines;
  final String plainText;

  bool get isSynced => syncedLines.any((line) => line.isTimed);
  bool get hasTranslatedLyrics =>
      syncedLines.any((line) => line.translation.trim().isNotEmpty);
  String get translatedText => syncedLines
      .map((line) => line.translation.trim())
      .where((line) => line.isNotEmpty)
      .join('\n')
      .trim();

  const MusicLyric({this.syncedLines = const [], this.plainText = ''});

  MusicLyric copyWith({List<LyricLine>? syncedLines, String? plainText}) {
    return MusicLyric(
      syncedLines: syncedLines ?? this.syncedLines,
      plainText: plainText ?? this.plainText,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MusicLyric &&
        listEquals(other.syncedLines, syncedLines) &&
        other.plainText == plainText;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(syncedLines), plainText);
}
