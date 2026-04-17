import 'package:flutter/material.dart';

Future<String?> showManualLyricsDialog(
  BuildContext context, {
  required String initialLyrics,
}) async {
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) {
      return _ManualLyricsDialog(initialLyrics: initialLyrics);
    },
  );
}

class _ManualLyricsDialog extends StatefulWidget {
  const _ManualLyricsDialog({required this.initialLyrics});

  final String initialLyrics;

  @override
  State<_ManualLyricsDialog> createState() => _ManualLyricsDialogState();
}

class _ManualLyricsDialogState extends State<_ManualLyricsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialLyrics);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentValue = _controller.text;
    final canSave = currentValue.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('填写歌词'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          maxLines: 14,
          minLines: 8,
          decoration: const InputDecoration(
            hintText: '在这里粘贴或输入歌词，支持多行文本',
            alignLabelWithHint: true,
          ),
          onChanged: (_) {
            setState(() {});
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(currentValue.trim())
              : null,
          child: const Text('确认'),
        ),
      ],
    );
  }
}
