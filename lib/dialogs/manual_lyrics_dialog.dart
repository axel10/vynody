import 'package:flutter/material.dart';

Future<String?> showManualLyricsDialog(
  BuildContext context, {
  required String initialLyrics,
}) async {
  final controller = TextEditingController(text: initialLyrics);
  try {
    return await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        var currentValue = initialLyrics;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final canSave = currentValue.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('填写歌词'),
              content: SizedBox(
                width: 520,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: 14,
                  minLines: 8,
                  decoration: const InputDecoration(
                    hintText: '在这里粘贴或输入歌词，支持多行文本',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      currentValue = value;
                    });
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () =>
                            Navigator.of(dialogContext).pop(currentValue.trim())
                      : null,
                  child: const Text('确认'),
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
