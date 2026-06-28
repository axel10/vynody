import 'dart:ui';

import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/network_client.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/l10n/app_localizations_en.dart';
import 'package:vynody/l10n/app_localizations_zh.dart';

AppLocalizations _l10n() {
  return PlatformDispatcher.instance.locale.languageCode == 'zh' 
      ? AppLocalizationsZh() 
      : AppLocalizationsEn();
}

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

  Future<LyricsModelCatalogResult> fetchModels({
    required LyricsAiProvider provider,
    required LyricsAiModelPurpose purpose,
    String apiKey = '',
    String baseUrl = '',
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
      LyricsAiProvider.custom => _fetchCustomModels(
        purpose: purpose,
        apiKey: apiKey,
        baseUrl: baseUrl,
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
        message: _l10n().enterGoogleAiStudioApiKeyFirst,
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
        message: _l10n().fetchedCountModels(models.length),
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
        message: _l10n().fetchedCountModels(models.length),
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
        message: _l10n().enterDoubaoApiKeyFirst,
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
        message: _l10n().fetchedCountModels(models.length),
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
        message: _l10n().enterDeepseekApiKeyFirst,
      );
    }

    if (purpose != LyricsAiModelPurpose.translation) {
      return LyricsModelCatalogResult(
        success: true,
        message: _l10n().deepseekOnlyTranslation,
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
        message: _l10n().fetchedCountModels(models.length),
        models: models,
      );
    } catch (error) {
      return LyricsModelCatalogResult(
        success: false,
        message: _formatErrorMessage(error),
      );
    }
  }

  Future<LyricsModelCatalogResult> _fetchCustomModels({
    required LyricsAiModelPurpose purpose,
    required String apiKey,
    required String baseUrl,
  }) async {
    final normalizedKey = apiKey.trim();
    final normalizedUrl = baseUrl.trim();
    if (normalizedKey.isEmpty || normalizedUrl.isEmpty) {
      return LyricsModelCatalogResult(
        success: false,
        message: _l10n().enterCustomApiKeyAndBaseUrl,
      );
    }

    if (purpose != LyricsAiModelPurpose.translation) {
      return LyricsModelCatalogResult(
        success: true,
        message: _l10n().customProviderOnlyTranslation,
        models: const [],
      );
    }

    try {
      final modelsUrl = normalizedUrl.endsWith('/')
          ? '${normalizedUrl}models'
          : '$normalizedUrl/models';
      final response = await _client.get(
        modelsUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $normalizedKey',
        }),
      );
      final models = _extractCustomModels(response.data);
      return LyricsModelCatalogResult(
        success: true,
        message: _l10n().fetchedCountModels(models.length),
        models: models,
      );
    } catch (error) {
      return LyricsModelCatalogResult(
        success: false,
        message: _formatErrorMessage(error),
      );
    }
  }

  List<LyricsModelInfo> _extractCustomModels(dynamic data) {
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
          return LyricsModelInfo(
            id: id,
            displayName: name,
            provider: LyricsAiProvider.custom,
          );
        })
        .whereType<LyricsModelInfo>()
        .toList(growable: false);
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
            : _l10n().requestFailedWithStatus(message, statusCode);
      }
      return statusCode == null
          ? _l10n().requestFailedCheckNetwork
          : _l10n().requestFailedStatus(statusCode);
    }

    return _l10n().requestFailedCheckNetwork;
  }
}
