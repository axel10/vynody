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

import 'package:vibe_flow/player/lyrics/lyrics_ai_stream_parser.dart';
import 'package:vibe_flow/player/lyrics/lyrics_generation_result.dart';
import 'package:vibe_flow/utils/lrc_utils.dart';
import 'package:vibe_flow/utils/localized_text.dart';
import 'package:vibe_flow/utils/network_client.dart';

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
  }) : _client = client ?? NetworkClient.instance,
       _streamParser = streamParser ?? LyricsAiStreamTextParser();

  final NetworkClient _client;
  final LyricsAiStreamTextParser _streamParser;

  Future<DoubaoFileUploadResult?> uploadFile({
    required File file,
    required String apiKey,
    required String mimeType,
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
        _t(
          '本地歌曲文件不存在，无法生成时间轴。',
          'The local song file does not exist, so a timeline cannot be generated.',
        ),
      );
    }

    final normalizedLyrics = lyrics.trim();
    if (normalizedLyrics.isEmpty) {
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

  Future<String?> translateLyricsStream({
    required String apiKey,
    required String lyrics,
    required String modelId,
    String targetLanguageCode = 'zh',
    void Function(List<String> translatedLines, String translatedText)?
    onProgress,
    CancelToken? cancelToken,
  }) async {
    final sourceLines = lyrics.split(RegExp(r'\r?\n'));
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
    if (compactSourceLines.isEmpty) {
      return _t('没有可用于翻译的歌词。', 'No lyrics are available for translation.');
    }

    final targetLanguageName = _targetLanguageName(targetLanguageCode);
    final prompt =
        '将以下歌词翻译成$targetLanguageName，仅输出目标译文不输出其他内容。不要输出原文。'
        '请保留完整时间轴和原有分行顺序，不要删减、合并、重排任何一行，也不要自行补充空行、编号或解释。'
        '如果输入中带有时间轴，请在输出中原样保留对应时间轴，程序会在后处理去掉时间轴。'
        '总结整首歌的意境并结合上下文尽量意译。如果无标题不要自行生成标题。\n'
        '${lyrics.trim()}';

    try {
      final response = await _client.post(
        'https://ark.cn-beijing.volces.com/api/v3/responses',
        data: {
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
        },
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
        return _t('豆包返回了空流响应。', 'Doubao returned an empty streaming response.');
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
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') {
          if (data == '[DONE]') break;
          continue;
        }
        final chunk = _streamParser.extractText(data);
        if (chunk == null || chunk.isEmpty) continue;
        translatedBuffer.write(chunk);
        final cleaned = LrcUtils.cleanGeneratedLyricsText(
          translatedBuffer.toString(),
        );
        final lines = _splitLines(cleaned);
        final restoredLines = _restoreBlankLines(
          lines,
          blankLineIndexes,
          sourceLines.length,
        );
        final snapshot = restoredLines.join('\n');
        if (onProgress != null && snapshot != lastSnapshot) {
          lastSnapshot = snapshot;
          onProgress(restoredLines, snapshot);
        }
      }

      final translatedText = LrcUtils.cleanGeneratedLyricsText(
        translatedBuffer.toString(),
      );
      if (translatedText.trim().isEmpty) {
        return _t('豆包返回了空响应。', 'Doubao returned an empty response.');
      }

      return null;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return 'cancelled';
      }
      return _formatErrorMessage(
        e,
        fallback: _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        ),
      );
    } catch (e) {
      return _formatErrorMessage(
        e,
        fallback: _t(
          '翻译歌词时发生未知错误。',
          'An unknown error occurred while translating lyrics.',
        ),
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
      final mimeType = _mimeTypeForFilePath(file.path);
      final uploadedFile = await uploadFile(
        file: file,
        apiKey: apiKey,
        mimeType: mimeType,
        onUploadProgress: onUploadProgress,
        cancelToken: cancelToken,
      );
      if (uploadedFile == null) {
        return LyricsGenerationResult.failure(
          _t('文件上传失败，请重试。', 'File upload failed. Please try again.'),
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
          _t(
            '上传后的文件未能就绪，请稍后重试。',
            'The uploaded file did not become ready. Please try again later.',
          ),
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
          _t('豆包返回了空流响应。', 'Doubao returned an empty streaming response.'),
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

        final chunk = _streamParser.extractText(data);
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
          _t('豆包返回了空响应。', 'Doubao returned an empty response.'),
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
          fallback: _t(
            '生成歌词时发生未知错误。',
            'An unknown error occurred while generating lyrics.',
          ),
        ),
      );
    } catch (e) {
      return LyricsGenerationResult.failure(
        _formatErrorMessage(
          e,
          fallback: _t(
            '生成歌词时发生未知错误。',
            'An unknown error occurred while generating lyrics.',
          ),
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

  List<String> _splitLines(String text) {
    return text.split(RegExp(r'\r?\n'));
  }

  bool _hasTimestampedLyrics(String lyrics) {
    return RegExp(r'\[\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*\]').hasMatch(lyrics);
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

    return fallback ?? _t('未知错误', 'Unknown error');
  }

  String _t(String zh, String en) => localizedText(zh, en);
}
