import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../dialogs/acoustid_api_key_dialog.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../dialogs/shortcut_settings_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/ai/lyrics_model_catalog_service.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';
import '../transcode/transcode_models.dart';
import 'package:vibe_flow/player/settings/windows_association_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/desktop_window_title_bar.dart';
import 'package:vibe_flow/utils/language_code_utils.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _appVersion = '';
  bool _isAssociated = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _checkAssociationStatus();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkAssociationStatus() async {
    if (Platform.isWindows) {
      final status = await WindowsAssociationService.isAssociated();
      if (mounted) {
        setState(() {
          _isAssociated = status;
        });
      }
    }
  }

  Widget _buildWindowsSection(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        _buildSectionHeader(
          l10n.windowsSettingsTitle,
          l10n.fileAssociationDescription,
        ),
        ListTile(
          leading: const Icon(Icons.open_in_new_rounded),
          title: Text(l10n.fileAssociationTitle),
          subtitle: Text(
            _isAssociated ? '已开启关联 (Associated)' : '未开启关联 (Not Associated)',
            style: TextStyle(
              color: _isAssociated ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () async {
                  try {
                    await WindowsAssociationService.associate();
                    await _checkAssociationStatus();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.associationSuccess)),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.associationFailed(e.toString())),
                      ),
                    );
                  }
                },
                child: Text(l10n.associateButton),
              ),
              if (_isAssociated)
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await WindowsAssociationService.disassociate();
                      await _checkAssociationStatus();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.disassociationSuccess)),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.associationFailed(e.toString())),
                        ),
                      );
                    }
                  },
                  child: Text(l10n.disassociateButton),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _selectLyricsModel({
    required SettingsService settings,
    required LyricsAiModelPurpose purpose,
    required LyricsAiModelSlot slot,
  }) async {
    final currentSelection = _selectionFor(settings, purpose, slot);
    final selected = await showDialog<LyricsAiModelSelection>(
      context: context,
      builder: (dialogContext) {
        return _LyricsModelPickerDialog(
          ref: ref,
          purpose: purpose,
          initialSelection: currentSelection,
        );
      },
    );
    if (selected == null) {
      return;
    }
    _saveSelection(settings, purpose, slot, selected);
  }

  LyricsAiModelSelection _selectionFor(
    SettingsService settings,
    LyricsAiModelPurpose purpose,
    LyricsAiModelSlot slot,
  ) {
    return switch ((purpose, slot)) {
      (LyricsAiModelPurpose.generation, LyricsAiModelSlot.primary) =>
        settings.generationPrimaryModel,
      (LyricsAiModelPurpose.generation, LyricsAiModelSlot.fallback) =>
        settings.generationFallbackModel,
      (LyricsAiModelPurpose.translation, LyricsAiModelSlot.primary) =>
        settings.translationPrimaryModel,
      (LyricsAiModelPurpose.translation, LyricsAiModelSlot.fallback) =>
        settings.translationFallbackModel,
    };
  }

  void _saveSelection(
    SettingsService settings,
    LyricsAiModelPurpose purpose,
    LyricsAiModelSlot slot,
    LyricsAiModelSelection selection,
  ) {
    switch ((purpose, slot)) {
      case (LyricsAiModelPurpose.generation, LyricsAiModelSlot.primary):
        settings.generationPrimaryModel = selection;
      case (LyricsAiModelPurpose.generation, LyricsAiModelSlot.fallback):
        settings.generationFallbackModel = selection;
      case (LyricsAiModelPurpose.translation, LyricsAiModelSlot.primary):
        settings.translationPrimaryModel = selection;
      case (LyricsAiModelPurpose.translation, LyricsAiModelSlot.fallback):
        settings.translationFallbackModel = selection;
    }
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

  String _transcodeQualityLabel(
    BuildContext context,
    TranscodeQualityTier tier,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return switch (tier) {
      TranscodeQualityTier.low => l10n.transcodeQualityLow,
      TranscodeQualityTier.medium => l10n.transcodeQualityMedium,
      TranscodeQualityTier.high => l10n.transcodeQualityHigh,
      TranscodeQualityTier.extreme => l10n.transcodeQualityExtreme,
    };
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

  Widget _buildLyricsModelSection(
    BuildContext context,
    SettingsService settings,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelGroupCard(
            context,
            title: '歌词生成模型',
            description: '用于 AI 听歌生成歌词，以及给现有歌词生成/修正时间轴。',
            primarySelection: settings.generationPrimaryModel,
            fallbackSelection: settings.generationFallbackModel,
            onPrimaryTap: () => _selectLyricsModel(
              settings: settings,
              purpose: LyricsAiModelPurpose.generation,
              slot: LyricsAiModelSlot.primary,
            ),
            onFallbackTap: () => _selectLyricsModel(
              settings: settings,
              purpose: LyricsAiModelPurpose.generation,
              slot: LyricsAiModelSlot.fallback,
            ),
          ),
          const SizedBox(height: 16),
          _buildModelGroupCard(
            context,
            title: '歌词翻译模型',
            description: '用于把歌词翻译到目标语言。',
            primarySelection: settings.translationPrimaryModel,
            fallbackSelection: settings.translationFallbackModel,
            onPrimaryTap: () => _selectLyricsModel(
              settings: settings,
              purpose: LyricsAiModelPurpose.translation,
              slot: LyricsAiModelSlot.primary,
            ),
            onFallbackTap: () => _selectLyricsModel(
              settings: settings,
              purpose: LyricsAiModelPurpose.translation,
              slot: LyricsAiModelSlot.fallback,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () {
                settings.resetLyricsAiModels();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.restoreDefault)));
              },
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.restoreDefault),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelGroupCard(
    BuildContext context, {
    required String title,
    required String description,
    required LyricsAiModelSelection primarySelection,
    required LyricsAiModelSelection fallbackSelection,
    required VoidCallback onPrimaryTap,
    required VoidCallback onFallbackTap,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          _buildModelTile(
            context,
            title: AppLocalizations.of(context)!.primaryModelLabel,
            selection: primarySelection,
            onTap: onPrimaryTap,
          ),
          const SizedBox(height: 12),
          _buildModelTile(
            context,
            title: AppLocalizations.of(context)!.backupModelLabel,
            selection: fallbackSelection,
            onTap: onFallbackTap,
          ),
        ],
      ),
    );
  }

  Widget _buildModelTile(
    BuildContext context, {
    required String title,
    required LyricsAiModelSelection selection,
    required VoidCallback onTap,
  }) {
    final modelLabel = SettingsService.lyricsModelSelectionLabel(selection);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    modelLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  String _translationLanguageLabel(BuildContext context, String languageCode) {
    final l10n = AppLocalizations.of(context)!;
    final normalized = LanguageCodeUtils.normalizeLanguageCode(languageCode);
    if (normalized.isEmpty) {
      return l10n.followSystemLanguage;
    }
    return LanguageCodeUtils.languageDisplayName(normalized);
  }

  List<DropdownMenuItem<String>> _translationLanguageItems(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return [
      DropdownMenuItem<String>(
        value: '',
        child: Text(l10n.followSystemLanguage),
      ),
      ...LanguageCodeUtils.supportedTranslationLanguageCodes.map(
        (languageCode) => DropdownMenuItem<String>(
          value: languageCode,
          child: Text(_translationLanguageLabel(context, languageCode)),
        ),
      ),
    ];
  }

  Widget _buildLyricsTranslationLanguageSection(
    BuildContext context,
    SettingsService settings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final value = settings.lyricsTranslationTargetLanguageCode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lyricsTranslationTargetLanguageDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: value.isEmpty ? '' : value,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.lyricsTranslationTargetLanguageLabel,
              border: const OutlineInputBorder(),
            ),
            items: _translationLanguageItems(context),
            onChanged: (newValue) {
              if (newValue == null) return;
              settings.lyricsTranslationTargetLanguageCode = newValue;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTranscodeSection(
    BuildContext context,
    SettingsService settings,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: DropdownButtonFormField<AudioFormat>(
            initialValue: settings.transcodeDefaultFormat,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.transcodeDefaultFormat,
              border: const OutlineInputBorder(),
            ),
            items: AudioFormat.values
                .map(
                  (format) => DropdownMenuItem<AudioFormat>(
                    value: format,
                    child: Text(format.displayName),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              settings.transcodeDefaultFormat = value;
            },
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: DropdownButtonFormField<TranscodeQualityTier>(
            initialValue: settings.transcodeDefaultQualityTier,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.transcodeDefaultQuality,
              border: const OutlineInputBorder(),
            ),
            items: TranscodeQualityTier.values
                .map(
                  (tier) => DropdownMenuItem<TranscodeQualityTier>(
                    value: tier,
                    child: Text(_transcodeQualityLabel(context, tier)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              settings.transcodeDefaultQualityTier = value;
            },
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: Text(l10n.transcodeAutoScanOutput),
          subtitle: Text(l10n.transcodeAutoScanOutputDescription),
          value: settings.transcodeAutoScanOutputEnabled,
          onChanged: (value) {
            settings.transcodeAutoScanOutputEnabled = value;
          },
        ),
      ],
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
        SwitchListTile(
          title: Text(l10n.enableWaveformProgressBar),
          subtitle: Text(l10n.enableWaveformProgressBarDescription),
          value: settings.isWaveformProgressBarEnabled,
          onChanged: (value) {
            settings.isWaveformProgressBarEnabled = value;
          },
        ),
        SwitchListTile(
          title: Text(l10n.showDeveloperOptions),
          value: settings.showDeveloperOptions,
          onChanged: (value) {
            settings.showDeveloperOptions = value;
          },
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(l10n.resetOnboarding),
          subtitle: Text(l10n.resetOnboardingDesc),
          trailing: FilledButton.tonal(
            onPressed: () {
              settings.hasShownOnboarding = false;
              final isZh = Localizations.localeOf(context).languageCode == 'zh';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isZh
                        ? '已重置新手引导状态，下次启动时生效。'
                        : 'Onboarding has been reset. It will take effect on next startup.',
                  ),
                ),
              );
            },
            child: Text(l10n.reset),
          ),
        ),
        if (settings.showDeveloperOptions) ...[
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
          ListTile(
            title: Text(l10n.sampleStride),
            subtitle: Text(l10n.sampleStrideDescription),
            trailing: SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: settings.sampleStride > 1
                        ? () => settings.sampleStride -= 1
                        : null,
                  ),
                  Text('${settings.sampleStride}'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: settings.sampleStride < 16
                        ? () => settings.sampleStride += 1
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
        const Divider(height: 1),
        _buildSectionHeader(l10n.scanSectionTitle, l10n.scanSectionDescription),
        _buildScanSection(context, settings),
        const Divider(height: 1),
        _buildSectionHeader(
          l10n.transcodeSectionTitle,
          l10n.transcodeSectionDescription,
        ),
        _buildTranscodeSection(context, settings),
        const Divider(height: 1),
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
        _buildLyricsTranslationLanguageSection(context, settings),
        ListTile(
          isThreeLine: true,
          leading: const Icon(Icons.key),
          title: const Text('Google AI Studio API Key'),
          subtitle: Text(
            settings.geminiApiKey.trim().isEmpty
                ? l10n.googleAiStudioApiKeyMissing
                : l10n.googleAiStudioApiKeySaved,
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showGoogleAiStudioApiKeyDialog(
                context,
                ref: ref,
                initialApiKey: settings.geminiApiKey,
              );
              if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
                return;
              }
              settings.geminiApiKey = enteredApiKey;

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.apiKeySaved('Google AI Studio'))),
              );
            },
            child: Text(
              settings.geminiApiKey.trim().isEmpty ? l10n.fill : l10n.modify,
            ),
          ),
        ),
        ListTile(
          isThreeLine: true,
          leading: const Icon(Icons.vpn_key_outlined),
          title: const Text('OpenRouter API Key'),
          subtitle: Text(
            settings.openRouterApiKey.trim().isEmpty
                ? l10n.openRouterApiKeyMissing
                : l10n.openRouterApiKeySaved,
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showOpenRouterApiKeyDialog(
                context,
                ref: ref,
                initialApiKey: settings.openRouterApiKey,
              );
              if (enteredApiKey == null || enteredApiKey.trim().isEmpty) {
                return;
              }
              settings.openRouterApiKey = enteredApiKey;
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.apiKeySaved('OpenRouter'))),
              );
            },
            child: Text(
              settings.openRouterApiKey.trim().isEmpty
                  ? l10n.fill
                  : l10n.modify,
            ),
          ),
        ),
        _buildSectionHeader(
          l10n.geminiModelsSectionTitle,
          '分别设置歌词生成和歌词翻译使用的主模型、备用模型。',
        ),
        _buildLyricsModelSection(context, settings),
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
        _buildWindowsSection(context),
        const Divider(height: 40, thickness: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              Text(
                'VibeFlow ${_appVersion.isEmpty ? "" : "v$_appVersion"}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final uri = Uri.parse('https://github.com/axel10/vibe_flow');
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'https://github.com/axel10/vibe_flow',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);
    final theme = Theme.of(context);
    final isMacOS = Platform.isMacOS;
    final showCustomTitleBar =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget content = Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.settings)),
      body: _buildBody(context, settings),
    );

    if (showCustomTitleBar || isMacOS) {
      content = Material(
        color: theme.colorScheme.surface,
        child: Column(
          children: [
            if (showCustomTitleBar)
              DesktopWindowTitleBar(brightness: theme.brightness)
            else
              const DragToMoveArea(child: SizedBox(height: 32)),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }
}

class _LyricsModelPickerDialog extends ConsumerStatefulWidget {
  const _LyricsModelPickerDialog({
    required this.ref,
    required this.purpose,
    required this.initialSelection,
  });

  final WidgetRef ref;
  final LyricsAiModelPurpose purpose;
  final LyricsAiModelSelection initialSelection;

  @override
  ConsumerState<_LyricsModelPickerDialog> createState() =>
      _LyricsModelPickerDialogState();
}

class _LyricsModelPickerDialogState
    extends ConsumerState<_LyricsModelPickerDialog> {
  late LyricsAiProvider _provider;
  late LyricsAiModelSelection _selection;
  final TextEditingController _searchController = TextEditingController();
  List<LyricsModelInfo> _models = const [];
  bool _isLoading = false;
  String _statusText = '';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _provider = widget.initialSelection.provider;
    _selection = widget.initialSelection;
    _fetchModels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    final settings = ref.read(settingsServiceProvider);
    setState(() {
      _isLoading = true;
      _statusText = '';
    });
    final result = await ref
        .read(lyricsModelCatalogServiceProvider)
        .fetchModels(
          provider: _provider,
          purpose: widget.purpose,
          apiKey: settings.apiKeyForProvider(_provider),
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _statusText = result.message;
      _models = result.models;
      final hasCurrent = _models.any((item) => item.id == _selection.modelId);
      if (!hasCurrent) {
        _selection = _selection.copyWith(modelId: '');
      }
    });
  }

  List<LyricsModelInfo> get _filteredModels {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _models;
    }

    return _models
        .where((model) {
          final label = model.label.toLowerCase();
          final id = model.id.toLowerCase();
          return label.contains(query) || id.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _selection.modelId.trim().isNotEmpty ||
        _provider != _selection.provider;
    return AlertDialog(
      title: Text(
        widget.purpose == LyricsAiModelPurpose.generation
            ? '选择歌词生成模型'
            : '选择歌词翻译模型',
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<LyricsAiProvider>(
              segments: LyricsAiProvider.values
                  .map(
                    (provider) => ButtonSegment<LyricsAiProvider>(
                      value: provider,
                      label: Text(provider.displayName),
                    ),
                  )
                  .toList(growable: false),
              selected: {_provider},
              onSelectionChanged: (selection) {
                final provider = selection.first;
                setState(() {
                  _provider = provider;
                  _selection = LyricsAiModelSelection(
                    provider: provider,
                    modelId: '',
                  );
                  _searchQuery = '';
                  _searchController.clear();
                });
                _fetchModels();
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                labelText: '搜索模型',
                hintText: '输入模型名、ID 或定价信息',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_statusText.isNotEmpty) Text(_statusText),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _filteredModels.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('没有找到匹配的模型'),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          RadioListTile<String>(
                            value: '',
                            groupValue: _selection.modelId,
                            title: const Text('留空'),
                            subtitle: const Text('不设置备用模型时可选择此项。'),
                            onChanged: (value) {
                              setState(() {
                                _selection = LyricsAiModelSelection(
                                  provider: _provider,
                                  modelId: value ?? '',
                                );
                              });
                            },
                          ),
                          for (final model in _filteredModels)
                            RadioListTile<String>(
                              value: model.id,
                              groupValue: _selection.modelId,
                              title: Text(model.label),
                              subtitle: Text(
                                model.pricingLabel == null
                                    ? model.id
                                    : '${model.id}\n${model.pricingLabel}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _selection = LyricsAiModelSelection(
                                    provider: _provider,
                                    modelId: value ?? '',
                                  );
                                });
                              },
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(_selection)
              : null,
          child: Text(AppLocalizations.of(context)!.save),
        ),
      ],
    );
  }
}
