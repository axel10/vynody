import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException, Headers, ResponseType;
import 'package:flutter/foundation.dart';

import '../utils/lrc_utils.dart';
import '../utils/network_client.dart';
import 'lyrics_ai_api_client.dart';
import 'lyrics_ai_openrouter.dart';
import 'lyrics_ai_stream_parser.dart';
import 'lyrics_generation_result.dart';
import 'settings_service.dart';

class _LyricsAiCredentials {
  const _LyricsAiCredentials({required this.provider, required this.apiKey});

  final LyricsAiProvider provider;
  final String apiKey;
}

class LyricsAiService {
  static const String _primaryGeminiModelId = 'gemini-3-flash-preview';
  static const String _fallbackGeminiModelId = 'gemini-2.5-flash';

  LyricsAiService({
    NetworkClient? client,
    required SettingsService settingsService,
  }) : _client = client ?? NetworkClient.instance,
       _settingsService = settingsService,
       _geminiApiClient = GeminiLyricsApiClient(client: client),
       _openRouterClient = LyricsAiOpenRouterClient(
         client: client,
         streamParser: LyricsAiStreamTextParser(),
       );

  final NetworkClient _client;
  final SettingsService _settingsService;
  final GeminiLyricsApiClient _geminiApiClient;
  final LyricsAiOpenRouterClient _openRouterClient;
  final LyricsAiStreamTextParser _streamParser = LyricsAiStreamTextParser();
  static final RegExp _lineSplitPattern = RegExp(r'\r?\n');
  static final RegExp _timestampLinePattern = RegExp(
    r'\[\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*\]',
  );

  Future<_LyricsAiCredentials?> _loadGenerationCredentials() async {
    final provider = _settingsService.lyricsAiProvider;
    final apiKey = _settingsService.activeLyricsGenerationApiKey.trim();
    if (apiKey.isEmpty) {
      return null;
    }

    return _LyricsAiCredentials(provider: provider, apiKey: apiKey);
  }

  String _providerLabel(LyricsAiProvider provider) {
    return provider.displayName;
  }

  String _missingApiKeyMessage(
    LyricsAiProvider provider, {
    required String action,
  }) {
    final providerName = _providerLabel(provider);
    return '未找到 $providerName API Key，无法$action。';
  }

  Future<bool> translateLyricsStream({
    required String lyrics,
    String targetLanguageCode = 'zh',
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    String modelId = 'gemma-4-31b-it',
  }) async {
    final apiKey = _settingsService.geminiApiKey.trim();
    if (apiKey.isEmpty) {
      debugPrint('[LyricsAi] gemini API key not found, skip translation.');
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
      debugPrint('[LyricsAi] no usable lyrics after stripping timestamps.');
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
        '[LyricsAi] request start, lyrics length=${lyrics.length}',
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
        debugPrint('[LyricsAi] Empty streaming body.');
        return false;
      }

      debugPrint('[LyricsAi] stream connected');
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
        debugPrint('[LyricsAi] translated: $current');
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
      debugPrint('[LyricsAi] request failed: ${e.message}');
    } catch (e) {
      debugPrint('[LyricsAi] translation failed: $e');
    }
    return false;
  }

  Future<LyricsGenerationResult> generateLyricsFromFile({
    required String filePath,
    String? songTitle,
    String modelId = _primaryGeminiModelId,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final credentials = await _loadGenerationCredentials();
    if (credentials == null) {
      debugPrint('[LyricsAi] active API key not found, skip generation.');
      return LyricsGenerationResult.failure(
        _missingApiKeyMessage(
          _settingsService.lyricsAiProvider,
          action: '生成歌词',
        ),
      );
    }

    if (credentials.provider == LyricsAiProvider.openRouter) {
      return _openRouterClient.generateLyricsFromFile(
        apiKey: credentials.apiKey,
        filePath: filePath,
        songTitle: songTitle,
        onUploadProgress: onUploadProgress,
        onStageChanged: onStageChanged,
        onProgress: onProgress,
      );
    }

    final apiKey = credentials.apiKey;

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[LyricsAi] file not found for generation: $filePath');
      return const LyricsGenerationResult.failure(
        '本地歌曲文件不存在，无法生成歌词。',
      );
    }

    final mimeType = _geminiApiClient.mimeTypeForFilePath(filePath);
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

  Future<LyricsGenerationResult> generateTimelineFromLyrics({
    required String filePath,
    required String lyrics,
    String? songTitle,
    String modelId = _primaryGeminiModelId,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final credentials = await _loadGenerationCredentials();
    if (credentials == null) {
      debugPrint('[LyricsAi] active API key not found, skip timeline.');
      return LyricsGenerationResult.failure(
        _missingApiKeyMessage(
          _settingsService.lyricsAiProvider,
          action: '生成时间轴',
        ),
      );
    }

    if (credentials.provider == LyricsAiProvider.openRouter) {
      return _openRouterClient.generateTimelineFromLyrics(
        apiKey: credentials.apiKey,
        filePath: filePath,
        lyrics: lyrics,
        onUploadProgress: onUploadProgress,
        onStageChanged: onStageChanged,
        onProgress: onProgress,
      );
    }

    final apiKey = credentials.apiKey;

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[LyricsAi] file not found for timeline: $filePath');
      return const LyricsGenerationResult.failure(
        '本地歌曲文件不存在，无法生成时间轴。',
      );
    }

    final mimeType = _geminiApiClient.mimeTypeForFilePath(filePath);
    final normalizedLyrics = lyrics.trim();
    if (normalizedLyrics.isEmpty) {
      debugPrint('[LyricsAi] no usable lyrics for timeline generation.');
      return const LyricsGenerationResult.failure(
        '没有可用歌词，无法生成时间轴。',
      );
    }

    final hasOriginalTimestamps = _hasTimestampedLyrics(normalizedLyrics);
    final promptPrefix = hasOriginalTimestamps
        ? '这是这首歌的歌词和源文件，但是时间轴和原曲有些对不上，帮我重新核对下时间轴。仅输出结果即可，不要输出其他内容（我拿来当api用的）'
        : '这是这首歌的歌词和原文件，帮我把这些歌词打上时间轴。格式为[mm:ss.ms]歌词内容。mm: 分钟（00-99）ss: 秒（00-59）ms: 毫秒（通常为 3 位）。仅输出结果不输出其他内容（我拿来当api用的）';
    final prompt =
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

  Future<LyricsGenerationResult> _generateFromUploadedFile({
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
      debugPrint('[LyricsAi] 开始上传文件: $filePath');
      final uploadedFile = await _geminiApiClient.uploadFile(
        file: file,
        apiKey: apiKey,
        mimeType: mimeType,
        onUploadProgress: onUploadProgress,
      );
      if (uploadedFile == null) {
        debugPrint('[LyricsAi] 文件上传失败: $filePath');
        return const LyricsGenerationResult.failure('文件上传失败，请重试。');
      }

      onStageChanged?.call('processing');

      final fileName = uploadedFile.name;
      final fileUri = uploadedFile.uri;
      final isActive = await _geminiApiClient.waitForFileActive(
        fileName: fileName,
        apiKey: apiKey,
        initialState: uploadedFile.state,
      );
      if (!isActive) {
        debugPrint(
          '[LyricsAi] file never became ACTIVE after upload: '
          'name=$fileName uri=$fileUri',
        );
        return const LyricsGenerationResult.failure(
          '上传后的文件未能就绪，请稍后重试。',
        );
      }
      return _generateWithUploadedFileUri(
        apiKey: apiKey,
        fileUri: fileUri,
        filePath: filePath,
        fileName: fileName,
        mimeType: mimeType,
        modelId: modelId,
        prompt: prompt,
        preserveTimestamps: preserveTimestamps,
        onProgress: onProgress,
      );
    } catch (e) {
      return LyricsGenerationResult.failure(
        _formatGenerationErrorMessage(e, fallback: '生成歌词时发生未知错误。'),
      );
    }
  }

  Future<LyricsGenerationResult> _generateWithUploadedFileUri({
    required String apiKey,
    required String fileUri,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String modelId,
    required String prompt,
    required bool preserveTimestamps,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    String? lastErrorMessage;
    final modelCandidates = <String>[
      modelId,
      if (modelId == _primaryGeminiModelId) _fallbackGeminiModelId,
    ];

    for (final effectiveModelId in modelCandidates) {
      var shouldTryNextModel = false;

      for (var attempt = 1; attempt <= 3; attempt++) {
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
        debugPrint('[LyricsAi] generation request model=$effectiveModelId');
        debugPrint('[LyricsAi] generation request attempt=$attempt');
        debugPrint('[LyricsAi] generation request filePath=$filePath');
        debugPrint('[LyricsAi] generation request fileName=$fileName');
        debugPrint('[LyricsAi] generation request mimeType=$mimeType');
        debugPrint('[LyricsAi] generation request fileUri=$fileUri');
        debugPrint('[LyricsAi] generation request payload=${jsonEncode(requestData)}');

        try {
          final response = await _client.post(
            'https://generativelanguage.googleapis.com/v1beta/models/$effectiveModelId:streamGenerateContent',
            queryParameters: {'key': apiKey},
            data: requestData,
            options: Options(
              responseType: ResponseType.stream,
              contentType: Headers.jsonContentType,
            ),
          );

          final body = response.data;
          if (body == null || body.stream == null) {
            lastErrorMessage = 'Gemini 返回了空流响应。';
            debugPrint('[LyricsAi] Empty streaming body.');
            if (attempt < 3) {
              debugPrint(
                '[LyricsAi] generation retry scheduled attempt=${attempt + 1} '
                'reason=$lastErrorMessage',
              );
              continue;
            }
            break;
          }

          debugPrint('[LyricsAi] generation stream connected');
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

          final textStream = body.stream.cast<List<int>>().transform(
            utf8.decoder,
          );
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

          final generatedText = _streamParser.extractText(generatedBuffer.toString());
          final cleanedText = LrcUtils.cleanGeneratedLyricsText(
            generatedText ?? generatedBuffer.toString(),
          );
          final finalText = preserveTimestamps
              ? cleanedText
              : _stripTimestamps(cleanedText);
          if (finalText.isEmpty) {
            lastErrorMessage = 'Gemini 返回了空响应。';
            debugPrint('[LyricsAi] empty lyrics response.');
            debugPrint(
              '[LyricsAi] raw generate response: ${generatedBuffer.toString()}',
            );
            if (attempt < 3) {
              debugPrint(
                '[LyricsAi] generation retry scheduled attempt=${attempt + 1} '
                'reason=$lastErrorMessage',
              );
              continue;
            }
            break;
          }

          // 最终结果会再做一次清洗，去掉代码块、杂项前缀和非 LRC 内容。
          debugPrint('[LyricsAi] final generated lyrics:');
          debugPrint(finalText);
          onProgress?.call(finalText, true);
          return LyricsGenerationResult.success(finalText);
        } on DioException catch (e) {
          lastErrorMessage = _formatGenerationErrorMessage(e);
          debugPrint('[LyricsAi] generation failed: ${e.message}');
          debugPrint(
            '[LyricsAi] generation status: ${e.response?.statusCode}',
          );
          debugPrint('[LyricsAi] generation response: ${e.response?.data}');
          debugPrint(
            '[LyricsAi] generation request path: ${e.requestOptions.path}',
          );
          debugPrint(
            '[LyricsAi] generation request query: ${e.requestOptions.queryParameters}',
          );
          debugPrint(
            '[LyricsAi] generation request headers: ${e.requestOptions.headers}',
          );
          debugPrint(
            '[LyricsAi] generation request data: ${e.requestOptions.data}',
          );
          debugPrint(
            '[LyricsAi] generation response data: ${e.response?.data}',
          );

          final statusCode = e.response?.statusCode;
          if (effectiveModelId == _primaryGeminiModelId &&
              _shouldUseFallbackModel(statusCode)) {
            // 这里只切换模型并重试同一个 fileUri，不会重新上传文件。
            shouldTryNextModel = true;
            debugPrint(
              '[LyricsAi] model downgraded to $_fallbackGeminiModelId '
              'after status=$statusCode, reusing fileUri=$fileUri.',
            );
            break;
          }

          if (effectiveModelId == _fallbackGeminiModelId) {
            final specialMessage = _fallbackFailureMessageForStatus(statusCode);
            if (specialMessage != null) {
              return LyricsGenerationResult.failure(specialMessage);
            }
          }
        } catch (e) {
          lastErrorMessage = _formatGenerationErrorMessage(e);
          debugPrint('[LyricsAi] generation error: $e');
        }

        if (attempt < 3) {
          debugPrint(
            '[LyricsAi] generation retry scheduled attempt=${attempt + 1} '
            'reason=$lastErrorMessage',
          );
          continue;
        }
      }

      if (shouldTryNextModel) {
        continue;
      }
      break;
    }

    return LyricsGenerationResult.failure('生成歌词失败：$lastErrorMessage');
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

  String _formatGenerationErrorMessage(Object error, {String? fallback}) {
    if (error is DioException) {
      final response = error.response;
      final statusCode = response?.statusCode;
      final responseData = response?.data;

      if (responseData is Map) {
        final errorMap = responseData['error'];
        if (errorMap is Map) {
          final message = errorMap['message']?.toString().trim();
          if (message != null && message.isNotEmpty) {
            if (statusCode == null) {
              return message;
            }
            return '($statusCode) $message';
          }
        }
      }

      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        if (statusCode == null) {
          return message;
        }
        return '($statusCode) $message';
      }
    }

    final text = error.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }

    return fallback ?? '未知错误';
  }

  bool _shouldUseFallbackModel(int? statusCode) {
    return statusCode == 429 || _isServerError(statusCode);
  }

  bool _isServerError(int? statusCode) {
    return statusCode != null && statusCode >= 500 && statusCode < 600;
  }

  String? _fallbackFailureMessageForStatus(int? statusCode) {
    if (statusCode == 429) {
      return '今天额度已用完，请等待明天额度恢复再试';
    }
    if (_isServerError(statusCode)) {
      return '谷歌AI服务遭遇大量请求，暂时不可用';
    }
    return null;
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
