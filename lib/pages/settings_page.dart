import 'dart:io';
import 'dart:async';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../dialogs/acoustid_api_key_dialog.dart';
import '../dialogs/ai_guide_dialog.dart';
import '../dialogs/shortcut_settings_dialog.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/ai/lyrics_model_catalog_service.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import '../transcode/transcode_models.dart';
import 'package:vynody/player/settings/windows_association_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/desktop_window_title_bar.dart';
import 'package:vynody/utils/language_code_utils.dart';
import 'package:vynody/widgets/lyrics_provider_icon.dart';

enum _SettingsSection {
  home,
  general,
  scanning,
  tags,
  transcode,
  lyrics,
  acoustid,
  shortcuts,
  windows,
  about,
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _appVersion = '';
  bool _isAssociated = false;
  _SettingsSection _currentSection = _SettingsSection.home;

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

  void _openSection(_SettingsSection section) {
    setState(() {
      _currentSection = section;
    });
  }

  void _goHome() {
    setState(() {
      _currentSection = _SettingsSection.home;
    });
  }

  String _sectionTitle(BuildContext context, _SettingsSection section) {
    final l10n = AppLocalizations.of(context)!;
    return switch (section) {
      _SettingsSection.home => l10n.settings,
      _SettingsSection.general => l10n.generalSectionTitle,
      _SettingsSection.scanning => l10n.scanSectionTitle,
      _SettingsSection.tags =>
        Localizations.localeOf(context).languageCode == 'zh' ? '标签' : 'Tags',
      _SettingsSection.transcode => l10n.transcodeSectionTitle,
      _SettingsSection.lyrics => l10n.lyricsSectionTitle,
      _SettingsSection.acoustid => l10n.acoustidSectionTitle,
      _SettingsSection.shortcuts => l10n.shortcutSettingsTitle,
      _SettingsSection.windows => l10n.windowsSettingsTitle,
      _SettingsSection.about =>
        Localizations.localeOf(context).languageCode == 'zh' ? '关于' : 'About',
    };
  }

  Widget _buildWindowsSection(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    return ListTile(
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
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.associationSuccess)),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.associationFailed(e.toString()))),
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
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.disassociationSuccess)),
                  );
                } catch (e) {
                  if (!context.mounted) return;
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
    );
  }

  Future<void> _selectLyricsModel({
    required SettingsService settings,
    required LyricsAiModelPurpose purpose,
    required LyricsAiModelSlot slot,
  }) async {
    if (!settings.hasAnyLyricsModelProvider) {
      return;
    }
    final currentSelection = _selectionFor(settings, purpose, slot);
    final selected = await showDialog<LyricsAiModelSelection>(
      context: context,
      builder: (dialogContext) {
        return _LyricsModelPickerDialog(
          ref: ref,
          purpose: purpose,
          slot: slot,
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

  Widget _buildProviderIcon(LyricsAiProvider provider) {
    return LyricsProviderIcon(provider: provider, size: 36);
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
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '重建索引'
                : 'Rebuild Index',
          ),
          subtitle: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '清空除外部来源以外的所有歌曲记录并重新扫描所有根目录。'
                : 'Clear all song records (except external sources) and rescan all root directories.',
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final isZh = Localizations.localeOf(context).languageCode == 'zh';
              final title = isZh ? '重建索引' : 'Rebuild Index';
              final content = isZh
                  ? '确认清空除外部来源以外的所有歌曲记录并重新扫描所有根目录吗？此操作需要一些时间。'
                  : 'Are you sure you want to clear all song records (except external sources) and re-scan all root directories? This process may take some time.';
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(title),
                  content: Text(content),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(l10n.cancel),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(l10n.confirm),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                final scanner = ref.read(scannerServiceProvider);
                unawaited(scanner.rebuildIndex());
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isZh ? '重建索引已启动' : 'Rebuild index started',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '重建'
                  : 'Rebuild',
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
            enabled: settings.hasAnyLyricsModelProvider,
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
            enabled: settings.hasAnyLyricsModelProvider,
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
    required bool enabled,
    required VoidCallback onPrimaryTap,
    required VoidCallback onFallbackTap,
  }) {
    final theme = Theme.of(context);
    final content = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
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
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
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
      ],
    );
  }

  Widget _buildHomeSectionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      minTileHeight: 60,
      leading: Icon(icon),
      title: Text(title, style: theme.textTheme.titleMedium),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Widget _buildHomeBody(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _buildHomeSectionTile(
          context,
          icon: Icons.tune_rounded,
          title: l10n.generalSectionTitle,
          onTap: () => _openSection(_SettingsSection.general),
        ),
        _buildHomeSectionTile(
          context,
          icon: Icons.search_rounded,
          title: l10n.scanSectionTitle,
          onTap: () => _openSection(_SettingsSection.scanning),
        ),
        _buildHomeSectionTile(
          context,
          icon: Icons.label_outline_rounded,
          title: Localizations.localeOf(context).languageCode == 'zh' ? '标签' : 'Tags',
          onTap: () => _openSection(_SettingsSection.tags),
        ),
        _buildHomeSectionTile(
          context,
          icon: Icons.swap_horiz_rounded,
          title: l10n.transcodeSectionTitle,
          onTap: () => _openSection(_SettingsSection.transcode),
        ),
        _buildHomeSectionTile(
          context,
          icon: Icons.auto_awesome_rounded,
          title: l10n.lyricsSectionTitle,
          onTap: () => _openSection(_SettingsSection.lyrics),
        ),
        _buildHomeSectionTile(
          context,
          icon: Icons.fingerprint_rounded,
          title: l10n.acoustidSectionTitle,
          onTap: () => _openSection(_SettingsSection.acoustid),
        ),
        _buildHomeSectionTile(
          context,
          icon: Icons.keyboard_rounded,
          title: l10n.shortcutSettingsTitle,
          onTap: () => _openSection(_SettingsSection.shortcuts),
        ),
        if (Platform.isWindows)
          _buildHomeSectionTile(
            context,
            icon: Icons.open_in_new_rounded,
            title: l10n.windowsSettingsTitle,
            onTap: () => _openSection(_SettingsSection.windows),
          ),
        _buildHomeSectionTile(
          context,
          icon: Icons.info_outline_rounded,
          title: Localizations.localeOf(context).languageCode == 'zh'
              ? '关于'
              : 'About',
          onTap: () => _openSection(_SettingsSection.about),
        ),
      ],
    );
  }

  Widget _buildGeneralPage(BuildContext context, SettingsService settings) {
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
          subtitle: Text(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '显示更多偏调试用途的高级项。'
                : 'Show advanced options intended for debugging.',
          ),
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
          const SizedBox(height: 8),
          _buildSectionHeader(
            Localizations.localeOf(context).languageCode == 'zh'
                ? '高级'
                : 'Advanced',
            Localizations.localeOf(context).languageCode == 'zh'
                ? '更偏调试和行为控制的选项。'
                : 'Options for debugging and behavior tuning.',
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
      ],
    );
  }

  Widget _buildScanningPage(BuildContext context, SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(l10n.scanSectionTitle, l10n.scanSectionDescription),
        _buildScanSection(context, settings),
      ],
    );
  }

  Widget _buildTagsPage(BuildContext context, SettingsService settings) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          isZh ? '标签' : 'Tags',
          isZh
              ? '关于音频文件元数据和自动补全的配置。'
              : 'Configure audio file metadata and auto-completion.',
        ),
        SwitchListTile(
          title: Text(isZh ? '自动写入源文件' : 'Auto-save to Source File'),
          subtitle: Text(
            isZh
                ? '补全或更新歌曲标签时，默认同步写入物理音频文件。'
                : 'Automatically write tags back to the physical audio file when completed.',
          ),
          value: settings.tagCompletionSaveToSourceFile,
          onChanged: (value) {
            settings.tagCompletionSaveToSourceFile = value;
          },
        ),
      ],
    );
  }

  Widget _buildTranscodePage(BuildContext context, SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          l10n.transcodeSectionTitle,
          l10n.transcodeSectionDescription,
        ),
        _buildTranscodeSection(context, settings),
      ],
    );
  }

  Widget _buildLyricsPage(BuildContext context, SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;
    final hasAnyProvider = settings.hasAnyLyricsModelProvider;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          l10n.lyricsSectionTitle,
          l10n.lyricsSectionDescription,
        ),
        _buildLyricsTranslationLanguageSection(context, settings),
        _buildSectionHeader(l10n.platformApiKeysSectionTitle),
        ListTile(
          leading: _buildProviderIcon(LyricsAiProvider.googleAiStudio),
          title: const Text('Google AI Studio API Key'),
          subtitle: Text(
            settings.geminiApiKey.trim().isEmpty
                ? l10n.apiKeyMissingStatus
                : l10n.apiKeySavedStatus,
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showGoogleAiStudioApiKeyDialog(
                context,
                ref: ref,
                initialApiKey: settings.geminiApiKey,
              );
              if (enteredApiKey == null) {
                return;
              }
              settings.geminiApiKey = enteredApiKey;

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    enteredApiKey.trim().isEmpty
                        ? '已清空 Google AI Studio API Key'
                        : l10n.apiKeySaved('Google AI Studio'),
                  ),
                ),
              );
            },
            child: Text(
              settings.geminiApiKey.trim().isEmpty ? l10n.fill : l10n.modify,
            ),
          ),
        ),
        ListTile(
          leading: _buildProviderIcon(LyricsAiProvider.openRouter),
          title: const Text('OpenRouter API Key'),
          subtitle: Text(
            settings.openRouterApiKey.trim().isEmpty
                ? l10n.apiKeyMissingStatus
                : l10n.apiKeySavedStatus,
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showOpenRouterApiKeyDialog(
                context,
                ref: ref,
                initialApiKey: settings.openRouterApiKey,
              );
              if (enteredApiKey == null) {
                return;
              }
              settings.openRouterApiKey = enteredApiKey;
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    enteredApiKey.trim().isEmpty
                        ? '已清空 OpenRouter API Key'
                        : l10n.apiKeySaved('OpenRouter'),
                  ),
                ),
              );
            },
            child: Text(
              settings.openRouterApiKey.trim().isEmpty
                  ? l10n.fill
                  : l10n.modify,
            ),
          ),
        ),
        ListTile(
          leading: _buildProviderIcon(LyricsAiProvider.doubao),
          title: const Text('豆包 API Key'),
          subtitle: Text(
            settings.doubaoApiKey.trim().isEmpty
                ? l10n.apiKeyMissingStatus
                : l10n.apiKeySavedStatus,
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showDoubaoApiKeyDialog(
                context,
                ref: ref,
                initialApiKey: settings.doubaoApiKey,
              );
              if (enteredApiKey == null) {
                return;
              }
              settings.doubaoApiKey = enteredApiKey;
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    enteredApiKey.trim().isEmpty
                        ? '已清空豆包 API Key'
                        : '已保存豆包 API Key',
                  ),
                ),
              );
            },
            child: Text(
              settings.doubaoApiKey.trim().isEmpty ? l10n.fill : l10n.modify,
            ),
          ),
        ),
        ListTile(
          leading: _buildProviderIcon(LyricsAiProvider.deepseek),
          title: const Text('DeepSeek API Key'),
          subtitle: Text(
            settings.deepseekApiKey.trim().isEmpty
                ? l10n.apiKeyMissingStatus
                : l10n.apiKeySavedStatus,
          ),
          trailing: FilledButton.tonal(
            onPressed: () async {
              final enteredApiKey = await showDeepSeekApiKeyDialog(
                context,
                ref: ref,
                initialApiKey: settings.deepseekApiKey,
              );
              if (enteredApiKey == null) {
                return;
              }
              settings.deepseekApiKey = enteredApiKey;
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    enteredApiKey.trim().isEmpty
                        ? '已清空 DeepSeek API Key'
                        : '已保存 DeepSeek API Key',
                  ),
                ),
              );
            },
            child: Text(
              settings.deepseekApiKey.trim().isEmpty ? l10n.fill : l10n.modify,
            ),
          ),
        ),
        _buildSectionHeader(
          l10n.geminiModelsSectionTitle,
        ),
        if (!hasAnyProvider)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '请先填写至少一个 API Key，模型选择才会启用。',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
        _buildLyricsModelSection(context, settings),
      ],
    );
  }

  Widget _buildAcoustidPage(BuildContext context, SettingsService settings) {
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
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

  Widget _buildShortcutsPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          l10n.shortcutSettingsTitle,
          l10n.shortcutSettingsDescription,
        ),
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
      ],
    );
  }

  Widget _buildWindowsPage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          l10n.windowsSettingsTitle,
          l10n.fileAssociationDescription,
        ),
        _buildWindowsSection(context),
      ],
    );
  }

  Widget _buildAboutPage(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildSectionHeader(
          isZh ? '关于' : 'About',
          isZh
              ? '版本信息、项目链接和相关资料。'
              : 'Version info, project links, and related info.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vynody ${_appVersion.isEmpty ? "" : "v$_appVersion"}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final uri = Uri.parse(
                      'https://github.com/axel10/vynody',
                    );
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      'https://github.com/axel10/vynody',
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
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, SettingsService settings) {
    final currentBody = switch (_currentSection) {
      _SettingsSection.home => _buildHomeBody(context),
      _SettingsSection.general => _buildGeneralPage(context, settings),
      _SettingsSection.scanning => _buildScanningPage(context, settings),
      _SettingsSection.tags => _buildTagsPage(context, settings),
      _SettingsSection.transcode => _buildTranscodePage(context, settings),
      _SettingsSection.lyrics => _buildLyricsPage(context, settings),
      _SettingsSection.acoustid => _buildAcoustidPage(context, settings),
      _SettingsSection.shortcuts => _buildShortcutsPage(context),
      _SettingsSection.windows => _buildWindowsPage(context),
      _SettingsSection.about => _buildAboutPage(context),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: KeyedSubtree(key: ValueKey(_currentSection), child: currentBody),
    );
  }

  Widget _buildRootScaffold(BuildContext context, SettingsService settings) {
    final title = _sectionTitle(context, _currentSection);

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        notificationPredicate: (_) => false,
        title: Text(title),
        leading: _currentSection == _SettingsSection.home
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _goHome,
              ),
      ),
      body: _buildBody(context, settings),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsServiceProvider);
    final theme = Theme.of(context);
    final isMacOS = Platform.isMacOS;
    final showCustomTitleBar =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    Widget content = _buildRootScaffold(context, settings);

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
    required this.slot,
    required this.initialSelection,
  });

  final WidgetRef ref;
  final LyricsAiModelPurpose purpose;
  final LyricsAiModelSlot slot;
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
  final Map<LyricsAiProvider, List<LyricsModelInfo>> _modelsByProvider = {};
  final Map<LyricsAiProvider, String> _statusTextByProvider = {};
  final Set<LyricsAiProvider> _loadedProviders = {};
  final Set<LyricsAiProvider> _loadingProviders = {};
  String _statusText = '';
  String _searchQuery = '';
  bool _showRecommendedOnly = true;

  bool get _isLoading => _loadingProviders.contains(_provider);

  Widget _buildProviderIcon(LyricsAiProvider provider) {
    return LyricsProviderIcon(provider: provider, size: 24);
  }

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
    final targetProvider = _provider;
    if (_loadedProviders.contains(targetProvider)) {
      setState(() {
        _statusText = _statusTextByProvider[targetProvider] ?? '';
      });
      return;
    }
    if (_loadingProviders.contains(targetProvider)) {
      return;
    }

    final settings = ref.read(settingsServiceProvider);
    setState(() {
      _loadingProviders.add(targetProvider);
      if (_provider == targetProvider) {
        _statusText = '';
      }
    });

    try {
      final result = await ref
          .read(lyricsModelCatalogServiceProvider)
          .fetchModels(
            provider: targetProvider,
            purpose: widget.purpose,
            apiKey: settings.apiKeyForProvider(targetProvider),
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProviders.remove(targetProvider);
        _modelsByProvider[targetProvider] = result.models;
        _statusTextByProvider[targetProvider] = result.message;
        _loadedProviders.add(targetProvider);

        if (_provider == targetProvider) {
          _statusText = result.message;
          final hasCurrent = result.models.any(
            (item) => item.id == _selection.modelId,
          );
          if (!hasCurrent) {
            _selection = _selection.copyWith(modelId: '');
          }
        }
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingProviders.remove(targetProvider);
        _statusTextByProvider[targetProvider] = e.toString();
        if (_provider == targetProvider) {
          _statusText = e.toString();
        }
      });
    }
  }

  bool _isModelRecommended(LyricsModelInfo model) {
    if (model.id == _selection.modelId) {
      return true;
    }
    return LyricsModelRecommendation.isRecommended(model.id, model.provider);
  }

  List<LyricsModelInfo> get _filteredModels {
    final models = _modelsByProvider[_provider] ?? const [];
    final baseModels = _showRecommendedOnly
        ? models.where(_isModelRecommended).toList()
        : models;
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return baseModels;
    }

    return baseModels
        .where((model) {
          final label = model.label.toLowerCase();
          final id = model.id.toLowerCase();
          return label.contains(query) || id.contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final settings = ref.watch(settingsServiceProvider);
    final availableProviders = settings.availableLyricsModelProviders;
    final availableTabs = [
      LyricsAiProvider.googleAiStudio,
      LyricsAiProvider.openRouter,
      LyricsAiProvider.doubao,
      if (widget.purpose == LyricsAiModelPurpose.translation)
        LyricsAiProvider.deepseek,
    ].where(availableProviders.contains).toList(growable: false);
    final canSave = widget.slot == LyricsAiModelSlot.fallback ||
        _selection.modelId.trim().isNotEmpty;
    final effectiveProvider = availableTabs.contains(_provider)
        ? _provider
        : (availableTabs.isNotEmpty
            ? availableTabs.first
            : _provider);
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
            if (availableTabs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('请先填写 API Key，才能查看可用模型。'),
              )
            else
              DropdownButtonFormField<LyricsAiProvider>(
                value: effectiveProvider,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: isZh ? '平台' : 'Platform',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: availableTabs
                    .map(
                      (provider) => DropdownMenuItem<LyricsAiProvider>(
                        value: provider,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _buildProviderIcon(provider),
                            const SizedBox(width: 12),
                            Text(
                              provider.displayName,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (provider) {
                  if (provider == null) return;
                  setState(() {
                    _provider = provider;
                    _selection = LyricsAiModelSelection(
                      provider: provider,
                      modelId: '',
                    );
                    _searchQuery = '';
                    _searchController.clear();
                    _statusText = _statusTextByProvider[provider] ?? '';
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
                hintText: '输入模型名、ID',
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
            if (_statusText.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _statusText,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  if (_provider != LyricsAiProvider.deepseek)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _showRecommendedOnly,
                            onChanged: (value) {
                              setState(() {
                                _showRecommendedOnly = value ?? true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _showRecommendedOnly = !_showRecommendedOnly;
                            });
                          },
                          child: const Text('仅显示推荐模型'),
                        ),
                      ],
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: availableTabs.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('暂无可用渠道'),
                        ),
                      )
                    : _isLoading
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
                          if (widget.slot == LyricsAiModelSlot.fallback)
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
