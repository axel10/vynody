import '../models/lyric_line.dart';

class LrcUtils {
  static final RegExp _timestampLinePattern = RegExp(
    r'\[\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*\]',
  );

  static final RegExp _timestampTokenPattern = RegExp(
    r'^(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?$',
  );

  static List<LyricLine> parseTimedLyrics(String? lyrics) {
    if (lyrics == null || lyrics.trim().isEmpty) {
      return const [];
    }

    final lines = <LyricLine>[];
    for (final rawLine in lyrics.split(RegExp(r'\r?\n'))) {
      final line = normalizeLrcLine(rawLine);
      if (line == null || line.isEmpty) continue;

      final timestamps = <Duration>[];
      var index = 0;
      while (index < line.length) {
        final end = line.indexOf(']', index);
        if (index >= line.length || line[index] != '[' || end == -1) {
          break;
        }
        final token = line.substring(index + 1, end);
        final parsed = parseTimestampToken(token);
        if (parsed == null) {
          break;
        }
        timestamps.add(parsed);
        index = end + 1;
      }

      final text = line.substring(index).trim();
      if (timestamps.isEmpty || text.isEmpty) {
        continue;
      }

      for (final timestamp in timestamps) {
        lines.add(LyricLine(timestamp: timestamp, text: text, isTimed: true));
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }

  static String? normalizeLrcLine(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty) return null;

    line = line.replaceFirst(RegExp(r'^\uFEFF'), '');
    line = line.replaceFirst(RegExp(r'^(?:[-*•]+|\d+[.)])\s*'), '');

    final timestampMatch = _timestampLinePattern.firstMatch(line);
    if (timestampMatch == null) return null;

    return line.substring(timestampMatch.start).trimLeft();
  }

  static Duration? parseTimestampToken(String token) {
    final match = _timestampTokenPattern.firstMatch(token);
    if (match == null) return null;

    final minutes = int.tryParse(match.group(1)!);
    final seconds = int.tryParse(match.group(2)!);
    final fractionText = match.group(3) ?? '0';
    if (minutes == null || seconds == null) return null;

    final fraction = int.tryParse(
      fractionText.padRight(3, '0').substring(0, 3),
    );
    if (fraction == null) return null;

    return Duration(minutes: minutes, seconds: seconds, milliseconds: fraction);
  }

  static String stripTimestamps(String lyrics) {
    final lines = lyrics.split(RegExp(r'\r?\n'));
    final stripped = lines.map((line) {
      final withoutTimestamps = line.replaceAll(_timestampLinePattern, '');
      return withoutTimestamps.trimRight();
    }).toList();
    return stripped.join('\n').trim();
  }

  static String cleanGeneratedLyricsText(String? text) {
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return '';

    final fenceMatch = RegExp(
      r'```(?:lrc|lyrics)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final unwrapped = fenceMatch?.group(1)?.trim() ?? trimmed;

    final lines = unwrapped.split(RegExp(r'\r?\n'));
    final lrcLikeLines = <String>[];
    for (final rawLine in lines) {
      final normalized = normalizeLrcLine(rawLine);
      if (normalized != null) {
        lrcLikeLines.add(normalized);
      }
    }

    if (lrcLikeLines.isNotEmpty) {
      return lrcLikeLines.join('\n').trim();
    }

    return unwrapped.trim();
  }
}
