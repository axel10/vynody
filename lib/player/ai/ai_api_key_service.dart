import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibe_flow/utils/network_client.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';

class AIApiKeyService {
  AIApiKeyService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;
  bool get _isZh => PlatformDispatcher.instance.locale.languageCode == 'zh';

  Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(SettingsService.geminiApiKeyStorageKey);
    final normalizedStoredKey = storedKey?.trim();
    if (normalizedStoredKey != null && normalizedStoredKey.isNotEmpty) {
      return normalizedStoredKey;
    }

    return null;
  }

  Future<GeminiApiKeyTestResult> testConnection(String apiKey) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return GeminiApiKeyTestResult(
        success: false,
        message: _isZh ? '请输入 API key。' : 'Please enter an API key.',
      );
    }

    try {
      final response = await _client.get(
        'https://generativelanguage.googleapis.com/v1beta/models',
        queryParameters: {'key': normalizedKey},
      );

      final models = _extractModels(response.data);
      return GeminiApiKeyTestResult(
        success: true,
        message: models.isEmpty
            ? (_isZh
                  ? '连接成功，已通过验证。'
                  : 'Connection successful, verification passed.')
            : (_isZh
                  ? '连接成功，检测到 ${models.length} 个模型。'
                  : 'Connection successful, detected ${models.length} models.'),
        models: models,
      );
    } catch (e) {
      return GeminiApiKeyTestResult(
        success: false,
        message: _formatErrorMessage(e),
      );
    }
  }

  List<GeminiModelInfo> _extractModels(dynamic data) {
    if (data is! Map) return const [];
    final models = data['models'];
    if (models is! List) return const [];

    return models
        .map((item) {
          if (item is Map) {
            final rawName = item['name']?.toString().trim() ?? '';
            final modelId = rawName.isEmpty
                ? ''
                : rawName.contains('/')
                ? rawName.split('/').last.trim()
                : rawName;
            final displayName =
                item['displayName']?.toString().trim() ?? modelId;
            return GeminiModelInfo(id: modelId, displayName: displayName);
          }
          final fallbackId = item?.toString().trim() ?? '';
          return GeminiModelInfo(id: fallbackId, displayName: fallbackId);
        })
        .where((value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  String _formatErrorMessage(Object error) {
    if (error is DioException) {
      final response = error.response;
      final statusCode = response?.statusCode;
      final responseData = response?.data;

      if (responseData is Map) {
        final errorMap = responseData['error'];
        if (errorMap is Map) {
          final message = errorMap['message']?.toString().trim();
          if (message != null && message.isNotEmpty) {
            return statusCode == null
                ? message
                : (_isZh
                      ? '测试失败（$statusCode）：$message'
                      : 'Test failed ($statusCode): $message');
          }
        }
      }

      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return statusCode == null
            ? message
            : (_isZh
                  ? '测试失败（$statusCode）：$message'
                  : 'Test failed ($statusCode): $message');
      }

      return statusCode == null
          ? (_isZh
                ? '测试失败，请检查网络或 API key。'
                : 'Test failed. Please check your network or API key.')
          : (_isZh
                ? '测试失败（$statusCode），请检查 API key 是否有效。'
                : 'Test failed ($statusCode). Please check whether the API key is valid.');
    }

    return _isZh
        ? '测试失败，请检查网络或 API key。'
        : 'Test failed. Please check your network or API key.';
  }
}

class GeminiApiKeyTestResult {
  const GeminiApiKeyTestResult({
    required this.success,
    required this.message,
    this.models = const [],
  });

  final bool success;
  final String message;
  final List<GeminiModelInfo> models;
}

class GeminiModelInfo {
  const GeminiModelInfo({required this.id, required this.displayName});

  final String id;
  final String displayName;

  String get label => displayName.trim().isNotEmpty ? displayName : id;
}
