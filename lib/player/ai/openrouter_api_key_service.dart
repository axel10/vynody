import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/utils/network_client.dart';
import 'package:vynody/player/settings/settings_service.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/l10n/app_localizations_en.dart';
import 'package:vynody/l10n/app_localizations_zh.dart';

AppLocalizations _l10n() {
  return PlatformDispatcher.instance.locale.languageCode == 'zh' 
      ? AppLocalizationsZh() 
      : AppLocalizationsEn();
}

class OpenRouterApiKeyService {
  OpenRouterApiKeyService({NetworkClient? client})
    : _client = client ?? NetworkClient.instance;

  final NetworkClient _client;

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
        message: _l10n().pleaseEnterApiKey,
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
            ? _l10n().connectionSuccessVerificationPassed
            : _l10n().connectionSuccessDetectedModels(models.length),
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
                : _l10n().testFailedWithStatus(message, statusCode);
          }
        }
      }

      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return statusCode == null
            ? message
            : _l10n().testFailedWithStatus(message, statusCode);
      }

      return statusCode == null
          ? _l10n().testFailedCheckNetworkOrApiKey
          : _l10n().testFailedStatusCheckApiKey(statusCode);
    }

    return _l10n().testFailedCheckNetworkOrApiKey;
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
