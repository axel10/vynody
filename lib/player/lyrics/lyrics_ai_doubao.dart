import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart'
    show
        FormData,
        MultipartFile,
        CancelToken,
        DioException,
        DioExceptionType,
        Headers,
        Options,
        RequestOptions,
        ResponseType;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:audio_core/audio_core.dart';

import 'package:vynody/utils/localized_text.dart';
import 'package:vynody/player/lyrics/lyrics_ai_stream_parser.dart';
import 'package:vynody/player/lyrics/lyrics_ai_shared.dart';
import 'package:vynody/player/lyrics/lyrics_ai_temp_files.dart';
import 'package:vynody/player/lyrics/lyrics_generation_result.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/utils/network_client.dart';
import 'package:vynody/transcode/transcode_models.dart';
import 'package:vynody/transcode/transcode_service.dart';

final class DoubaoFileUploadResult {
  const DoubaoFileUploadResult({
    required this.id,
    required this.status,
    this.expireAt,
  });

  final String id;
  final String status;
  final int? expireAt;
}

class LyricsAiDoubaoClient {
  LyricsAiDoubaoClient({
    NetworkClient? client,
    LyricsAiStreamTextParser? streamParser,
    TranscodeService? transcodeService,
  }) : _client = client ?? NetworkClient.instance,
       _streamParser = streamParser ?? LyricsAiStreamTextParser(),
       _transcodeService = transcodeService ?? TranscodeService();

  final NetworkClient _client;
  final LyricsAiStreamTextParser _streamParser;
  final TranscodeService _transcodeService;

  Future<DoubaoFileUploadResult?> uploadFile({
    required File file,
    required String apiKey,
    void Function(double progress)? onUploadProgress,
    CancelToken? cancelToken,
  }) async {
    final fileSize = await file.length();
    final fileName = p.basename(file.path);
    final formData = FormData.fromMap({
      'purpose': 'user_data',
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });

    final response = await _client.post(
      'https://ark.cn-beijing.volces.com/api/v3/files',
      data: formData,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'multipart/form-data',
        },
      ),
      onSendProgress: (sent, total) {
        if (total <= 0) return;
        onUploadProgress?.call(sent / total);
      },
      cancelToken: cancelToken,
    );

    debugPrint('[DoubaoLyrics] upload fileName=$fileName size=$fileSize');
    debugPrint('[DoubaoLyrics] upload response data=${response.data}');

    return _parseUploadedFile(response.data);
  }

  Future<DoubaoFileUploadResult?> waitForFileReady({
    required String fileId,
    required String apiKey,
    String? initialStatus,
    CancelToken? cancelToken,
  }) async {
    final normalizedInitialStatus = initialStatus?.trim().toLowerCase();
    if (normalizedInitialStatus == null || normalizedInitialStatus.isEmpty) {
      return DoubaoFileUploadResult(id: fileId, status: 'ready');
    }
    if (normalizedInitialStatus == 'processed' ||
        normalizedInitialStatus == 'ready' ||
        normalizedInitialStatus == 'active') {
      return DoubaoFileUploadResult(
        id: fileId,
        status: normalizedInitialStatus,
      );
    }

    for (var attempt = 0; attempt < 20; attempt++) {
      if (cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      if (cancelToken?.isCancelled == true) {
        throw DioException(
          requestOptions: RequestOptions(path: ''),
          type: DioExceptionType.cancel,
        );
      }

      final info = await fetchFileInfo(
        fileId,
        apiKey,
        cancelToken: cancelToken,
      );
      final status = info?.status.trim().toLowerCase();
      if (status == null || status.isEmpty) {
        return DoubaoFileUploadResult(id: fileId, status: 'ready');
      }
      if (status == 'processed' || status == 'ready' || status == 'active') {
        return info!;
      }
      if (status == 'failed') {
        throw Exception('Doubao 文件处理失败: $fileId');
      }
    }

    return null;
  }

  Future<DoubaoFileUploadResult?> fetchFileInfo(
    String fileId,
    String apiKey, {
    CancelToken? cancelToken,
  }) async {
    final response = await _client.get(
      'https://ark.cn-beijing.volces.com/api/v3/files/$fileId',
      options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      cancelToken: cancelToken,
    );
    return _parseUploadedFile(response.data);
  }

  Future<LyricsGenerationResult> generateLyricsFromFile({
    required String apiKey,
    required String filePath,
    required String modelId,
    String? songTitle,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[DoubaoLyrics] file not found for generation: $filePath');
      return LyricsGenerationResult.failure(
        _l10n().localSongFileNotFoundForGeneration,
      );
    }

    final normalizedTitle = songTitle?.trim();
    final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
        ? ''
        : '这首歌的标题是《$normalizedTitle》。';
    final prompt = '$titleHint输出这首歌的带标准lrc时间轴的歌词，只输出歌词不输出其他内容';

    _PreparedUploadAudio? preparedUpload;
    try {
      preparedUpload = await _prepareDoubaoUploadFile(
        inputFile: file,
        onStageChanged: onStageChanged,
      );
      return await _generateFromAudioFile(
        apiKey: apiKey,
        file: preparedUpload.file,
        modelId: modelId,
        prompt: prompt,
        onUploadProgress: onUploadProgress,
        onStageChanged: onStageChanged,
        onProgress: onProgress,
        cancelToken: cancelToken,
        preserveTimestamps: true,
      );
    } finally {
      await _deleteIfExists(preparedUpload?.tempFile);
    }
  }

  Future<LyricsGenerationResult> generateTimelineFromLyrics({
    required String apiKey,
    required String filePath,
    required String lyrics,
    required String modelId,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[DoubaoLyrics] file not found for timeline: $filePath');
      return LyricsGenerationResult.failure(
        _l10n().localSongFileNotFoundForTimeline,
      );
    }

    final normalizedLyrics = lyrics.trim();
    if (normalizedLyrics.isEmpty) {
      return LyricsGenerationResult.failure(
        _l10n().noLyricsForTimelineGeneration,
      );
    }

    final prompt = LyricsAiPromptBuilder.buildGenerateTimelinePrompt(
      lyrics: normalizedLyrics,
    );

    return _generateFromAudioFile(
      apiKey: apiKey,
      file: file,
      modelId: modelId,
      prompt: prompt,
      onUploadProgress: onUploadProgress,
      onStageChanged: onStageChanged,
      onProgress: onProgress,
      cancelToken: cancelToken,
      preserveTimestamps: true,
    );
  }

  Future<_PreparedUploadAudio> _prepareDoubaoUploadFile({
    required File inputFile,
    void Function(String stage)? onStageChanged,
  }) async {
    if (_isMp3File(inputFile.path)) {
      return _PreparedUploadAudio(file: inputFile);
    }

    onStageChanged?.call('transcoding');
    final tempDir = await getLyricsAiTempDirectory();
    final draft = TranscodeDraft(
      outputFormat: AudioFormat.mp3,
      qualityTier: TranscodeQualityTier.high,
      bitRate: 320000,
      bitRateMode: BitRateMode.cbr,
      valueOrigin: TranscodeValueOrigin.customized,
      outputDirectory: tempDir.path,
      useSystemEncoder: false,
      aacEncoder: AacEncoder.ffmpeg,
    );
    final result = await _transcodeService.convertToOutputDirectory(
      inputPath: inputFile.path,
      draft: draft,
      copyMetadata: false,
    );
    if (!result.result.success || result.result.outputPath == null) {
      throw Exception(
        _l10n().doubaoPreUploadTranscodingFailed,
      );
    }

    final outputPath = result.result.outputPath!;
    final outputFile = File(outputPath);

    bool isWithin = p.isWithin(tempDir.path, outputFile.path);
    if (!isWithin) {
      String resolvedOutputPath = outputFile.path;
      String resolvedTempPath = tempDir.path;
      try {
        resolvedOutputPath = outputFile.resolveSymbolicLinksSync();
      } catch (_) {}
      try {
        resolvedTempPath = tempDir.resolveSymbolicLinksSync();
      } catch (_) {}
      isWithin = p.isWithin(resolvedTempPath, resolvedOutputPath);
    }

    if (!isWithin) {
      throw Exception(
        _l10n().doubaoTempTranscodeNotInTempDir,
      );
    }
    return _PreparedUploadAudio(file: outputFile, tempFile: outputFile);
  }

  bool _isMp3File(String filePath) {
    return p.extension(filePath).toLowerCase() == '.mp3';
  }

  Future<void> _deleteIfExists(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<String?> translateLyricsStream({
    required String apiKey,
    required String lyrics,
    required String modelId,
    String targetLanguageCode = 'zh',
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
    final preparedLyrics = LyricsAiTranslationTextHelper.prepareSourceLyrics(
      lyrics,
    );
    final processor = LyricsAiTranslationStreamProcessor(
      preparation: preparedLyrics,
    );
    if (preparedLyrics.targetLineCount == 0) {
      return _l10n().noLyricsAvailableForTranslation;
    }

    final prompt = LyricsAiPromptBuilder.buildTranslateLyricsPrompt(
      lyrics: LyricsAiTranslationTextHelper.normalizeSourceLyrics(lyrics),
      targetLanguageCode: targetLanguageCode,
    );
    debugPrint(
      '[DoubaoLyrics] translation request modelId=$modelId '
      'targetLanguageCode=$targetLanguageCode '
      'sourceLineCount=${preparedLyrics.sourceLines.length} '
      'targetLineCount=${preparedLyrics.targetLineCount}',
    );
    debugPrint('[DoubaoLyrics] translation request prompt:');
    debugPrint(prompt);

    try {
      final requestData = {
        'model': modelId,
        'top_p': 0.95,
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': prompt},
            ],
          },
        ],
        'stream': true,
      };
      debugPrint(
        '[DoubaoLyrics] translation request payload: ${jsonEncode(requestData)}',
      );
      final response = await _client.post(
        'https://ark.cn-beijing.volces.com/api/v3/responses',
        data: requestData,
        options: Options(
          responseType: ResponseType.stream,
          contentType: Headers.jsonContentType,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );

      final body = response.data;
      if (body == null || body.stream == null) {
        return _l10n().doubaoEmptyStreamingResponse;
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
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') {
          if (data == '[DONE]') break;
          continue;
        }
        final chunk = _streamParser.extractDoubaoDeltaText(data);
        if (chunk == null || chunk.isEmpty) continue;
        processor.addChunk(chunk);
        final snapshot = processor.buildProgressSnapshot();
        if (onProgress != null && snapshot != null) {
          onProgress(snapshot.visibleLines, snapshot.visibleText);
        }
      }

      if (!processor.hasReceivedAnyChunk ||
          processor.finalVisibleText.trim().isEmpty) {
          return _l10n().doubaoEmptyResponse;
      }

      debugPrint('[DoubaoLyrics] translation result:');
      debugPrint(processor.finalVisibleText);
      return null;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return 'cancelled';
      }
      return _formatErrorMessage(
        e,
        fallback: _l10n().unknownTranslationError,
      );
    } catch (e) {
      return _formatErrorMessage(
        e,
        fallback: _l10n().unknownTranslationError,
      );
    }
  }

  Future<LyricsGenerationResult> _generateFromAudioFile({
    required String apiKey,
    required File file,
    required String modelId,
    required String prompt,
    required bool preserveTimestamps,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      onStageChanged?.call('uploading');
      debugPrint('[DoubaoLyrics] uploading file: ${file.path}');
      final uploadedFile = await uploadFile(
        file: file,
        apiKey: apiKey,
        onUploadProgress: onUploadProgress,
        cancelToken: cancelToken,
      );
      if (uploadedFile == null) {
        return LyricsGenerationResult.failure(
          _l10n().fileUploadFailed,
        );
      }

      onStageChanged?.call('processing');
      final fileId = uploadedFile.id;
      final readyFile = await waitForFileReady(
        fileId: fileId,
        apiKey: apiKey,
        initialStatus: uploadedFile.status,
        cancelToken: cancelToken,
      );
      if (readyFile == null) {
        return LyricsGenerationResult.failure(
          _l10n().uploadedFileNotReady,
        );
      }

      onStageChanged?.call('requesting');
      final requestData = {
        'model': modelId,
        'top_p': 0.95,
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_audio', 'file_id': readyFile.id},
              {'type': 'input_text', 'text': prompt},
            ],
          },
        ],
        'stream': true,
      };

      final response = await _client.post(
        'https://ark.cn-beijing.volces.com/api/v3/responses',
        data: requestData,
        options: Options(
          responseType: ResponseType.stream,
          contentType: Headers.jsonContentType,
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
        cancelToken: cancelToken,
      );

      final body = response.data;
      if (body == null || body.stream == null) {
        return LyricsGenerationResult.failure(
          _l10n().doubaoEmptyStreamingResponse,
        );
      }

      final generatedBuffer = StringBuffer();
      String lastEmitted = '';
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
          if (data == '[DONE]') break;
          continue;
        }

        final chunk = _streamParser.extractDoubaoDeltaText(data);
        if (chunk == null || chunk.isEmpty) {
          continue;
        }
        generatedBuffer.write(chunk);
        final cleaned = LrcUtils.cleanGeneratedLyricsText(
          generatedBuffer.toString(),
        );
        final visible = preserveTimestamps
            ? cleaned
            : LrcUtils.stripTimestamps(cleaned);
        if (visible.isEmpty || visible == lastEmitted) {
          continue;
        }
        lastEmitted = visible;
        onProgress?.call(visible, false);
      }

      final cleanedText = LrcUtils.cleanGeneratedLyricsText(
        generatedBuffer.toString(),
      );
      final normalizedText = preserveTimestamps
          ? LrcUtils.normalizeGeneratedLyricsText(cleanedText)
          : LrcUtils.stripTimestamps(
              LrcUtils.normalizeGeneratedLyricsText(cleanedText),
            );
      if (normalizedText.trim().isEmpty) {
        return LyricsGenerationResult.failure(
          _l10n().doubaoEmptyResponse,
        );
      }

      onProgress?.call(normalizedText, true);
      return LyricsGenerationResult.success(normalizedText);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        rethrow;
      }
      return LyricsGenerationResult.failure(
        _formatErrorMessage(
          e,
          fallback: _l10n().unknownGenerationError,
        ),
      );
    } catch (e) {
      return LyricsGenerationResult.failure(
        _formatErrorMessage(
          e,
          fallback: _l10n().unknownGenerationError,
        ),
      );
    }
  }

  DoubaoFileUploadResult? _parseUploadedFile(dynamic data) {
    if (data is! Map) return null;
    final id = data['id']?.toString().trim();
    final status = data['status']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return DoubaoFileUploadResult(
      id: id,
      status: status == null || status.isEmpty ? 'ready' : status,
      expireAt: int.tryParse(data['expire_at']?.toString() ?? ''),
    );
  }

  String _formatErrorMessage(Object error, {String? fallback}) {
    if (error is DioException) {
      final response = error.response;
      final statusCode = response?.statusCode;
      final responseData = response?.data;

      if (responseData is Map) {
        final errorMap = responseData['error'];
        if (errorMap is Map) {
          final message = errorMap['message']?.toString().trim();
          if (message != null && message.isNotEmpty) {
            return statusCode == null ? message : '($statusCode) $message';
          }
        }
      }

      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return statusCode == null ? message : '($statusCode) $message';
      }
    }

    final text = error.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }

    return fallback ?? _l10n().unknownError;
  }

}

AppLocalizations _l10n() => currentAppL10n;

class _PreparedUploadAudio {
  const _PreparedUploadAudio({required this.file, this.tempFile});

  final File file;
  final File? tempFile;
}
