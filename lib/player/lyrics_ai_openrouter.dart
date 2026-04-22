import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show DioException, Headers, Options, ResponseType;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/lrc_utils.dart';
import '../utils/network_client.dart';
import 'lyrics_ai_stream_parser.dart';
import 'lyrics_generation_result.dart';

class LyricsAiOpenRouterClient {
  LyricsAiOpenRouterClient({
    NetworkClient? client,
    LyricsAiStreamTextParser? streamParser,
  }) : _client = client ?? NetworkClient.instance,
       _streamParser = streamParser ?? LyricsAiStreamTextParser();

  final NetworkClient _client;
  final LyricsAiStreamTextParser _streamParser;

  static const String audioModelId = 'google/gemini-3.1-flash-lite-preview';
  static const String textModelId = 'google/gemini-3.1-flash-lite-preview';
  static const String textModelDisplayName = 'Gemini 3.1 Flash Lite Preview';

  Future<LyricsGenerationResult> generateLyricsFromFile({
    required String apiKey,
    required String filePath,
    String? songTitle,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[OpenRouterLyrics] file not found for generation: $filePath');
      return const LyricsGenerationResult.failure('本地歌曲文件不存在，无法生成歌词。');
    }

    final normalizedTitle = songTitle?.trim();
    final titleHint = normalizedTitle == null || normalizedTitle.isEmpty
        ? ''
        : '这首歌的标题是《$normalizedTitle》。';
    final prompt =
        '$titleHint'
        '输出这首歌的完整的带时间轴的标准LRC格式歌词,每一行歌词前面都带有一个方括号包裹的时间点，格式通常为：[mm:ss.ms]歌词内容。mm: 分钟（00-99）ss: 秒（00-59）ms: 毫秒（通常为 3 位）。'
        '仅输出结果不输出其他内容。';

    try {
      onStageChanged?.call('requesting');
      onUploadProgress?.call(1.0);
      final fileBytes = await file.readAsBytes();
      final audioFormat = _audioFormatForFilePath(filePath);
      final requestData = _buildAudioRequestData(
        prompt: prompt,
        audioBase64: base64Encode(fileBytes),
        audioFormat: audioFormat,
        stream: true,
      );
      _logRequest(
        action: 'generate_lyrics',
        requestData: requestData,
        prompt: prompt,
        extra: {
          'filePath': filePath,
          'fileSizeBytes': fileBytes.length,
          'audioFormat': audioFormat,
          'songTitle': songTitle?.trim() ?? '',
        },
      );

      final generatedBuffer = StringBuffer();
      String lastEmitted = '';
      await _streamTextResponse(
        apiKey: apiKey,
        requestData: requestData,
        onStageChanged: onStageChanged,
        onChunk: (chunk) {
          generatedBuffer.write(chunk);
          final current = LrcUtils.cleanGeneratedLyricsText(
            generatedBuffer.toString(),
          );
          if (current.isEmpty || current == lastEmitted) {
            return;
          }
          lastEmitted = current;
          onProgress?.call(current, false);
        },
      );

      final generatedText = _streamParser.extractText(
        generatedBuffer.toString(),
      );
      final cleanedText = LrcUtils.cleanGeneratedLyricsText(
        generatedText ?? generatedBuffer.toString(),
      );
      final normalizedText = LrcUtils.normalizeGeneratedLyricsText(cleanedText);
      if (normalizedText.trim().isEmpty) {
        return const LyricsGenerationResult.failure('OpenRouter 返回了空响应。');
      }

      debugPrint('[OpenRouterLyrics] final generated lyrics:');
      debugPrint(normalizedText);
      onProgress?.call(normalizedText, true);
      return LyricsGenerationResult.success(normalizedText);
    } catch (e) {
      return LyricsGenerationResult.failure(
        _formatGenerationErrorMessage(e, fallback: '生成歌词时发生未知错误。'),
      );
    }
  }

  Future<LyricsGenerationResult> generateTimelineFromLyrics({
    required String apiKey,
    required String filePath,
    required String lyrics,
    void Function(double progress)? onUploadProgress,
    void Function(String stage)? onStageChanged,
    void Function(String partialText, bool isFinal)? onProgress,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('[OpenRouterLyrics] file not found for timeline: $filePath');
      return const LyricsGenerationResult.failure('本地歌曲文件不存在，无法生成时间轴。');
    }

    final normalizedLyrics = lyrics.trim();
    if (normalizedLyrics.isEmpty) {
      debugPrint(
        '[OpenRouterLyrics] no usable lyrics for timeline generation.',
      );
      return const LyricsGenerationResult.failure('没有可用歌词，无法生成时间轴。');
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

    try {
      onStageChanged?.call('requesting');
      onUploadProgress?.call(1.0);
      final requestData = {
        'model': textModelId,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': prompt},
            ],
          },
        ],
        'stream': true,
      };
      _logRequest(
        action: 'generate_timeline',
        requestData: requestData,
        prompt: prompt,
        extra: {
          'filePath': filePath,
          'sourceLength': normalizedLyrics.length,
          'hasOriginalTimestamps': hasOriginalTimestamps,
        },
      );

      final generatedBuffer = StringBuffer();
      String lastEmitted = '';
      await _streamTextResponse(
        apiKey: apiKey,
        requestData: requestData,
        onStageChanged: onStageChanged,
        onChunk: (chunk) {
          _logChunk('generate_timeline', chunk);
          generatedBuffer.write(chunk);
          final current = LrcUtils.cleanGeneratedLyricsText(
            generatedBuffer.toString(),
          );
          if (current.isEmpty || current == lastEmitted) {
            return;
          }
          lastEmitted = current;
          onProgress?.call(current, false);
        },
      );

      final generatedText = _streamParser.extractText(
        generatedBuffer.toString(),
      );
      final cleanedText = LrcUtils.cleanGeneratedLyricsText(
        generatedText ?? generatedBuffer.toString(),
      );
      final normalizedText = LrcUtils.normalizeGeneratedLyricsText(cleanedText);
      debugPrint(
        '[OpenRouterLyrics] timeline completed -> '
        'rawLength=${generatedBuffer.length} cleanedLength=${normalizedText.length}',
      );
      if (normalizedText.trim().isEmpty) {
        return const LyricsGenerationResult.failure('OpenRouter 返回了空响应。');
      }

      onProgress?.call(normalizedText, true);
      return LyricsGenerationResult.success(normalizedText);
    } catch (e) {
      return LyricsGenerationResult.failure(
        _formatGenerationErrorMessage(e, fallback: '生成时间轴时发生未知错误。'),
      );
    }
  }

  Map<String, dynamic> _buildAudioRequestData({
    required String prompt,
    required String audioBase64,
    required String audioFormat,
    required bool stream,
    bool enableReasoning = true,
  }) {
    return {
      'model': audioModelId,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'input_audio',
              'input_audio': {'data': audioBase64, 'format': audioFormat},
            },
          ],
        },
      ],
      'stream': stream,
      if (enableReasoning) 'reasoning': {'enabled': true},
    };
  }

  Future<void> _streamTextResponse({
    required String apiKey,
    required Map<String, dynamic> requestData,
    void Function(String stage)? onStageChanged,
    required void Function(String chunk) onChunk,
  }) async {
    debugPrint(
      '[OpenRouterLyrics] request dispatch -> '
      'model=${requestData['model']} '
      'messageCount=${(requestData['messages'] as List?)?.length ?? 0} '
      'stream=${requestData['stream']}',
    );
    final response = await _client.post(
      'https://openrouter.ai/api/v1/chat/completions',
      data: requestData,
      options: Options(
        responseType: ResponseType.stream,
        contentType: Headers.jsonContentType,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    onStageChanged?.call('generating');
    debugPrint(
      '[OpenRouterLyrics] response metadata -> '
      'status=${response.statusCode} '
      'contentType=${response.headers.value('content-type') ?? 'n/a'}',
    );

    final body = response.data;
    if (body == null || body.stream == null) {
      throw Exception('OpenRouter 返回了空流响应。');
    }

    final textStream = body.stream.cast<List<int>>().transform(utf8.decoder);
    await for (final line in textStream.transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith(':')) {
        debugPrint('[OpenRouterLyrics] sse comment -> $trimmed');
        continue;
      }

      final data = trimmed.startsWith('data:')
          ? trimmed.substring(5).trim()
          : trimmed;
      if (data.isEmpty || data == '[DONE]') {
        if (data == '[DONE]') break;
        continue;
      }

      debugPrint('[OpenRouterLyrics] sse raw -> ${_truncateForLog(data)}');
      final chunk = _streamParser.extractText(data);
      if (chunk == null || chunk.isEmpty) continue;
      onChunk(chunk);
    }
    debugPrint('[OpenRouterLyrics] stream completed');
  }

  void _logRequest({
    required String action,
    required Map<String, dynamic> requestData,
    required String prompt,
    required Map<String, Object?> extra,
  }) {
    debugPrint(
      '[OpenRouterLyrics] $action start -> model=${requestData['model']} '
      'promptLength=${prompt.length} extra=${jsonEncode(extra)}',
    );
    debugPrint(
      '[OpenRouterLyrics] $action prompt preview -> '
      '${_truncateForLog(prompt, maxLength: 800)}',
    );
    debugPrint(
      '[OpenRouterLyrics] $action request payload -> '
      '${jsonEncode(_sanitizeRequestData(requestData))}',
    );
  }

  void _logChunk(String action, String chunk) {
    debugPrint(
      '[OpenRouterLyrics] $action chunk -> '
      'length=${chunk.length} preview=${_truncateForLog(chunk, maxLength: 200)}',
    );
  }

  String _truncateForLog(String value, {int maxLength = 300}) {
    final text = value.trim();
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  Map<String, dynamic> _sanitizeRequestData(Map<String, dynamic> requestData) {
    return requestData.map((key, value) {
      if (key != 'messages' || value is! List) {
        return MapEntry(key, value);
      }

      final sanitizedMessages = value
          .map((message) {
            if (message is! Map) return message;

            final sanitizedMessage = Map<String, dynamic>.from(message);
            final content = sanitizedMessage['content'];
            if (content is! List) return sanitizedMessage;

            sanitizedMessage['content'] = content
                .map((part) {
                  if (part is! Map) return part;

                  final sanitizedPart = Map<String, dynamic>.from(part);
                  if (sanitizedPart['type'] == 'input_audio') {
                    final inputAudio = sanitizedPart['input_audio'];
                    if (inputAudio is Map) {
                      final sanitizedAudio = Map<String, dynamic>.from(
                        inputAudio,
                      );
                      final data = sanitizedAudio['data'];
                      sanitizedAudio['data'] = data is String
                          ? '<base64 omitted, length=${data.length}>'
                          : '<base64 omitted>';
                      sanitizedPart['input_audio'] = sanitizedAudio;
                    }
                  }
                  return sanitizedPart;
                })
                .toList(growable: false);

            return sanitizedMessage;
          })
          .toList(growable: false);

      return MapEntry(key, sanitizedMessages);
    });
  }

  String _audioFormatForFilePath(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.mp3':
        return 'mp3';
      case '.m4a':
      case '.mp4':
      case '.m4b':
        return 'm4a';
      case '.flac':
        return 'flac';
      case '.wav':
        return 'wav';
      case '.aac':
        return 'aac';
      case '.ogg':
        return 'ogg';
      case '.opus':
        return 'opus';
      case '.aif':
      case '.aiff':
        return 'aiff';
      default:
        return 'wav';
    }
  }

  bool _hasTimestampedLyrics(String lyrics) {
    return RegExp(r'\[\s*\d{1,3}:\d{2}(?:[.:]\d{1,3})?\s*\]').hasMatch(lyrics);
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
}
