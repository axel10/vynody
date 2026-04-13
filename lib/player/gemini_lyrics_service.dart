import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show Headers, ResponseType;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'gemini_api_key_service.dart';
import '../utils/network_client.dart';
import '../utils/lrc_utils.dart';

part 'gemini_lyrics_api_client.dart';
part 'gemini_lyrics_stream_parser.dart';

class GeminiLyricsService {
  GeminiLyricsService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance,
      _api = _GeminiLyricsApiClient(client: client);

  final NetworkClient _client;
  final _GeminiLyricsApiClient _api;
  final _GeminiStreamTextParser _streamParser = _GeminiStreamTextParser();
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
    final apiKey = await _api.loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[GeminiLyrics] GEMINI_API_KEY not found, skip translation.');
      return false;
    }

    final sourceLines = _splitLyricsLines(lyrics);
    final blankLineIndexes = <int>[];
    final compactSourceLines = <String>[];
    for (var i = 0; i < sourceLines.length; i++) {
      final line = _stripTimestampPrefix(sourceLines[i]).trim();
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
    final sourceLyricsForModel = _normalizeSourceLyrics(lyrics);
    final prompt =
        '将以下歌词翻译成$targetLanguageName，仅输出目标译文不输出其他内容。不要输出原文。'
        '请保留完整时间轴和原有分行顺序，不要删减、合并、重排任何一行，也不要自行补充空行、编号或解释。'
        '如果输入中带有时间轴，请在输出中原样保留对应时间轴，程序会在后处理去掉时间轴。'
        '总结整首歌的意境并结合上下文尽量意译。如果无标题不要自行生成标题。\n'
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
        final rawCurrent = translatedBuffer.toString();
        final cleanedCurrent = _stripTimestamps(
          LrcUtils.cleanGeneratedLyricsText(rawCurrent),
        );
        final current = _visibleTranslationText(
          cleanedCurrent,
          rawCurrent,
          force: force,
        );
        if (current.isEmpty) return;
        if (!force && current.length == lastPrintedLength) return;
        lastPrintedLength = current.length;
        final lines = _normalizeTranslationLines(current, targetLineCount);
        final restoredLines = _restoreBlankLines(
          lines,
          blankLineIndexes,
          sourceLines.length,
        );
        final visibleLines = restoredLines
            .map((line) => _stripTimestampPrefix(line).trimRight())
            .toList(growable: false);
        final snapshot = visibleLines.join('\n');
        if (onProgress != null && (force || snapshot != lastProgressSnapshot)) {
          lastProgressSnapshot = snapshot;
          onProgress(visibleLines, snapshot);
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

          final chunk = _streamParser.extractText(data);
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
    final apiKey = await _api.loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[GeminiLyrics] GEMINI_API_KEY not found, skip generation.');
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[GeminiLyrics] file not found for generation: $filePath');
      return null;
    }

    final mimeType = _api.mimeTypeForFilePath(filePath);
    final normalizedTitle = songTitle?.trim();
    final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
        ? ''
        : '这首歌的标题是《$normalizedTitle》。';
    final prompt =
        '$titleHint'
        '输出这首歌的完整的带时间轴的标准LRC格式歌词,每一行歌词前面都带有一个方括号包裹的时间点，格式通常为：[mm:ss.ms]歌词内容。mm: 分钟（00-99）ss: 秒（00-59）ms: 毫秒（通常为 3 位）。'
        '仅输出结果不输出其他内容。';

    return _generateFromUploadedFile(
      file: file,
      apiKey: apiKey,
      mimeType: mimeType,
      modelId: modelId,
      prompt: prompt,
      preserveTimestamps: true,
      onUploadProgress: onUploadProgress,
      onStageChanged: onStageChanged,
      onProgress: onProgress,
    );
  }

  Future<String?> generateTimelineFromLyrics({
    required String filePath,
    required String lyrics,
    String? songTitle,
    String modelId = 'gemini-3.1-flash-lite-preview',
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final apiKey = await _api.loadApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[GeminiLyrics] GEMINI_API_KEY not found, skip timeline.');
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[GeminiLyrics] file not found for timeline: $filePath');
      return null;
    }

    final mimeType = _api.mimeTypeForFilePath(filePath);
    final normalizedLyrics = lyrics.trim();
    if (normalizedLyrics.isEmpty) {
      debugPrint('[GeminiLyrics] no usable lyrics for timeline generation.');
      return null;
    }

    // final normalizedTitle = songTitle?.trim();
    // final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
    //     ? ''
    //     : '这首歌的标题是《$normalizedTitle》。';
    final hasOriginalTimestamps = _hasTimestampedLyrics(normalizedLyrics);
    final promptPrefix = hasOriginalTimestamps
        ? '这是这首歌的歌词和源文件，但是时间轴和原曲有些对不上，帮我重新核对下时间轴。仅输出结果即可，不要输出其他内容（我拿来当api用的）'
        : '这是这首歌的歌词和原文件，帮我把这些歌词打上时间轴。格式为[mm:ss.ms]歌词内容。mm: 分钟（00-99）ss: 秒（00-59）ms: 毫秒（通常为 3 位）。仅输出结果不输出其他内容（我拿来当api用的）';
    final prompt =
        // '$titleHint'
        '$promptPrefix\n'
        '```text\n'
        '$normalizedLyrics\n'
        '```';

    return _generateFromUploadedFile(
      file: file,
      apiKey: apiKey,
      mimeType: mimeType,
      modelId: modelId,
      prompt: prompt,
      preserveTimestamps: true,
      onUploadProgress: onUploadProgress,
      onStageChanged: onStageChanged,
      onProgress: onProgress,
    );
  }

  Future<String?> _generateFromUploadedFile({
    required File file,
    required String apiKey,
    required String mimeType,
    required String modelId,
    required String prompt,
    required bool preserveTimestamps,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final filePath = file.path;
    try {
      onStageChanged?.call('uploading');
      // 先把本地文件上传到 Gemini 文件服务，后续生成请求只引用文件 URI。
      // 这样模型可以直接读取整份输入，而不是只靠 prompt 猜测。
      debugPrint('[GeminiLyrics] 开始上传文件: $filePath');
      final uploadedFile = await _api.uploadFile(
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
      final isActive = await _api.waitForFileActive(
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

      // 这里使用 streamGenerateContent，是为了让结果在模型生成时就能逐步回传给界面。
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

          final chunk = _streamParser.extractText(data);
          if (chunk == null || chunk.isEmpty) continue;
          generatedBuffer.write(chunk);
          emitProgress();
        }
      } finally {
        emitProgress(force: true);
      }

      final generatedText = _streamParser.extractText(
        generatedBuffer.toString(),
      );
      final cleanedText = LrcUtils.cleanGeneratedLyricsText(
        generatedText ?? generatedBuffer.toString(),
      );
      final finalText = preserveTimestamps
          ? cleanedText
          : _stripTimestamps(cleanedText);
      if (finalText.isEmpty) {
        debugPrint('[GeminiLyrics] empty lyrics response.');
        debugPrint(
          '[GeminiLyrics] raw generate response: ${generatedBuffer.toString()}',
        );
        return null;
      }

      // 最终结果会再做一次清洗，去掉代码块、杂项前缀和非 LRC 内容。
      debugPrint('[GeminiLyrics] final generated lyrics:');
      debugPrint(finalText);
      onProgress?.call(finalText, true);
      return finalText;
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

  List<String> _splitLyricsLines(String lyrics) {
    return lyrics.split(_lineSplitPattern);
  }

  String _normalizeSourceLyrics(String lyrics) {
    return _splitLyricsLines(lyrics).join('\n').trim();
  }

  String _stripTimestampPrefix(String line) {
    return line.replaceAll(_timestampLinePattern, '');
  }

  bool _hasTimestampedLyrics(String lyrics) {
    return _timestampLinePattern.hasMatch(lyrics);
  }

  String _stripTimestamps(String text) {
    return LrcUtils.stripTimestamps(text);
  }

  String _visibleTranslationText(
    String cleanedText,
    String rawText, {
    required bool force,
  }) {
    if (cleanedText.isEmpty) return '';
    if (force || rawText.endsWith('\n') || rawText.endsWith('\r')) {
      return cleanedText;
    }

    final lines = _splitTranslationLines(cleanedText);
    if (lines.length <= 1) return '';
    return lines.take(lines.length - 1).join('\n').trim();
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
}
