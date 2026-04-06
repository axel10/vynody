import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class GeminiLyricsTranslationService {
  GeminiLyricsTranslationService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  String? _cachedApiKey;

  Future<bool> translateLyricsStream({
    required String lyrics,
    String targetLanguageCode = 'zh',
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    String modelId = 'gemma-4-31b-it',
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[GeminiLyrics] GEMINI_API_KEY not found, skip translation.');
      return false;
    }

    final sourceLyrics = _stripTimestamps(lyrics);
    final sourceLines = sourceLyrics.split(RegExp(r'\r?\n'));
    final targetLineCount = sourceLines.isEmpty ? 0 : sourceLines.length;
    if (targetLineCount == 0) {
      debugPrint('[GeminiLyrics] no usable lyrics after stripping timestamps.');
      return false;
    }
    final targetLanguageName = _targetLanguageName(targetLanguageCode);
    final prompt =
        '将以下歌词翻译成$targetLanguageName，仅输出目标译文不输出其他内容。不要输出原文。'
        '总整首歌的意境，尽量意译。'
        '请保持原有分行顺序，每一行对应原歌词的一行。请严格保持原歌词结构。'
        '不要输出时间轴，不要输出解释，不要输出编号。不要省略任何一行，包括标题。\n'
        '$sourceLyrics';
    final requestData = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
      },
      'tools': [
        {'googleSearch': {}},
      ],
    };

    final url =
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:streamGenerateContent';

    try {
      debugPrint(
        '[GeminiLyrics] request start, lyrics length=${lyrics.length}',
      );
      final response = await _dio.post(
        url,
        data: requestData,
        queryParameters: {'key': apiKey},
        options: Options(
          responseType: ResponseType.stream,
          contentType: Headers.jsonContentType,
        ),
      );

      final body = response.data;
      if (body == null || body.stream == null) {
        debugPrint('[GeminiLyrics] Empty streaming body.');
        return false;
      }

      debugPrint('[GeminiLyrics] stream connected');
      final translatedBuffer = StringBuffer();
      var lastPrintedLength = -1;
      var lastProgressSnapshot = '';
      Timer? printTimer;

      void emitProgress({bool force = false}) {
        final current = translatedBuffer.toString().trim();
        if (current.isEmpty) return;
        if (!force && current.length == lastPrintedLength) return;
        lastPrintedLength = current.length;
        final lines = _normalizeTranslationLines(current, targetLineCount);
        final snapshot = lines.join('\n');
        if (onProgress != null && (force || snapshot != lastProgressSnapshot)) {
          lastProgressSnapshot = snapshot;
          onProgress(lines, snapshot);
        }
        debugPrint('[GeminiLyrics] translated: $current');
      }

      printTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        emitProgress();
      });

      final textStream = body.stream.cast<List<int>>().transform(utf8.decoder);
      try {
        await for (final line in textStream.transform(const LineSplitter())) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          final data = trimmed.startsWith('data:')
              ? trimmed.substring(5).trim()
              : trimmed;
          if (data.isEmpty || data == '[DONE]') {
            if (data == '[DONE]') break;
            continue;
          }

          final chunk = _extractText(data);
          if (chunk == null || chunk.isEmpty) {
            continue;
          }
          translatedBuffer.write(chunk);
          emitProgress();
        }
      } finally {
        printTimer.cancel();
      }

      emitProgress(force: true);
      return true;
    } on DioException catch (e) {
      debugPrint('[GeminiLyrics] request failed: ${e.message}');
    } catch (e) {
      debugPrint('[GeminiLyrics] translation failed: $e');
    }
    return false;
  }

  String _targetLanguageName(String languageCode) {
    switch (languageCode.toLowerCase().trim()) {
      case 'zh':
      case 'zh-cn':
      case 'zh-hans':
        return '中文';
      case 'zh-tw':
      case 'zh-hant':
        return '繁体中文';
      case 'en':
        return '英文';
      case 'ja':
        return '日文';
      case 'ko':
        return '韩文';
      case 'fr':
        return '法文';
      case 'de':
        return '德文';
      case 'es':
        return '西班牙文';
      case 'pt':
        return '葡萄牙文';
      case 'ru':
        return '俄文';
      default:
        return languageCode.trim().isEmpty ? '目标语言' : languageCode;
    }
  }

  String _stripTimestamps(String lyrics) {
    final lines = lyrics.split(RegExp(r'\r?\n'));
    final stripped = lines.map((line) {
      final withoutTimestamps = line.replaceAll(
        RegExp(r'\[(?:\d{2}:\d{2}(?:\.\d{1,3})?)\]'),
        '',
      );
      return withoutTimestamps.trimRight();
    }).toList();
    return stripped.join('\n').trim();
  }

  List<String> _splitTranslationLines(String text) {
    return text.split(RegExp(r'\r?\n'));
  }

  List<String> _normalizeTranslationLines(String text, int targetLineCount) {
    final lines = _splitTranslationLines(text);
    if (targetLineCount <= 0) return lines;
    if (lines.length >= targetLineCount) {
      return lines.take(targetLineCount).toList(growable: false);
    }

    final normalized = List<String>.from(lines);
    while (normalized.length < targetLineCount) {
      normalized.add('');
    }
    return normalized;
  }

  Future<String?> _loadApiKey() async {
    if (_cachedApiKey != null) return _cachedApiKey;

    final candidates = <File>[];

    var currentDir = Directory.current.absolute;
    for (var i = 0; i < 5; i++) {
      candidates.add(File(p.join(currentDir.path, 'api_keys.json')));
      final parent = currentDir.parent;
      if (parent.path == currentDir.path) {
        break;
      }
      currentDir = parent;
    }

    var executableDir = File(Platform.resolvedExecutable).parent.absolute;
    for (var i = 0; i < 3; i++) {
      candidates.add(File(p.join(executableDir.path, 'api_keys.json')));
      final parent = executableDir.parent;
      if (parent.path == executableDir.path) {
        break;
      }
      executableDir = parent;
    }

    for (final file in candidates) {
      if (!await file.exists()) continue;
      try {
        final content = await file.readAsString();
        final jsonData = jsonDecode(content);
        if (jsonData is Map<String, dynamic>) {
          final key = jsonData['GEMINI_API_KEY']?.toString().trim();
          if (key != null && key.isNotEmpty) {
            _cachedApiKey = key;
            return key;
          }
        }
      } catch (e) {
        debugPrint(
          '[GeminiLyrics] failed to read api key from ${file.path}: $e',
        );
      }
    }

    return null;
  }

  String? _extractText(String raw) {
    try {
      final decoded = jsonDecode(raw);
      final extracted = _extractTextFromDecoded(decoded);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
    } catch (_) {
      // Ignore malformed SSE payloads and continue with a loose fallback.
    }

    final looseMatch = RegExp(
      r'"text"\s*:\s*"((?:\\.|[^"\\])*)"',
      dotAll: true,
    ).firstMatch(raw);
    if (looseMatch != null) {
      final rawText = '"${looseMatch.group(1)!}"';
      try {
        final text = jsonDecode(rawText);
        if (text is String && text.isNotEmpty) {
          return text;
        }
      } catch (_) {
        // Keep returning null if the fallback cannot be decoded.
      }
    }

    return null;
  }

  String? _extractTextFromDecoded(dynamic decoded) {
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        if (entry.key == 'text' && entry.value is String) {
          final text = entry.value as String;
          if (text.isNotEmpty) return text;
        }

        final nested = _extractTextFromDecoded(entry.value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
      return null;
    }

    if (decoded is List) {
      for (final item in decoded) {
        final nested = _extractTextFromDecoded(item);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
      return null;
    }

    return null;
  }
}
