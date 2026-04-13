import 'package:flutter/material.dart';

Future<String?> showAcoustidApiKeyDialog(
  BuildContext context, {
  required String initialApiKey,
}) async {
  final controller = TextEditingController(text: initialApiKey);

  try {
    return await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final apiKey = controller.text.trim();

            return AlertDialog(
              title: const Text('填写 AcoustID API Key'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('用于音频指纹识别。留空后会恢复使用应用内置的默认 key。'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: '粘贴你的 AcoustID API Key',
                      ),
                      onChanged: (_) {
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: apiKey.isNotEmpty || controller.text.isEmpty
                      ? () => Navigator.of(dialogContext).pop(controller.text)
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
