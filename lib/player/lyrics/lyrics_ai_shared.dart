import 'dart:convert';

import 'package:dio/dio.dart' show FormData;
import 'package:flutter/foundation.dart';

import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/lrc_utils.dart';

final class LyricsAiPromptBuilder {
  const LyricsAiPromptBuilder._();

  static String buildGenerateLyricsPrompt({String? songTitle}) {
    final normalizedTitle = songTitle?.trim();
    final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
        ? ''
        : '这首歌的标题是《$normalizedTitle》。';
    return '$titleHint'
        '输出这首歌的完整的带时间轴的标准LRC格式歌词,每一行歌词前面都带有一个方括号包裹的时间点，格式通常为：[mm:ss.ms]歌词内容。'
        '特别注意时间戳格式：mm 是分钟（00-99），ss 是秒（00-59），ms 是毫秒。第一位是分不是秒，绝对不能把第一位当成秒，未到 1 分钟时分钟位必须是 00（例如第 4 秒是 [00:04.00]，绝对不能写成 [04:00.00]）。'
        '合理组织每一行歌词长度，不要太长也不要太短。'
        '仅输出结果不输出其他内容。';
  }

  static String buildGenerateTimelinePrompt({
    required String lyrics,
  }) {
    final cleanLyrics = LrcUtils.stripTimestamps(lyrics);
    const prompt = '这是这首歌的歌词和原文件，帮我把这些歌词打上时间轴。'
        '格式为[mm:ss.ms]歌词内容。特别注意：mm 是分钟（00-99），ss 是秒（00-59），ms 是毫秒。第一位是分不是秒，绝对不能把第一位当成秒，未到 1 分钟时分钟位必须是 00（例如第 4 秒是 [00:04.00]，绝对不能写成 [04:00.00]）。'
        '仅输出结果不输出其他内容（我拿来当api用的）';
    return '$prompt\n```text\n$cleanLyrics\n```';
  }

  static String buildConvertToKaraokePrompt({
    required String lyrics,
  }) {
    final targetLyrics = lyrics.trim();
    return '这是这首歌的歌词和音频，请将歌词转换为卡拉OK逐字时间轴格式（word-by-word LRC / Enhanced LRC）。\n'
        '要求：\n'
        '1. 严格保持原歌词的分行结构和行数不变，原歌词有几行输出就必须是几行！绝对禁止在词与词、字与字之间换行！\n'
        '2. 每一行开头只允许包含一个时间轴（即该行第一个词的起始时间），严禁在行首并排出现两个时间轴（绝对禁止像 [00:01.00][00:01.50] 这样并排）！\n'
        '3. 格式标准示例：[00:01.23]word1 [00:01.80]word2 [00:02.30]word3，或 [00:01.23]字[00:01.80]字[00:02.30]字。行首时间轴即为第一个词的开始时间，后续词前面依次标记时间轴。\n'
        '4. 【打轴粒度要求（极其重要）】：\n'
        '   - 英文/西文：按单词（word-by-word）打轴，单词与单词之间保留正常空格（如：[00:01.23]Hello [00:01.80]world）。\n'
        '   - 多语言混杂特别注意：当歌词中包含英文单词（如日文/中文歌曲中混杂英文短语，例如“届けBrand new heart”）时，英文单词之间【绝对必须保留正常空格】，严禁把英文单词间的空格删掉导致粘连（必须输出 [ts]Brand [ts]new [ts]heart，严禁输出 [ts]Brand[ts]new[ts]heart）！\n'
        '   - 日文：必须细化到【每一个假名和每一个汉字】（逐音节/逐假名打轴），严禁按词语、文节或短语合并打轴！\n'
        '     * 错误示例：[00:05.15]もう[00:05.65]ヤキモキが[00:06.66]止まらないの （严重错误：将多个假名/短语打包在一起）\n'
        '     * 正确示例：[00:05.15]も[00:05.35]う[00:05.65]ヤ[00:05.85]キ[00:06.05]モ[00:06.25]キ[00:06.45]が[00:06.66]止[00:06.86]ま[00:07.06]ら[00:07.26]な[00:07.46]い[00:07.66]の\n'
        '   - 中文/韩文：必须细化到【每一个单字】（逐字打轴，每个汉字或韩语音节块都必须有独立时间戳），严禁按词组打包（例如必须输出 [00:01.00]我[00:01.50]们，严禁输出 [00:01.00]我们）！\n'
        '5. 【重要时间戳格式】：时间戳格式严格为 [mm:ss.xx]，其中第一位 mm 是【分（00-99）】，第二位 ss 是【秒（00-59）】，xx 是百分秒/毫秒。必须特别注意：第一位是分不是秒！绝对不能把第一位当成秒！例如歌曲在第 4.15 秒发音，时间戳必须是 [00:04.15]，绝对不能写成 [04:15.08]（[04:15.08] 表示 4分15秒，是严重的时间轴错乱）！未达到 1 分钟时，第一位分钟位必须是 00（例如 15 秒是 [00:15.00]）！\n'
        '6. 【空格规范】：中文、日文、韩文等非英文歌词，字与字之间、字与时间戳之间严禁添加任何空格（例如必须输出 [00:14.39]繋[00:14.65]い[00:15.00]だ，严禁输出 [00:14.39] 繋[00:14.65] い 或 [00:14.39]繋 [00:14.65]い 等多余空格格式）！对于歌词中的英文单词，单词与单词之间必须保留正常空格，原歌词中英文单词之间有空格的，打轴后单词之间必须保留空格，绝不能删除。\n'
        '7. 保持歌词文本内容原样不变，不要翻译，不要增加或删减任何歌词行，不要输出任何解释说明或Markdown代码块以外的内容。\n'
        '待转换歌词如下：\n'
        '$targetLyrics';
  }

  static String buildTranslateLyricsPrompt({
    required String lyrics,
    required String targetLanguageCode,
  }) {
    final targetLanguageName = LyricsAiTranslationTextHelper.targetLanguageName(
      targetLanguageCode,
    );
    return '将以下歌词翻译成$targetLanguageName，仅输出目标译文不输出其他内容。不要输出原文。'
        '请保留完整时间轴和原有分行顺序，不要删减、合并、重排任何一行，也不要自行补充空行、编号或解释。'
        '如果输入中带有时间轴，请在输出中原样保留对应时间轴，程序会在后处理去掉时间轴。'
        '总结整首歌的意境并结合上下文尽量意译。如果无标题不要自行生成标题。\n'
        '${lyrics.trim()}';
  }
}

final class LyricsAiTranslationPreparation {
  const LyricsAiTranslationPreparation({
    required this.sourceLines,
    required this.blankLineIndexes,
    required this.compactSourceLines,
  });

  final List<String> sourceLines;
  final List<int> blankLineIndexes;
  final List<String> compactSourceLines;

  int get targetLineCount => compactSourceLines.length;
}

final class LyricsAiTranslationProgressSnapshot {
  const LyricsAiTranslationProgressSnapshot({
    required this.visibleLines,
    required this.visibleText,
  });

  final List<String> visibleLines;
  final String visibleText;
}

final class LyricsAiTranslationStreamProcessor {
  LyricsAiTranslationStreamProcessor({
    required LyricsAiTranslationPreparation preparation,
    this.emitPartialLineForStreaming = true,
  }) : _preparation = preparation;

  final LyricsAiTranslationPreparation _preparation;
  final bool emitPartialLineForStreaming;
  final StringBuffer _translatedBuffer = StringBuffer();
  String _lastSnapshot = '';
  int _lastPrintedLength = -1;
  bool _receivedAnyChunk = false;

  bool get hasReceivedAnyChunk => _receivedAnyChunk;

  void addChunk(String chunk) {
    if (chunk.isEmpty) return;
    _receivedAnyChunk = true;
    _translatedBuffer.write(chunk);
  }

  LyricsAiTranslationProgressSnapshot? buildProgressSnapshot({
    bool force = false,
    bool dedupeByLength = false,
  }) {
    final rawCurrent = _translatedBuffer.toString();
    final cleanedCurrent = LyricsAiTranslationTextHelper.stripTimestamps(
      rawCurrent,
    );
    final current = emitPartialLineForStreaming
        ? cleanedCurrent
        : LyricsAiTranslationTextHelper.visibleTranslationText(
            cleanedCurrent,
            rawCurrent,
            force: force,
          );
    if (current.isEmpty) {
      return null;
    }
    if (dedupeByLength && !force && current.length == _lastPrintedLength) {
      return null;
    }
    _lastPrintedLength = current.length;

    final lines = LyricsAiTranslationTextHelper.normalizeTranslationLines(
      current,
      _preparation.targetLineCount,
    );
    final restoredLines = LyricsAiTranslationTextHelper.restoreBlankLines(
      lines,
      _preparation.blankLineIndexes,
      _preparation.sourceLines.length,
    );
    final visibleLines = restoredLines
        .map(
          (line) => LyricsAiTranslationTextHelper.stripTimestampPrefix(
            line,
          ).trimRight(),
        )
        .toList(growable: false);
    final snapshot = visibleLines.join('\n');
    if (!force && snapshot == _lastSnapshot) {
      return null;
    }
    _lastSnapshot = snapshot;
    return LyricsAiTranslationProgressSnapshot(
      visibleLines: visibleLines,
      visibleText: snapshot,
    );
  }

  String get finalVisibleText => LyricsAiTranslationTextHelper.stripTimestamps(
    _translatedBuffer.toString(),
  ).trim();
}

final class LyricsAiTranslationTextHelper {
  LyricsAiTranslationTextHelper._();

  static final RegExp _lineSplitPattern = RegExp(r'\r?\n');
  static final RegExp _timestampLinePattern = RegExp(
    r'[\[<\(]\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*[\]>\)]',
  );

  static LyricsAiTranslationPreparation prepareSourceLyrics(String lyrics) {
    final sourceLines = splitLines(lyrics);
    final blankLineIndexes = <int>[];
    final compactSourceLines = <String>[];
    for (var i = 0; i < sourceLines.length; i++) {
      final line = stripTimestampPrefix(sourceLines[i]).trim();
      if (line.isEmpty) {
        blankLineIndexes.add(i);
      } else {
        compactSourceLines.add(line);
      }
    }
    return LyricsAiTranslationPreparation(
      sourceLines: sourceLines,
      blankLineIndexes: blankLineIndexes,
      compactSourceLines: compactSourceLines,
    );
  }

  static List<String> splitLines(String text) {
    return text.split(_lineSplitPattern);
  }

  static String normalizeSourceLyrics(String lyrics) {
    return splitLines(lyrics).join('\n').trim();
  }

  static String stripTimestamps(String lyrics) {
    final normalized = LrcUtils.normalizeGeneratedLyricsText(lyrics);
    return LrcUtils.stripTimestamps(normalized);
  }

  static String stripTimestampPrefix(String line) {
    return line.replaceAll(_timestampLinePattern, '');
  }

  static List<String> normalizeTranslationLines(
    String text,
    int targetLineCount,
  ) {
    final lines = splitLines(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (targetLineCount <= 0) return lines;
    if (lines.length <= targetLineCount) return lines;
    return lines.take(targetLineCount).toList(growable: false);
  }

  static List<String> restoreBlankLines(
    List<String> translatedLines,
    List<int> blankLineIndexes,
    int originalLineCount,
  ) {
    if (originalLineCount <= 0) return const [];
    if (translatedLines.isEmpty && blankLineIndexes.isEmpty) {
      return List<String>.filled(originalLineCount, '', growable: false);
    }

    final blankLineIndexSet = blankLineIndexes.toSet();
    final restoredLines = List<String>.filled(
      originalLineCount,
      '',
      growable: false,
    );
    var translatedIndex = 0;

    for (var i = 0; i < originalLineCount; i++) {
      if (blankLineIndexSet.contains(i)) continue;
      if (translatedIndex >= translatedLines.length) break;
      restoredLines[i] = translatedLines[translatedIndex++];
    }

    return restoredLines;
  }

  static String visibleTranslationText(
    String cleanedText,
    String rawText, {
    required bool force,
  }) {
    if (cleanedText.isEmpty) return '';
    if (force || rawText.endsWith('\n') || rawText.endsWith('\r')) {
      return cleanedText;
    }

    final lines = splitLines(cleanedText);
    if (lines.length <= 1) return '';
    return lines.take(lines.length - 1).join('\n').trim();
  }

  static String targetLanguageName(String languageCode) {
    switch (languageCode.toLowerCase().trim()) {
      case 'zh':
      case 'zh-cn':
      case 'zh-hans':
        return _l10n().chineseLanguage;
      case 'zh-tw':
      case 'zh-hant':
        return _l10n().traditionalChinese;
      case 'en':
        return _l10n().englishLanguage;
      case 'ja':
        return _l10n().japaneseLanguage;
      case 'ko':
        return _l10n().koreanLanguage;
      case 'fr':
        return _l10n().frenchLanguage;
      case 'de':
        return _l10n().germanLanguage;
      case 'es':
        return _l10n().spanishLanguage;
      case 'pt':
        return _l10n().portugueseLanguage;
      case 'ru':
        return _l10n().russianLanguage;
      case 'tr':
        return _l10n().turkishLanguage;
      default:
        return languageCode.trim().isEmpty
            ? _l10n().targetLanguage
            : languageCode;
    }
  }

}

final class LyricsAiLogger {
  const LyricsAiLogger._();

  static void logRequest({
    required String provider,
    required String action,
    String? model,
    required dynamic data,
    Map<String, Object?>? extra,
  }) {
    final sanitized = _sanitize(data);
    final payloadJson = _safeJsonEncode(sanitized);
    final modelPart =
        (model != null && model.trim().isNotEmpty) ? ' model=$model' : '';
    final extraPart = (extra != null && extra.isNotEmpty)
        ? ' extra=${_safeJsonEncode(extra)}'
        : '';

    debugPrint(
      '[LyricsAi][$provider][$action]$modelPart$extraPart payload: $payloadJson',
    );
  }

  static dynamic _sanitize(dynamic data) {
    if (data is Map) {
      return data.map((key, value) {
        final keyStr = key.toString();
        // 针对 base64 音频或超大二进制数据脱敏截断，避免控制台卡死
        if ((keyStr == 'data' || keyStr == 'audioBase64') &&
            value is String &&
            value.length > 500) {
          return MapEntry(
            key,
            '<base64 audio omitted, length=${value.length}>',
          );
        }
        if (value is String &&
            value.length > 20000 &&
            keyStr != 'text' &&
            keyStr != 'content' &&
            keyStr != 'lyrics') {
          return MapEntry(
            key,
            '<data omitted, length=${value.length}>',
          );
        }
        return MapEntry(key, _sanitize(value));
      });
    } else if (data is List) {
      return data.map(_sanitize).toList(growable: false);
    } else if (data is FormData) {
      final fields = data.fields.map((f) => '${f.key}=${f.value}').toList();
      final files = data.files
          .map((f) => '${f.key}=${f.value.filename} (${f.value.length} bytes)')
          .toList();
      return '<FormData fields=$fields files=$files>';
    }
    return data;
  }

  static String _safeJsonEncode(dynamic data) {
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }
}

AppLocalizations _l10n() => currentAppL10n;
