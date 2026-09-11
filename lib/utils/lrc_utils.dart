import 'dart:math';

import 'package:vynody/models/lyric_line.dart';

class ParsedLyricsResult {
  final List<LyricLine> syncedLines;
  final List<String>? translatedLines;

  const ParsedLyricsResult({
    required this.syncedLines,
    this.translatedLines,
  });

  bool get hasTranslation =>
      translatedLines != null &&
      translatedLines!.any((line) => line.trim().isNotEmpty);
}

class LrcUtils {
  static final RegExp _timestampLinePattern = RegExp(
    r'[\[<\(]\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*[\]>\)]',
  );

  static final RegExp _timestampTokenPattern = RegExp(
    r'^(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?$',
  );

  static final RegExp _inlineTranslationDelimiterPattern = RegExp(
    r'\s+[/／]\s+|\s*//\s*',
  );

  static List<LyricLine> parseTimedLyrics(String? lyrics) {
    return parseLyricsWithTranslation(lyrics).syncedLines;
  }

  static ParsedLyricsResult parseLyricsWithTranslation(String? lyrics) {
    if (lyrics == null || lyrics.trim().isEmpty) {
      return const ParsedLyricsResult(syncedLines: []);
    }

    final rawLines = lyrics.split(RegExp(r'\r?\n'));
    final blocks = <List<String>>[];
    var currentBlock = <String>[];

    for (final rawLine in rawLines) {
      final line = normalizeLrcLine(rawLine);
      if (line == null || line.isEmpty) {
        if (currentBlock.isNotEmpty) {
          blocks.add(currentBlock);
          currentBlock = <String>[];
        }
        continue;
      }
      currentBlock.add(line);
    }
    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock);
    }

    final allParsedLines = <LyricLine>[];

    for (final block in blocks) {
      final blockLines = <LyricLine>[];
      for (final line in block) {
        _parseSingleNormalizedLine(line, blockLines);
      }

      if (blockLines.isEmpty) continue;

      allParsedLines.addAll(_groupWordPerLineIfNeeded(blockLines));
    }

    if (allParsedLines.isEmpty) {
      return const ParsedLyricsResult(syncedLines: []);
    }

    // Check Format ①: Inline translation delimiter ("原文 / 译文")
    int inlineDelimiterCount = 0;
    for (final line in allParsedLines) {
      if (_hasInlineTranslationDelimiter(line.text)) {
        inlineDelimiterCount++;
      }
    }

    final isFormat1 = inlineDelimiterCount >= 2 ||
        (inlineDelimiterCount == 1 && allParsedLines.length <= 2);

    if (isFormat1) {
      final syncedLines = <LyricLine>[];
      final translatedLines = <String>[];

      for (final line in allParsedLines) {
        final split = _splitInlineTranslation(line.text);
        if (split != null) {
          syncedLines.add(line.copyWith(text: split.$1));
          translatedLines.add(split.$2);
        } else {
          syncedLines.add(line);
          translatedLines.add('');
        }
      }

      syncedLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return ParsedLyricsResult(
        syncedLines: syncedLines,
        translatedLines: translatedLines,
      );
    }

    // Check Format ② & ③: Duplicate timestamps for main lyric vs translation
    // Group lines by exact timestamp, preserving file order in each bucket
    final timestampBuckets = <Duration, List<LyricLine>>{};
    for (final line in allParsedLines) {
      timestampBuckets.putIfAbsent(line.timestamp, () => []).add(line);
    }

    final hasTranslationDuplicates = timestampBuckets.values.any((bucket) {
      if (bucket.length <= 1) return false;
      final firstText = bucket.first.text.trim();
      return bucket.sublist(1).any((line) => line.text.trim() != firstText);
    });

    if (hasTranslationDuplicates) {
      final sortedTimestamps = timestampBuckets.keys.toList()
        ..sort((a, b) => a.compareTo(b));

      final syncedLines = <LyricLine>[];
      final translatedLines = <String>[];

      for (final ts in sortedTimestamps) {
        final bucket = timestampBuckets[ts]!;
        // 1st line in bucket is main lyric
        syncedLines.add(bucket.first);
        // 2nd (and subsequent) lines in bucket with different text are translation
        final firstText = bucket.first.text.trim();
        final translationBucket = bucket
            .sublist(1)
            .where((l) => l.text.trim() != firstText)
            .toList();

        if (translationBucket.isNotEmpty) {
          final translationText =
              translationBucket.map((l) => l.text.trim()).join(' / ');
          translatedLines.add(translationText);
        } else {
          translatedLines.add('');
        }
      }

      return ParsedLyricsResult(
        syncedLines: syncedLines,
        translatedLines: translatedLines,
      );
    }

    allParsedLines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return ParsedLyricsResult(syncedLines: allParsedLines);
  }

  static bool _hasInlineTranslationDelimiter(String text) {
    if (text.isEmpty) return false;
    if (_inlineTranslationDelimiterPattern.hasMatch(text)) return true;
    final cjkSlashMatch = RegExp(r'^(.*?)\s*[/／]\s*(.*?)$').firstMatch(text);
    if (cjkSlashMatch != null) {
      final part1 = cjkSlashMatch.group(1) ?? '';
      final part2 = cjkSlashMatch.group(2) ?? '';
      if (part1.isNotEmpty && part2.isNotEmpty && (_hasCJK(part1) || _hasCJK(part2))) {
        return true;
      }
    }
    return false;
  }

  static (String, String)? _splitInlineTranslation(String text) {
    final match = _inlineTranslationDelimiterPattern.firstMatch(text);
    if (match != null) {
      final orig = text.substring(0, match.start).trim();
      final trans = text.substring(match.end).trim();
      if (orig.isNotEmpty || trans.isNotEmpty) {
        return (orig, trans);
      }
    }

    final cjkSlashMatch = RegExp(r'^(.*?)\s*[/／]\s*(.*?)$').firstMatch(text);
    if (cjkSlashMatch != null) {
      final part1 = cjkSlashMatch.group(1)?.trim() ?? '';
      final part2 = cjkSlashMatch.group(2)?.trim() ?? '';
      if (part1.isNotEmpty && part2.isNotEmpty && (_hasCJK(part1) || _hasCJK(part2))) {
        return (part1, part2);
      }
    }

    return null;
  }

  static bool _hasCJK(String text) {
    for (final unit in text.codeUnits) {
      if (_isCJKCodeUnit(unit)) return true;
    }
    return false;
  }

  static void _parseSingleNormalizedLine(String rawLine, List<LyricLine> targetList) {
    var line = rawLine;
    if (isKaraokeLyricsLine(line)) {
      line = sanitizeKaraokeLineSpaces(line);
    }
    final lineTimestamps = <Duration>[];
    var index = 0;
    while (index < line.length) {
      final startChar = line[index];
      if (startChar != '[' && startChar != '<' && startChar != '(') {
        break;
      }
      final closingChar = startChar == '['
          ? ']'
          : (startChar == '<' ? '>' : ')');
      final end = line.indexOf(closingChar, index);
      if (end == -1) {
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
      return;
    }

    final remainingContent = line.substring(index);
    final wordMatches = _timestampLinePattern.allMatches(remainingContent).toList();

    final effectiveTimestamps = <Duration>[];
    for (final t in lineTimestamps) {
      if (effectiveTimestamps.isEmpty ||
          (t - effectiveTimestamps.last).abs() >= const Duration(seconds: 3)) {
        effectiveTimestamps.add(t);
      }
    }

    if (wordMatches.isEmpty) {
      final text = remainingContent.trim();
      for (final timestamp in effectiveTimestamps) {
        targetList.add(LyricLine(timestamp: timestamp, text: text, isTimed: true));
      }
    } else {
      // Parse word-by-word lyrics
      final baseTimestamp = effectiveTimestamps.isNotEmpty
          ? effectiveTimestamps.first
          : lineTimestamps.first;
      final firstWordTimestamp = lineTimestamps.length > 1 &&
              (lineTimestamps[1] - baseTimestamp).abs() < const Duration(seconds: 3)
          ? lineTimestamps[1]
          : baseTimestamp;

      final wordTokens = <_ParsedWordToken>[];

      final firstWordEnd = wordMatches.first.start;
      final firstWordText = remainingContent.substring(0, firstWordEnd);
      if (firstWordText.trim().isNotEmpty) {
        wordTokens.add(_ParsedWordToken(firstWordTimestamp, firstWordText.trimLeft()));
      }

      Duration? trailingTimestamp;
      for (int i = 0; i < wordMatches.length; i++) {
        final match = wordMatches[i];
        final token = match.group(0)!;
        final timestamp = parseTimestampToken(token);
        if (timestamp == null) continue;

        final startIdx = match.end;
        final endIdx = (i + 1 < wordMatches.length) ? wordMatches[i + 1].start : remainingContent.length;
        var wordText = remainingContent.substring(startIdx, endIdx);

        if (wordText.trim().isNotEmpty) {
          if (wordTokens.isEmpty) {
            wordText = wordText.trimLeft();
          } else if (wordText.startsWith(RegExp(r'^\s+'))) {
            final last = wordTokens.removeLast();
            final shouldAddSpace = _needsSpace(last.text, wordText);
            final lastText = shouldAddSpace
                ? (last.text.endsWith(' ') ? last.text : '${last.text} ')
                : last.text.trimRight();
            wordTokens.add(_ParsedWordToken(last.timestamp, lastText));
            wordText = wordText.trimLeft();
          } else if (!wordTokens.last.text.endsWith(' ') &&
              _needsSpace(wordTokens.last.text, wordText)) {
            final last = wordTokens.removeLast();
            wordTokens.add(_ParsedWordToken(last.timestamp, '${last.text} '));
          }
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
          final wordsList = relativeWords.map((rw) {
            return LyricWord(
              timestamp: baseTimestamp + rw.offset,
              durationMs: rw.durationMs,
              text: rw.text,
            );
          }).toList();

          targetList.add(LyricLine(
            timestamp: baseTimestamp,
            text: cleanText,
            isTimed: true,
            words: wordsList,
          ));
        }
      }
    }
  }

  static List<LyricLine> _groupWordPerLineIfNeeded(List<LyricLine> initialLines) {
    if (initialLines.length <= 1) return initialLines;

    final result = <LyricLine>[];
    int i = 0;

    while (i < initialLines.length) {
      final current = initialLines[i];

      if (current.text.trim().isEmpty) {
        i++;
        continue;
      }

      final isCandidate = current.isTimed &&
          (current.words == null || current.words!.isEmpty || current.words!.length == 1) &&
          current.text.trim().length <= 4 &&
          !current.text.contains('\n');

      if (!isCandidate) {
        result.add(current);
        i++;
        continue;
      }

      final group = <LyricLine>[current];
      Duration? trailingTimestamp;
      int j = i + 1;
      while (j < initialLines.length) {
        final next = initialLines[j];
        final prev = group.last;

        if (next.isTimed && next.text.trim().isEmpty) {
          if (next.timestamp > prev.timestamp) {
            trailingTimestamp = next.timestamp;
          }
          j++;
          break;
        }

        final isNextCandidate = next.isTimed &&
            (next.words == null || next.words!.isEmpty || next.words!.length == 1) &&
            next.text.trim().length <= 4 &&
            !next.text.contains('\n') &&
            next.text.trim() != prev.text.trim();

        if (!isNextCandidate) break;

        final gap = next.timestamp - prev.timestamp;
        if (gap <= Duration.zero || gap > const Duration(milliseconds: 3000)) {
          break;
        }

        group.add(next);
        j++;
      }

      if (group.length >= 2) {
        final baseTimestamp = group.first.timestamp;
        final mergedWords = <LyricWord>[];
        final sb = StringBuffer();

        for (int k = 0; k < group.length; k++) {
          final gLine = group[k];
          final String wordText = gLine.text;

          final int durationMs;
          if (k + 1 < group.length) {
            durationMs = (group[k + 1].timestamp - gLine.timestamp).inMilliseconds;
          } else if (trailingTimestamp != null && trailingTimestamp > gLine.timestamp) {
            durationMs = (trailingTimestamp - gLine.timestamp).inMilliseconds;
          } else {
            durationMs = 1000;
          }

          if (k > 0 && _needsSpace(group[k - 1].text, wordText)) {
            sb.write(' ');
            if (mergedWords.isNotEmpty) {
              final prevWord = mergedWords.removeLast();
              final prevWithSpace = prevWord.text.endsWith(' ') ? prevWord.text : '${prevWord.text} ';
              mergedWords.add(prevWord.copyWith(text: prevWithSpace));
            }
            mergedWords.add(LyricWord(
              timestamp: gLine.timestamp,
              durationMs: durationMs,
              text: wordText.trimLeft(),
            ));
          } else {
            mergedWords.add(LyricWord(
              timestamp: gLine.timestamp,
              durationMs: durationMs,
              text: k == 0 ? wordText.trimLeft() : wordText,
            ));
          }
          sb.write(wordText);
        }

        result.add(LyricLine(
          timestamp: baseTimestamp,
          text: sb.toString().trim(),
          isTimed: true,
          words: mergedWords,
        ));

        i = j;
      } else {
        result.add(current);
        i++;
      }
    }

    return result;
  }

  static bool isCJKCodeUnit(int codeUnit) {
    return (codeUnit >= 0x4e00 && codeUnit <= 0x9fff) || // CJK Unified Ideographs
        (codeUnit >= 0x3400 && codeUnit <= 0x4dbf) ||     // CJK Extension A
        (codeUnit >= 0x3040 && codeUnit <= 0x30ff) ||     // Hiragana & Katakana
        (codeUnit >= 0x31f0 && codeUnit <= 0x31ff) ||     // Katakana Phonetic Extensions
        (codeUnit >= 0x1100 && codeUnit <= 0x11ff) ||     // Hangul Jamo
        (codeUnit >= 0x3130 && codeUnit <= 0x318f) ||     // Hangul Compatibility Jamo
        (codeUnit >= 0xac00 && codeUnit <= 0xd7af);       // Hangul Syllables
  }

  static bool isCJKPunctuation(int codeUnit) {
    return (codeUnit >= 0x3000 && codeUnit <= 0x303f) || // CJK Symbols and Punctuation
        (codeUnit >= 0xff01 && codeUnit <= 0xff0f) ||     // Fullwidth ASCII punctuation
        (codeUnit >= 0xff1a && codeUnit <= 0xff20) ||
        (codeUnit >= 0xff3b && codeUnit <= 0xff40) ||
        (codeUnit >= 0xff5b && codeUnit <= 0xff65);
  }

  static bool isWordConstituent(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||     // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||         // a-z
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||         // 0-9
        (codeUnit >= 0x00c0 && codeUnit <= 0x024f) ||     // Latin Extended-A and Extended-B
        codeUnit == 0x27 ||                               // '
        codeUnit == 0x2019;                               // ’
  }

  static bool _isPunctuation(int codeUnit) {
    return isCJKPunctuation(codeUnit) ||
        codeUnit == 0x2c || // ,
        codeUnit == 0x2e || // .
        codeUnit == 0x21 || // !
        codeUnit == 0x3f || // ?
        codeUnit == 0x3a || // :
        codeUnit == 0x3b || // ;
        codeUnit == 0x22 || // "
        codeUnit == 0x28 || // (
        codeUnit == 0x29 || // )
        codeUnit == 0x2d || // -
        codeUnit == 0x2f || // /
        codeUnit == 0x7e;   // ~
  }

  static bool _needsSpace(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return false;
    final trimmed1 = text1.trimRight();
    final trimmed2 = text2.trimLeft();
    if (trimmed1.isEmpty || trimmed2.isEmpty) return false;

    final lastChar = trimmed1.codeUnitAt(trimmed1.length - 1);
    final firstChar = trimmed2.codeUnitAt(0);

    final isCJK1 = isCJKCodeUnit(lastChar) || isCJKPunctuation(lastChar);
    final isCJK2 = isCJKCodeUnit(firstChar) || isCJKPunctuation(firstChar);

    if (isCJK1 || isCJK2) return false;
    return true;
  }

  static bool _isCJKCodeUnit(int codeUnit) => isCJKCodeUnit(codeUnit);

  static bool _isLatinLetter(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) || // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7a) || // a-z
        (codeUnit >= 0x00c0 && codeUnit <= 0x024f); // Latin Extended-A & B
  }

  static bool _isLatinWordLetterOrDigit(int codeUnit) {
    return _isLatinLetter(codeUnit) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39);
  }

  /// Cleans redundant spaces introduced by AI in karaoke lyrics while preserving
  /// and restoring spaces between English/Latin words. When [originalLineText] is
  /// provided, restores original spaces between words based on original lyrics.
  static String sanitizeKaraokeLineSpaces(
    String rawLine, {
    String? originalLineText,
  }) {
    if (rawLine.isEmpty) return rawLine;

    final matches = _timestampLinePattern.allMatches(rawLine).toList();
    if (matches.isEmpty) return rawLine;

    // 单个时间戳普通行：若时间戳后紧跟空格且首字符为 CJK 字符，去除多余空格
    if (matches.length == 1) {
      final match = matches.first;
      if (match.start == 0) {
        final tag = match.group(0)!;
        final rest = rawLine.substring(match.end);
        if (rest.startsWith(RegExp(r'[\s\u3000]+'))) {
          final trimmedRest = rest.replaceFirst(RegExp(r'^[\s\u3000]+'), '');
          if (trimmedRest.isNotEmpty && isCJKCodeUnit(trimmedRest.codeUnitAt(0))) {
            return '$tag$trimmedRest';
          }
        }
      }
      return rawLine;
    }

    // 逐字歌词行（卡拉OK行，含多个时间戳）
    final prefix = rawLine.substring(0, matches.first.start).trim();
    final spans = <_KaraokeTagSpan>[];
    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final tag = match.group(0)!;
      final start = match.end;
      final end = (i + 1 < matches.length) ? matches[i + 1].start : rawLine.length;
      final text = rawLine.substring(start, end);
      spans.add(_KaraokeTagSpan(tag, text));
    }

    if (spans.isEmpty) return rawLine;

    // 行首第一个标签后面的多余前导空格去掉
    spans.first.text = spans.first.text.replaceFirst(RegExp(r'^[\s\u3000]+'), '');
    // 行尾末尾的多余空白去掉
    spans.last.text = spans.last.text.replaceFirst(RegExp(r'[\s\u3000]+$'), '');

    String? cleanOriginal;
    if (originalLineText != null && originalLineText.trim().isNotEmpty) {
      var orig = originalLineText.replaceAll(_timestampLinePattern, '').trim();
      final split = _splitInlineTranslation(orig);
      if (split != null) {
        orig = split.$1.trim();
      }
      if (orig.isNotEmpty) {
        cleanOriginal = orig;
      }
    }

    final spanOrigRanges = List<({int start, int end})?>.filled(
      spans.length,
      null,
      growable: false,
    );

    if (cleanOriginal != null) {
      var currOrigIdx = 0;
      final cleanOrigLower = cleanOriginal.toLowerCase();

      for (int i = 0; i < spans.length; i++) {
        final text = spans[i].text.trim();
        if (text.isEmpty) continue;
        final textLower = text.toLowerCase();
        final found = cleanOrigLower.indexOf(textLower, currOrigIdx);
        if (found != -1 && (found - currOrigIdx) <= 25) {
          spanOrigRanges[i] = (start: found, end: found + text.length);
          currOrigIdx = found + text.length;
        }
      }
    }

    for (int i = 0; i < spans.length - 1; i++) {
      final currentSpan = spans[i];
      final nextSpan = spans[i + 1];

      final hasSpace = currentSpan.text.endsWith(' ') ||
          currentSpan.text.endsWith('\t') ||
          currentSpan.text.endsWith('\u3000') ||
          nextSpan.text.startsWith(' ') ||
          nextSpan.text.startsWith('\t') ||
          nextSpan.text.startsWith('\u3000');

      final trimmedCurrent =
          currentSpan.text.replaceFirst(RegExp(r'[\s\u3000]+$'), '');
      final trimmedNext =
          nextSpan.text.replaceFirst(RegExp(r'^[\s\u3000]+'), '');

      bool? needSpace;

      // 优先根据原歌词该行在两词之间的空白情况还原
      if (cleanOriginal != null) {
        final rangeA = spanOrigRanges[i];
        final rangeB = spanOrigRanges[i + 1];
        if (rangeA != null && rangeB != null && rangeB.start >= rangeA.end) {
          final origGap = cleanOriginal.substring(rangeA.end, rangeB.start);
          needSpace = origGap.contains(RegExp(r'[\s\u3000]'));
        }
      }

      if (needSpace == null) {
        final codeA = trimmedCurrent.isNotEmpty
            ? trimmedCurrent.codeUnitAt(trimmedCurrent.length - 1)
            : null;
        final codeB =
            trimmedNext.isNotEmpty ? trimmedNext.codeUnitAt(0) : null;

        if (codeA != null && codeB != null) {
          if (_isLatinWordLetterOrDigit(codeA) &&
              _isLatinWordLetterOrDigit(codeB)) {
            // 英文/西文单词之间（例如 "Brand" 和 "new"），必须保留或自动补齐空格！
            needSpace = true;
          } else if (isCJKCodeUnit(codeA) && isCJKCodeUnit(codeB)) {
            // 两个都是 CJK 字符（例如 "繋" 和 "い"），坚决去除空格！
            needSpace = false;
          } else if (isCJKCodeUnit(codeA) ||
              isCJKPunctuation(codeA) ||
              isCJKCodeUnit(codeB) ||
              isCJKPunctuation(codeB)) {
            if (_isPunctuation(codeA) || _isPunctuation(codeB)) {
              // 标点符号与 CJK 之间，去除空格
              needSpace = false;
            } else {
              // 一边是 CJK 字符，一边是西文单词（例如 "声" 和 "Goodbye"）
              // 仅在已有空格时保留
              needSpace = hasSpace;
            }
          } else {
            needSpace = hasSpace;
          }
        } else {
          needSpace = hasSpace;
        }
      }

      if (needSpace) {
        currentSpan.text = '$trimmedCurrent ';
        nextSpan.text = trimmedNext;
      } else {
        currentSpan.text = trimmedCurrent;
        nextSpan.text = trimmedNext;
      }
    }

    final sb = StringBuffer();
    if (prefix.isNotEmpty) {
      sb.write(prefix);
    }
    for (final span in spans) {
      sb.write(span.tag);
      sb.write(span.text);
    }
    return sb.toString();
  }

  /// Cleans extra spaces in entire karaoke lyrics text across all lines.
  static String sanitizeKaraokeLyricsSpaces(
    String lyrics, {
    String? originalLyrics,
  }) {
    if (lyrics.isEmpty) return lyrics;
    final lines = lyrics.split(RegExp(r'\r?\n'));
    final targetLines =
        originalLyrics != null && originalLyrics.trim().isNotEmpty
            ? _extractSourceLyricLines(originalLyrics)
            : null;
    final result = <String>[];
    var targetLineIdx = 0;
    for (final line in lines) {
      if (isKaraokeLyricsLine(line)) {
        String? originalLineText;
        if (targetLines != null && targetLines.isNotEmpty) {
          originalLineText = _findMatchingSourceLine(
            line,
            targetLines,
            targetLineIdx,
          );
          targetLineIdx++;
        }
        result.add(
          sanitizeKaraokeLineSpaces(line, originalLineText: originalLineText),
        );
      } else {
        result.add(line);
      }
    }
    return result.join('\n');
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

  static Duration? parseTimestampToken(String rawToken) {
    var token = rawToken.trim();
    if (token.startsWith('[') || token.startsWith('<') || token.startsWith('(')) {
      token = token.substring(1);
    }
    if (token.endsWith(']') || token.endsWith('>') || token.endsWith(')')) {
      token = token.substring(0, token.length - 1);
    }
    token = token.trim();

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

  static bool isKaraokeLyricsLine(String rawLine) {
    final line = normalizeLrcLine(rawLine);
    if (line == null || line.isEmpty) return false;

    if (line.contains('<') && line.contains('>')) return true;

    final matches = _timestampLinePattern.allMatches(line).toList();
    if (matches.length <= 1) return false;

    var hasNonEmptyBetween = false;
    Duration? prevTs;
    var shortGapCount = 0;
    for (var i = 0; i < matches.length; i++) {
      final currentMatch = matches[i];
      if (i + 1 < matches.length) {
        final nextMatch = matches[i + 1];
        final between = line.substring(currentMatch.end, nextMatch.start).trim();
        if (between.isNotEmpty) {
          hasNonEmptyBetween = true;
        }
      }
      final ts = parseTimestampToken(currentMatch.group(0)!);
      if (ts != null && prevTs != null) {
        if ((ts - prevTs).abs() <= const Duration(milliseconds: 2500)) {
          shortGapCount++;
        }
      }
      prevTs = ts;
    }
    return hasNonEmptyBetween && shortGapCount >= 1;
  }

  static String normalizeGeneratedLyricsText(
    String? text, {
    bool preserveKaraokeLineStructure = false,
    String? originalLyrics,
  }) {
    var cleaned = cleanGeneratedLyricsText(text);
    if (cleaned.isEmpty) return '';
    if (!_timestampLinePattern.hasMatch(cleaned)) return cleaned;

    List<_SourceLyricLine>? targetLines;
    if (originalLyrics != null && originalLyrics.trim().isNotEmpty) {
      final restored = restoreKaraokeLineBreaks(
        karaokeLyrics: cleaned,
        originalLyrics: originalLyrics,
      );
      if (restored.isNotEmpty) {
        cleaned = restored;
      }
      targetLines = _extractSourceLyricLines(originalLyrics);
    }

    final normalizedLines = <String>[];
    var targetLineIdx = 0;
    for (final rawLine in cleaned.split(RegExp(r'\r?\n'))) {
      if (preserveKaraokeLineStructure || isKaraokeLyricsLine(rawLine)) {
        final collapsed = _collapseDuplicateLineStartTimestamps(rawLine.trim());
        String? originalLineText;
        if (targetLines != null && targetLines.isNotEmpty) {
          originalLineText = _findMatchingSourceLine(
            collapsed,
            targetLines,
            targetLineIdx,
          );
          targetLineIdx++;
        }
        final line = sanitizeKaraokeLineSpaces(
          collapsed,
          originalLineText: originalLineText,
        );
        if (line.isNotEmpty) {
          normalizedLines.add(line);
        }
        continue;
      }

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

  static String restoreKaraokeLineBreaks({
    required String karaokeLyrics,
    required String originalLyrics,
  }) {
    final trimmedKaraoke = karaokeLyrics.trim();
    final trimmedOriginal = originalLyrics.trim();
    if (trimmedKaraoke.isEmpty || trimmedOriginal.isEmpty) {
      return karaokeLyrics;
    }

    final targetLines = _extractSourceLyricLines(trimmedOriginal);
    if (targetLines.length <= 1) {
      return karaokeLyrics;
    }

    final existingLines = trimmedKaraoke
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (existingLines.length >= targetLines.length) {
      return karaokeLyrics;
    }

    final matches = _timestampLinePattern.allMatches(trimmedKaraoke).toList();
    if (matches.length < 2) {
      return karaokeLyrics;
    }

    final items = <_KaraokeItem>[];
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      final nextStart =
          (i + 1 < matches.length) ? matches[i + 1].start : trimmedKaraoke.length;
      final textBetween = trimmedKaraoke.substring(match.end, nextStart);
      final prevEnd = (i == 0) ? 0 : matches[i - 1].end;
      final textBeforeMatch = trimmedKaraoke.substring(prevEnd, match.start);
      final hasNewline =
          textBeforeMatch.contains('\n') || textBeforeMatch.contains('\r');

      items.add(_KaraokeItem(
        index: i,
        matchStart: match.start,
        matchEnd: match.end,
        tag: match.group(0)!,
        timestamp: parseTimestampToken(match.group(0)!),
        text: textBetween,
        normalizedText: _normalizeForLyricMatch(textBetween),
        hasPrecedingNewline: hasNewline,
      ));
    }

    var cum = 0;
    for (final item in items) {
      cum += item.normalizedText.length;
      item.cumLen = cum;
    }

    if (cum == 0 || items.length < targetLines.length) {
      return karaokeLyrics;
    }

    final numLines = targetLines.length;
    final numItems = items.length;

    final dp = List.generate(numLines, (_) => <int, double>{});
    final parent = List.generate(numLines, (_) => <int, int>{});

    double computeCost(int k, int i, int j) {
      final targetLine = targetLines[k];
      final targetNorm = targetLine.normalizedText;
      final targetLen = targetNorm.length;

      final startCum = (i == 0) ? 0 : items[i - 1].cumLen;
      final endCum = items[j - 1].cumLen;
      final segLen = endCum - startCum;

      final lenDiff = (segLen - targetLen).abs();
      var cost = lenDiff * 8.0;

      final leadText = _itemLeadText(items, i, 8);
      final targetPrefix = targetNorm.substring(0, min(8, targetNorm.length));
      final prefixMatchLen = _commonPrefixLength(leadText, targetPrefix);
      cost -= prefixMatchLen * 12.0;

      if (k + 1 < numLines && j < numItems) {
        final nextTargetNorm = targetLines[k + 1].normalizedText;
        final nextLeadText = _itemLeadText(items, j, 8);
        final nextTargetPrefix =
            nextTargetNorm.substring(0, min(8, nextTargetNorm.length));
        final nextPrefixMatchLen =
            _commonPrefixLength(nextLeadText, nextTargetPrefix);
        cost -= nextPrefixMatchLen * 12.0;
      }

      if (targetLine.timestamp != null && items[i].timestamp != null) {
        final diffMs =
            (targetLine.timestamp! - items[i].timestamp!).inMilliseconds.abs();
        final diffSec = diffMs / 1000.0;
        if (diffSec <= 2.0) {
          cost += diffSec * 4.0;
        } else if (diffSec <= 6.0) {
          cost += 8.0 + (diffSec - 2.0) * 10.0;
        } else {
          cost += 48.0 + (diffSec - 6.0) * 20.0;
        }
      }

      if (i > 0 && items[i].hasPrecedingNewline) {
        cost -= 25.0;
      }

      return cost;
    }

    final target0Len = targetLines[0].normalizedText.length;
    final maxEnd0 = numItems - (numLines - 1);
    for (var j = 1; j <= maxEnd0; j++) {
      final segLen = items[j - 1].cumLen;
      if (segLen < max(0, target0Len - 20) && j < maxEnd0) continue;
      if (segLen > target0Len + 30 && dp[0].length >= 5) break;

      final cost = computeCost(0, 0, j);
      dp[0][j] = cost;
      parent[0][j] = 0;
    }

    if (dp[0].isEmpty) {
      for (var j = 1; j <= min(maxEnd0, 10); j++) {
        dp[0][j] = computeCost(0, 0, j);
        parent[0][j] = 0;
      }
    }

    for (var k = 1; k < numLines - 1; k++) {
      final lineLen = targetLines[k].normalizedText.length;
      final maxEndK = numItems - (numLines - 1 - k);

      for (final i in dp[k - 1].keys) {
        final prevCost = dp[k - 1][i]!;
        final startCum = items[i - 1].cumLen;

        for (var j = i + 1; j <= maxEndK; j++) {
          final segLen = items[j - 1].cumLen - startCum;
          if (segLen < max(0, lineLen - 20) && j < maxEndK) continue;
          if (segLen > lineLen + 30 && dp[k].length >= 5) break;

          final totalCost = prevCost + computeCost(k, i, j);
          if (!dp[k].containsKey(j) || totalCost < dp[k][j]!) {
            dp[k][j] = totalCost;
            parent[k][j] = i;
          }
        }
      }

      if (dp[k].isEmpty) {
        final bestI = dp[k - 1].keys.first;
        final nextJ = min(bestI + 1, maxEndK);
        dp[k][nextJ] = dp[k - 1][bestI]! + computeCost(k, bestI, nextJ);
        parent[k][nextJ] = bestI;
      }
    }

    final lastK = numLines - 1;
    var bestLastCost = double.infinity;
    var bestLastStart = -1;

    for (final i in dp[lastK - 1].keys) {
      final totalCost = dp[lastK - 1][i]! + computeCost(lastK, i, numItems);
      if (totalCost < bestLastCost) {
        bestLastCost = totalCost;
        bestLastStart = i;
      }
    }

    if (bestLastStart == -1) {
      return karaokeLyrics;
    }

    final splitPoints = List<int>.filled(numLines, 0);
    splitPoints[lastK] = bestLastStart;
    var currEnd = bestLastStart;
    for (var k = lastK - 1; k >= 1; k--) {
      final prevStart = parent[k][currEnd]!;
      splitPoints[k] = prevStart;
      currEnd = prevStart;
    }
    splitPoints[0] = 0;

    for (var k = 1; k < numLines; k++) {
      final splitIdx = splitPoints[k];
      if (splitIdx > 0) {
        final prev = items[splitIdx - 1];
        final curr = items[splitIdx];
        if (prev.normalizedText.isEmpty &&
            prev.timestamp != null &&
            curr.timestamp != null &&
            (prev.timestamp! - curr.timestamp!).inMilliseconds.abs() <= 500 &&
            prev.tag.startsWith('[') &&
            curr.tag.startsWith('<')) {
          splitPoints[k] = splitIdx - 1;
        }
      }
    }

    final resultLines = <String>[];
    for (var k = 0; k < numLines; k++) {
      final startOffset = (k == 0) ? 0 : items[splitPoints[k]].matchStart;
      final endOffset = (k + 1 < numLines)
          ? items[splitPoints[k + 1]].matchStart
          : trimmedKaraoke.length;

      var lineStr = trimmedKaraoke.substring(startOffset, endOffset).trim();
      lineStr = _collapseDuplicateLineStartTimestamps(lineStr);
      if (lineStr.isNotEmpty) {
        resultLines.add(lineStr);
      }
    }

    if (resultLines.length < 2) {
      return karaokeLyrics;
    }

    return resultLines.join('\n').trim();
  }

  static List<_SourceLyricLine> _extractSourceLyricLines(String originalLyrics) {
    final parsed = parseLyricsWithTranslation(originalLyrics);
    if (parsed.syncedLines.isNotEmpty) {
      final result = <_SourceLyricLine>[];
      for (final line in parsed.syncedLines) {
        final cleanText = line.text.trim();
        final norm = _normalizeForLyricMatch(cleanText);
        if (norm.isNotEmpty) {
          result.add(_SourceLyricLine(
            text: cleanText,
            normalizedText: norm,
            timestamp: line.timestamp,
          ));
        }
      }
      if (result.length >= 2) {
        return result;
      }
    }

    final rawLines = originalLyrics.split(RegExp(r'\r?\n'));
    final result = <_SourceLyricLine>[];
    for (final rawLine in rawLines) {
      var line = rawLine.trim();
      if (line.isEmpty) continue;
      if (RegExp(r'^\[[a-zA-Z]{2,8}:').hasMatch(line)) continue;

      Duration? ts;
      final firstMatch = _timestampLinePattern.firstMatch(line);
      if (firstMatch != null) {
        ts = parseTimestampToken(firstMatch.group(0)!);
        line = line.replaceAll(_timestampLinePattern, '').trim();
      }

      final split = _splitInlineTranslation(line);
      if (split != null) {
        line = split.$1.trim();
      }

      final norm = _normalizeForLyricMatch(line);
      if (norm.isNotEmpty) {
        result.add(_SourceLyricLine(
          text: line,
          normalizedText: norm,
          timestamp: ts,
        ));
      }
    }
    return result;
  }

  static String _normalizeForLyricMatch(String text) {
    var s = text.replaceAll(_timestampLinePattern, '');
    s = s.toLowerCase();
    s = s.replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
    return s;
  }

  static String _itemLeadText(
    List<_KaraokeItem> items,
    int startIdx,
    int maxChars,
  ) {
    final sb = StringBuffer();
    for (var idx = startIdx; idx < items.length; idx++) {
      sb.write(items[idx].normalizedText);
      if (sb.length >= maxChars) break;
    }
    return sb.toString();
  }

  static int _commonPrefixLength(String a, String b) {
    final maxLen = min(a.length, b.length);
    var len = 0;
    while (len < maxLen && a.codeUnitAt(len) == b.codeUnitAt(len)) {
      len++;
    }
    return len;
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

  static String _collapseDuplicateLineStartTimestamps(String rawLine) {
    var line = rawLine.trim();
    if (line.isEmpty) return line;

    final matches = _timestampLinePattern.allMatches(line).toList();
    if (matches.length < 2) return line;

    // 检查第 1 个与第 2 个时间戳是否紧贴在行首且均为 [ ] 格式（去除大模型在行首错误并排的方括号时间戳）
    if (matches[0].start == 0 &&
        matches[1].start == matches[0].end &&
        matches[0].group(0)!.startsWith('[') &&
        matches[1].group(0)!.startsWith('[')) {
      final t1 = parseTimestampToken(matches[0].group(0)!);
      final t2 = parseTimestampToken(matches[1].group(0)!);
      if (t1 != null && t2 != null && (t2 - t1).abs() < const Duration(seconds: 3)) {
        line = line.substring(0, matches[0].end) + line.substring(matches[1].end).trimLeft();
      }
    }
    return line;
  }

  static String? _findMatchingSourceLine(
    String rawLine,
    List<_SourceLyricLine> targetLines,
    int hintIndex,
  ) {
    if (targetLines.isEmpty) return null;

    final lineMatch = _timestampLinePattern.firstMatch(rawLine);
    final lineTs =
        lineMatch != null ? parseTimestampToken(lineMatch.group(0)!) : null;

    // 1. 若 hintIndex 处的起始时间戳高度吻合（<= 3s），直接采用
    if (hintIndex >= 0 && hintIndex < targetLines.length) {
      final candidate = targetLines[hintIndex];
      if (lineTs != null && candidate.timestamp != null) {
        if ((lineTs - candidate.timestamp!).abs() <=
            const Duration(seconds: 3)) {
          return candidate.text;
        }
      } else if (lineTs == null && candidate.timestamp == null) {
        return candidate.text;
      }
    }

    // 2. 根据起始时间戳在所有目标行中寻找最接近的一行
    if (lineTs != null) {
      _SourceLyricLine? bestCandidate;
      Duration? minDiff;
      for (final tLine in targetLines) {
        if (tLine.timestamp == null) continue;
        final diff = (lineTs - tLine.timestamp!).abs();
        if (diff <= const Duration(seconds: 3)) {
          if (minDiff == null || diff < minDiff) {
            minDiff = diff;
            bestCandidate = tLine;
          }
        }
      }
      if (bestCandidate != null) {
        return bestCandidate.text;
      }
    }

    // 3. 回退至 hintIndex
    if (hintIndex >= 0 && hintIndex < targetLines.length) {
      return targetLines[hintIndex].text;
    }

    return null;
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

class _SourceLyricLine {
  final String text;
  final String normalizedText;
  final Duration? timestamp;

  _SourceLyricLine({
    required this.text,
    required this.normalizedText,
    this.timestamp,
  });
}

class _KaraokeItem {
  final int index;
  final int matchStart;
  final int matchEnd;
  final String tag;
  final Duration? timestamp;
  final String text;
  final String normalizedText;
  final bool hasPrecedingNewline;
  int cumLen = 0;

  _KaraokeItem({
    required this.index,
    required this.matchStart,
    required this.matchEnd,
    required this.tag,
    required this.timestamp,
    required this.text,
    required this.normalizedText,
    required this.hasPrecedingNewline,
  });
}

class _KaraokeTagSpan {
  final String tag;
  String text;
  _KaraokeTagSpan(this.tag, this.text);
}
