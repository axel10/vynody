import 'dart:ui';

import 'package:vibe_flow/player/settings/settings_service.dart';
import 'package:vibe_flow/utils/network_client.dart';

final class LyricsModelInfo {
  const LyricsModelInfo({
    required this.id,
    required this.displayName,
    required this.provider,
    this.inputPricePerMillionTokens,
    this.outputPricePerMillionTokens,
  });

  final String id;
  final String displayName;
  final LyricsAiProvider provider;
  final double? inputPricePerMillionTokens;
  final double? outputPricePerMillionTokens;

  String get label => displayName.trim().isNotEmpty ? displayName : id;

  String? get pricingLabel {
    final input = inputPricePerMillionTokens;
    final output = outputPricePerMillionTokens;
    if (input == null && output == null) {
      return null;
    }

    final parts = <String>[];
    if (input != null) {
      parts.add('输入 ${_formatPrice(input)} / 100万 token');
    }
    if (output != null) {
      parts.add('输出 ${_formatPrice(output)} / 100万 token');
    }
    return parts.join(' · ');
  }

  static String _formatPrice(double value) {
    final fixed = value.toStringAsFixed(8);
    final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
    return '\$$trimmed';
  }
}

final class LyricsModelCatalogResult {
  const LyricsModelCatalogResult({
    required this.success,
    required this.message,
    this.models = const [],
  });

  final bool success;
  final String message;
  final List<LyricsModelInfo> models;
}

class LyricsModelCatalogService {
  LyricsModelCatalogService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;

  bool get _isZh => PlatformDispatcher.instance.locale.languageCode == 'zh';

  Future<LyricsModelCatalogResult> fetchModels({
    required LyricsAiProvider provider,
    required LyricsAiModelPurpose purpose,
    String apiKey = '',
  }) async {
    return switch (provider) {
      LyricsAiProvider.googleAiStudio => _fetchGoogleAiStudioModels(
        purpose: purpose,
        apiKey: apiKey,
      ),
      LyricsAiProvider.openRouter => _fetchOpenRouterModels(purpose: purpose),
      LyricsAiProvider.doubao => _fetchDoubaoModels(
        purpose: purpose,
        apiKey: apiKey,
      ),
      LyricsAiProvider.deepseek => _fetchDeepSeekModels(
        purpose: purpose,
        apiKey: apiKey,
      ),
    };
  }

  Future<LyricsModelCatalogResult> _fetchGoogleAiStudioModels({
    required LyricsAiModelPurpose purpose,
    required String apiKey,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return LyricsModelCatalogResult(
        success: false,
        message: _isZh
            ? '请先填写 Google AI Studio API Key。'
            : 'Please enter a Google AI Studio API key first.',
      );
    }

    try {
      final response = await _client.get(
        'https://generativelanguage.googleapis.com/v1beta/models',
        queryParameters: {'key': normalizedKey},
      );
      final models = _extractGoogleModels(response.data, purpose);
      return LyricsModelCatalogResult(
        success: true,
        message: _isZh
            ? '已获取 ${models.length} 个模型。'
            : 'Fetched ${models.length} models.',
        models: models,
      );
    } catch (error) {
      return LyricsModelCatalogResult(
        success: false,
        message: _formatErrorMessage(error),
      );
    }
  }

  Future<LyricsModelCatalogResult> _fetchOpenRouterModels({
    required LyricsAiModelPurpose purpose,
  }) async {
    try {
      final response = await _client.get('https://openrouter.ai/api/v1/models');
      final models = _extractOpenRouterModels(response.data, purpose);
      return LyricsModelCatalogResult(
        success: true,
        message: _isZh
            ? '已获取 ${models.length} 个模型。'
            : 'Fetched ${models.length} models.',
        models: models,
      );
    } catch (error) {
      return LyricsModelCatalogResult(
        success: false,
        message: _formatErrorMessage(error),
      );
    }
  }

  Future<LyricsModelCatalogResult> _fetchDoubaoModels({
    required LyricsAiModelPurpose purpose,
    required String apiKey,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return LyricsModelCatalogResult(
        success: false,
        message: _isZh
            ? '请先填写豆包 API Key。'
            : 'Please enter a Doubao API key first.',
      );
    }

    try {
      final response = await _client.get(
        'https://ark.cn-beijing.volces.com/api/v3/models',
        options: Options(headers: {'Authorization': 'Bearer $normalizedKey'}),
      );
      final models = _extractDoubaoModels(response.data, purpose);
      return LyricsModelCatalogResult(
        success: true,
        message: _isZh
            ? '已获取 ${models.length} 个模型。'
            : 'Fetched ${models.length} models.',
        models: models,
      );
    } catch (error) {
      return LyricsModelCatalogResult(
        success: false,
        message: _formatErrorMessage(error),
      );
    }
  }

  Future<LyricsModelCatalogResult> _fetchDeepSeekModels({
    required LyricsAiModelPurpose purpose,
    required String apiKey,
  }) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return LyricsModelCatalogResult(
        success: false,
        message: _isZh
            ? '请先填写 DeepSeek API Key。'
            : 'Please enter a DeepSeek API key first.',
      );
    }

    if (purpose != LyricsAiModelPurpose.translation) {
      return LyricsModelCatalogResult(
        success: true,
        message: _isZh
            ? 'DeepSeek 仅用于歌词翻译。'
            : 'DeepSeek is only available for lyric translation.',
        models: const [],
      );
    }

    try {
      final response = await _client.get(
        'https://api.deepseek.com/models',
        options: Options(headers: {'Authorization': 'Bearer $normalizedKey'}),
      );
      final models = _extractDeepSeekModels(response.data);
      return LyricsModelCatalogResult(
        success: true,
        message: _isZh
            ? '已获取 ${models.length} 个模型。'
            : 'Fetched ${models.length} models.',
        models: models,
      );
    } catch (error) {
      return LyricsModelCatalogResult(
        success: false,
        message: _formatErrorMessage(error),
      );
    }
  }

  List<LyricsModelInfo> _extractGoogleModels(
    dynamic data,
    LyricsAiModelPurpose purpose,
  ) {
    if (data is! Map) {
      return const [];
    }
    final models = data['models'];
    if (models is! List) {
      return const [];
    }

    return models
        .whereType<Map>()
        .map((item) {
          final rawName = item['name']?.toString().trim() ?? '';
          final modelId = rawName.isEmpty
              ? ''
              : rawName.contains('/')
              ? rawName.split('/').last.trim()
              : rawName;
          final displayName = item['displayName']?.toString().trim() ?? modelId;
          final supportedMethods =
              (item['supportedGenerationMethods'] as List?)
                  ?.map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false) ??
              const [];
          final supportsGeneration =
              supportedMethods.contains('generateContent') ||
              supportedMethods.contains('streamGenerateContent');
          if (modelId.isEmpty || !supportsGeneration) {
            return null;
          }
          final lowerId = modelId.toLowerCase();
          final looksLikeTranslation = lowerId.contains('gemma');
          final looksLikeGeneration =
              lowerId.contains('flash') || lowerId.contains('gemini');
          final shouldInclude = switch (purpose) {
            LyricsAiModelPurpose.generation => looksLikeGeneration,
            LyricsAiModelPurpose.translation =>
              looksLikeTranslation || looksLikeGeneration,
          };
          if (!shouldInclude) {
            return null;
          }
          return LyricsModelInfo(
            id: modelId,
            displayName: displayName,
            provider: LyricsAiProvider.googleAiStudio,
          );
        })
        .whereType<LyricsModelInfo>()
        .toList(growable: false);
  }

  List<LyricsModelInfo> _extractOpenRouterModels(
    dynamic data,
    LyricsAiModelPurpose purpose,
  ) {
    if (data is! Map) {
      return const [];
    }
    final models = data['data'];
    if (models is! List) {
      return const [];
    }

    return models
        .whereType<Map>()
        .map((item) {
          final id = item['id']?.toString().trim() ?? '';
          if (id.isEmpty) {
            return null;
          }
          final name = item['name']?.toString().trim() ?? id;
          final architecture = item['architecture'];
          final inputModalities = architecture is Map
              ? (architecture['input_modalities'] as List?)
                        ?.map((value) => value.toString().trim().toLowerCase())
                        .where((value) => value.isNotEmpty)
                        .toList(growable: false) ??
                    const []
              : const <String>[];
          final outputModalities = architecture is Map
              ? (architecture['output_modalities'] as List?)
                        ?.map((value) => value.toString().trim().toLowerCase())
                        .where((value) => value.isNotEmpty)
                        .toList(growable: false) ??
                    const []
              : const <String>[];
          final supportsPurpose = switch (purpose) {
            LyricsAiModelPurpose.generation =>
              inputModalities.contains('audio') &&
                  outputModalities.contains('text'),
            LyricsAiModelPurpose.translation =>
              inputModalities.contains('text') &&
                  outputModalities.contains('text'),
          };
          if (!supportsPurpose) {
            return null;
          }
          final pricing = item['pricing'];
          final inputPrice = _parsePrice(
            pricing is Map ? pricing['prompt'] : null,
          );
          final outputPrice = _parsePrice(
            pricing is Map ? pricing['completion'] : null,
          );
          return LyricsModelInfo(
            id: id,
            displayName: name,
            provider: LyricsAiProvider.openRouter,
            inputPricePerMillionTokens: inputPrice,
            outputPricePerMillionTokens: outputPrice,
          );
        })
        .whereType<LyricsModelInfo>()
        .toList(growable: false);
  }

  List<LyricsModelInfo> _extractDoubaoModels(
    dynamic data,
    LyricsAiModelPurpose purpose,
  ) {
    if (data is! Map) {
      return const [];
    }
    final models = data['data'];
    if (models is! List) {
      return const [];
    }

    return models
        .whereType<Map>()
        .map((item) {
          final id = item['id']?.toString().trim() ?? '';
          if (id.isEmpty) {
            return null;
          }
          final name = item['name']?.toString().trim() ?? id;
          final lowerId = id.toLowerCase();
          final supportsPurpose = switch (purpose) {
            LyricsAiModelPurpose.generation =>
              lowerId.contains('seed') || lowerId.contains('doubao'),
            LyricsAiModelPurpose.translation =>
              lowerId.contains('seed') || lowerId.contains('doubao'),
          };
          if (!supportsPurpose) {
            return null;
          }
          return LyricsModelInfo(
            id: id,
            displayName: name,
            provider: LyricsAiProvider.doubao,
          );
        })
        .whereType<LyricsModelInfo>()
        .toList(growable: false)
      ..sort(_compareDoubaoModels);
  }

  List<LyricsModelInfo> _extractDeepSeekModels(dynamic data) {
    if (data is! Map) {
      return const [];
    }
    final models = data['data'];
    if (models is! List) {
      return const [];
    }

    return models
        .whereType<Map>()
        .map((item) {
          final id = item['id']?.toString().trim() ?? '';
          if (id.isEmpty) {
            return null;
          }
          final name = item['name']?.toString().trim() ?? id;
          final lowerId = id.toLowerCase();
          final isTranslationModel =
              lowerId.contains('chat') ||
              lowerId.contains('reasoner') ||
              lowerId.contains('deepseek');
          if (!isTranslationModel) {
            return null;
          }
          return LyricsModelInfo(
            id: id,
            displayName: name,
            provider: LyricsAiProvider.deepseek,
          );
        })
        .whereType<LyricsModelInfo>()
        .toList(growable: false);
  }

  int _compareDoubaoModels(LyricsModelInfo a, LyricsModelInfo b) {
    final aSuffix = _extractTrailingNumber(a.id);
    final bSuffix = _extractTrailingNumber(b.id);
    if (aSuffix != null && bSuffix != null) {
      final byNumber = bSuffix.compareTo(aSuffix);
      if (byNumber != 0) return byNumber;
    } else if (aSuffix != null) {
      return -1;
    } else if (bSuffix != null) {
      return 1;
    }

    return a.id.compareTo(b.id);
  }

  int? _extractTrailingNumber(String modelId) {
    final match = RegExp(r'(\d+)$').firstMatch(modelId.trim());
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  double? _parsePrice(dynamic value) {
    final parsed = double.tryParse(value?.toString().trim() ?? '');
    if (parsed == null) {
      return null;
    }
    if (parsed == 0) {
      return 0;
    }
    return parsed * 1000000;
  }

  String _formatErrorMessage(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return statusCode == null
            ? message
            : (_isZh
                  ? '请求失败（$statusCode）：$message'
                  : 'Request failed ($statusCode): $message');
      }
      return statusCode == null
          ? (_isZh ? '请求失败，请检查网络。' : 'Request failed. Check your network.')
          : (_isZh ? '请求失败（$statusCode）。' : 'Request failed ($statusCode).');
    }

    return _isZh ? '请求失败，请检查网络。' : 'Request failed. Check your network.';
  }
}
