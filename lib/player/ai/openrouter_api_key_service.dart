import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:vibe_flow/utils/network_client.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';

class OpenRouterApiKeyService {
  OpenRouterApiKeyService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;
  bool get _isZh => PlatformDispatcher.instance.locale.languageCode == 'zh';

  Future<String?> loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final storedKey = prefs.getString(
      SettingsService.openRouterApiKeyStorageKey,
    );
    final normalizedStoredKey = storedKey?.trim();
    if (normalizedStoredKey != null && normalizedStoredKey.isNotEmpty) {
      return normalizedStoredKey;
    }

    return null;
  }

  Future<OpenRouterApiKeyTestResult> testConnection(String apiKey) async {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      return OpenRouterApiKeyTestResult(
        success: false,
        message: _isZh ? '请输入 API key。' : 'Please enter an API key.',
      );
    }

    try {
      final response = await _client.get(
        'https://openrouter.ai/api/v1/models',
        options: Options(
          headers: {
            'Authorization': 'Bearer $normalizedKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final models = _extractModels(response.data);
      return OpenRouterApiKeyTestResult(
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
      return OpenRouterApiKeyTestResult(
        success: false,
        message: _formatErrorMessage(e),
      );
    }
  }

  List<String> _extractModels(dynamic data) {
    if (data is! Map) return const [];
    final models = data['data'];
    if (models is! List) return const [];

    return models
        .map((item) {
          if (item is Map) {
            return item['name']?.toString().trim() ??
                item['id']?.toString().trim() ??
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

class OpenRouterApiKeyTestResult {
  const OpenRouterApiKeyTestResult({
    required this.success,
    required this.message,
    this.models = const [],
  });

  final bool success;
  final String message;
  final List<String> models;
}
