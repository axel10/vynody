import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/audio_riverpod.dart';
import '../player/gemini_api_key_service.dart';

Future<String?> showGeminiApiKeyDialog(
  BuildContext context, {
  required String initialApiKey,
}) async {
  final controller = TextEditingController(text: initialApiKey);
  final service = GeminiApiKeyService();

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
              statusText = '请输入 API key。';
              statusColor = Colors.orangeAccent;
            });
            return;
          }

          setDialogState(() {
            isTesting = true;
            statusText = '正在测试连接...';
            statusColor = Colors.white70;
          });

          final result = await service.testConnection(apiKey);
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
              title: const Text('填写 Google AI Studio API Key'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('用于 Gemini 生成歌词、生成时间轴和翻译歌词。'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: '粘贴 Google AI Studio API Key',
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
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: isTesting ? null : () => runTest(setDialogState),
                  child: Text(isTesting ? '测试中...' : '测试连接'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () => Navigator.of(dialogContext).pop(apiKey)
                      : null,
                  child: const Text('保存'),
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

Future<bool> ensureGeminiApiKey(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsServiceProvider);
  final currentApiKey = settings.geminiApiKey.trim();
  if (currentApiKey.isNotEmpty) {
    return true;
  }

  final enteredApiKey = await showGeminiApiKeyDialog(
    context,
    initialApiKey: currentApiKey,
  );
  if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
    return false;
  }

  settings.geminiApiKey = enteredApiKey;
  return true;
}
