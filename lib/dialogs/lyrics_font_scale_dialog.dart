import 'package:flutter/material.dart';
import '../widgets/app_tooltip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/settings/settings_service.dart';

/// Shows a floating capsule slider (similar to the volume slider) at the bottom
/// of the screen to adjust the lyrics font scale in real-time.
/// The dialog's background barrier is transparent, allowing the user to see
/// the text size change dynamically underneath.
Future<void> showLyricsFontScaleDialog(
  BuildContext context,
  WidgetRef ref, {
  required LyricsStyle lyricsStyle,
}) async {
  final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    builder: (dialogContext) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: isLandscape ? 100 : 160),
          child: Container(
            width: 320,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Consumer(
                  builder: (context, ref, child) {
                    final settings = ref.watch(settingsServiceProvider);
                    final currentScale = lyricsStyle == LyricsStyle.apple
                        ? settings.lyricsFontScaleApple
                        : settings.lyricsFontScaleTraditional;
                    final l10n = AppLocalizations.of(context)!;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AppTooltip(
                          message: l10n.restoreDefaultSize,
                          child: IconButton(
                            icon: const Icon(Icons.format_size_rounded, color: Colors.white, size: 20),
                            onPressed: () {
                              if (lyricsStyle == LyricsStyle.apple) {
                                ref.read(settingsServiceProvider).resetLyricsFontScaleApple();
                              } else {
                                ref.read(settingsServiceProvider).resetLyricsFontScaleTraditional();
                              }
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white.withValues(alpha: 0.2),
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            ),
                            child: Slider(
                              value: currentScale,
                              min: SettingsService.minLyricsFontScale,
                              max: SettingsService.maxLyricsFontScale,
                              divisions: ((SettingsService.maxLyricsFontScale - SettingsService.minLyricsFontScale) / SettingsService.lyricsFontScaleStep).round(),
                              onChanged: (value) {
                                // Round to one decimal place to avoid floating point precision issues
                                final rounded = (value * 10).round() / 10.0;
                                if (lyricsStyle == LyricsStyle.apple) {
                                  ref.read(settingsServiceProvider).lyricsFontScaleApple = rounded;
                                } else {
                                  ref.read(settingsServiceProvider).lyricsFontScaleTraditional = rounded;
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${(currentScale * 100).round()}%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
