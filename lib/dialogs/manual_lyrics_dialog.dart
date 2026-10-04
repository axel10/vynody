import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_bottom_sheet.dart';

Future<String?> showManualLyricsDialog(
  BuildContext context, {
  required String initialLyrics,
}) async {
  return showAppAdaptiveModal<String?>(
    context: context,
    useRootNavigator: true,
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

  void _submit() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AppAdaptiveSheet(
      title: widget.title,
      sheetMaxWidth: 720,
      dialogMaxWidth: 640,
      dialogHeight: 560,
      expandHeight: true,
      padding: EdgeInsets.fromLTRB(24, 8, 24, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: widget.hintText,
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(widget.cancelLabel),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _submit,
                child: Text(widget.confirmLabel),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
