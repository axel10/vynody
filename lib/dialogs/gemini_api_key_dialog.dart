import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/audio_riverpod.dart';
import '../player/settings_service.dart';

class _ApiKeyDialogResult {
  const _ApiKeyDialogResult({required this.success, required this.message});

  final bool success;
  final String message;
}

Future<String?> _showApiKeyDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String hintText,
  required String testButtonLabel,
  required Future<_ApiKeyDialogResult> Function(String apiKey) testConnection,
  required String saveButtonLabel,
  required String emptyMessage,
  required String dialogActionLabel,
  required String fieldLabel,
  String initialApiKey = '',
}) async {
  final controller = TextEditingController(text: initialApiKey);

  try {
    return await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        var isTesting = false;
        var statusText = '';
        var statusColor = Colors.white70;

        Future<void> runTest(StateSetter setDialogState) async {
          final apiKey = controller.text.trim();
          if (apiKey.isEmpty) {
            setDialogState(() {
              statusText = emptyMessage;
              statusColor = Colors.orangeAccent;
            });
            return;
          }

          setDialogState(() {
            isTesting = true;
            statusText = '正在测试连接...';
            statusColor = Colors.white70;
          });

          final result = await testConnection(apiKey);
          if (!dialogContext.mounted) return;

          setDialogState(() {
            isTesting = false;
            statusText = result.message;
            statusColor = result.success
                ? Colors.lightGreenAccent
                : Colors.redAccent;
          });
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final apiKey = controller.text.trim();
            final canSave = apiKey.isNotEmpty && !isTesting;

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(description),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: fieldLabel,
                        hintText: hintText,
                      ),
                      onChanged: (_) {
                        setDialogState(() {
                          statusText = '';
                        });
                      },
                    ),
                    if (statusText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isTesting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(dialogActionLabel),
                ),
                TextButton(
                  onPressed: isTesting ? null : () => runTest(setDialogState),
                  child: Text(isTesting ? '测试中...' : testButtonLabel),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () => Navigator.of(dialogContext).pop(apiKey)
                      : null,
                  child: Text(saveButtonLabel),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    controller.dispose();
  }
}

Future<String?> showGoogleAiStudioApiKeyDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String initialApiKey,
}) async {
  final service = ref.read(geminiApiKeyServiceProvider);
  return _showApiKeyDialog(
    context,
    title: '填写 Google AI Studio API Key',
    description: '用于 Google AI Studio 的歌词生成、时间轴生成和翻译。',
    hintText: '粘贴 Google AI Studio API Key',
    testButtonLabel: '测试连接',
    saveButtonLabel: '保存',
    emptyMessage: '请输入 API key。',
    dialogActionLabel: '取消',
    fieldLabel: 'API Key',
    initialApiKey: initialApiKey,
    testConnection: (apiKey) async {
      final result = await service.testConnection(apiKey);
      return _ApiKeyDialogResult(
        success: result.success,
        message: result.message,
      );
    },
  );
}

Future<String?> showOpenRouterApiKeyDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String initialApiKey,
}) async {
  final service = ref.read(openRouterApiKeyServiceProvider);
  return _showApiKeyDialog(
    context,
    title: '填写 OpenRouter API Key',
    description: '用于 OpenRouter 的歌词生成和时间轴生成，翻译始终走 Gemini。',
    hintText: '粘贴 OpenRouter API Key',
    testButtonLabel: '测试连接',
    saveButtonLabel: '保存',
    emptyMessage: '请输入 API key。',
    dialogActionLabel: '取消',
    fieldLabel: 'API Key',
    initialApiKey: initialApiKey,
    testConnection: (apiKey) async {
      final result = await service.testConnection(apiKey);
      return _ApiKeyDialogResult(
        success: result.success,
        message: result.message,
      );
    },
  );
}

Future<String?> showGeminiApiKeyDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String initialApiKey,
}) async {
  final service = ref.read(geminiApiKeyServiceProvider);
  return _showApiKeyDialog(
    context,
    title: '填写 Gemini API Key',
    description: '用于歌词翻译。',
    hintText: '粘贴 Gemini API Key',
    testButtonLabel: '测试连接',
    saveButtonLabel: '保存',
    emptyMessage: '请输入 API key。',
    dialogActionLabel: '取消',
    fieldLabel: 'API Key',
    initialApiKey: initialApiKey,
    testConnection: (apiKey) async {
      final result = await service.testConnection(apiKey);
      return _ApiKeyDialogResult(
        success: result.success,
        message: result.message,
      );
    },
  );
}

Future<String?> showLyricsProviderApiKeyDialog(
  BuildContext context, {
  required WidgetRef ref,
  required LyricsAiProvider provider,
  required String initialApiKey,
}) async {
  return switch (provider) {
    LyricsAiProvider.googleAiStudio => showGoogleAiStudioApiKeyDialog(
      context,
      ref: ref,
      initialApiKey: initialApiKey,
    ),
    LyricsAiProvider.openRouter => showOpenRouterApiKeyDialog(
      context,
      ref: ref,
      initialApiKey: initialApiKey,
    ),
  };
}

Future<bool> ensureLyricsGenerationApiKey(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsServiceProvider);
  final provider = settings.lyricsAiProvider;
  final currentApiKey = settings.activeLyricsGenerationApiKey.trim();
  if (currentApiKey.isNotEmpty) {
    return true;
  }

  final enteredApiKey = await showLyricsProviderApiKeyDialog(
    context,
    ref: ref,
    provider: provider,
    initialApiKey: currentApiKey,
  );
  if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
    return false;
  }

  switch (provider) {
    case LyricsAiProvider.googleAiStudio:
      settings.geminiApiKey = enteredApiKey;
      break;
    case LyricsAiProvider.openRouter:
      settings.openRouterApiKey = enteredApiKey;
      break;
  }
  return true;
}

Future<bool> ensureLyricsApiKey(BuildContext context, WidgetRef ref) async {
  return ensureLyricsGenerationApiKey(context, ref);
}

Future<bool> ensureGeminiApiKey(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsServiceProvider);
  final currentApiKey = settings.geminiApiKey.trim();
  if (currentApiKey.isNotEmpty) {
    return true;
  }

  final enteredApiKey = await showGeminiApiKeyDialog(
    context,
    ref: ref,
    initialApiKey: currentApiKey,
  );
  if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
    return false;
  }

  settings.geminiApiKey = enteredApiKey;
  return true;
}
