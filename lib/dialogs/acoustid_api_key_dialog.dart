import 'package:flutter/material.dart';

Future<String?> showAcoustidApiKeyDialog(
  BuildContext context, {
  required String initialApiKey,
}) async {
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) {
      return _AcoustidApiKeyDialog(initialApiKey: initialApiKey);
    },
  );
}

class _AcoustidApiKeyDialog extends StatefulWidget {
  const _AcoustidApiKeyDialog({required this.initialApiKey});

  final String initialApiKey;

  @override
  State<_AcoustidApiKeyDialog> createState() => _AcoustidApiKeyDialogState();
}

class _AcoustidApiKeyDialogState extends State<_AcoustidApiKeyDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialApiKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apiKey = _controller.text.trim();

    return AlertDialog(
      title: const Text('填写 AcoustID API Key'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('用于音频指纹识别。留空后会恢复使用应用内置的默认 key。'),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: '粘贴你的 AcoustID API Key',
                ),
                onChanged: (_) {
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: apiKey.isNotEmpty || _controller.text.isEmpty
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
