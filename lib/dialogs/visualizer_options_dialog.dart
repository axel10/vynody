import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:audio_core/audio_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/audio/audio_service.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';

class VisualizerOptionsDialog extends ConsumerWidget {
  const VisualizerOptionsDialog({
    super.key,
    required this.audio,
    required this.settings,
  });

  final AudioService audio;
  final SettingsService settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = AppLocalizations.of(context)!;

          return AlertDialog(
            backgroundColor: const Color(0xFF101114),
            surfaceTintColor: Colors.transparent,
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.visualizerSettings,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                TabBar(
                  tabs: [
                    Tab(text: l10n.algorithm),
                    Tab(text: l10n.appearance),
                  ],
                  labelColor: Colors.blueAccent,
                  unselectedLabelColor: Colors.white70,
                  indicatorColor: Colors.blueAccent,
                  dividerColor: Colors.transparent,
                ),
              ],
            ),
            content: SizedBox(
              width: 660,
              height: 520,
              child: TabBarView(
                children: [
                  _buildAlgorithmTab(context, ref, setDialogState),
                  _buildAppearanceTab(context, settings, setDialogState),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  AppLocalizations.of(context)!.confirm,
                  style: TextStyle(color: Colors.blueAccent),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAlgorithmTab(
    BuildContext context,
    WidgetRef ref,
    StateSetter setDialogState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isAuto = settings.isAutoMode;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.autoMode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              value: isAuto,
              activeThumbColor: Colors.blueAccent,
              onChanged: (val) {
                settings.isAutoMode = val;
                if (val) {
                  final Orientation orientation = MediaQuery.of(
                    context,
                  ).orientation;
                  audio.applyVisualizerSettings(orientation: orientation);
                } else {
                  audio.visualizerOptions.loadOptions();
                }
                setDialogState(() {});
              },
            ),
          ),
          const SizedBox(height: 16),
          if (isAuto) ...[
            _buildAutoModeControls(context, setDialogState),
          ] else ...[
            _buildSectionHeader(
              context,
              l10n.spectrumAdvancedOptions,
              resetLabel: l10n.resetAlgorithm,
              onReset: () {
                audio.resetVisualizerOptions();
                setDialogState(() {});
              },
            ),
            const SizedBox(height: 12),
            _buildSpectrumAdvancedControls(context, ref, setDialogState),
          ],
        ],
      ),
    );
  }

  Widget _buildAutoModeControls(
    BuildContext context,
    StateSetter setDialogState,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return _buildSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.spectrumQuantity,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildSegmentedControl<String>(
            value: settings.autoSpectrumQuantity,
            items: {
              'low': l10n.quantityLow,
              'medium': l10n.quantityMedium,
              'high': l10n.quantityHigh,
            },
            onChanged: (val) {
              settings.autoSpectrumQuantity = val;
              audio.applyVisualizerSettings(
                orientation: MediaQuery.of(context).orientation,
              );
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 24),
          Text(
            l10n.speed,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildSegmentedControl<String>(
            value: settings.autoSpeed,
            items: {
              'slow': l10n.speedSlow,
              'medium': l10n.speedMedium,
              'fast': l10n.speedFast,
            },
            onChanged: (val) {
              settings.autoSpeed = val;
              audio.applyVisualizerSettings(
                orientation: MediaQuery.of(context).orientation,
              );
              setDialogState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpectrumAdvancedControls(
    BuildContext context,
    WidgetRef ref,
    StateSetter setDialogState,
  ) {
    final options = ref.watch(audioCurrentVisualizerOptionsProvider);

    return _buildSectionCard(
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.smoothing,
            value: options.smoothingCoefficient,
            min: 0.0,
            max: 1.0,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(smoothingCoefficient: val),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.gravity,
            value: options.gravityCoefficient,
            min: 0.1,
            max: 5.0,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(gravityCoefficient: val),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.logScale,
            value: options.logarithmicScale,
            min: 1.0,
            max: 5.0,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(logarithmicScale: val),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.contrast,
            value: options.groupContrastExponent,
            min: 0.1,
            max: 3.0,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(groupContrastExponent: val),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.normalization,
            value: options.normalizationFloorDb,
            min: -100.0,
            max: 0.0,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(normalizationFloorDb: val),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.multiplier,
            value: options.overallMultiplier,
            min: 0.5,
            max: 5.0,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(overallMultiplier: val),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.skipHighFrequency,
            value: options.skipHighFrequencyGroups.toDouble(),
            min: 0,
            max: 50,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(skipHighFrequencyGroups: val.toInt()),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.landscapeFrequencyGroups,
            value: settings.landscapeFrequencyGroups.toDouble(),
            min: 8,
            max: 512,
            onChanged: (val) {
              settings.landscapeFrequencyGroups = val.toInt();
              if (MediaQuery.of(context).orientation == Orientation.landscape) {
                audio.updateVisualOptions(
                  options.copyWith(frequencyGroups: val.toInt()),
                );
              }
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.portraitFrequencyGroups,
            value: settings.portraitFrequencyGroups.toDouble(),
            min: 8,
            max: 512,
            onChanged: (val) {
              settings.portraitFrequencyGroups = val.toInt();
              if (MediaQuery.of(context).orientation == Orientation.portrait) {
                audio.updateVisualOptions(
                  options.copyWith(frequencyGroups: val.toInt()),
                );
              }
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.landscapeGap,
            value: settings.landscapeGap,
            min: 0.0,
            max: 10.0,
            onChanged: (val) {
              settings.landscapeGap = val;
              setDialogState(() {});
            },
          ),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.portraitGap,
            value: settings.portraitGap,
            min: 0.0,
            max: 10.0,
            onChanged: (val) {
              settings.portraitGap = val;
              setDialogState(() {});
            },
          ),
          _buildAggregationModeDropdown(context, options, setDialogState),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return SegmentedButton<T>(
      segments: items.entries.map((e) {
        return ButtonSegment<T>(
          value: e.key,
          label: Text(e.value, style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
      selected: {value},
      onSelectionChanged: (Set<T> selection) {
        onChanged(selection.first);
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.grey[850],
        selectedBackgroundColor: Colors.blueAccent,
        selectedForegroundColor: Colors.white,
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white12),
      ),
    );
  }

  Widget _buildAggregationModeDropdown(
    BuildContext context,
    VisualizerOptimizationOptions options,
    StateSetter setDialogState,
  ) {
    return SizedBox(
      width: 270,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              AppLocalizations.of(context)!.aggregationMode,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          DropdownButtonFormField<FftAggregationMode>(
            initialValue: options.aggregationMode,
            dropdownColor: Colors.grey[900],
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white12),
              ),
            ),
            style: const TextStyle(color: Colors.white),
            items: FftAggregationMode.values.map((mode) {
              return DropdownMenuItem(
                value: mode,
                child: Text(_aggregationModeLabel(context, mode)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                audio.updateVisualOptions(
                  options.copyWith(aggregationMode: val),
                );
                setDialogState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceTab(
    BuildContext context,
    SettingsService settings,
    StateSetter setDialogState,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isDynamicMeshBackground = settings.playbackBackgroundType == 1;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBackgroundTypeDropdown(context, settings, setDialogState),
                if (isDynamicMeshBackground) ...[
                  const SizedBox(height: 20),
                  _buildOptionSlider(
                    context,
                    label: l10n.speed,
                    value: settings.playbackMeshBackgroundSpeed,
                    min: 0.02,
                    max: 2.0,
                    onChanged: (val) {
                      settings.playbackMeshBackgroundSpeed = val;
                      setDialogState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildSectionHeader(
            context,
            l10n.spectrumAppearanceGroup,
            resetLabel: l10n.resetAppearance,
            onReset: () {
              settings.resetVisualizerAppearance();
              final Orientation orientation = MediaQuery.of(
                context,
              ).orientation;
              audio.applyVisualizerSettings(orientation: orientation);
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 12),
          _buildSectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOptionSlider(
                  context,
                  label: l10n.opacity,
                  value: settings.visualizerOpacity,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (val) {
                    settings.visualizerOpacity = val;
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: Text(
                    l10n.enableGradient,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  value: settings.isVisualizerGradientEnabled,
                  activeThumbColor: Colors.blueAccent,
                  onChanged: (val) {
                    settings.isVisualizerGradientEnabled = val;
                    setDialogState(() {});
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 4),
                if (settings.isVisualizerGradientEnabled) ...[
                  _buildColorPickerRow(
                    context,
                    label: l10n.startColor,
                    color: settings.visualizerStartColor,
                    isDynamic: settings.isVisualizerDynamicStartColor,
                    onDynamicChanged: (val) {
                      settings.isVisualizerDynamicStartColor = val;
                      if (val) {
                        audio.updateDynamicColors();
                      }
                      setDialogState(() {});
                    },
                    onColorChanged: (c) {
                      settings.visualizerStartColor = c;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildColorPickerRow(
                    context,
                    label: l10n.endColor,
                    color: settings.visualizerEndColor,
                    isDynamic: settings.isVisualizerDynamicEndColor,
                    onDynamicChanged: (val) {
                      settings.isVisualizerDynamicEndColor = val;
                      if (val) {
                        audio.updateDynamicColors();
                      }
                      setDialogState(() {});
                    },
                    onColorChanged: (c) {
                      settings.visualizerEndColor = c;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildOptionSlider(
                    context,
                    label: l10n.gradientRangeStop1,
                    value: settings.visualizerGradientStop1,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      settings.visualizerGradientStop1 = val;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildOptionSlider(
                    context,
                    label: l10n.gradientRangeStop2,
                    value: settings.visualizerGradientStop2,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      settings.visualizerGradientStop2 = val;
                      setDialogState(() {});
                    },
                  ),
                ] else ...[
                  _buildColorPickerRow(
                    context,
                    label: l10n.color,
                    color: settings.visualizerColor,
                    isDynamic: settings.isVisualizerDynamicColor,
                    onDynamicChanged: (val) {
                      settings.isVisualizerDynamicColor = val;
                      if (val) {
                        audio.updateDynamicColors();
                      }
                      setDialogState(() {});
                    },
                    onColorChanged: (c) {
                      settings.visualizerColor = c;
                      setDialogState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionSlider(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    VoidCallback? onChangeEnd,
  }) {
    return SizedBox(
      width: 270,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Text(
              '$label: ${value.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          SliderTheme(
            data: const SliderThemeData(
              activeTrackColor: Colors.blueAccent,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.blueAccent,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: (val) => onChangeEnd?.call(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPickerRow(
    BuildContext context, {
    required String label,
    required Color color,
    required ValueChanged<Color> onColorChanged,
    bool isDynamic = false,
    ValueChanged<bool>? onDynamicChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(width: 16),
            if (!isDynamic)
              InkWell(
                onTap: () => _pickColor(context, color, onColorChanged),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: Colors.white70, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
        if (onDynamicChanged != null)
          Row(
            children: [
              Text(
                AppLocalizations.of(context)!.followCoverColor,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Switch(
                value: isDynamic,
                activeTrackColor: Colors.blueAccent,
                onChanged: onDynamicChanged,
              ),
            ],
          ),
      ],
    );
  }

  void _pickColor(
    BuildContext context,
    Color initialColor,
    ValueChanged<Color> onColorChanged,
  ) {
    Color selectedColor = initialColor;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            AppLocalizations.of(context)!.selectColor,
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: initialColor,
              onColorChanged: (c) => selectedColor = c,
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsv,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                AppLocalizations.of(context)!.cancel,
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () {
                onColorChanged(selectedColor);
                Navigator.pop(context);
              },
              child: Text(
                AppLocalizations.of(context)!.confirm,
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBackgroundTypeDropdown(
    BuildContext context,
    SettingsService settings,
    StateSetter setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Text(
            AppLocalizations.of(context)!.playbackBackground,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        DropdownButtonFormField<int>(
          initialValue: settings.playbackBackgroundType,
          dropdownColor: Colors.grey[900],
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white12),
            ),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: [
            DropdownMenuItem(
              value: 0,
              child: Text(AppLocalizations.of(context)!.blurredArtwork),
            ),
            DropdownMenuItem(
              value: 1,
              child: Text(AppLocalizations.of(context)!.dynamicMesh),
            ),
          ],
          onChanged: (val) {
            if (val != null) {
              settings.playbackBackgroundType = val;
              setDialogState(() {});
            }
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    String? resetLabel,
    VoidCallback? onReset,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (onReset != null)
          TextButton.icon(
            onPressed: onReset,
            style: TextButton.styleFrom(
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(resetLabel ?? AppLocalizations.of(context)!.reset),
          ),
      ],
    );
  }

  String _aggregationModeLabel(BuildContext context, FftAggregationMode mode) {
    final isZh = AppLocalizations.of(context)!.localeName.startsWith('zh');
    return switch (mode) {
      FftAggregationMode.peak => isZh ? '峰值' : 'Peak',
      FftAggregationMode.mean => isZh ? '平均值' : 'Mean',
      FftAggregationMode.rms => isZh ? '均方根' : 'RMS',
    };
  }

  Widget _buildSectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

void showVisualizerOptionsDialog(
  BuildContext context,
  AudioService audio,
  SettingsService settings,
) {
  showDialog(
    context: context,
    builder: (context) =>
        VisualizerOptionsDialog(audio: audio, settings: settings),
  );
}
