import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
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

          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppLocalizations.of(context)!.visualizerSettings, style: TextStyle(color: Colors.white)),
                SizedBox(height: 10),
                TabBar(
                  tabs: [
                    Tab(text: AppLocalizations.of(context)!.algorithm),
                    Tab(text: AppLocalizations.of(context)!.appearance),
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
              height: 400,
              child: TabBarView(
                children: [
                  _buildAlgorithmTab(context, setDialogState),
                  _buildAppearanceTab(context, settings, setDialogState),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  audio.updateVisualOptions(
                    const VisualizerOptimizationOptions(),
                  );
                  setDialogState(() {});
                },
                child: Text(
                  AppLocalizations.of(context)!.resetAlgorithm,
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: () {
                  context.read<SettingsService>().resetVisualizerAppearance();
                  setDialogState(() {});
                },
                child: Text(
                  AppLocalizations.of(context)!.resetAppearance,
                  style: TextStyle(color: Colors.redAccent),
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
    final options = audio.player.visualOptions;

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
            max: 0.99,
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
            min: 0.5,
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
            label: AppLocalizations.of(context)!.frequencyGroups,
            value: options.frequencyGroups.toDouble(),
            min: 8,
            max: 512,
            divisions: 15,
            onChanged: (val) {
              audio.updateVisualOptions(
                options.copyWith(frequencyGroups: val.toInt()),
              );
              setDialogState(() {});
            },
            onChangeEnd: () => audio.saveVisualizerOptions(),
          ),
          _buildAggregationModeDropdown(context, options, setDialogState),
        ],
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
            padding: EdgeInsets.only(
              top: 16,
              bottom: 8,
            ),
            child: Text(
              AppLocalizations.of(context)!.aggregationMode,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
          DropdownButtonFormField<FftAggregationMode>(
            value: options.aggregationMode,
            dropdownColor: Colors.grey[900],
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Colors.white12,
                ),
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
            activeColor: Colors.blueAccent,
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
          title: Text(AppLocalizations.of(context)!.selectColor, style: TextStyle(color: Colors.white)),
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
              child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(color: Colors.white70)),
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
          value: settings.playbackBackgroundType,
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
    builder: (context) => VisualizerOptionsDialog(
      audio: audio,
      settings: settings,
    ),
  );
}