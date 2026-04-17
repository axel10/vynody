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
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) {
      return _ApiKeyDialog(
        title: title,
        description: description,
        hintText: hintText,
        testButtonLabel: testButtonLabel,
        saveButtonLabel: saveButtonLabel,
        emptyMessage: emptyMessage,
        dialogActionLabel: dialogActionLabel,
        fieldLabel: fieldLabel,
        initialApiKey: initialApiKey,
        testConnection: testConnection,
      );
    },
  );
}

class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({
    required this.title,
    required this.description,
    required this.hintText,
    required this.testButtonLabel,
    required this.saveButtonLabel,
    required this.emptyMessage,
    required this.dialogActionLabel,
    required this.fieldLabel,
    required this.initialApiKey,
    required this.testConnection,
  });

  final String title;
  final String description;
  final String hintText;
  final String testButtonLabel;
  final String saveButtonLabel;
  final String emptyMessage;
  final String dialogActionLabel;
  final String fieldLabel;
  final String initialApiKey;
  final Future<_ApiKeyDialogResult> Function(String apiKey) testConnection;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final TextEditingController _controller;
  bool _isTesting = false;
  String _statusText = '';
  Color _statusColor = Colors.white70;

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

  Future<void> _runTest() async {
    final apiKey = _controller.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _statusText = widget.emptyMessage;
        _statusColor = Colors.orangeAccent;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _statusText = '正在测试连接...';
      _statusColor = Colors.white70;
    });

    final result = await widget.testConnection(apiKey);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _statusText = result.message;
      _statusColor = result.success
          ? Colors.lightGreenAccent
          : Colors.redAccent;
    });
  }

  @override
  Widget build(BuildContext context) {
    final apiKey = _controller.text.trim();
    final canSave = apiKey.isNotEmpty && !_isTesting;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
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
                labelText: widget.fieldLabel,
                hintText: widget.hintText,
              ),
              onChanged: (_) {
                setState(() {
                  _statusText = '';
                });
              },
            ),
            if (_statusText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _statusText,
                style: TextStyle(color: _statusColor, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : () => Navigator.of(context).pop(),
          child: Text(widget.dialogActionLabel),
        ),
        TextButton(
          onPressed: _isTesting ? null : _runTest,
          child: Text(_isTesting ? '测试中...' : widget.testButtonLabel),
        ),
        FilledButton(
          onPressed: canSave ? () => Navigator.of(context).pop(apiKey) : null,
          child: Text(widget.saveButtonLabel),
        ),
      ],
    );
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
