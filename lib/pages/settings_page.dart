import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dialogs/acoustid_api_key_dialog.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../l10n/app_localizations.dart';
import '../player/ai_api_key_service.dart';
import '../player/audio_riverpod.dart';
import '../player/settings_service.dart';
import '../widgets/desktop_window_title_bar.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.showDesktopTitleBar = true});

  final bool showDesktopTitleBar;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  static const List<GeminiModelInfo> _defaultGeminiModels = [
    GeminiModelInfo(
      id: SettingsService.defaultGeminiPrimaryModelId,
      displayName: 'Gemini 3.1 Flash Lite Preview',
    ),
    GeminiModelInfo(
      id: SettingsService.defaultGeminiFallbackModelId,
      displayName: 'Gemini 2.5 Flash',
    ),
  ];

  List<GeminiModelInfo> _geminiModels = const [];
  bool _isLoadingGeminiModels = false;

  List<GeminiModelInfo> _mergedGeminiModels(SettingsService settings) {
    final merged = <String, GeminiModelInfo>{};
    for (final model in _defaultGeminiModels) {
      merged[model.id] = model;
    }
    for (final model in _geminiModels) {
      merged[model.id] = model;
    }

    final primaryId = settings.geminiPrimaryModelId.trim();
    final fallbackId = settings.geminiFallbackModelId.trim();
    if (primaryId.isNotEmpty && !merged.containsKey(primaryId)) {
      merged[primaryId] = GeminiModelInfo(
        id: primaryId,
        displayName: SettingsService.geminiModelDisplayName(primaryId),
      );
    }
    if (fallbackId.isNotEmpty && !merged.containsKey(fallbackId)) {
      merged[fallbackId] = GeminiModelInfo(
        id: fallbackId,
        displayName: SettingsService.geminiModelDisplayName(fallbackId),
      );
    }

    return merged.values.toList(growable: false);
  }

  Future<void> _fetchGeminiModelList() async {
    final settings = ref.read(settingsServiceProvider);
    final apiKey = settings.geminiApiKey.trim();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Google AI Studio API Key')),
      );
      return;
    }

    setState(() {
      _isLoadingGeminiModels = true;
    });

    final result = await ref
        .read(geminiApiKeyServiceProvider)
        .testConnection(apiKey);
    if (!mounted) return;

    setState(() {
      _isLoadingGeminiModels = false;
      if (result.success) {
        _geminiModels = result.models;
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  void _restoreDefaultGeminiModels() {
    final settings = ref.read(settingsServiceProvider);
    settings.resetGeminiModels();
    setState(() {
      _geminiModels = const [];
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已恢复默认 Gemini 模型')));
  }

  Widget _buildSectionHeader(String title, [String? description]) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(description, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _buildGeminiModelSection(
    BuildContext context,
    SettingsService settings,
  ) {
    final options = _mergedGeminiModels(settings);
    final primaryValue = settings.geminiPrimaryModelId;
    final fallbackValue = settings.geminiFallbackModelId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '这里的两个模型会用于 Google AI Studio 的歌词生成与时间轴生成。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: primaryValue.isEmpty ? null : primaryValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '主模型',
              border: OutlineInputBorder(),
            ),
            items: options
                .map(
                  (model) => DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(model.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              settings.geminiPrimaryModelId = value;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: fallbackValue.isEmpty ? null : fallbackValue,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '备用模型',
              border: OutlineInputBorder(),
            ),
            items: options
                .map(
                  (model) => DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(model.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              settings.geminiFallbackModelId = value;
            },
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.tonalIcon(
                onPressed: _isLoadingGeminiModels
                    ? null
                    : _fetchGeminiModelList,
                icon: _isLoadingGeminiModels
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_isLoadingGeminiModels ? '获取中...' : '获取模型列表'),
              ),
              OutlinedButton.icon(
                onPressed: _restoreDefaultGeminiModels,
                icon: const Icon(Icons.restart_alt),
                label: const Text('恢复默认'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildSectionHeader('界面', '这些选项会影响页面和播放界面的整体显示方式。'),
        SwitchListTile(
          title: Text(l10n.immersiveTabBar),
          subtitle: Text(l10n.immersiveTabBarDescription),
          value: settings.isImmersiveTabBarEnabled,
          onChanged: (value) {
            settings.isImmersiveTabBarEnabled = value;
          },
        ),
        ListTile(
          title: Text(l10n.waveformSegments),
          subtitle: Text(l10n.waveformSegmentsDescription),
          trailing: SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: settings.waveformChunks > 20
                      ? () => settings.waveformChunks -= 10
                      : null,
                ),
                Text('${settings.waveformChunks}'),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: settings.waveformChunks < 200
                      ? () => settings.waveformChunks += 10
                      : null,
                ),
              ],
            ),
          ),
        ),
        SwitchListTile(
          title: Text(l10n.enableWaveformProgressBar),
          subtitle: Text(l10n.enableWaveformProgressBarDescription),
          value: settings.isWaveformProgressBarEnabled,
          onChanged: (value) {
            settings.isWaveformProgressBarEnabled = value;
          },
        ),
        const Divider(height: 1),
        _buildSectionHeader('歌词', '这里的配置只影响歌词生成和时间轴生成。'),
        SwitchListTile(
          title: const Text('自动切换歌词供应商'),
          subtitle: Text(
            settings.canAutoSwitchLyricsProvider
                ? '开启后会先请求 Google AI Studio；主模型和备用模型都因 429 或 5xx 失败时，再自动切到 OpenRouter 继续请求。'
                : '请先同时填写 Google AI Studio 和 OpenRouter 的 API Key，才可以开启自动切换。',
          ),
          value: settings.isLyricsAiAutoSwitchEnabled,
          onChanged: settings.canAutoSwitchLyricsProvider
              ? (value) {
                  settings.isLyricsAiAutoSwitchEnabled = value;
                }
              : null,
        ),
        ListTile(
          title: const Text('歌词生成 AI 提供方'),
          subtitle: const Text('这里只影响歌词生成和时间轴生成。翻译始终走 Google AI Studio'),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<LyricsAiProvider>(
              value: settings.lyricsAiProvider,
              onChanged: (value) {
                if (value == null) return;
                settings.lyricsAiProvider = value;
              },
              items: LyricsAiProvider.values
                  .map(
                    (provider) => DropdownMenuItem<LyricsAiProvider>(
                      value: provider,
                      child: Text(provider.displayName),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        ListTile(
          isThreeLine: true,
          leading: const Icon(Icons.key),
          title: Text('${settings.lyricsAiProvider.displayName} API Key'),
          subtitle: Text(
            settings.lyricsAiProvider == LyricsAiProvider.googleAiStudio
                ? (settings.geminiApiKey.trim().isEmpty
                      ? '当前未保存 Google AI Studio key，歌词生成和时间轴生成会先弹窗提示。'
                      : '已保存 Google AI Studio key，可用于歌词生成和时间轴生成。')
                : (settings.openRouterApiKey.trim().isEmpty
                      ? '当前未保存 OpenRouter key，歌词生成和时间轴生成会先弹窗提示。'
                      : '已保存 OpenRouter key，可用于歌词生成和时间轴生成。'),
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showLyricsProviderApiKeyDialog(
                context,
                ref: ref,
                provider: settings.lyricsAiProvider,
                initialApiKey: switch (settings.lyricsAiProvider) {
                  LyricsAiProvider.googleAiStudio => settings.geminiApiKey,
                  LyricsAiProvider.openRouter => settings.openRouterApiKey,
                },
              );
              if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
                return;
              }

              switch (settings.lyricsAiProvider) {
                case LyricsAiProvider.googleAiStudio:
                  settings.geminiApiKey = enteredApiKey;
                  break;
                case LyricsAiProvider.openRouter:
                  settings.openRouterApiKey = enteredApiKey;
                  break;
              }

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${settings.lyricsAiProvider.displayName} API Key 已保存',
                  ),
                ),
              );
            },
            child: Text(switch (settings.lyricsAiProvider) {
              LyricsAiProvider.googleAiStudio =>
                settings.geminiApiKey.trim().isEmpty ? '填写' : '修改',
              LyricsAiProvider.openRouter =>
                settings.openRouterApiKey.trim().isEmpty ? '填写' : '修改',
            }),
          ),
        ),
        if (settings.lyricsAiProvider == LyricsAiProvider.googleAiStudio)
          _buildSectionHeader(
            'Gemini 模型',
            '这两个模型会用于 Google AI Studio 的歌词生成与时间轴生成。',
          ),
        if (settings.lyricsAiProvider == LyricsAiProvider.googleAiStudio)
          _buildGeminiModelSection(context, settings),
        _buildSectionHeader('指纹识别', 'AcoustID 用于音频指纹识别，建议使用你自己的 API Key。'),
        ListTile(
          isThreeLine: true,
          leading: const Icon(Icons.fingerprint),
          title: const Text('AcoustID API Key'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.hasCustomAcoustidApiKey
                    ? '已保存自定义 key，音频指纹识别会优先使用它。'
                    : '当前使用应用内置的默认 key，建议申请你自己的 key 后替换。',
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse('https://acoustid.org/new-application');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: const Text(
                  '申请 API key: https://acoustid.org/new-application',
                  style: TextStyle(
                    color: Colors.lightBlueAccent,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showAcoustidApiKeyDialog(
                context,
                initialApiKey: settings.hasCustomAcoustidApiKey
                    ? settings.acoustidApiKey
                    : '',
              );
              if (enteredApiKey == null) {
                return;
              }

              settings.acoustidApiKey = enteredApiKey;
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AcoustID API Key 已保存')),
              );
            },
            child: Text(settings.hasCustomAcoustidApiKey ? '修改' : '填写'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final showDesktopTitleBar = isDesktop && widget.showDesktopTitleBar;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.settings),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: showDesktopTitleBar ? 32 : 0),
            child: SafeArea(
              top: !showDesktopTitleBar,
              child: _buildBody(context, settings),
            ),
          ),
          if (showDesktopTitleBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DesktopWindowTitleBar(
                brightness: Theme.of(context).brightness,
              ),
            ),
        ],
      ),
    );
  }
}
