import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart'
    show
        CancelToken,
        DioException,
        DioExceptionType,
        Headers,
        Options,
        RequestOptions,
        ResponseType;
import 'package:flutter/foundation.dart';

import 'package:vibe_flow/utils/lrc_utils.dart';
import 'package:vibe_flow/utils/localized_text.dart';
import 'package:vibe_flow/utils/network_client.dart';
import 'package:vibe_flow/player/lyrics/lyrics_ai_api_client.dart';
import 'package:vibe_flow/player/lyrics/lyrics_ai_openrouter.dart';
import 'package:vibe_flow/player/lyrics/lyrics_ai_stream_parser.dart';
import 'package:vibe_flow/player/lyrics/lyrics_generation_result.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';

final class LyricsAiRuntimeConfig {
  const LyricsAiRuntimeConfig({
    required this.generationPrimaryModel,
    required this.generationFallbackModel,
    required this.translationPrimaryModel,
    required this.translationFallbackModel,
    required this.geminiApiKey,
    required this.openRouterApiKey,
  });

  final LyricsAiModelSelection generationPrimaryModel;
  final LyricsAiModelSelection generationFallbackModel;
  final LyricsAiModelSelection translationPrimaryModel;
  final LyricsAiModelSelection translationFallbackModel;
  final String geminiApiKey;
  final String openRouterApiKey;

  String apiKeyForProvider(LyricsAiProvider provider) {
    return switch (provider) {
      LyricsAiProvider.googleAiStudio => geminiApiKey,
      LyricsAiProvider.openRouter => openRouterApiKey,
    };
  }

  String get activeGenerationProviderTag =>
      generationPrimaryModel.provider.storageValue;
}

class _LyricsGenerationOutcome {
  const _LyricsGenerationOutcome({
    required this.result,
  });

  final LyricsGenerationResult result;
}

class LyricsAiService {
  LyricsAiService({
    NetworkClient? client,
    required LyricsAiRuntimeConfig Function() readConfig,
  }) : _client = client ?? NetworkClient.instance,
       _readConfig = readConfig,
       _geminiApiClient = GeminiLyricsApiClient(client: client),
       _openRouterClient = LyricsAiOpenRouterClient(
         client: client,
         streamParser: LyricsAiStreamTextParser(),
       );

  final NetworkClient _client;
  final LyricsAiRuntimeConfig Function() _readConfig;
  final GeminiLyricsApiClient _geminiApiClient;
  final LyricsAiOpenRouterClient _openRouterClient;
  final LyricsAiStreamTextParser _streamParser = LyricsAiStreamTextParser();
  static const int maxGenerationRetries = 2;
  static const int maxGenerationAttempts = maxGenerationRetries + 1;
  static final RegExp _lineSplitPattern = RegExp(r'\r?\n');
  static final RegExp _timestampLinePattern = RegExp(
    r'\[\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*\]',
  );

  LyricsAiModelSelection get _generationPrimaryModel =>
      _readConfig().generationPrimaryModel;
  LyricsAiModelSelection get _generationFallbackModel =>
      _readConfig().generationFallbackModel;
  LyricsAiModelSelection get _translationPrimaryModel =>
      _readConfig().translationPrimaryModel;
  LyricsAiModelSelection get _translationFallbackModel =>
      _readConfig().translationFallbackModel;

  LyricsAiRuntimeConfig get _config => _readConfig();

  String get currentGenerationModelLabel {
    return _modelLabel(_generationPrimaryModel);
  }

  String get currentGenerationProviderTag => _config.activeGenerationProviderTag;

  String _googleModelLabel(String modelId) {
    return 'Google AI Studio · ${SettingsService.lyricsModelDisplayName(modelId)}';
  }

  String _openRouterModelLabel(String modelId) {
    return 'OpenRouter · ${SettingsService.lyricsModelDisplayName(modelId)}';
  }

  String _modelLabel(LyricsAiModelSelection selection) {
    return switch (selection.provider) {
      LyricsAiProvider.googleAiStudio => _googleModelLabel(selection.modelId),
      LyricsAiProvider.openRouter => _openRouterModelLabel(selection.modelId),
    };
  }

  String _providerLabel(LyricsAiProvider provider) {
    return provider.displayName;
  }

  String _missingApiKeyMessage(
    LyricsAiProvider provider, {
    required String action,
  }) {
    final providerName = _providerLabel(provider);
    return _t(
      '未找到 $providerName API Key，无法$action。',
      'API key for $providerName was not found, so $action is unavailable.',
    );
  }

  static String get _googleServerFlakyMessage => localizedText(
    'Google服务器开小差了，重试一下或许会成功哦',
    'Google is having a rough moment. Please try again and it may succeed.',
  );

  static String get _translationServerFlakyMessage => localizedText(
    '谷歌服务器开小差了，请等一会儿后重试',
    'Google is having a rough moment. Please try again later.',
  );

  bool _shouldUseGoogleServerFlakyMessage(Object error) {
    if (error is DioException) {
      final message = error.message?.trim();
      return message == null || message.isEmpty;
    }

    return false;
  }

  Future<String?> translateLyricsStream({
    required String lyrics,
    String targetLanguageCode = 'zh',
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    void Function(String? modelLabel)? onModelLabelChanged,
    String? modelId,
    CancelToken? cancelToken,
  }) async {
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
      return _t('没有可用于翻译的歌词。', 'No lyrics are available for translation.');
    }
    final targetLanguageName = _targetLanguageName(targetLanguageCode);
    final sourceLyricsForModel = _normalizeSourceLyrics(lyrics);
    final prompt =
        '将以下歌词翻译成$targetLanguageName，仅输出目标译文不输出其他内容。不要输出原文。'
        '请保留完整时间轴和原有分行顺序，不要删减、合并、重排任何一行，也不要自行补充空行、编号或解释。'
        '如果输入中带有时间轴，请在输出中原样保留对应时间轴，程序会在后处理去掉时间轴。'
        '总结整首歌的意境并结合上下文尽量意译。如果无标题不要自行生成标题。\n'
        '$sourceLyricsForModel';
    final candidates = <LyricsAiModelSelection>[
      LyricsAiModelSelection(
        provider: _translationPrimaryModel.provider,
        modelId: modelId?.trim().isNotEmpty == true
            ? modelId!.trim()
            : _translationPrimaryModel.modelId,
      ),
      if (_translationFallbackModel.modelId.trim().isNotEmpty)
        _translationFallbackModel,
    ];

    String? lastError;
    for (final candidate in candidates) {
      final apiKey = _config.apiKeyForProvider(candidate.provider).trim();
      if (apiKey.isEmpty) {
        lastError = _missingApiKeyMessage(
          candidate.provider,
          action: _t('翻译歌词', 'translate lyrics'),
        );
        continue;
      }
      onModelLabelChanged?.call(_modelLabel(candidate));
      final error = await switch (candidate.provider) {
        LyricsAiProvider.googleAiStudio => _translateWithGoogleAiStudio(
          apiKey: apiKey,
          modelId: candidate.modelId,
          prompt: prompt,
          sourceLines: sourceLines,
          blankLineIndexes: blankLineIndexes,
          targetLineCount: targetLineCount,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
        LyricsAiProvider.openRouter => _translateWithOpenRouter(
          apiKey: apiKey,
          modelId: candidate.modelId,
          prompt: prompt,
          sourceLines: sourceLines,
          blankLineIndexes: blankLineIndexes,
          targetLineCount: targetLineCount,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
      };
      if (error == null) {
        return null;
      }
      if (error == 'cancelled') {
        return error;
      }
      lastError = error;
    }
    return lastError ??
        _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        );
  }

  Future<LyricsGenerationResult> generateLyricsFromFile({
    required String filePath,
    String? songTitle,
    String? modelId,
    void Function(String? modelLabel)? onModelLabelChanged,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[LyricsAi] file not found for generation: $filePath');
      return LyricsGenerationResult.failure(
        _t(
          '本地歌曲文件不存在，无法生成歌词。',
          'The local song file does not exist, so lyrics cannot be generated.',
        ),
      );
    }
    final normalizedTitle = songTitle?.trim();
    final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
        ? ''
        : '这首歌的标题是《$normalizedTitle》。';
    final prompt =
        '$titleHint'
        '输出这首歌的完整的带时间轴的标准LRC格式歌词,每一行歌词前面都带有一个方括号包裹的时间点，格式通常为：[mm:ss.ms]歌词内容。mm: 分钟（00-99）ss: 秒（00-59）ms: 毫秒（通常为 3 位）。'
        '仅输出结果不输出其他内容。';
    final candidates = <LyricsAiModelSelection>[
      LyricsAiModelSelection(
        provider: _generationPrimaryModel.provider,
        modelId: modelId?.trim().isNotEmpty == true
            ? modelId!.trim()
            : _generationPrimaryModel.modelId,
      ),
      if (_generationFallbackModel.modelId.trim().isNotEmpty)
        _generationFallbackModel,
    ];
    String? lastError;
    for (final candidate in candidates) {
      final apiKey = _config.apiKeyForProvider(candidate.provider).trim();
      if (apiKey.isEmpty) {
        lastError = _missingApiKeyMessage(
          candidate.provider,
          action: _t('生成歌词', 'generate lyrics'),
        );
        continue;
      }
      onModelLabelChanged?.call(_modelLabel(candidate));
      final result = switch (candidate.provider) {
        LyricsAiProvider.googleAiStudio => await _generateWithGoogleAiStudio(
          file: file,
          apiKey: apiKey,
          modelId: candidate.modelId,
          prompt: prompt,
          preserveTimestamps: true,
          onStageChanged: onStageChanged,
          onUploadProgress: onUploadProgress,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
        LyricsAiProvider.openRouter => await _openRouterClient.generateLyricsFromFile(
          apiKey: apiKey,
          modelId: candidate.modelId,
          filePath: filePath,
          songTitle: songTitle,
          onUploadProgress: onUploadProgress,
          onStageChanged: onStageChanged,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
      };
      if (result.isSuccess) {
        return _normalizeGenerationResult(result);
      }
      lastError = result.errorMessage;
    }
    return LyricsGenerationResult.failure(
      lastError ??
          _t(
            '生成歌词时发生未知错误。',
            'An unknown error occurred while generating lyrics.',
          ),
    );
  }

  Future<LyricsGenerationResult> generateTimelineFromLyrics({
    required String filePath,
    required String lyrics,
    String? songTitle,
    String? modelId,
    void Function(String? modelLabel)? onModelLabelChanged,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[LyricsAi] file not found for timeline: $filePath');
      return LyricsGenerationResult.failure(
        _t(
          '本地歌曲文件不存在，无法生成时间轴。',
          'The local song file does not exist, so a timeline cannot be generated.',
        ),
      );
    }
    final normalizedLyrics = lyrics.trim();
    if (normalizedLyrics.isEmpty) {
      debugPrint('[LyricsAi] no usable lyrics for timeline generation.');
      return LyricsGenerationResult.failure(
        _t(
          '没有可用歌词，无法生成时间轴。',
          'No lyrics are available for timeline generation.',
        ),
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
    final candidates = <LyricsAiModelSelection>[
      LyricsAiModelSelection(
        provider: _generationPrimaryModel.provider,
        modelId: modelId?.trim().isNotEmpty == true
            ? modelId!.trim()
            : _generationPrimaryModel.modelId,
      ),
      if (_generationFallbackModel.modelId.trim().isNotEmpty)
        _generationFallbackModel,
    ];
    String? lastError;
    for (final candidate in candidates) {
      final apiKey = _config.apiKeyForProvider(candidate.provider).trim();
      if (apiKey.isEmpty) {
        lastError = _missingApiKeyMessage(
          candidate.provider,
          action: _t('生成时间轴', 'generate timeline'),
        );
        continue;
      }
      onModelLabelChanged?.call(_modelLabel(candidate));
      final result = switch (candidate.provider) {
        LyricsAiProvider.googleAiStudio => await _generateWithGoogleAiStudio(
          file: file,
          apiKey: apiKey,
          modelId: candidate.modelId,
          prompt: prompt,
          preserveTimestamps: true,
          onStageChanged: onStageChanged,
          onUploadProgress: onUploadProgress,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
        LyricsAiProvider.openRouter => await _openRouterClient.generateTimelineFromLyrics(
          apiKey: apiKey,
          modelId: candidate.modelId,
          filePath: filePath,
          lyrics: lyrics,
          onUploadProgress: onUploadProgress,
          onStageChanged: onStageChanged,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
      };
      if (result.isSuccess) {
        return _normalizeGenerationResult(result);
      }
      lastError = result.errorMessage;
    }
    return LyricsGenerationResult.failure(
      lastError ??
          _t(
            '生成时间轴时发生未知错误。',
            'An unknown error occurred while generating the timeline.',
          ),
    );
  }

  Future<LyricsGenerationResult> _generateFromUploadedFile({
    required File file,
    required String apiKey,
    required String mimeType,
    required String modelId,
    required String primaryModelId,
    required String fallbackModelId,
    required String prompt,
    required bool preserveTimestamps,
    void Function(String? modelLabel)? onModelLabelChanged,
    Future<LyricsGenerationResult> Function(String apiKey)?
    openRouterFallbackGenerator,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
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
        cancelToken: cancelToken,
      );
      if (uploadedFile == null) {
        debugPrint('[LyricsAi] 文件上传失败: $filePath');
        final fallbackResult = await _maybeFallbackToOpenRouter(
          openRouterFallbackGenerator: openRouterFallbackGenerator,
          fallbackLog: 'upload failed',
        );
        if (fallbackResult != null) {
          return _normalizeGenerationResult(fallbackResult);
        }
        return LyricsGenerationResult.failure(
          _t('文件上传失败，请重试。', 'File upload failed. Please try again.'),
        );
      }

      onStageChanged?.call('processing');

      final fileName = uploadedFile.name;
      final fileUri = uploadedFile.uri;
      final isActive = await _geminiApiClient.waitForFileActive(
        fileName: fileName,
        apiKey: apiKey,
        initialState: uploadedFile.state,
        cancelToken: cancelToken,
      );
      if (!isActive) {
        debugPrint(
          '[LyricsAi] file never became ACTIVE after upload: '
          'name=$fileName uri=$fileUri',
        );
        final fallbackResult = await _maybeFallbackToOpenRouter(
          openRouterFallbackGenerator: openRouterFallbackGenerator,
          fallbackLog: 'upload never became ACTIVE',
        );
        if (fallbackResult != null) {
          return _normalizeGenerationResult(fallbackResult);
        }
        return LyricsGenerationResult.failure(
          _t(
            '上传后的文件未能就绪，请稍后重试。',
            'The uploaded file did not become ready. Please try again later.',
          ),
        );
      }
      onStageChanged?.call('requesting');
      final generationOutcome = await _generateWithUploadedFileUri(
        apiKey: apiKey,
        fileUri: fileUri,
        filePath: filePath,
        fileName: fileName,
        mimeType: mimeType,
        modelId: modelId,
        primaryModelId: primaryModelId,
        fallbackModelId: fallbackModelId,
        prompt: prompt,
        preserveTimestamps: preserveTimestamps,
        onModelLabelChanged: onModelLabelChanged,
        onStageChanged: onStageChanged,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
      return _normalizeGenerationResult(generationOutcome.result);
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        rethrow;
      }
      if (_shouldUseGoogleServerFlakyMessage(e)) {
        return LyricsGenerationResult.failure(_googleServerFlakyMessage);
      }
      final fallbackResult = await _maybeFallbackToOpenRouter(
        openRouterFallbackGenerator: openRouterFallbackGenerator,
        fallbackLog: 'upload or active wait failed with exception',
      );
      if (fallbackResult != null) {
        return _normalizeGenerationResult(fallbackResult);
      }
      return LyricsGenerationResult.failure(
        _formatGenerationErrorMessage(
          e,
          fallback: _t(
            '生成歌词时发生未知错误。',
            'An unknown error occurred while generating lyrics.',
          ),
        ),
      );
    }
  }

  Future<LyricsGenerationResult> _generateWithGoogleAiStudio({
    required File file,
    required String apiKey,
    required String modelId,
    required String prompt,
    required bool preserveTimestamps,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final mimeType = _geminiApiClient.mimeTypeForFilePath(file.path);
    final result = await _generateFromUploadedFile(
      file: file,
      apiKey: apiKey,
      mimeType: mimeType,
      modelId: modelId,
      primaryModelId: modelId,
      fallbackModelId: '',
      prompt: prompt,
      preserveTimestamps: preserveTimestamps,
      openRouterFallbackGenerator: null,
      onUploadProgress: onUploadProgress,
      onStageChanged: onStageChanged,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    return _normalizeGenerationResult(result);
  }

  Future<String?> _translateWithGoogleAiStudio({
    required String apiKey,
    required String modelId,
    required String prompt,
    required List<String> sourceLines,
    required List<int> blankLineIndexes,
    required int targetLineCount,
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
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
      final response = await _client.post(
        url,
        data: requestData,
        queryParameters: {'key': apiKey},
        options: Options(
          responseType: ResponseType.stream,
          contentType: Headers.jsonContentType,
        ),
        cancelToken: cancelToken,
      );

      final body = response.data;
      if (body == null || body.stream == null) {
        return _t(
          'Gemini 返回了空流响应。',
          'Gemini returned an empty streaming response.',
        );
      }

      final translatedBuffer = StringBuffer();
      var lastPrintedLength = -1;
      var lastProgressSnapshot = '';
      var receivedAnyChunk = false;
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
        if (current.isEmpty) {
          return;
        }
        if (!force && current.length == lastPrintedLength) {
          return;
        }
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
      }

      printTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        emitProgress();
      });

      final textStream = body.stream.cast<List<int>>().transform(utf8.decoder);
      try {
        await for (final line in textStream.transform(const LineSplitter())) {
          if (cancelToken?.isCancelled == true) {
            throw DioException(
              requestOptions: RequestOptions(path: ''),
              type: DioExceptionType.cancel,
            );
          }
          final trimmed = line.trim();
          if (trimmed.isEmpty) {
            continue;
          }

          final data = trimmed.startsWith('data:')
              ? trimmed.substring(5).trim()
              : trimmed;
          if (data.isEmpty || data == '[DONE]') {
            if (data == '[DONE]') {
              break;
            }
            continue;
          }

          final chunk = _streamParser.extractText(data);
          if (chunk == null || chunk.isEmpty) {
            continue;
          }
          receivedAnyChunk = true;
          translatedBuffer.write(chunk);
          emitProgress();
        }
      } finally {
        printTimer.cancel();
      }

      emitProgress(force: true);
      final rawCurrent = translatedBuffer.toString();
      final cleanedCurrent = _stripTimestamps(
        LrcUtils.cleanGeneratedLyricsText(rawCurrent),
      );
      if (!receivedAnyChunk || cleanedCurrent.trim().isEmpty) {
        return _t('Gemini 返回了空响应。', 'Gemini returned an empty response.');
      }
      return null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        return 'cancelled';
      }
      if (_shouldUseGoogleServerFlakyMessage(error)) {
        return _googleServerFlakyMessage;
      }
      return _formatGenerationErrorMessage(
        error,
        fallback: _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        ),
      );
    } catch (error) {
      return _formatGenerationErrorMessage(
        error,
        fallback: _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        ),
      );
    }
  }

  Future<String?> _translateWithOpenRouter({
    required String apiKey,
    required String modelId,
    required String prompt,
    required List<String> sourceLines,
    required List<int> blankLineIndexes,
    required int targetLineCount,
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _client.post(
        'https://openrouter.ai/api/v1/chat/completions',
        data: {
          'model': modelId,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          'stream': true,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': Headers.jsonContentType,
          },
        ),
        cancelToken: cancelToken,
      );

      final body = response.data;
      if (body == null || body.stream == null) {
        return _t(
          'OpenRouter 返回了空流响应。',
          'OpenRouter returned an empty streaming response.',
        );
      }

      final translatedBuffer = StringBuffer();
      String lastSnapshot = '';
      final textStream = body.stream.cast<List<int>>().transform(utf8.decoder);
      await for (final line in textStream.transform(const LineSplitter())) {
        if (cancelToken?.isCancelled == true) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
        }
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) {
          continue;
        }
        final data = trimmed.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') {
          if (data == '[DONE]') {
            break;
          }
          continue;
        }
        final chunk = _streamParser.extractText(data);
        if (chunk == null || chunk.isEmpty) {
          continue;
        }
        translatedBuffer.write(chunk);
        final cleaned = _stripTimestamps(
          LrcUtils.cleanGeneratedLyricsText(translatedBuffer.toString()),
        );
        final lines = _normalizeTranslationLines(cleaned, targetLineCount);
        final restoredLines = _restoreBlankLines(
          lines,
          blankLineIndexes,
          sourceLines.length,
        );
        final snapshot = restoredLines
            .map((line) => _stripTimestampPrefix(line).trimRight())
            .join('\n');
        if (onProgress != null && snapshot != lastSnapshot) {
          lastSnapshot = snapshot;
          onProgress(restoredLines, snapshot);
        }
      }
      if (translatedBuffer.toString().trim().isEmpty) {
        return _t(
          'OpenRouter 返回了空响应。',
          'OpenRouter returned an empty response.',
        );
      }
      return null;
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        return 'cancelled';
      }
      return _formatGenerationErrorMessage(
        error,
        fallback: _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        ),
      );
    } catch (error) {
      return _formatGenerationErrorMessage(
        error,
        fallback: _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        ),
      );
    }
  }

  Future<_LyricsGenerationOutcome> _generateWithUploadedFileUri({
    required String apiKey,
    required String fileUri,
    required String filePath,
    required String fileName,
    required String mimeType,
    required String modelId,
    required String primaryModelId,
    required String fallbackModelId,
    required String prompt,
    required bool preserveTimestamps,
    void Function(String? modelLabel)? onModelLabelChanged,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    String? lastErrorMessage;
    bool lastFailureShouldUseGoogleFlakyMessage = false;
    var lastFailureEligibleForFallback = false;
    final modelCandidates = <String>[
      modelId,
      if (modelId == primaryModelId) fallbackModelId,
    ];

    for (final effectiveModelId in modelCandidates) {
      var shouldTryNextModel = false;

      for (var attempt = 1; attempt <= maxGenerationAttempts; attempt++) {
        if (cancelToken?.isCancelled == true) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
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
        debugPrint('[LyricsAi] generation request model=$effectiveModelId');
        debugPrint('[LyricsAi] generation request attempt=$attempt');
        debugPrint('[LyricsAi] generation request filePath=$filePath');
        debugPrint('[LyricsAi] generation request fileName=$fileName');
        debugPrint('[LyricsAi] generation request mimeType=$mimeType');
        debugPrint('[LyricsAi] generation request fileUri=$fileUri');
        debugPrint(
          '[LyricsAi] generation request payload=${jsonEncode(requestData)}',
        );

        try {
          onStageChanged?.call('requesting');
          final response = await _client.post(
            'https://generativelanguage.googleapis.com/v1beta/models/$effectiveModelId:streamGenerateContent',
            queryParameters: {'key': apiKey},
            data: requestData,
            options: Options(
              responseType: ResponseType.stream,
              contentType: Headers.jsonContentType,
            ),
            cancelToken: cancelToken,
          );

          final body = response.data;
          if (body == null || body.stream == null) {
            lastErrorMessage = _t(
              'Gemini 返回了空流响应。',
              'Gemini returned an empty streaming response.',
            );
            debugPrint('[LyricsAi] Empty streaming body.');
            onStageChanged?.call('retrying');
            if (attempt < maxGenerationAttempts) {
              debugPrint(
                '[LyricsAi] generation retry scheduled attempt=${attempt + 1} '
                'reason=$lastErrorMessage',
              );
              continue;
            }
            break;
          }

          debugPrint('[LyricsAi] generation stream connected');
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

          final textStream = body.stream.cast<List<int>>().transform(
            utf8.decoder,
          );
          try {
            await for (final line in textStream.transform(
              const LineSplitter(),
            )) {
              if (cancelToken?.isCancelled == true) {
                throw DioException(
                  requestOptions: RequestOptions(path: ''),
                  type: DioExceptionType.cancel,
                );
              }
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
          final normalizedFinalText = preserveTimestamps
              ? LrcUtils.normalizeGeneratedLyricsText(finalText)
              : finalText;
          if (normalizedFinalText.isEmpty) {
            lastErrorMessage = _t(
              'Gemini 返回了空响应。',
              'Gemini returned an empty response.',
            );
            debugPrint('[LyricsAi] empty lyrics response.');
            debugPrint(
              '[LyricsAi] raw generate response: ${generatedBuffer.toString()}',
            );
            onStageChanged?.call('retrying');
            if (attempt < maxGenerationAttempts) {
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
          debugPrint(normalizedFinalText);
          onProgress?.call(normalizedFinalText, true);
          return _LyricsGenerationOutcome(
            result: LyricsGenerationResult.success(normalizedFinalText),
          );
        } on DioException catch (e) {
          if (CancelToken.isCancel(e)) {
            rethrow;
          }
          lastFailureShouldUseGoogleFlakyMessage =
              _shouldUseGoogleServerFlakyMessage(e);
          lastErrorMessage = lastFailureShouldUseGoogleFlakyMessage
              ? _googleServerFlakyMessage
              : _formatGenerationErrorMessage(e);
          lastFailureEligibleForFallback = _shouldUseFallbackModel(
            e.response?.statusCode,
          );
          debugPrint(
            '[LyricsAi] generation failed: type=${e.type} '
            'status=${e.response?.statusCode} '
            'uri=${e.requestOptions.uri} '
            'message=${e.message} '
            'error=${e.error}',
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
          if (effectiveModelId == primaryModelId &&
              _shouldUseFallbackModel(statusCode)) {
            // 这里只切换模型并重试同一个 fileUri，不会重新上传文件。
            shouldTryNextModel = true;
            onStageChanged?.call('retrying');
            onModelLabelChanged?.call(_googleModelLabel(fallbackModelId));
            debugPrint(
              '[LyricsAi] model downgraded to $fallbackModelId '
              'after status=$statusCode, reusing fileUri=$fileUri.',
            );
            break;
          }

          if (effectiveModelId == fallbackModelId) {
            final specialMessage = _fallbackFailureMessageForStatus(statusCode);
            if (specialMessage != null) {
              return _LyricsGenerationOutcome(
                result: LyricsGenerationResult.failure(specialMessage),
              );
            }
          }
        } catch (e) {
          lastErrorMessage = _formatGenerationErrorMessage(e);
          debugPrint('[LyricsAi] generation error: ${e.runtimeType} $e');
          onStageChanged?.call('retrying');
        }

        if (attempt < maxGenerationAttempts) {
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

    if (lastFailureShouldUseGoogleFlakyMessage) {
      return _LyricsGenerationOutcome(
        result: LyricsGenerationResult.failure(_googleServerFlakyMessage),
      );
    }

    return _LyricsGenerationOutcome(
      result: LyricsGenerationResult.failure(
        _t(
          '生成歌词失败：$lastErrorMessage',
          'Lyrics generation failed: $lastErrorMessage',
        ),
      ),
    );
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
      if (_isNetworkUnavailableError(error)) {
        return _networkUnavailableMessage;
      }

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

    return fallback ?? _t('未知错误', 'Unknown error');
  }

  bool _isNetworkUnavailableError(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return true;
    }

    if (error.error is SocketException) {
      return true;
    }

    final text = [
      error.message,
      error.error?.toString(),
    ].whereType<String>().join(' ').toLowerCase();

    return text.contains('connection failed') ||
        text.contains('network is unreachable') ||
        text.contains('failed host lookup') ||
        text.contains('no address associated with hostname') ||
        text.contains('software caused connection abort') ||
        text.contains('connection refused') ||
        text.contains('os error: 101') ||
        text.contains('os error: 113');
  }

  String get _networkUnavailableMessage => _t(
    '网络请求失败，请检查网络以及代理状态。',
    'Network request failed. Please check your network and proxy settings.',
  );

  bool _shouldUseFallbackModel(int? statusCode) {
    return statusCode == 429 || _isServerError(statusCode);
  }

  bool _isServerError(int? statusCode) {
    return statusCode != null && statusCode >= 500 && statusCode < 600;
  }

  String? _fallbackFailureMessageForStatus(int? statusCode) {
    if (statusCode == 429) {
      return _t(
        '今天额度已用完，请等待明天额度恢复再试',
        'Today’s quota has been exhausted. Please try again after it resets tomorrow.',
      );
    }
    if (_isServerError(statusCode)) {
      return _t(
        '谷歌AI服务遭遇大量请求，暂时不可用',
        'Google AI is under heavy load and is temporarily unavailable.',
      );
    }
    return null;
  }

  String _stripTimestamps(String text) {
    return LrcUtils.stripTimestamps(text);
  }

  LyricsGenerationResult _normalizeGenerationResult(
    LyricsGenerationResult result,
  ) {
    final text = result.text;
    if (!result.isSuccess || text == null) {
      return result;
    }

    final normalizedText = LrcUtils.normalizeGeneratedLyricsText(text);
    if (normalizedText.trim().isEmpty || normalizedText.trim() == text.trim()) {
      return result;
    }

    return LyricsGenerationResult.success(normalizedText);
  }

  Future<LyricsGenerationResult?> _maybeFallbackToOpenRouter({
    required Future<LyricsGenerationResult> Function(String apiKey)?
    openRouterFallbackGenerator,
    required String fallbackLog,
  }) async {
    if (openRouterFallbackGenerator == null) {
      return null;
    }

    final fallbackApiKey = _config.openRouterApiKey.trim();
    if (fallbackApiKey.isEmpty) {
      return null;
    }

    debugPrint('[LyricsAi] switching to OpenRouter after $fallbackLog.');
    return openRouterFallbackGenerator(fallbackApiKey);
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
        return _t('中文', 'Chinese');
      case 'zh-tw':
      case 'zh-hant':
        return _t('繁体中文', 'Traditional Chinese');
      case 'en':
        return _t('英文', 'English');
      case 'ja':
        return _t('日文', 'Japanese');
      case 'ko':
        return _t('韩文', 'Korean');
      case 'fr':
        return _t('法文', 'French');
      case 'de':
        return _t('德文', 'German');
      case 'es':
        return _t('西班牙文', 'Spanish');
      case 'pt':
        return _t('葡萄牙文', 'Portuguese');
      case 'ru':
        return _t('俄文', 'Russian');
      default:
        return languageCode.trim().isEmpty
            ? _t('目标语言', 'Target language')
            : languageCode;
    }
  }

  List<String> _splitTranslationLines(String text) {
    return text.split(_lineSplitPattern);
  }

  String _t(String zh, String en) {
    return localizedText(zh, en);
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
