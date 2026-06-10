import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';
import 'package:url_launcher/url_launcher_string.dart';

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
  required String getKeyButtonLabel,
  String initialApiKey = '',
  String? getKeyUrl,
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
        getKeyButtonLabel: getKeyButtonLabel,
        initialApiKey: initialApiKey,
        testConnection: testConnection,
        getKeyUrl: getKeyUrl,
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
    required this.getKeyButtonLabel,
    required this.initialApiKey,
    required this.testConnection,
    this.getKeyUrl,
  });

  final String title;
  final String description;
  final String hintText;
  final String testButtonLabel;
  final String saveButtonLabel;
  final String emptyMessage;
  final String dialogActionLabel;
  final String fieldLabel;
  final String getKeyButtonLabel;
  final String initialApiKey;
  final Future<_ApiKeyDialogResult> Function(String apiKey) testConnection;
  final String? getKeyUrl;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

enum _StatusType { none, warning, loading, success, error }

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final TextEditingController _controller;
  bool _isTesting = false;
  String _statusText = '';
  _StatusType _statusType = _StatusType.none;

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
        _statusType = _StatusType.warning;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _statusText = AppLocalizations.of(context)!.testingConnection;
      _statusType = _StatusType.loading;
    });

    final result = await widget.testConnection(apiKey);
    if (!mounted) return;

    setState(() {
      _isTesting = false;
      _statusText = result.message;
      _statusType = result.success ? _StatusType.success : _StatusType.error;
    });
  }

  void _saveCurrentValue() {
    Navigator.of(context).pop(_controller.text.trim());
  }

  void _clearAndSave() {
    Navigator.of(context).pop('');
  }

  @override
  Widget build(BuildContext context) {
    final apiKey = _controller.text.trim();
    final canSave = apiKey.isNotEmpty && !_isTesting;
    final theme = Theme.of(context);

    final statusColor = switch (_statusType) {
      _StatusType.warning =>
        theme.brightness == Brightness.dark
            ? Colors.orangeAccent
            : Colors.orange.shade800,
      _StatusType.loading => theme.colorScheme.onSurface.withValues(alpha: 0.7),
      _StatusType.success =>
        theme.brightness == Brightness.dark
            ? Colors.greenAccent
            : Colors.green.shade800,
      _StatusType.error => theme.colorScheme.error,
      _StatusType.none => Colors.transparent,
    };

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
                  labelText: widget.fieldLabel,
                  hintText: widget.hintText,
                ),
                onChanged: (_) {
                  setState(() {
                    _statusText = '';
                    _statusType = _StatusType.none;
                  });
                },
              ),
              if (_statusText.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _statusText,
                  style: TextStyle(color: statusColor, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isTesting ? null : () => Navigator.of(context).pop(),
          child: Text(widget.dialogActionLabel),
        ),
        TextButton(
          onPressed: _isTesting ? null : _clearAndSave,
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: _isTesting ? null : _runTest,
          child: Text(
            _isTesting
                ? AppLocalizations.of(context)!.testingConnection
                : widget.testButtonLabel,
          ),
        ),
        if (widget.getKeyUrl != null)
          TextButton(
            onPressed: () => launchUrlString(widget.getKeyUrl!),
            child: Text(widget.getKeyButtonLabel),
        ),
        FilledButton(
          onPressed: canSave ? _saveCurrentValue : null,
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
  final l10n = AppLocalizations.of(context)!;
  return _showApiKeyDialog(
    context,
    title: l10n.enterGoogleAiStudioApiKeyTitle,
    description: l10n.googleAiStudioApiKeyDescription,
    hintText: l10n.pasteGoogleAiStudioApiKey,
    testButtonLabel: l10n.testConnection,
    saveButtonLabel: l10n.save,
    emptyMessage: l10n.enterApiKey,
    dialogActionLabel: l10n.cancel,
    fieldLabel: l10n.apiKey,
    getKeyButtonLabel: l10n.getKey,
    initialApiKey: initialApiKey,
    getKeyUrl: 'https://aistudio.google.com/app/api-keys',
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
  final l10n = AppLocalizations.of(context)!;
  return _showApiKeyDialog(
    context,
    title: l10n.enterOpenRouterApiKeyTitle,
    description: l10n.openRouterApiKeyDescription,
    hintText: l10n.pasteOpenRouterApiKey,
    testButtonLabel: l10n.testConnection,
    saveButtonLabel: l10n.save,
    emptyMessage: l10n.enterApiKey,
    dialogActionLabel: l10n.cancel,
    fieldLabel: l10n.apiKey,
    getKeyButtonLabel: l10n.getKey,
    initialApiKey: initialApiKey,
    getKeyUrl: 'https://openrouter.ai/settings/keys',
    testConnection: (apiKey) async {
      final result = await service.testConnection(apiKey);
      return _ApiKeyDialogResult(
        success: result.success,
        message: result.message,
      );
    },
  );
}

Future<String?> showDoubaoApiKeyDialog(
  BuildContext context, {
  required String initialApiKey,
}) async {
  final l10n = AppLocalizations.of(context)!;
  return showDialog<String?>(
    context: context,
    builder: (dialogContext) {
      return _ApiKeyDialog(
        title: '输入豆包 API Key',
        description: '请输入火山方舟 / 豆包的 API Key，用于歌词生成和翻译。',
        hintText: '请输入 API Key',
        testButtonLabel: l10n.testConnection,
        saveButtonLabel: l10n.save,
        emptyMessage: l10n.enterApiKey,
        dialogActionLabel: l10n.cancel,
        fieldLabel: l10n.apiKey,
        getKeyButtonLabel: l10n.getKey,
        initialApiKey: initialApiKey,
        getKeyUrl: 'https://console.volcengine.com/ark',
        testConnection: (apiKey) async {
          return _ApiKeyDialogResult(
            success: true,
            message: '已输入 API Key，可直接保存。',
          );
        },
      );
    },
  );
}

Future<String?> showDeepSeekApiKeyDialog(
  BuildContext context, {
  required String initialApiKey,
}) async {
  final l10n = AppLocalizations.of(context)!;
  return _showApiKeyDialog(
    context,
    title: '输入 DeepSeek API Key',
    description: '请输入 DeepSeek 的 API Key，仅用于歌词翻译。',
    hintText: '请输入 API Key',
    testButtonLabel: l10n.testConnection,
    saveButtonLabel: l10n.save,
    emptyMessage: l10n.enterApiKey,
    dialogActionLabel: l10n.cancel,
    fieldLabel: l10n.apiKey,
    getKeyButtonLabel: l10n.getKey,
    initialApiKey: initialApiKey,
    getKeyUrl: 'https://platform.deepseek.com/api_keys',
    testConnection: (apiKey) async {
      return _ApiKeyDialogResult(
        success: true,
        message: '已输入 API Key，可直接保存。',
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
  final l10n = AppLocalizations.of(context)!;
  return _showApiKeyDialog(
    context,
    title: l10n.enterGeminiApiKeyTitle,
    description: l10n.geminiApiKeyDescription,
    hintText: l10n.pasteGeminiApiKey,
    testButtonLabel: l10n.testConnection,
    saveButtonLabel: l10n.save,
    emptyMessage: l10n.enterApiKey,
    dialogActionLabel: l10n.cancel,
    fieldLabel: l10n.apiKey,
    getKeyButtonLabel: l10n.getKey,
    initialApiKey: initialApiKey,
    getKeyUrl: 'https://aistudio.google.com/app/api-keys',
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
    LyricsAiProvider.doubao => showDoubaoApiKeyDialog(
      context,
      initialApiKey: initialApiKey,
    ),
    LyricsAiProvider.deepseek => showDeepSeekApiKeyDialog(
      context,
      initialApiKey: initialApiKey,
    ),
  };
}

Future<bool> ensureLyricsGenerationApiKey(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsServiceProvider);
  final providers = <LyricsAiProvider>{
    settings.generationPrimaryModel.provider,
    if (settings.generationFallbackModel.modelId.trim().isNotEmpty)
      settings.generationFallbackModel.provider,
  };
  if (providers.every(settings.hasApiKeyForProvider)) {
    return true;
  }

  return _showLyricsApiKeyWizard(
    context,
    ref,
    purpose: LyricsAiModelPurpose.generation,
  );
}

Future<bool> ensureLyricsApiKey(BuildContext context, WidgetRef ref) async {
  return ensureLyricsGenerationApiKey(context, ref);
}

Future<bool> ensureGeminiApiKey(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsServiceProvider);
  final providers = <LyricsAiProvider>{
    settings.translationPrimaryModel.provider,
    if (settings.translationFallbackModel.modelId.trim().isNotEmpty)
      settings.translationFallbackModel.provider,
  };
  if (providers.every(settings.hasApiKeyForProvider)) {
    return true;
  }

  return _showLyricsApiKeyWizard(
    context,
    ref,
    purpose: LyricsAiModelPurpose.translation,
  );
}

Future<bool> _showLyricsApiKeyWizard(
  BuildContext context,
  WidgetRef ref, {
  required LyricsAiModelPurpose purpose,
}) async {
  final settings = ref.read(settingsServiceProvider);
  final provider = await showDialog<LyricsAiProvider>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          purpose == LyricsAiModelPurpose.generation
              ? '启用 AI 歌词生成'
              : '启用 AI 歌词翻译',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请先选择要使用的服务商，然后填写对应的 API Key。'),
            const SizedBox(height: 16),
            ...LyricsAiProvider.values.where(
              (provider) =>
                  purpose == LyricsAiModelPurpose.translation ||
                  provider != LyricsAiProvider.deepseek,
            ).map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.displayName),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(dialogContext).pop(item),
              ),
            ),
          ],
        ),
      );
    },
  );
  if (provider == null) {
    return false;
  }
  if (!context.mounted) {
    return false;
  }

  final enteredApiKey = await showLyricsProviderApiKeyDialog(
    context,
    ref: ref,
    provider: provider,
    initialApiKey: settings.apiKeyForProvider(provider),
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
    case LyricsAiProvider.doubao:
      settings.doubaoApiKey = enteredApiKey;
      break;
    case LyricsAiProvider.deepseek:
      settings.deepseekApiKey = enteredApiKey;
      break;
  }

  if (purpose == LyricsAiModelPurpose.generation) {
    settings.generationPrimaryModel = LyricsAiModelSelection(
      provider: provider,
      modelId: provider == LyricsAiProvider.googleAiStudio
          ? SettingsService.defaultGenerationPrimaryModelId
          : provider == LyricsAiProvider.openRouter
          ? SettingsService.defaultOpenRouterGenerationModelId
          : provider == LyricsAiProvider.doubao
          ? SettingsService.defaultDoubaoGenerationModelId
          : '',
    );
    settings.generationFallbackModel = LyricsAiModelSelection(
      provider: provider,
      modelId: '',
    );
    settings.translationPrimaryModel = LyricsAiModelSelection(
      provider: provider,
      modelId: provider == LyricsAiProvider.googleAiStudio
          ? SettingsService.defaultTranslationPrimaryModelId
          : provider == LyricsAiProvider.openRouter
          ? SettingsService.defaultOpenRouterTranslationModelId
          : provider == LyricsAiProvider.doubao
          ? SettingsService.defaultDoubaoTranslationModelId
          : SettingsService.defaultDeepSeekTranslationModelId,
    );
    settings.translationFallbackModel = LyricsAiModelSelection(
      provider: provider,
      modelId: '',
    );
  }

  return true;
}
