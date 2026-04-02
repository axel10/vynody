import 'package:flutter/foundation.dart';
import 'lyric_line.dart';

class MusicLyric {
  final List<LyricLine> syncedLines;
  final String plainText;

  bool get isSynced => syncedLines.isNotEmpty;

  const MusicLyric({
    this.syncedLines = const [],
    this.plainText = '',
  });

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
