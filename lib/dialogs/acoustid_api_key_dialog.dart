import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

Future<String?> showAcoustidApiKeyDialog(
  BuildContext context, {
  required String initialApiKey,
}) async {
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return _AcoustidApiKeyDialog(
        initialApiKey: initialApiKey,
        title: l10n.enterAcoustidApiKeyTitle,
        description: l10n.acoustidApiKeyDescription,
        apiKeyLabel: l10n.apiKey,
        apiKeyHint: l10n.acoustidApiKeyHint,
        cancelLabel: l10n.cancel,
        saveLabel: l10n.save,
      );
    },
  );
}

class _AcoustidApiKeyDialog extends StatefulWidget {
  const _AcoustidApiKeyDialog({
    required this.initialApiKey,
    required this.title,
    required this.description,
    required this.apiKeyLabel,
    required this.apiKeyHint,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String initialApiKey;
  final String title;
  final String description;
  final String apiKeyLabel;
  final String apiKeyHint;
  final String cancelLabel;
  final String saveLabel;

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
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.description),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: widget.apiKeyLabel,
                  hintText: widget.apiKeyHint,
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
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: apiKey.isNotEmpty || _controller.text.isEmpty
              ? () => Navigator.of(context).pop(_controller.text)
              : null,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
