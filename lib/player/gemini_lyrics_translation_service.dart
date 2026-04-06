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
    String modelId = 'gemma-4-31b-it',
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[GeminiLyrics] GEMINI_API_KEY not found, skip translation.');
      return false;
    }

    final prompt = '将以下歌词翻译成中文，仅输出结果不输出其他内容。$lyrics';
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
      Timer? printTimer;

      void printBuffer({bool force = false}) {
        final current = translatedBuffer.toString().trim();
        if (current.isEmpty) return;
        if (!force && current.length == lastPrintedLength) return;
        lastPrintedLength = current.length;
        debugPrint('[GeminiLyrics] translated: $current');
      }

      printTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        printBuffer();
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
        }
      } finally {
        printTimer.cancel();
      }

      printBuffer(force: true);
      return true;
    } on DioException catch (e) {
      debugPrint('[GeminiLyrics] request failed: ${e.message}');
    } catch (e) {
      debugPrint('[GeminiLyrics] translation failed: $e');
    }
    return false;
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
