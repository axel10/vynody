import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:vibe_flow/player/ai/lyrics_model_catalog_service.dart';

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
        getKeyUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey',
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
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return _LyricsApiKeyWizardDialog(purpose: purpose);
    },
  );
  return result ?? false;
}

class _LyricsApiKeyWizardDialog extends ConsumerStatefulWidget {
  const _LyricsApiKeyWizardDialog({
    required this.purpose,
  });

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
          _statusType = result.success ? _StatusType.success : _StatusType.error;
        });
      } else if (provider == LyricsAiProvider.openRouter) {
        final service = ref.read(openRouterApiKeyServiceProvider);
        final result = await service.testConnection(apiKey);
        setState(() {
          _isTesting = false;
          _statusText = result.message;
          _statusType = result.success ? _StatusType.success : _StatusType.error;
        });
      } else {
        // 豆包 & DeepSeek
        final LyricsModelCatalogService service =
            ref.read(lyricsModelCatalogServiceProvider);
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
          _statusType = result.success ? _StatusType.success : _StatusType.error;
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

  _ProviderDetail _getProviderDetail(LyricsAiProvider provider) {
    switch (provider) {
      case LyricsAiProvider.googleAiStudio:
        return const _ProviderDetail(
          pros: '官方通道，Gemini 模型（如 Flash Lite）性能强劲，提供大额度免费配额。',
          cons: '在中国大陆直连受限，需要稳定的网络代理 (VPN/Proxy)。',
        );
      case LyricsAiProvider.openRouter:
        return const _ProviderDetail(
          pros: '海外大模型聚合平台。支持免代理直连，且有免费的 Gemini 等模型额度。',
          cons: '注册或高并发时可能需要绑定，部分模型响应速度受海外节点影响。',
        );
      case LyricsAiProvider.doubao:
        return const _ProviderDetail(
          pros: '字节跳动出品。国内直连极速，无需代理，中文歌词创作与润色效果极佳。',
          cons: '需要注册火山引擎，创建接入点 (Endpoint) 的步骤相对繁琐。',
        );
      case LyricsAiProvider.deepseek:
        return const _ProviderDetail(
          pros: '国内高性价比模型，中文理解出色，价格极便宜。',
          cons: '本项目目前仅支持使用 DeepSeek 进行歌词翻译，不支持歌词生成。',
        );
    }
  }

  String _providerIconPath(LyricsAiProvider provider) {
    switch (provider) {
      case LyricsAiProvider.googleAiStudio:
        return 'assets/icons/lyrics/google.png';
      case LyricsAiProvider.openRouter:
        return 'assets/icons/lyrics/openrouter.png';
      case LyricsAiProvider.doubao:
        return 'assets/icons/lyrics/doubao.png';
      case LyricsAiProvider.deepseek:
        return 'assets/icons/lyrics/deepseek.png';
    }
  }

  Widget _buildIntroPage(BuildContext context) {
    final isGeneration = widget.purpose == LyricsAiModelPurpose.generation;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isGeneration ? '什么是 AI 歌词？' : '什么是 AI 歌词翻译？',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          isGeneration
              ? 'AI 歌词功能可以利用大语言模型，自动为您的歌曲生成精密的同步歌词及时间轴。'
              : 'AI 歌词翻译功能可以利用大语言模型，将歌词翻译为您的目标语言，让您更好地理解歌曲意境。',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 16),
        const Text(
          '为什么需要 API Key？',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        const Text(
          '此功能完全运行在您的本地设备上，不经过第三方中间服务器。因此，您需要填写对应大模型服务商的 API Key 来直接调用其接口。',
          style: TextStyle(fontSize: 14, height: 1.4),
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
              const Expanded(
                child: Text(
                  '您的 API Key 会以加密形式妥善保存在本地，绝不会上传至 vibe_flow 开发者服务器，请放心使用。',
                  style: TextStyle(fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderSelectionPage(BuildContext context) {
    final filteredProviders = LyricsAiProvider.values.where((p) {
      if (widget.purpose == LyricsAiModelPurpose.generation) {
        return p != LyricsAiProvider.deepseek;
      }
      return true;
    }).toList();

    final theme = Theme.of(context);

    final chunkSize = filteredProviders.length == 3 ? 3 : 2;
    final List<List<LyricsAiProvider>> rows = [];
    for (var i = 0; i < filteredProviders.length; i += chunkSize) {
      final end = (i + chunkSize < filteredProviders.length)
          ? i + chunkSize
          : filteredProviders.length;
      rows.add(filteredProviders.sublist(i, end));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '请选择要使用的 AI 服务商：',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 12),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(rows.length, (rowIndex) {
            final rowItems = rows[rowIndex];
            return Padding(
              padding: EdgeInsets.only(bottom: rowIndex < rows.length - 1 ? 10.0 : 0.0),
              child: Row(
                children: List.generate(rowItems.length, (colIndex) {
                  final provider = rowItems[colIndex];
                  final isSelected = _selectedProvider == provider;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: colIndex < rowItems.length - 1 ? 10.0 : 0.0),
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
                        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedProvider = provider;
                              final settings = ref.read(settingsServiceProvider);
                              _keyController.text = settings.apiKeyForProvider(provider);
                              _statusText = '';
                              _statusType = _StatusType.none;
                            });
                          },
                          child: Stack(
                            children: [
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 3,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        padding: const EdgeInsets.all(5),
                                        child: Image.asset(
                                          _providerIconPath(provider),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        provider.displayName,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
        ),
        if (_selectedProvider != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '【特点】',
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
                  '【注意事项】',
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
        getKeyUrl = 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey';
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
          '请输入 ${provider.displayName} 的 API Key：',
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
            hintText: '在此粘贴您的 API Key',
            suffixIcon: IconButton(
              icon: Icon(
                _obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
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
              label: const Text('获取 API Key'),
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
              label: Text(_isTesting ? '正在测试...' : '测试连接'),
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
    final isPage3Valid = _selectedProvider != null && _keyController.text.trim().isNotEmpty;
    final settings = ref.read(settingsServiceProvider);

    Widget content;
    String title;
    List<Widget> actions;

    if (_currentPage == 1) {
      title = widget.purpose == LyricsAiModelPurpose.generation
          ? '启用 AI 歌词生成'
          : '启用 AI 歌词翻译';
      content = _buildIntroPage(context);
      actions = [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('暂不启用'),
        ),
        FilledButton(
          onPressed: () {
            setState(() {
              _currentPage = 2;
            });
          },
          child: const Text('开始配置'),
        ),
      ];
    } else if (_currentPage == 2) {
      title = '选择 AI 服务商';
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
            settings.hasAnyLyricsModelProvider ? '取消' : '上一步',
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
                          title: const Text('提示'),
                          content: const Text(
                            'DeepSeek 不支持歌词/时间轴生成，后续如果需要用到歌词/时间轴生成功能则需另外填入其他平台 API Key。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(true),
                              child: const Text('继续'),
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
          child: const Text('下一步'),
        ),
      ];
    } else {
      title = '配置 API Key';
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
          child: const Text('上一步'),
        ),
        FilledButton(
          onPressed: isPage3Valid && !_isTesting ? _saveAndFinish : null,
          child: const Text('保存并完成'),
        ),
      ];
    }

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: content,
        ),
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
