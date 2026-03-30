import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:audio_core/audio_core.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';

class VisualizerOptionsDialog extends StatelessWidget {
  const VisualizerOptionsDialog({
    super.key,
    required this.audio,
    required this.settings,
  });

  final AudioService audio;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          final l10n = AppLocalizations.of(context)!;
          final isAuto = settings.isAutoMode;

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.visualizerSettings,
                      style: const TextStyle(color: Colors.white),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.autoMode,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        Switch(
                          value: isAuto,
                          activeColor: Colors.blueAccent,
                          onChanged: (val) {
                            settings.isAutoMode = val;
                            if (val) {
                              // Re-apply auto settings immediately
                              final Orientation orientation = MediaQuery.of(
                                context,
                              ).orientation;
                              audio.applyVisualizerSettings(
                                orientation: orientation,
                              );
                            }
                            setDialogState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                if (!isAuto)
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
              width: 600,
              height: 450,
              child: isAuto
                  ? _buildAutoModeControls(context, setDialogState)
                  : TabBarView(
                      children: [
                        _buildAlgorithmTab(context, setDialogState),
                        _buildAppearanceTab(context, settings, setDialogState),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  audio.resetVisualizerOptions();
                  setDialogState(() {});
                },
                child: Text(
                  l10n.resetAlgorithm,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: () {
                  settings.resetVisualizerAppearance();
                  setDialogState(() {});
                },
                child: Text(
                  l10n.resetAppearance,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
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

  Widget _buildAlgorithmTab(BuildContext context, StateSetter setDialogState) {
    final options = audio.player.visualizer.options;

    return SingleChildScrollView(
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

  Widget _buildAutoModeControls(
    BuildContext context,
    StateSetter setDialogState,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
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
          const SizedBox(height: 32),
          // In Auto Mode, Appearance settings are also accessible via an expansion or similar?
          // The user said "current visualizer options as advanced options, hidden when auto mode is on".
          // So I will hide EVERYTHING except these two in Auto Mode.
          Center(
            child: Text(
              l10n.appearance,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ),
          const Divider(color: Colors.white12),
          _buildAppearanceTab(context, settings, setDialogState),
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
                child: Text(mode.name.toUpperCase()),
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
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBackgroundTypeDropdown(context, settings, setDialogState),
          const SizedBox(height: 16),
          _buildOptionSlider(
            context,
            label: AppLocalizations.of(context)!.opacity,
            value: settings.visualizerOpacity,
            min: 0.0,
            max: 1.0,
            onChanged: (val) {
              settings.visualizerOpacity = val;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(
              AppLocalizations.of(context)!.enableGradient,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
            value: settings.isVisualizerGradientEnabled,
            activeThumbColor: Colors.blueAccent,
            onChanged: (val) {
              settings.isVisualizerGradientEnabled = val;
              setDialogState(() {});
            },
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          if (settings.isVisualizerGradientEnabled) ...[
            _buildColorPickerRow(
              context,
              label: AppLocalizations.of(context)!.startColor,
              color: settings.visualizerStartColor,
              isDynamic: settings.isVisualizerDynamicStartColor,
              onDynamicChanged: (val) {
                settings.isVisualizerDynamicStartColor = val;
                if (val) {
                  context.read<AudioService>().updateDynamicColors();
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
              label: AppLocalizations.of(context)!.endColor,
              color: settings.visualizerEndColor,
              isDynamic: settings.isVisualizerDynamicEndColor,
              onDynamicChanged: (val) {
                settings.isVisualizerDynamicEndColor = val;
                if (val) {
                  context.read<AudioService>().updateDynamicColors();
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
              label: AppLocalizations.of(context)!.gradientRangeStop1,
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
              label: AppLocalizations.of(context)!.gradientRangeStop2,
              value: settings.visualizerGradientStop2,
              min: 0.0,
              max: 1.0,
              onChanged: (val) {
                settings.visualizerGradientStop2 = val;
                setDialogState(() {});
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.gradientRepeatMode,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: settings.visualizerGradientTileMode,
                  dropdownColor: Colors.grey[800],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      settings.visualizerGradientTileMode = newValue;
                      setDialogState(() {});
                    }
                  },
                  items: TileMode.values.map<DropdownMenuItem<int>>((mode) {
                    return DropdownMenuItem<int>(
                      value: mode.index,
                      child: Text(mode.name),
                    );
                  }).toList(),
                ),
              ],
            ),
          ] else ...[
            _buildColorPickerRow(
              context,
              label: AppLocalizations.of(context)!.color,
              color: settings.visualizerColor,
              isDynamic: settings.isVisualizerDynamicColor,
              onDynamicChanged: (val) {
                settings.isVisualizerDynamicColor = val;
                if (val) {
                  context.read<AudioService>().updateDynamicColors();
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
