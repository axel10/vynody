import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

Future<String?> showManualLyricsDialog(
  BuildContext context, {
  required String initialLyrics,
}) async {
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) {
      final l10n = AppLocalizations.of(dialogContext)!;
      return _ManualLyricsDialog(
        initialLyrics: initialLyrics,
        title: l10n.enterLyricsTitle,
        hintText: l10n.lyricsInputHint,
        cancelLabel: l10n.cancel,
        confirmLabel: l10n.confirm,
      );
    },
  );
}

class _ManualLyricsDialog extends StatefulWidget {
  const _ManualLyricsDialog({
    required this.initialLyrics,
    required this.title,
    required this.hintText,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final String initialLyrics;
  final String title;
  final String hintText;
  final String cancelLabel;
  final String confirmLabel;

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
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          maxLines: 14,
          minLines: 8,
          decoration: InputDecoration(
            hintText: widget.hintText,
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
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(currentValue.trim())
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
