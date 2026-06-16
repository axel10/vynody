import 'package:vynody/models/lyric_line.dart';

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

  static String normalizeGeneratedLyricsText(String? text) {
    final cleaned = cleanGeneratedLyricsText(text);
    if (cleaned.isEmpty) return '';
    if (!_timestampLinePattern.hasMatch(cleaned)) return cleaned;

    final normalizedLines = <String>[];
    for (final rawLine in cleaned.split(RegExp(r'\r?\n'))) {
      final expandedLines = _expandPackedTimestampLine(rawLine);
      if (expandedLines.isEmpty) {
        final line = rawLine.trim();
        if (line.isNotEmpty) {
          normalizedLines.add(line);
        }
        continue;
      }

      normalizedLines.addAll(expandedLines);
    }

    return normalizedLines.join('\n').trim();
  }

  static List<String> _expandPackedTimestampLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty) return const [];

    final normalized = normalizeLrcLine(line);
    if (normalized == null || normalized.isEmpty) return const [];

    final matches = _timestampLinePattern
        .allMatches(normalized)
        .toList(growable: false);
    if (matches.isEmpty) return const [];

    final expandedLines = <String>[];
    final timestampGroup = <String>[];
    var lastTimestampEnd = matches.first.end;

    String timestampText(int index) {
      return matches[index].group(0)!.trim();
    }

    void emitGroup(String text) {
      final normalizedText = text.trim();
      if (normalizedText.isEmpty || timestampGroup.isEmpty) {
        timestampGroup.clear();
        return;
      }

      for (final timestamp in timestampGroup) {
        expandedLines.add('$timestamp $normalizedText'.trim());
      }
      timestampGroup.clear();
    }

    timestampGroup.add(timestampText(0));

    for (var i = 1; i < matches.length; i++) {
      final match = matches[i];
      final betweenText = normalized
          .substring(lastTimestampEnd, match.start)
          .trim();
      if (betweenText.isEmpty) {
        timestampGroup.add(timestampText(i));
      } else {
        emitGroup(betweenText);
        timestampGroup.add(timestampText(i));
      }
      lastTimestampEnd = match.end;
    }

    emitGroup(normalized.substring(lastTimestampEnd));
    return expandedLines;
  }
}
