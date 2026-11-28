import 'dart:async';
import 'dart:io';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/dialogs/shortcut_settings_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/android_usb_exclusive_controller.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/metadata/loudness_backfill_service.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/pro/pro_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/settings/shortcut_bindings.dart';
import 'package:vynody/widgets/pro/pro_badge.dart';
import '../widgets/settings_dropdown_tile.dart';
import '../widgets/settings_group_card.dart';
import '../widgets/settings_section_header.dart';

class AudioSection extends ConsumerWidget {
  final SettingsService settings;

  const AudioSection({
    super.key,
    required this.settings,
  });

  Widget _buildWindowsAudioOutputCard(
    BuildContext context,
    WidgetRef ref,
  ) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final audioService = ref.read(audioServiceProvider);
    final isProUnlocked = ref.watch(isProUnlockedProvider);
    final isExclusive =
        settings.windowsAudioOutputMode == 'wasapi_exclusive' && isProUnlocked;

    return SettingsGroupCard(
      title: l10n.windowsAudioOutputTitle,
      icon: Icons.speaker_group_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            l10n.windowsAudioOutputDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SettingsDropdownTile<String>(
          title: l10n.windowsAudioOutputTitle,
          icon: Icons.audio_file_rounded,
          value: isExclusive ? 'wasapi_exclusive' : 'shared',
          options: [
            SettingsDropdownOption(
              value: 'shared',
              label: l10n.audioOutputModeShared,
            ),
            SettingsDropdownOption(
              value: 'wasapi_exclusive',
              label: l10n.audioOutputModeExclusive,
              trailing: !isProUnlocked ? const ProBadge(size: 9.5) : null,
            ),
          ],
          onChanged: (newMode) async {
            if (newMode == 'wasapi_exclusive') {
              final allowed = await checkProGate(
                context,
                ref,
                feature: ProFeature.wasapiExclusive,
              );
              if (!allowed) return;
            }
            if (newMode != null) {
              unawaited(audioService.updateWindowsAudioOutput(mode: newMode));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.keyboard_rounded),
          title: Text(l10n.wasapiExclusiveShortcutTitle),
          subtitle: Text(l10n.wasapiExclusiveShortcutDescription),
          trailing: OutlinedButton.icon(
            onPressed: () {
              showSingleShortcutEditDialog(
                context,
                action: AppShortcutAction.toggleWasapiExclusive,
              );
            },
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: Text(
              settings
                  .shortcutBinding(AppShortcutAction.toggleWasapiExclusive)
                  .displayLabel,
            ),
          ),
        ),
        if (isExclusive) ...[
          FutureBuilder<List<AudioDeviceDesc>>(
            future: audioService.getAudioOutputDevices(),
            builder: (context, snapshot) {
              final devices = snapshot.data ?? const <AudioDeviceDesc>[];
              final currentId = settings.windowsAudioDeviceId.trim();

              final options = <SettingsDropdownOption<String>>[
                SettingsDropdownOption(
                  value: '',
                  label: l10n.audioOutputDeviceDefault,
                ),
                for (final dev in devices)
                  SettingsDropdownOption(
                    value: dev.id,
                    label: dev.name + (dev.isDefault ? ' (*)' : ''),
                  ),
              ];

              return SettingsDropdownTile<String>(
                title: l10n.audioOutputDeviceTitle,
                icon: Icons.speaker_rounded,
                value: options.any((opt) => opt.value == currentId) ? currentId : '',
                options: options,
                onChanged: (newDeviceId) {
                  if (newDeviceId != null) {
                    unawaited(
                      audioService.updateWindowsAudioOutput(
                        mode: settings.windowsAudioOutputMode,
                        deviceId: newDeviceId,
                      ),
                    );
                  }
                },
              );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.auto_fix_high_rounded),
            title: Text(l10n.wasapiBitPerfectTitle),
            subtitle: Text(l10n.wasapiBitPerfectDescription),
            value: settings.wasapiBitPerfect,
            onChanged: (val) {
              unawaited(
                audioService.updateWindowsAudioOutput(
                  mode: settings.windowsAudioOutputMode,
                  bitPerfect: val,
                ),
              );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.pause_circle_outline_rounded),
            title: Text(l10n.wasapiReleaseOnPauseTitle),
            subtitle: Text(l10n.wasapiReleaseOnPauseDescription),
            value: settings.wasapiReleaseOnPause,
            onChanged: (val) {
              unawaited(
                audioService.updateWindowsAudioOutput(
                  mode: settings.windowsAudioOutputMode,
                  releaseOnPause: val,
                ),
              );
            },
          ),
          FutureBuilder<ActiveAudioHardwareFormat?>(
            future: audioService.getActiveAudioHardwareFormat(),
            builder: (context, snapshot) {
              final fmt = snapshot.data;
              if (fmt == null) return const SizedBox.shrink();

              final sampleRateFormatted =
                  '${(fmt.sampleRate / 1000).toStringAsFixed(fmt.sampleRate % 1000 == 0 ? 0 : 1)} kHz';
              final channelDesc =
                  fmt.channels == 2 ? 'Stereo (2.0)' : '${fmt.channels} Channels';
              final formatStr =
                  '$sampleRateFormatted / ${fmt.bitDepth}-bit / $channelDesc';

              return Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                l10n.activeHardwareFormatTitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              if (fmt.isBitPerfect)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    l10n.activeHardwareBitPerfectBadge,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${fmt.deviceName} • $formatStr',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildAndroidUsbAudioCard(
    BuildContext context,
    WidgetRef ref,
  ) {
    final usbState = ref.watch(androidUsbExclusiveProvider);
    if (!usbState.isSupported) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final controller = ref.read(androidUsbExclusiveProvider.notifier);
    final isProUnlocked = ref.watch(isProUnlockedProvider);
    final isExclusive = usbState.isExclusiveActive && isProUnlocked;
    final hasDevices = usbState.devices.isNotEmpty;

    final canToggle = !usbState.isBusy &&
        (isExclusive || !isProUnlocked || hasDevices);

    final status = usbState.status;
    final deviceLabel = status.deviceName.isNotEmpty
        ? status.deviceName
        : (usbState.devices
                .where((d) => d.deviceName == usbState.selectedDeviceName)
                .firstOrNull
                ?.productName ??
            'USB DAC');

    String? formatStr;
    if (status.sampleRate > 0) {
      final sr = status.sampleRate;
      final sampleRateFormatted =
          '${(sr / 1000).toStringAsFixed(sr % 1000 == 0 ? 0 : 1)} kHz';
      final channelDesc = status.channels == 2
          ? 'Stereo (2.0)'
          : (status.channels > 0 ? '${status.channels} Channels' : '');
      final parts = <String>[
        sampleRateFormatted,
        if (status.bitDepth > 0) '${status.bitDepth}-bit',
        if (channelDesc.isNotEmpty) channelDesc,
      ];
      formatStr = parts.join(' / ');
    }

    return SettingsGroupCard(
      title: l10n.androidUsbAudioTitle,
      icon: Icons.usb_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            l10n.androidUsbAudioDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SwitchListTile(
          secondary: usbState.isBusy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.graphic_eq_rounded),
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(l10n.androidUsbExclusiveModeTitle),
              if (!isProUnlocked) const ProBadge(size: 9.5),
            ],
          ),
          subtitle: Text(l10n.androidUsbExclusiveModeDescription),
          value: isExclusive,
          onChanged: canToggle
              ? (enable) async {
                  if (enable) {
                    final allowed = await checkProGate(
                      context,
                      ref,
                      feature: ProFeature.usbAudioExclusive,
                    );
                    if (!allowed) return;
                  }
                  unawaited(controller.setExclusiveMode(enable));
                }
              : null,
        ),
        if (!hasDevices)
          ListTile(
            leading: Icon(
              Icons.usb_off_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            title: Text(
              l10n.androidUsbNoDeviceDetected,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: l10n.androidUsbRefreshDevices,
              onPressed: usbState.isBusy ? null : () => controller.refresh(),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Builder(
              builder: (context) {
                String deviceDisplayName(UsbAudioDeviceInfo dev) {
                  return dev.manufacturerName.isNotEmpty &&
                          !dev.productName
                              .toLowerCase()
                              .contains(dev.manufacturerName.toLowerCase())
                      ? '${dev.manufacturerName} ${dev.productName}'
                      : dev.productName;
                }

                final selectedDev = usbState.devices
                        .where((d) => d.deviceName == usbState.selectedDeviceName)
                        .firstOrNull ??
                    usbState.devices.first;
                final isDropdownEnabled = !usbState.isBusy;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.headphones_rounded,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            l10n.androidUsbDeviceTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: l10n.androidUsbRefreshDevices,
                          onPressed:
                              usbState.isBusy ? null : () => controller.refresh(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    PopupMenuButton<String>(
                      enabled: isDropdownEnabled,
                      onSelected: isDropdownEnabled
                          ? (newDeviceName) {
                              unawaited(controller.selectDevice(newDeviceName));
                            }
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      itemBuilder: (context) => [
                        for (final dev in usbState.devices)
                          PopupMenuItem<String>(
                            value: dev.deviceName,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    deviceDisplayName(dev),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight:
                                          dev.deviceName == selectedDev.deviceName
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                      color:
                                          dev.deviceName == selectedDev.deviceName
                                              ? colorScheme.primary
                                              : null,
                                    ),
                                  ),
                                ),
                                if (dev.deviceName == selectedDev.deviceName) ...[
                                  const SizedBox(width: 12),
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: colorScheme.primary,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDropdownEnabled
                              ? colorScheme.surfaceContainerHigh
                              : colorScheme.surfaceContainerHigh
                                  .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                deviceDisplayName(selectedDev),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDropdownEnabled
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurface
                                          .withValues(alpha: 0.38),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.unfold_more_rounded,
                              size: 18,
                              color: isDropdownEnabled
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.onSurface
                                      .withValues(alpha: 0.38),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (usbState.lastError != null && usbState.lastError!.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.error.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colorScheme.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    usbState.lastError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (isExclusive)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            l10n.activeHardwareFormatTitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                          if (status.uacVersion.isNotEmpty &&
                              status.uacVersion.toLowerCase() != 'none')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status.uacVersion.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              l10n.activeHardwareBitPerfectBadge,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatStr != null
                            ? '$deviceLabel • $formatStr'
                            : deviceLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isUsbExclusive = ref.watch(
      androidUsbExclusiveProvider.select(
        (s) => s.isSupported && s.isExclusiveActive,
      ),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        SettingsSectionHeader(
          title: l10n.audioSettings,
          description: l10n.audioSettingsDescription,
        ),
        if (Platform.isWindows) _buildWindowsAudioOutputCard(context, ref),
        _buildAndroidUsbAudioCard(context, ref),
        SettingsGroupCard(
          title: l10n.equalizerBandCount,
          icon: Icons.equalizer_rounded,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.equalizerBandCountDescription,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final button = SegmentedButton<int>(
                        segments: [
                          ButtonSegment<int>(value: 5, label: Text(l10n.bandsCountOption(5))),
                          ButtonSegment<int>(value: 10, label: Text(l10n.bandsCountOption(10))),
                          ButtonSegment<int>(value: 15, label: Text(l10n.bandsCountOption(15))),
                          ButtonSegment<int>(value: 20, label: Text(l10n.bandsCountOption(20))),
                          ButtonSegment<int>(value: 31, label: Text(l10n.bandsCountOption(31))),
                        ],
                        selected: {settings.equalizerBandCount},
                        onSelectionChanged: (Set<int> selected) {
                          if (selected.isNotEmpty) {
                            settings.equalizerBandCount = selected.first;
                          }
                        },
                        showSelectedIcon: false,
                      );
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                          child: button,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsGroupCard(
          title: l10n.playbackBehaviorGroup,
          icon: Icons.graphic_eq_rounded,
          children: [
            SwitchListTile(
              key: const ValueKey<String>('settings_enable_fade_effect_switch'),
              title: Text(l10n.enableFadeEffect),
              subtitle: Text(
                isUsbExclusive
                    ? l10n.androidUsbExclusiveFadeDisabledHint
                    : l10n.enableFadeEffectDescription,
              ),
              value: settings.enableFadeEffect,
              onChanged: isUsbExclusive
                  ? null
                  : (value) {
                      settings.enableFadeEffect = value;
                    },
            ),
          ],
        ),
        _buildLoudnessNormalizationCard(context, ref),
      ],
    );
  }

  Widget _buildLoudnessNormalizationCard(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final backfillState = ref.watch(loudnessBackfillProvider);
    final backfillNotifier = ref.read(loudnessBackfillProvider.notifier);
    final audio = ref.read(audioServiceProvider);
    final enabled = settings.loudnessNormalizationEnabled;

    return SettingsGroupCard(
      title: l10n.loudnessNormalizationGroup,
      icon: Icons.volume_up_rounded,
      children: [
        SwitchListTile(
          key: const ValueKey<String>('settings_loudness_normalization_switch'),
          title: Text(l10n.loudnessNormalizationTitle),
          subtitle: Text(l10n.loudnessNormalizationDescription),
          value: enabled,
          onChanged: (value) {
            settings.loudnessNormalizationEnabled = value;
            if (value) {
              unawaited(backfillNotifier.refreshStats());
            }
          },
        ),
        if (enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.loudnessNormalizationModeLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'track',
                      label: Text(l10n.loudnessModeTrack),
                    ),
                    ButtonSegment<String>(
                      value: 'album',
                      label: Text(l10n.loudnessModeAlbum),
                    ),
                  ],
                  selected: {
                    settings.loudnessNormalizationMode == 'album'
                        ? 'album'
                        : 'track',
                  },
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      settings.loudnessNormalizationMode = selected.first;
                    }
                  },
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.loudnessTargetLufsLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: const [
                    ButtonSegment<double>(value: -18.0, label: Text('-18 LUFS')),
                    ButtonSegment<double>(value: -16.0, label: Text('-16 LUFS')),
                    ButtonSegment<double>(value: -14.0, label: Text('-14 LUFS')),
                  ],
                  selected: {
                    const [-18.0, -16.0, -14.0].contains(
                      settings.loudnessTargetLufs,
                    )
                        ? settings.loudnessTargetLufs
                        : -18.0,
                  },
                  onSelectionChanged: (selected) {
                    if (selected.isNotEmpty) {
                      settings.loudnessTargetLufs = selected.first;
                    }
                  },
                  showSelectedIcon: false,
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(l10n.loudnessClippingProtectionTitle),
            subtitle: Text(l10n.loudnessClippingProtectionDescription),
            value: settings.loudnessClippingProtection,
            onChanged: (value) {
              settings.loudnessClippingProtection = value;
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.loudnessBackfillProgress(
                    backfillState.libraryAnalyzed,
                    backfillState.libraryTotal,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: backfillState.libraryProgress),
                if (backfillState.isRunning &&
                    backfillState.currentFileName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.loudnessBackfillRunningDetail(
                      backfillState.currentFileName!,
                      backfillState.completedInRun,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (!backfillState.isRunning)
                      FilledButton.icon(
                        key: const ValueKey<String>(
                          'settings_loudness_backfill_button',
                        ),
                        onPressed: () {
                          unawaited(
                            backfillNotifier.startBackfill(
                              isPlaying: () => audio.isPlaying,
                              currentTarget: () {
                                final current = audio.currentMusic;
                                if (current == null) return null;
                                return LoudnessPriorityTarget(
                                  path: current.path,
                                  album: current.album,
                                  albumArtist: current.albumArtist,
                                  artist: current.artist,
                                );
                              },
                            ),
                          );
                        },
                        icon: const Icon(Icons.analytics_outlined),
                        label: Text(l10n.loudnessBackfillButton),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: backfillState.isStopping
                            ? null
                            : backfillNotifier.requestStop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(
                          backfillState.isStopping
                              ? l10n.loudnessBackfillStopping
                              : l10n.loudnessBackfillStopButton,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
