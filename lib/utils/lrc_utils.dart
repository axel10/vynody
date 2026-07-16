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

      final lineTimestamps = <Duration>[];
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
        lineTimestamps.add(parsed);
        index = end + 1;
      }

      if (lineTimestamps.isEmpty) {
        continue;
      }

      final remainingContent = line.substring(index);
      final wordMatches = _timestampLinePattern.allMatches(remainingContent).toList();

      if (wordMatches.isEmpty) {
        final text = remainingContent.trim();
        if (text.isEmpty) continue;
        for (final timestamp in lineTimestamps) {
          lines.add(LyricLine(timestamp: timestamp, text: text, isTimed: true));
        }
      } else {
        // Parse word-by-word lyrics
        final baseTimestamp = lineTimestamps.first;
        final wordTokens = <_ParsedWordToken>[];

        final firstWordEnd = wordMatches.first.start;
        final firstWordText = remainingContent.substring(0, firstWordEnd);
        if (firstWordText.isNotEmpty) {
          wordTokens.add(_ParsedWordToken(baseTimestamp, firstWordText));
        }

        Duration? trailingTimestamp;
        for (int i = 0; i < wordMatches.length; i++) {
          final match = wordMatches[i];
          final token = match.group(0)!;
          final timestampStr = token.substring(1, token.length - 1);
          final timestamp = parseTimestampToken(timestampStr);
          if (timestamp == null) continue;

          final startIdx = match.end;
          final endIdx = (i + 1 < wordMatches.length) ? wordMatches[i + 1].start : remainingContent.length;
          final wordText = remainingContent.substring(startIdx, endIdx);

          if (wordText.isNotEmpty) {
            wordTokens.add(_ParsedWordToken(timestamp, wordText));
          } else if (i == wordMatches.length - 1) {
            trailingTimestamp = timestamp;
          }
        }

        if (wordTokens.isNotEmpty) {
          final relativeWords = <_RelativeWord>[];
          final cleanTextBuffer = StringBuffer();

          for (int i = 0; i < wordTokens.length; i++) {
            final token = wordTokens[i];
            final Duration duration;
            if (i + 1 < wordTokens.length) {
              duration = wordTokens[i + 1].timestamp - token.timestamp;
            } else if (trailingTimestamp != null && trailingTimestamp > token.timestamp) {
              duration = trailingTimestamp - token.timestamp;
            } else {
              duration = const Duration(milliseconds: 1000);
            }

            final relativeOffset = token.timestamp - baseTimestamp;
            relativeWords.add(_RelativeWord(
              offset: relativeOffset,
              durationMs: duration.inMilliseconds,
              text: token.text,
            ));
            cleanTextBuffer.write(token.text);
          }

          final cleanText = cleanTextBuffer.toString().trim();
          if (cleanText.isNotEmpty) {
            for (final t in lineTimestamps) {
              final wordsList = relativeWords.map((rw) {
                return LyricWord(
                  timestamp: t + rw.offset,
                  durationMs: rw.durationMs,
                  text: rw.text,
                );
              }).toList();

              lines.add(LyricLine(
                timestamp: t,
                text: cleanText,
                isTimed: true,
                words: wordsList,
              ));
            }
          }
        }
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

class _ParsedWordToken {
  final Duration timestamp;
  final String text;
  _ParsedWordToken(this.timestamp, this.text);
}

class _RelativeWord {
  final Duration offset;
  final int durationMs;
  final String text;
  _RelativeWord({
    required this.offset,
    required this.durationMs,
    required this.text,
  });
}
