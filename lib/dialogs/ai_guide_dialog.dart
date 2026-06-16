import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:vynody/player/ai/lyrics_model_catalog_service.dart';
import 'package:vynody/widgets/lyrics_provider_icon.dart';

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
  required WidgetRef ref,
  required String initialApiKey,
}) async {
  final service = ref.read(lyricsModelCatalogServiceProvider);
  final l10n = AppLocalizations.of(context)!;
  return _showApiKeyDialog(
    context,
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
    getKeyUrl:
        'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey',
    testConnection: (apiKey) async {
      try {
        final result = await service.fetchModels(
          provider: LyricsAiProvider.doubao,
          purpose: LyricsAiModelPurpose.generation,
          apiKey: apiKey,
        );
        return _ApiKeyDialogResult(
          success: result.success,
          message: result.success
              ? '连接成功，检测到 ${result.models.length} 个模型。'
              : result.message,
        );
      } catch (e) {
        return _ApiKeyDialogResult(success: false, message: '连接测试异常：$e');
      }
    },
  );
}

Future<String?> showDeepSeekApiKeyDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String initialApiKey,
}) async {
  final service = ref.read(lyricsModelCatalogServiceProvider);
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
      try {
        final result = await service.fetchModels(
          provider: LyricsAiProvider.deepseek,
          purpose: LyricsAiModelPurpose.translation,
          apiKey: apiKey,
        );
        return _ApiKeyDialogResult(
          success: result.success,
          message: result.success
              ? '连接成功，检测到 ${result.models.length} 个模型。'
              : result.message,
        );
      } catch (e) {
        return _ApiKeyDialogResult(success: false, message: '连接测试异常：$e');
      }
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
      ref: ref,
      initialApiKey: initialApiKey,
    ),
    LyricsAiProvider.deepseek => showDeepSeekApiKeyDialog(
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
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return _LyricsApiKeyWizardDialog(purpose: purpose);
    },
  );
  return result ?? false;
}

class _LyricsApiKeyWizardDialog extends ConsumerStatefulWidget {
  const _LyricsApiKeyWizardDialog({required this.purpose});

  final LyricsAiModelPurpose purpose;

  @override
  ConsumerState<_LyricsApiKeyWizardDialog> createState() =>
      _LyricsApiKeyWizardDialogState();
}

class _LyricsApiKeyWizardDialogState
    extends ConsumerState<_LyricsApiKeyWizardDialog> {
  int _currentPage = 1;
  LyricsAiProvider? _selectedProvider;
  late final TextEditingController _keyController;
  bool _isTesting = false;
  String _statusText = '';
  _StatusType _statusType = _StatusType.none;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    final settings = ref.read(settingsServiceProvider);
    // 智能跳转逻辑：如果有任何一个渠道的 Key 已经填了，直接进入第二页
    if (settings.hasAnyLyricsModelProvider) {
      _currentPage = 2;
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _runTestConnection() async {
    final apiKey = _keyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() {
        _statusText = '请输入 API Key。';
        _statusType = _StatusType.warning;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _statusText = '正在测试连接...';
      _statusType = _StatusType.loading;
    });

    try {
      final provider = _selectedProvider!;
      if (provider == LyricsAiProvider.googleAiStudio) {
        final service = ref.read(geminiApiKeyServiceProvider);
        final result = await service.testConnection(apiKey);
        setState(() {
          _isTesting = false;
          _statusText = result.message;
          _statusType = result.success
              ? _StatusType.success
              : _StatusType.error;
        });
      } else if (provider == LyricsAiProvider.openRouter) {
        final service = ref.read(openRouterApiKeyServiceProvider);
        final result = await service.testConnection(apiKey);
        setState(() {
          _isTesting = false;
          _statusText = result.message;
          _statusType = result.success
              ? _StatusType.success
              : _StatusType.error;
        });
      } else {
        // 豆包 & DeepSeek
        final LyricsModelCatalogService service = ref.read(
          lyricsModelCatalogServiceProvider,
        );
        final result = await service.fetchModels(
          provider: provider,
          purpose: widget.purpose,
          apiKey: apiKey,
        );
        setState(() {
          _isTesting = false;
          _statusText = result.success
              ? '连接成功，检测到 ${result.models.length} 个模型。'
              : result.message;
          _statusType = result.success
              ? _StatusType.success
              : _StatusType.error;
        });
      }
    } catch (e) {
      setState(() {
        _isTesting = false;
        _statusText = '连接测试异常：$e';
        _statusType = _StatusType.error;
      });
    }
  }

  void _saveAndFinish() {
    final provider = _selectedProvider!;
    final apiKey = _keyController.text.trim();
    final settings = ref.read(settingsServiceProvider);

    // 1. 保存对应的 API Key
    switch (provider) {
      case LyricsAiProvider.googleAiStudio:
        settings.geminiApiKey = apiKey;
        break;
      case LyricsAiProvider.openRouter:
        settings.openRouterApiKey = apiKey;
        break;
      case LyricsAiProvider.doubao:
        settings.doubaoApiKey = apiKey;
        break;
      case LyricsAiProvider.deepseek:
        settings.deepseekApiKey = apiKey;
        break;
    }

    // 2. 自动配置对应的默认模型
    if (widget.purpose == LyricsAiModelPurpose.generation) {
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
    } else if (widget.purpose == LyricsAiModelPurpose.translation) {
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

    Navigator.of(context).pop(true);
  }

  bool _isZhLocale(BuildContext context) {
    return Localizations.localeOf(context).languageCode.toLowerCase() == 'zh';
  }

  _ProviderDetail _getProviderDetail(LyricsAiProvider provider) {
    final isZh = _isZhLocale(context);
    switch (provider) {
      case LyricsAiProvider.googleAiStudio:
        return _ProviderDetail(
          pros: isZh
              ? 'Google 官方通道，Gemini 模型能力强，免费额度较多。'
              : 'Official Google channel with strong Gemini models and generous free quotas.',
          cons: isZh
              ? '中国大陆直连受限，需要稳定的 VPN/代理。请求人数较多时可能报 429，遇到 429 请切换到其他渠道。'
              : 'High traffic can occasionally cause 429 errors. If that happens, switch to another provider.',
        );
      case LyricsAiProvider.openRouter:
        return _ProviderDetail(
          pros: isZh
              ? '海外大模型聚合平台，可使用多个模型，也有部分免费模型。'
              : 'A model aggregator with access to many providers and some free models.',
          cons: isZh
              ? '充值需要支付手续费，网页只有英文。'
              : 'Top-ups may include processing fees, and the website is English-only.',
        );
      case LyricsAiProvider.doubao:
        return _ProviderDetail(
          pros: isZh
              ? '字节跳动出品，国内访问快，中文效果好。新用户每个模型有 50 万免费 token。'
              : 'Built by ByteDance, strong for Chinese text. New users get 500k free tokens per model.',
          cons: isZh
              ? '注册步骤相对繁琐，需要实名认证。'
              : 'Registration is relatively involved and requires real-name verification.',
        );
      case LyricsAiProvider.deepseek:
        return _ProviderDetail(
          pros: isZh
              ? '中文理解好，价格便宜，适合歌词翻译。'
              : 'Good Chinese understanding, low pricing, and well suited for lyric translation.',
          cons: isZh
              ? '仅支持文本输入。如需歌词生成、时间轴调整，需要填入其他渠道 API Key。'
              : 'Text input only. Lyric generation and timeline adjustment require an API key from another provider.',
        );
    }
  }

  Widget _buildIntroPage(BuildContext context) {
    final isGeneration = widget.purpose == LyricsAiModelPurpose.generation;
    final isZh = _isZhLocale(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isZh
              ? isGeneration
                    ? '什么是 AI 歌词？'
                    : '什么是 AI 歌词翻译？'
              : isGeneration
              ? 'What are AI lyrics?'
              : 'What is AI lyric translation?',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          isZh
              ? isGeneration
                    ? 'AI 可以根据歌曲内容生成歌词，并自动匹配时间轴。'
                    : 'AI 可以把歌词翻译成你熟悉的语言，方便理解歌曲内容。'
              : isGeneration
              ? 'AI can generate lyrics from the song and align them to a timeline.'
              : 'AI can translate lyrics into your preferred language so the song is easier to understand.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        Text(
          isZh ? '为什么需要 API Key？' : 'Why do I need an API key?',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          isZh
              ? 'API Key 相当于你在 AI 服务商那里的访问凭证。应用会用它直接向服务商发起请求，完成歌词生成、时间轴调整或翻译。'
              : 'An API key is your access credential for an AI provider. The app uses it to send requests directly for lyric generation, timeline adjustment, or translation.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.security_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isZh
                      ? 'API Key 只保存在你的本地设备，不会上传到 Vynody 开发者服务器。'
                      : 'Your API key is stored only on this device and is never uploaded to Vynody developer servers.',
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderSelectionPage(BuildContext context) {
    final isZh = _isZhLocale(context);
    final filteredProviders = LyricsAiProvider.values.where((p) {
      if (widget.purpose == LyricsAiModelPurpose.generation) {
        return p != LyricsAiProvider.deepseek;
      }
      return true;
    }).toList();

    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isZh ? '选择一个 AI 服务商：' : 'Choose an AI provider:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final chunkSize = filteredProviders.length == 3 ? 3 : 2;
            final cardWidth = (maxWidth - (chunkSize - 1) * 10.0) / chunkSize;

            // Check if any provider's displayName cannot fit in the cardWidth with horizontal padding (8 * 2 = 16)
            const textStyle = TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
            );

            bool useListLayout = false;
            for (final provider in filteredProviders) {
              final textPainter = TextPainter(
                text: TextSpan(text: provider.displayName, style: textStyle),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout();
              if (textPainter.width > cardWidth - 16) {
                useListLayout = true;
                break;
              }
            }

            if (useListLayout) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(filteredProviders.length, (index) {
                  final provider = filteredProviders[index];
                  final isSelected = _selectedProvider == provider;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < filteredProviders.length - 1 ? 8.0 : 0.0,
                    ),
                    child: Card(
                      elevation: 0,
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.dividerColor.withValues(alpha: 0.1),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      color: theme.colorScheme.surfaceContainerLow.withValues(
                        alpha: 0.5,
                      ),
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedProvider = provider;
                            final settings = ref.read(settingsServiceProvider);
                            _keyController.text = settings.apiKeyForProvider(
                              provider,
                            );
                            _statusText = '';
                            _statusType = _StatusType.none;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              LyricsProviderIcon(provider: provider, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  provider.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.primary,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }

            final List<List<LyricsAiProvider>> rows = [];
            for (var i = 0; i < filteredProviders.length; i += chunkSize) {
              final end = (i + chunkSize < filteredProviders.length)
                  ? i + chunkSize
                  : filteredProviders.length;
              rows.add(filteredProviders.sublist(i, end));
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(rows.length, (rowIndex) {
                final rowItems = rows[rowIndex];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: rowIndex < rows.length - 1 ? 10.0 : 0.0,
                  ),
                  child: Row(
                    children: List.generate(rowItems.length, (colIndex) {
                      final provider = rowItems[colIndex];
                      final isSelected = _selectedProvider == provider;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: colIndex < rowItems.length - 1 ? 10.0 : 0.0,
                          ),
                          child: Card(
                            elevation: 0,
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : theme.dividerColor.withValues(alpha: 0.1),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            color: theme.colorScheme.surfaceContainerLow
                                .withValues(alpha: 0.5),
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedProvider = provider;
                                  final settings = ref.read(
                                    settingsServiceProvider,
                                  );
                                  _keyController.text = settings
                                      .apiKeyForProvider(provider);
                                  _statusText = '';
                                  _statusType = _StatusType.none;
                                });
                              },
                              child: Stack(
                                children: [
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          LyricsProviderIcon(
                                            provider: provider,
                                            size: 36,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            provider.displayName,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: Icon(
                                        Icons.check_circle,
                                        color: theme.colorScheme.primary,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            );
          },
        ),
        if (_selectedProvider != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZh ? '【特点】' : 'Highlights',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getProviderDetail(_selectedProvider!).pros,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  isZh ? '【注意事项】' : 'Notes',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getProviderDetail(_selectedProvider!).cons,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildApiKeyInputPage(BuildContext context) {
    final provider = _selectedProvider!;
    final isZh = _isZhLocale(context);
    final theme = Theme.of(context);

    String getKeyUrl = '';
    switch (provider) {
      case LyricsAiProvider.googleAiStudio:
        getKeyUrl = 'https://aistudio.google.com/app/api-keys';
        break;
      case LyricsAiProvider.openRouter:
        getKeyUrl = 'https://openrouter.ai/settings/keys';
        break;
      case LyricsAiProvider.doubao:
        getKeyUrl =
            'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey';
        break;
      case LyricsAiProvider.deepseek:
        getKeyUrl = 'https://platform.deepseek.com/api_keys';
        break;
    }

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isZh
              ? '请输入 ${provider.displayName} 的 API Key：'
              : 'Enter your ${provider.displayName} API key:',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _keyController,
          autofocus: true,
          obscureText: _obscureText,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText: isZh ? '在此粘贴你的 API Key' : 'Paste your API key here',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () {
                setState(() {
                  _obscureText = !_obscureText;
                });
              },
            ),
          ),
          onChanged: (_) {
            setState(() {
              _statusText = '';
              _statusType = _StatusType.none;
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: () => launchUrlString(getKeyUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(isZh ? '获取 API Key' : 'Get API key'),
            ),
            ElevatedButton.icon(
              onPressed: _isTesting ? null : _runTestConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded, size: 16),
              label: Text(
                _isTesting
                    ? isZh
                          ? '正在测试...'
                          : 'Testing...'
                    : isZh
                    ? '测试连接'
                    : 'Test connection',
              ),
            ),
          ],
        ),
        if (_statusText.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor.withValues(alpha: 0.2)),
            ),
            child: Text(
              _statusText,
              style: TextStyle(color: statusColor, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPage3Valid =
        _selectedProvider != null && _keyController.text.trim().isNotEmpty;
    final isZh = _isZhLocale(context);
    final settings = ref.read(settingsServiceProvider);

    Widget content;
    String title;
    List<Widget> actions;

    if (_currentPage == 1) {
      title = isZh
          ? widget.purpose == LyricsAiModelPurpose.generation
                ? '启用 AI 歌词生成'
                : '启用 AI 歌词翻译'
          : widget.purpose == LyricsAiModelPurpose.generation
          ? 'Enable AI Lyric Generation'
          : 'Enable AI Lyric Translation';
      content = _buildIntroPage(context);
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(isZh ? '暂不启用' : 'Not now'),
        ),
        FilledButton(
          onPressed: () {
            setState(() {
              _currentPage = 2;
            });
          },
          child: Text(isZh ? '开始配置' : 'Start setup'),
        ),
      ];
    } else if (_currentPage == 2) {
      title = isZh ? '选择 AI 服务商' : 'Choose AI Provider';
      content = _buildProviderSelectionPage(context);
      actions = [
        TextButton(
          onPressed: () {
            if (settings.hasAnyLyricsModelProvider) {
              Navigator.of(context).pop(false);
            } else {
              setState(() {
                _currentPage = 1;
              });
            }
          },
          child: Text(
            isZh
                ? settings.hasAnyLyricsModelProvider
                      ? '取消'
                      : '上一步'
                : settings.hasAnyLyricsModelProvider
                ? 'Cancel'
                : 'Back',
          ),
        ),
        FilledButton(
          onPressed: _selectedProvider == null
              ? null
              : () async {
                  if (_selectedProvider == LyricsAiProvider.deepseek) {
                    final proceed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) {
                        return AlertDialog(
                          title: Text(isZh ? '提示' : 'Note'),
                          content: Text(
                            isZh
                                ? 'DeepSeek 仅支持文本输入。如需歌词生成、时间轴调整，需要填入其他渠道 API Key。'
                                : 'DeepSeek supports text input only. Lyric generation and timeline adjustment require an API key from another provider.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: Text(isZh ? '取消' : 'Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(true),
                              child: Text(isZh ? '继续' : 'Continue'),
                            ),
                          ],
                        );
                      },
                    );
                    if (proceed != true) return;
                  }
                  if (!mounted) return;
                  setState(() {
                    _currentPage = 3;
                  });
                },
          child: Text(isZh ? '下一步' : 'Next'),
        ),
      ];
    } else {
      title = isZh ? '配置 API Key' : 'Configure API Key';
      content = _buildApiKeyInputPage(context);
      actions = [
        TextButton(
          onPressed: () {
            setState(() {
              _currentPage = 2;
              _statusText = '';
              _statusType = _StatusType.none;
            });
          },
          child: Text(isZh ? '上一步' : 'Back'),
        ),
        FilledButton(
          onPressed: isPage3Valid && !_isTesting ? _saveAndFinish : null,
          child: Text(isZh ? '保存并完成' : 'Save and finish'),
        ),
      ];
    }

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: content),
      ),
      actions: actions,
    );
  }
}

class _ProviderDetail {
  const _ProviderDetail({required this.pros, required this.cons});
  final String pros;
  final String cons;
}
