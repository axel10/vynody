import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../dialogs/acoustid_api_key_dialog.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../dialogs/shortcut_settings_dialog.dart';
import '../l10n/app_localizations.dart';
import '../player/ai_api_key_service.dart';
import '../player/audio_riverpod.dart';
import '../player/settings_service.dart';
import '../widgets/desktop_window_title_bar.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

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
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.enterApiKey)));
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
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.restoreDefault)));
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

  Widget _buildThemeModeSection(
    BuildContext context,
    SettingsService settings,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: DropdownButtonFormField<ThemeMode>(
        initialValue: settings.themeMode,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.themeMode,
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.system,
            child: Text(l10n.themeModeSystem),
          ),
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.light,
            child: Text(l10n.themeModeLight),
          ),
          DropdownMenuItem<ThemeMode>(
            value: ThemeMode.dark,
            child: Text(l10n.themeModeDark),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          settings.themeMode = value;
        },
      ),
    );
  }

  Widget _buildScanSection(BuildContext context, SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;
    const minSeconds = 5;
    const maxSeconds = 300;
    const stepSeconds = 5;
    final enabled = settings.skipShortAudioScanEnabled;
    final currentSeconds = settings.skipShortAudioScanMinimumDurationSeconds;

    return Column(
      children: [
        SwitchListTile(
          title: Text(l10n.skipShortAudioDuringScan),
          subtitle: Text(l10n.skipShortAudioDuringScanDescription),
          value: enabled,
          onChanged: (value) {
            settings.skipShortAudioScanEnabled = value;
          },
        ),
        ListTile(
          enabled: enabled,
          title: Text(l10n.shortAudioScanThreshold),
          subtitle: Text(l10n.shortAudioScanThresholdDescription),
          trailing: SizedBox(
            width: 156,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: enabled && currentSeconds > minSeconds
                      ? () {
                          settings.skipShortAudioScanMinimumDurationSeconds =
                              currentSeconds - stepSeconds;
                        }
                      : null,
                ),
                Text(l10n.shortAudioScanThresholdValue(currentSeconds)),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: enabled && currentSeconds < maxSeconds
                      ? () {
                          settings.skipShortAudioScanMinimumDurationSeconds =
                              currentSeconds + stepSeconds;
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGeminiModelSection(
    BuildContext context,
    SettingsService settings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final options = _mergedGeminiModels(settings);
    final primaryValue = settings.geminiPrimaryModelId;
    final fallbackValue = settings.geminiFallbackModelId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.geminiModelsSectionDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: primaryValue.isEmpty ? null : primaryValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.primaryModelLabel,
              border: const OutlineInputBorder(),
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
            decoration: InputDecoration(
              labelText: l10n.backupModelLabel,
              border: const OutlineInputBorder(),
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
                label: Text(
                  _isLoadingGeminiModels ? l10n.fetching : l10n.fetchModelList,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _restoreDefaultGeminiModels,
                icon: const Icon(Icons.restart_alt),
                label: Text(l10n.restoreDefault),
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
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          l10n.generalSectionTitle,
          l10n.generalSectionDescription,
        ),
        _buildThemeModeSection(context, settings),
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
        _buildSectionHeader(l10n.scanSectionTitle, l10n.scanSectionDescription),
        _buildScanSection(context, settings),
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: Text(l10n.shortcutSettingsTitle),
          subtitle: Text(l10n.shortcutSettingsDescription),
          trailing: FilledButton.tonal(
            onPressed: () {
              showShortcutSettingsDialog(context);
            },
            child: Text(l10n.edit),
          ),
        ),
        const Divider(height: 1),
        _buildSectionHeader(
          l10n.lyricsSectionTitle,
          l10n.lyricsSectionDescription,
        ),
        SwitchListTile(
          title: Text(l10n.autoSwitchLyricsProvider),
          subtitle: Text(
            settings.canAutoSwitchLyricsProvider
                ? l10n.autoSwitchLyricsProviderEnabledDesc
                : l10n.autoSwitchLyricsProviderDisabledDesc,
          ),
          value: settings.isLyricsAiAutoSwitchEnabled,
          onChanged: settings.canAutoSwitchLyricsProvider
              ? (value) {
                  settings.isLyricsAiAutoSwitchEnabled = value;
                }
              : null,
        ),
        ListTile(
          title: Text(l10n.lyricsAiProviderTitle),
          subtitle: Text(l10n.lyricsAiProviderDescription),
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
                      ? l10n.googleAiStudioApiKeyMissing
                      : l10n.googleAiStudioApiKeySaved)
                : (settings.openRouterApiKey.trim().isEmpty
                      ? l10n.openRouterApiKeyMissing
                      : l10n.openRouterApiKeySaved),
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
                    l10n.apiKeySaved(settings.lyricsAiProvider.displayName),
                  ),
                ),
              );
            },
            child: Text(switch (settings.lyricsAiProvider) {
              LyricsAiProvider.googleAiStudio =>
                settings.geminiApiKey.trim().isEmpty ? l10n.fill : l10n.modify,
              LyricsAiProvider.openRouter =>
                settings.openRouterApiKey.trim().isEmpty
                    ? l10n.fill
                    : l10n.modify,
            }),
          ),
        ),
        if (settings.lyricsAiProvider == LyricsAiProvider.googleAiStudio)
          _buildSectionHeader(
            l10n.geminiModelsSectionTitle,
            l10n.geminiModelsSectionDescription,
          ),
        if (settings.lyricsAiProvider == LyricsAiProvider.googleAiStudio)
          _buildGeminiModelSection(context, settings),
        _buildSectionHeader(l10n.acoustidSectionTitle, l10n.acoustidApiKeyHelp),
        ListTile(
          isThreeLine: true,
          leading: const Icon(Icons.fingerprint),
          title: Text(l10n.acoustidApiKeyTitle),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.hasCustomAcoustidApiKey
                    ? l10n.acoustidApiKeySaved
                    : l10n.acoustidApiKeyDefault,
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse('https://acoustid.org/new-application');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                child: Text(
                  l10n.applyForApiKey,
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.acoustidApiKeySaved)));
            },
            child: Text(
              settings.hasCustomAcoustidApiKey ? l10n.modify : l10n.fill,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);
    final theme = Theme.of(context);
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget content = Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.settings)),
      body: _buildBody(context, settings),
    );

    if (isDesktop) {
      content = Material(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            DesktopWindowTitleBar(brightness: theme.brightness),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }
}
