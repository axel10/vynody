import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show Headers, ResponseType;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/network_client.dart';
import '../utils/lrc_utils.dart';

class _GeminiFileUploadResult {
  final String name;
  final String uri;
  final String? state;

  const _GeminiFileUploadResult({
    required this.name,
    required this.uri,
    this.state,
  });
}

class GeminiLyricsTranslationService {
  GeminiLyricsTranslationService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;
  String? _cachedApiKey;
  static final RegExp _lineSplitPattern = RegExp(r'\r?\n');
  static final RegExp _timestampLinePattern = RegExp(
    r'\[\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*\]',
  );

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

    final sourceLines = _stripTimestampsPreservingBlankLines(lyrics);
    final blankLineIndexes = <int>[];
    final compactSourceLines = <String>[];
    for (var i = 0; i < sourceLines.length; i++) {
      final line = sourceLines[i].trim();
      if (line.isEmpty) {
        blankLineIndexes.add(i);
      } else {
        compactSourceLines.add(line);
      }
    }

    final targetLineCount = compactSourceLines.length;
    if (targetLineCount == 0) {
      debugPrint('[GeminiLyrics] no usable lyrics after stripping timestamps.');
      return false;
    }
    final targetLanguageName = _targetLanguageName(targetLanguageCode);
    final sourceLyricsForModel = compactSourceLines.join('\n');
    final prompt =
        '将以下歌词翻译成$targetLanguageName，仅输出目标译文不输出其他内容。不要输出原文。'
        '总结整首歌的意境并结合上下文尽量意译。'
        '请保持有内容歌词的分行顺序，每一行对应一行译文。'
        '原文中的空行已由程序单独处理，请不要自行补充空行、编号或时间轴。如果无标题不要自行生成标题。\n'
        '$sourceLyricsForModel';
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
      final response = await _client.post(
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
        final restoredLines = _restoreBlankLines(
          lines,
          blankLineIndexes,
          sourceLines.length,
        );
        final snapshot = restoredLines.join('\n');
        if (onProgress != null && (force || snapshot != lastProgressSnapshot)) {
          lastProgressSnapshot = snapshot;
          onProgress(restoredLines, snapshot);
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

  Future<String?> generateLyricsFromFile({
    required String filePath,
    String? songTitle,
    String modelId = 'gemini-3.1-flash-lite-preview',
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final apiKey = await _loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[GeminiLyrics] GEMINI_API_KEY not found, skip generation.');
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[GeminiLyrics] file not found for generation: $filePath');
      return null;
    }

    final mimeType = _mimeTypeForFilePath(filePath);

    try {
      onStageChanged?.call('uploading');
      // 先把本地音频文件上传到 Gemini 文件服务，后续生成请求只引用文件 URI。
      // 这样模型可以直接“看见”整首歌，而不是只靠标题或歌词文本猜测。
      debugPrint('[GeminiLyrics] 开始上传文件: $filePath');
      final uploadedFile = await _uploadFile(
        file: file,
        apiKey: apiKey,
        mimeType: mimeType,
        onUploadProgress: onUploadProgress,
      );
      if (uploadedFile == null) {
        debugPrint('[GeminiLyrics] 文件上传失败: $filePath');
        return null;
      }

      onStageChanged?.call('processing');

      final fileName = uploadedFile.name;
      final fileUri = uploadedFile.uri;
      final isActive = await _waitForGeminiFileActive(
        fileName: fileName,
        apiKey: apiKey,
        initialState: uploadedFile.state,
      );
      if (!isActive) {
        debugPrint(
          '[GeminiLyrics] file never became ACTIVE after upload: '
          'name=$fileName uri=$fileUri',
        );
        return null;
      }

      final normalizedTitle = songTitle?.trim();
      final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
          ? ''
          : '这首歌的标题是《$normalizedTitle》。';
      final prompt =
          '$titleHint'
          '输出这首歌的完整的带时间轴的标准LRC格式歌词,每一行歌词前面都带有一个方括号包裹的时间点，格式通常为：[mm:ss.ms]歌词内容。mm: 分钟（00-99）ss: 秒（00-59）ms: 毫秒（通常为 3 位）。'
          '仅输出结果不输出其他内容。';
      final requestData = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'file_data': {'mime_type': mimeType, 'file_uri': fileUri},
              },
            ],
          },
        ],
      };

      // 这里使用 streamGenerateContent，是为了让歌词在模型生成时就能逐步回传给界面。
      debugPrint('[GeminiLyrics] generation request model=$modelId');
      debugPrint('[GeminiLyrics] generation request filePath=$filePath');
      debugPrint('[GeminiLyrics] generation request fileName=$fileName');
      debugPrint('[GeminiLyrics] generation request mimeType=$mimeType');
      debugPrint('[GeminiLyrics] generation request fileUri=$fileUri');
      debugPrint(
        '[GeminiLyrics] generation request payload=${jsonEncode(requestData)}',
      );

      final response = await _client.post(
        'https://generativelanguage.googleapis.com/v1beta/models/$modelId:streamGenerateContent',
        queryParameters: {'key': apiKey},
        data: requestData,
        options: Options(
          responseType: ResponseType.stream,
          contentType: Headers.jsonContentType,
        ),
      );

      final body = response.data;
      if (body == null || body.stream == null) {
        debugPrint('[GeminiLyrics] Empty streaming body.');
        return null;
      }

      debugPrint('[GeminiLyrics] generation stream connected');
      onStageChanged?.call('generating');

      final generatedBuffer = StringBuffer();
      String lastEmitted = '';

      void emitProgress({bool force = false}) {
        final current = LrcUtils.cleanGeneratedLyricsText(
          generatedBuffer.toString(),
        );
        if (current.isEmpty) return;
        if (!force && current == lastEmitted) return;
        lastEmitted = current;
        onProgress?.call(current, false);
      }

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
          if (chunk == null || chunk.isEmpty) continue;
          generatedBuffer.write(chunk);
          emitProgress();
        }
      } finally {
        emitProgress(force: true);
      }

      final generatedText = _extractText(generatedBuffer.toString());
      final cleanedText = LrcUtils.cleanGeneratedLyricsText(
        generatedText ?? generatedBuffer.toString(),
      );
      if (cleanedText.isEmpty) {
        debugPrint('[GeminiLyrics] empty lyrics response.');
        debugPrint(
          '[GeminiLyrics] raw generate response: ${generatedBuffer.toString()}',
        );
        return null;
      }

      // 最终结果会再做一次清洗，去掉代码块、杂项前缀和非 LRC 内容。
      debugPrint('[GeminiLyrics] final generated lyrics:');
      debugPrint(cleanedText);
      onProgress?.call(cleanedText, true);
      return cleanedText;
    } on DioException catch (e) {
      debugPrint('[GeminiLyrics] generation failed: ${e.message}');
      debugPrint('[GeminiLyrics] generation status: ${e.response?.statusCode}');
      debugPrint('[GeminiLyrics] generation response: ${e.response?.data}');
      debugPrint(
        '[GeminiLyrics] generation request path: ${e.requestOptions.path}',
      );
      debugPrint(
        '[GeminiLyrics] generation request query: ${e.requestOptions.queryParameters}',
      );
      debugPrint(
        '[GeminiLyrics] generation request headers: ${e.requestOptions.headers}',
      );
      debugPrint(
        '[GeminiLyrics] generation request data: ${e.requestOptions.data}',
      );
      debugPrint(
        '[GeminiLyrics] generation response data: ${e.response?.data}',
      );
    } catch (e) {
      debugPrint('[GeminiLyrics] generation error: $e');
    }

    return null;
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

  List<String> _splitTranslationLines(String text) {
    return text.split(_lineSplitPattern);
  }

  List<String> _normalizeTranslationLines(String text, int targetLineCount) {
    final lines = _splitTranslationLines(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (targetLineCount <= 0) return lines;
    if (lines.length <= targetLineCount) return lines;
    return lines.take(targetLineCount).toList(growable: false);
  }

  List<String> _restoreBlankLines(
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

  List<String> _stripTimestampsPreservingBlankLines(String lyrics) {
    return lyrics
        .split(_lineSplitPattern)
        .map((line) {
          final withoutTimestamps = line.replaceAll(_timestampLinePattern, '');
          return withoutTimestamps.trimRight();
        })
        .toList(growable: false);
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

  Future<_GeminiFileUploadResult?> _uploadFile({
    required File file,
    required String apiKey,
    required String mimeType,
    void Function(double progress)? onUploadProgress,
  }) async {
    final fileSize = await file.length();
    final fileName = p.basename(file.path);
    final fileBytes = await file.readAsBytes();

    final initResponse = await _client.post(
      'https://generativelanguage.googleapis.com/upload/v1beta/files',
      queryParameters: {'key': apiKey},
      options: Options(
        headers: {
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'start',
          'X-Goog-Upload-Header-Content-Length': fileSize,
          'X-Goog-Upload-Header-Content-Type': mimeType,
          'Content-Type': 'application/json',
        },
      ),
      data: {
        'file': {'display_name': fileName},
      },
    );

    debugPrint('[GeminiLyrics] upload init fileName=$fileName');
    debugPrint('[GeminiLyrics] upload init mimeType=$mimeType');
    debugPrint('[GeminiLyrics] upload init fileSize=$fileSize');

    final uploadUrl = initResponse.headers.value('X-Goog-Upload-URL');
    if (uploadUrl == null || uploadUrl.isEmpty) {
      throw Exception('未能获取 Gemini 上传 URL');
    }

    debugPrint('[GeminiLyrics] upload session url=$uploadUrl');

    final uploadResponse = await _client.post(
      uploadUrl,
      options: Options(
        headers: {
          'X-Goog-Upload-Protocol': 'resumable',
          'X-Goog-Upload-Command': 'upload, finalize',
          'X-Goog-Upload-Offset': 0,
          Headers.contentLengthHeader: fileBytes.length,
        },
        contentType: mimeType,
      ),
      data: fileBytes,
      onSendProgress: (sent, total) {
        if (total <= 0) return;
        final progress = (sent / total * 100).toStringAsFixed(2);
        debugPrint('[GeminiLyrics] upload progress: $progress%');
        onUploadProgress?.call(sent / total);
      },
    );

    debugPrint(
      '[GeminiLyrics] upload response status=${uploadResponse.statusCode}',
    );
    debugPrint('[GeminiLyrics] upload response data=${uploadResponse.data}');

    final uploadedFile = _parseUploadedFile(uploadResponse.data);
    if (uploadedFile == null) {
      throw Exception('未能从 Gemini 上传响应中解析文件信息');
    }

    return uploadedFile;
  }

  Future<bool> _waitForGeminiFileActive({
    required String fileName,
    required String apiKey,
    String? initialState,
  }) async {
    final normalizedInitialState = initialState?.trim().toUpperCase();
    if (normalizedInitialState == null || normalizedInitialState.isEmpty) {
      return true;
    }
    if (normalizedInitialState == 'ACTIVE') {
      return true;
    }

    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));

      final info = await _fetchGeminiFileInfo(fileName, apiKey);
      final state = info?.state?.trim().toUpperCase();
      if (state == null || state == 'ACTIVE') {
        return true;
      }
      if (state == 'FAILED') {
        throw Exception('Gemini 文件处理失败: $fileName');
      }
    }

    return false;
  }

  Future<_GeminiFileUploadResult?> _fetchGeminiFileInfo(
    String fileName,
    String apiKey,
  ) async {
    final response = await _client.get(
      'https://generativelanguage.googleapis.com/v1beta/$fileName',
      queryParameters: {'key': apiKey},
    );
    return _parseUploadedFile(response.data);
  }

  _GeminiFileUploadResult? _parseUploadedFile(dynamic data) {
    if (data is! Map) return null;

    final root = data['file'];
    final fileMap = root is Map ? root : data;
    final name = fileMap['name']?.toString().trim();
    final uri = fileMap['uri']?.toString().trim();
    if (name == null || name.isEmpty || uri == null || uri.isEmpty) {
      return null;
    }

    final state = fileMap['state']?.toString();
    return _GeminiFileUploadResult(name: name, uri: uri, state: state);
  }

  String _mimeTypeForFilePath(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.mp4':
      case '.m4b':
        return 'audio/mp4';
      case '.flac':
        return 'audio/flac';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.opus':
        return 'audio/opus';
      case '.webm':
        return 'audio/webm';
      case '.wma':
        return 'audio/x-ms-wma';
      default:
        return 'application/octet-stream';
    }
  }

  String? _extractText(dynamic raw) {
    if (raw is Map || raw is List) {
      final extracted = _extractTextFromDecoded(raw);
      if (extracted != null && extracted.isNotEmpty) {
        return extracted;
      }
      return null;
    }

    if (raw is! String) {
      return null;
    }

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
