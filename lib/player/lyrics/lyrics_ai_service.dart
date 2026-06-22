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

import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/utils/network_client.dart';
import 'package:vynody/player/lyrics/lyrics_ai_api_client.dart';
import 'package:vynody/player/lyrics/lyrics_ai_doubao.dart';
import 'package:vynody/player/lyrics/lyrics_ai_openrouter.dart';
import 'package:vynody/player/lyrics/lyrics_ai_shared.dart';
import 'package:vynody/player/lyrics/lyrics_ai_stream_parser.dart';
import 'package:vynody/player/lyrics/lyrics_ai_temp_files.dart';
import 'package:vynody/player/lyrics/lyrics_generation_result.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:path/path.dart' as p;
import 'package:audio_core/audio_core.dart';
import 'package:flutter_taglib/flutter_taglib.dart' as taglib;
import 'package:vynody/transcode/transcode_models.dart';
import 'package:vynody/transcode/transcode_service.dart';

final class LyricsAiRuntimeConfig {
  const LyricsAiRuntimeConfig({
    required this.generationPrimaryModel,
    required this.generationFallbackModel,
    required this.translationPrimaryModel,
    required this.translationFallbackModel,
    required this.geminiApiKey,
    required this.openRouterApiKey,
    required this.doubaoApiKey,
    required this.deepseekApiKey,
  });

  final LyricsAiModelSelection generationPrimaryModel;
  final LyricsAiModelSelection generationFallbackModel;
  final LyricsAiModelSelection translationPrimaryModel;
  final LyricsAiModelSelection translationFallbackModel;
  final String geminiApiKey;
  final String openRouterApiKey;
  final String doubaoApiKey;
  final String deepseekApiKey;

  String apiKeyForProvider(LyricsAiProvider provider) {
    return switch (provider) {
      LyricsAiProvider.googleAiStudio => geminiApiKey,
      LyricsAiProvider.openRouter => openRouterApiKey,
      LyricsAiProvider.doubao => doubaoApiKey,
      LyricsAiProvider.deepseek => deepseekApiKey,
    };
  }

  String get activeGenerationProviderTag =>
      generationPrimaryModel.provider.storageValue;
}

class _LyricsGenerationOutcome {
  const _LyricsGenerationOutcome({required this.result});

  final LyricsGenerationResult result;
}

class LyricsAiService {
  LyricsAiService({
    NetworkClient? client,
    required LyricsAiRuntimeConfig Function() readConfig,
    TranscodeService? transcodeService,
  }) : _client = client ?? NetworkClient.instance,
       _readConfig = readConfig,
       _geminiApiClient = GeminiLyricsApiClient(client: client),
       _doubaoClient = LyricsAiDoubaoClient(
         client: client,
         streamParser: LyricsAiStreamTextParser(),
         transcodeService: transcodeService,
       ),
       _openRouterClient = LyricsAiOpenRouterClient(
         client: client,
         streamParser: LyricsAiStreamTextParser(),
       ),
       _transcodeService = transcodeService ?? TranscodeService();

  final NetworkClient _client;
  final LyricsAiRuntimeConfig Function() _readConfig;
  final GeminiLyricsApiClient _geminiApiClient;
  final LyricsAiDoubaoClient _doubaoClient;
  final LyricsAiOpenRouterClient _openRouterClient;
  final LyricsAiStreamTextParser _streamParser = LyricsAiStreamTextParser();
  final TranscodeService _transcodeService;
  static const int maxGenerationRetries = 2;
  static const int maxGenerationAttempts = maxGenerationRetries + 1;

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

  String get currentGenerationProviderTag =>
      _config.activeGenerationProviderTag;

  String _googleModelLabel(String modelId) {
    return 'Google AI Studio · ${SettingsService.lyricsModelDisplayName(modelId)}';
  }

  String _doubaoModelLabel(String modelId) {
    return '豆包 · ${SettingsService.lyricsModelDisplayName(modelId)}';
  }

  String _openRouterModelLabel(String modelId) {
    return 'OpenRouter · ${SettingsService.lyricsModelDisplayName(modelId)}';
  }

  String _deepSeekModelLabel(String modelId) {
    return 'DeepSeek · ${SettingsService.lyricsModelDisplayName(modelId)}';
  }

  String _modelLabel(LyricsAiModelSelection selection) {
    return switch (selection.provider) {
      LyricsAiProvider.googleAiStudio => _googleModelLabel(selection.modelId),
      LyricsAiProvider.doubao => _doubaoModelLabel(selection.modelId),
      LyricsAiProvider.openRouter => _openRouterModelLabel(selection.modelId),
      LyricsAiProvider.deepseek => _deepSeekModelLabel(selection.modelId),
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
    final preparedLyrics = LyricsAiTranslationTextHelper.prepareSourceLyrics(
      lyrics,
    );
    final sourceLines = preparedLyrics.sourceLines;
    final blankLineIndexes = preparedLyrics.blankLineIndexes;
    final targetLineCount = preparedLyrics.targetLineCount;
    if (targetLineCount == 0) {
      debugPrint('[LyricsAi] no usable lyrics after stripping timestamps.');
      return _t('没有可用于翻译的歌词。', 'No lyrics are available for translation.');
    }
    final prompt = LyricsAiPromptBuilder.buildTranslateLyricsPrompt(
      lyrics: LyricsAiTranslationTextHelper.normalizeSourceLyrics(lyrics),
      targetLanguageCode: targetLanguageCode,
    );
    _logTranslationRequest(
      providerLabel: 'LyricsAiService',
      modelId: modelId?.trim().isNotEmpty == true
          ? modelId!.trim()
          : _translationPrimaryModel.modelId,
      targetLanguageCode: targetLanguageCode,
      prompt: prompt,
    );
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
        LyricsAiProvider.doubao => _doubaoClient.translateLyricsStream(
          apiKey: apiKey,
          lyrics: lyrics,
          modelId: candidate.modelId,
          targetLanguageCode: targetLanguageCode,
          onProgress: onProgress,
          cancelToken: cancelToken,
        ),
        LyricsAiProvider.deepseek => _translateWithDeepSeek(
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
    final originalFile = File(filePath);
    if (!await originalFile.exists()) {
      debugPrint('[LyricsAi] file not found for generation: $filePath');
      return LyricsGenerationResult.failure(
        _t(
          '本地歌曲文件不存在，无法生成歌词。',
          'The local song file does not exist, so lyrics cannot be generated.',
        ),
      );
    }

    _PreparedAudio? preparedAudio;
    try {
      preparedAudio = await _prepareAudioFile(
        filePath,
        onStageChanged: onStageChanged,
      );
      final activeFile = preparedAudio.file;
      final activePath = activeFile.path;

      final normalizedTitle = songTitle?.trim();
      final prompt = LyricsAiPromptBuilder.buildGenerateLyricsPrompt(
        songTitle: normalizedTitle,
      );
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
            file: activeFile,
            apiKey: apiKey,
            modelId: candidate.modelId,
            prompt: prompt,
            preserveTimestamps: true,
            onStageChanged: onStageChanged,
            onUploadProgress: onUploadProgress,
            onProgress: onProgress,
            cancelToken: cancelToken,
          ),
          LyricsAiProvider.openRouter =>
            await _openRouterClient.generateLyricsFromFile(
              apiKey: apiKey,
              modelId: candidate.modelId,
              filePath: activePath,
              songTitle: songTitle,
              onUploadProgress: onUploadProgress,
              onStageChanged: onStageChanged,
              onProgress: onProgress,
              cancelToken: cancelToken,
            ),
          LyricsAiProvider.doubao => await _doubaoClient.generateLyricsFromFile(
            apiKey: apiKey,
            modelId: candidate.modelId,
            filePath: activePath,
            songTitle: songTitle,
            onUploadProgress: onUploadProgress,
            onStageChanged: onStageChanged,
            onProgress: onProgress,
            cancelToken: cancelToken,
          ),
          LyricsAiProvider.deepseek => LyricsGenerationResult.failure(
            _t(
              'DeepSeek 仅支持歌词翻译。',
              'DeepSeek is only available for lyric translation.',
            ),
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
    } finally {
      await _deleteIfExists(preparedAudio?.tempFile);
    }
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
    final originalFile = File(filePath);
    if (!await originalFile.exists()) {
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

    final prompt = LyricsAiPromptBuilder.buildGenerateTimelinePrompt(
      lyrics: normalizedLyrics,
    );
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

    _PreparedAudio? preparedAudio;
    try {
      preparedAudio = await _prepareAudioFile(
        filePath,
        onStageChanged: onStageChanged,
      );
      final activeFile = preparedAudio.file;
      final activePath = activeFile.path;

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
            file: activeFile,
            apiKey: apiKey,
            modelId: candidate.modelId,
            prompt: prompt,
            preserveTimestamps: true,
            onStageChanged: onStageChanged,
            onUploadProgress: onUploadProgress,
            onProgress: onProgress,
            cancelToken: cancelToken,
          ),
          LyricsAiProvider.openRouter =>
            await _openRouterClient.generateTimelineFromLyrics(
              apiKey: apiKey,
              modelId: candidate.modelId,
              filePath: activePath,
              lyrics: lyrics,
              onUploadProgress: onUploadProgress,
              onStageChanged: onStageChanged,
              onProgress: onProgress,
              cancelToken: cancelToken,
            ),
          LyricsAiProvider.doubao =>
            await _doubaoClient.generateTimelineFromLyrics(
              apiKey: apiKey,
              modelId: candidate.modelId,
              filePath: activePath,
              lyrics: lyrics,
              onUploadProgress: onUploadProgress,
              onStageChanged: onStageChanged,
              onProgress: onProgress,
              cancelToken: cancelToken,
            ),
          LyricsAiProvider.deepseek => LyricsGenerationResult.failure(
            _t(
              'DeepSeek 仅支持歌词翻译。',
              'DeepSeek is only available for lyric translation.',
            ),
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
    } finally {
      await _deleteIfExists(preparedAudio?.tempFile);
    }
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
    final preparation = LyricsAiTranslationPreparation(
      sourceLines: sourceLines,
      blankLineIndexes: blankLineIndexes,
      compactSourceLines: List<String>.filled(targetLineCount, ''),
    );
    final processor = LyricsAiTranslationStreamProcessor(
      preparation: preparation,
      emitPartialLineForStreaming: false,
    );
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
        '[LyricsAi] translation request provider=GoogleAIStudio '
        'modelId=$modelId',
      );
      debugPrint(
        '[LyricsAi] translation request payload: ${jsonEncode(requestData)}',
      );
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

      Timer? printTimer;

      void emitProgress({bool force = false}) {
        final snapshot = processor.buildProgressSnapshot(
          force: force,
          dedupeByLength: true,
        );
        if (snapshot == null || onProgress == null) {
          return;
        }
        onProgress(snapshot.visibleLines, snapshot.visibleText);
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
          processor.addChunk(chunk);
          emitProgress();
        }
      } finally {
        printTimer.cancel();
      }

      emitProgress(force: true);
      if (!processor.hasReceivedAnyChunk ||
          processor.finalVisibleText.trim().isEmpty) {
        return _t('Gemini 返回了空响应。', 'Gemini returned an empty response.');
      }
      _logTranslationResult(
        providerLabel: 'GoogleAIStudio',
        translatedText: processor.finalVisibleText,
      );
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
    final processor = LyricsAiTranslationStreamProcessor(
      preparation: LyricsAiTranslationPreparation(
        sourceLines: sourceLines,
        blankLineIndexes: blankLineIndexes,
        compactSourceLines: List<String>.filled(targetLineCount, ''),
      ),
    );
    try {
      final requestData = {
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
      };
      debugPrint(
        '[LyricsAi] translation request provider=OpenRouter modelId=$modelId',
      );
      debugPrint(
        '[LyricsAi] translation request payload: ${jsonEncode(requestData)}',
      );
      final response = await _client.post(
        'https://openrouter.ai/api/v1/chat/completions',
        data: requestData,
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
        processor.addChunk(chunk);
        final snapshot = processor.buildProgressSnapshot();
        if (onProgress != null && snapshot != null) {
          onProgress(snapshot.visibleLines, snapshot.visibleText);
        }
      }
      if (!processor.hasReceivedAnyChunk ||
          processor.finalVisibleText.trim().isEmpty) {
        return _t(
          'OpenRouter 返回了空响应。',
          'OpenRouter returned an empty response.',
        );
      }
      _logTranslationResult(
        providerLabel: 'OpenRouter',
        translatedText: processor.finalVisibleText,
      );
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

  Future<String?> _translateWithDeepSeek({
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
    final processor = LyricsAiTranslationStreamProcessor(
      preparation: LyricsAiTranslationPreparation(
        sourceLines: sourceLines,
        blankLineIndexes: blankLineIndexes,
        compactSourceLines: List<String>.filled(targetLineCount, ''),
      ),
    );
    try {
      final requestData = {
        'model': modelId,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
      };
      debugPrint(
        '[LyricsAi] translation request provider=DeepSeek modelId=$modelId',
      );
      debugPrint(
        '[LyricsAi] translation request payload: ${jsonEncode(requestData)}',
      );
      final response = await _client.post(
        'https://api.deepseek.com/chat/completions',
        data: requestData,
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
          'DeepSeek 返回了空流响应。',
          'DeepSeek returned an empty streaming response.',
        );
      }

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
        processor.addChunk(chunk);
        final snapshot = processor.buildProgressSnapshot();
        if (onProgress != null && snapshot != null) {
          onProgress(snapshot.visibleLines, snapshot.visibleText);
        }
      }

      if (!processor.hasReceivedAnyChunk ||
          processor.finalVisibleText.trim().isEmpty) {
        return _t('DeepSeek 返回了空响应。', 'DeepSeek returned an empty response.');
      }
      _logTranslationResult(
        providerLabel: 'DeepSeek',
        translatedText: processor.finalVisibleText,
      );
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

  void _logTranslationRequest({
    required String providerLabel,
    required String modelId,
    required String targetLanguageCode,
    required String prompt,
  }) {
    debugPrint(
      '[LyricsAi] translation request provider=$providerLabel '
      'modelId=$modelId targetLanguageCode=$targetLanguageCode',
    );
    debugPrint('[LyricsAi] translation request prompt:');
    debugPrint(prompt);
  }

  void _logTranslationResult({
    required String providerLabel,
    required String translatedText,
  }) {
    debugPrint('[LyricsAi] translation result provider=$providerLabel:');
    debugPrint(translatedText);
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
    return LyricsAiTranslationTextHelper.stripTimestamps(text);
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

  String _t(String zh, String en) {
    return localizedText(zh, en);
  }

  Future<_PreparedAudio> _prepareAudioFile(
    String filePath, {
    void Function(String stage)? onStageChanged,
  }) async {
    final file = File(filePath);
    bool needsTranscode = true;
    if (filePath.toLowerCase().endsWith('.mp3')) {
      if (taglib.TagLibFile.isSupported) {
        final tagFile = taglib.TagLibFile.open(filePath);
        if (tagFile != null) {
          try {
            final bitrate = tagFile.bitrate;
            if (bitrate > 0 && bitrate <= 128) {
              needsTranscode = false;
            }
          } catch (e) {
            debugPrint('[LyricsAi] Error reading bitrate: $e');
          } finally {
            tagFile.close();
          }
        }
      }
    }

    if (!needsTranscode) {
      return _PreparedAudio(file: file);
    }

    onStageChanged?.call('transcoding');
    final tempDir = await getLyricsAiTempDirectory();
    final draft = TranscodeDraft(
      outputFormat: AudioFormat.mp3,
      qualityTier: TranscodeQualityTier.medium,
      bitRate: 128000,
      bitRateMode: BitRateMode.cbr,
      valueOrigin: TranscodeValueOrigin.customized,
      outputDirectory: tempDir.path,
      useSystemEncoder: false,
      aacEncoder: AacEncoder.ffmpeg,
    );
    final result = await _transcodeService.convertToOutputDirectory(
      inputPath: filePath,
      draft: draft,
      copyMetadata: false,
    );
    if (!result.result.success || result.result.outputPath == null) {
      throw Exception(_t('音频转码失败。', 'Audio transcoding failed.'));
    }

    final outputPath = result.result.outputPath!;
    final outputFile = File(outputPath);

    String resolvedOutputPath = outputFile.path;
    String resolvedTempPath = tempDir.path;
    try {
      resolvedOutputPath = outputFile.resolveSymbolicLinksSync();
    } catch (_) {}
    try {
      resolvedTempPath = tempDir.resolveSymbolicLinksSync();
    } catch (_) {}

    if (!p.isWithin(resolvedTempPath, resolvedOutputPath)) {
      throw Exception(
        _t(
          '临时转码文件未生成在临时目录。',
          'The temporary transcoded file was not created in the temp directory.',
        ),
      );
    }
    return _PreparedAudio(file: outputFile, tempFile: outputFile);
  }

  Future<void> _deleteIfExists(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

class _PreparedAudio {
  const _PreparedAudio({required this.file, this.tempFile});

  final File file;
  final File? tempFile;
}
