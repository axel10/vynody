import 'package:shared_preferences/shared_preferences.dart';

import '../utils/network_client.dart';
import 'settings_service.dart';

class AIApiKeyService {
  AIApiKeyService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;

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
      return const GeminiApiKeyTestResult(
        success: false,
        message: '请输入 API key。',
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
            ? '连接成功，已通过验证。'
            : '连接成功，检测到 ${models.length} 个模型。',
        models: models,
      );
    } catch (e) {
      return GeminiApiKeyTestResult(
        success: false,
        message: _formatErrorMessage(e),
      );
    }
  }

  List<String> _extractModels(dynamic data) {
    if (data is! Map) return const [];
    final models = data['models'];
    if (models is! List) return const [];

    return models
        .map((item) {
          if (item is Map) {
            return item['displayName']?.toString().trim() ??
                item['name']?.toString().trim() ??
                '';
          }
          return item?.toString().trim() ?? '';
        })
        .where((value) => value.isNotEmpty)
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
            return statusCode == null ? message : '测试失败（$statusCode）：$message';
          }
        }
      }

      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return statusCode == null ? message : '测试失败（$statusCode）：$message';
      }

      return statusCode == null
          ? '测试失败，请检查网络或 API key。'
          : '测试失败（$statusCode），请检查 API key 是否有效。';
    }

    return '测试失败，请检查网络或 API key。';
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
  final List<String> models;
}
