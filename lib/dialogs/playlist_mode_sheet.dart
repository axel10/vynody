import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/utils/playback_utils.dart';
import '../widgets/app_bottom_sheet.dart';

class PlaylistModeSheet extends ConsumerWidget {
  const PlaylistModeSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(audioPlaybackModeProvider);
    final audio = ref.read(audioServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AppBottomSheet(
      maxWidth: 540,
      landscapeMaxWidth: 680,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              l10n.playbackMode,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
              const SizedBox(height: 12),
              // Playlist modes list
              ...AppPlaybackMode.values.map((mode) {
                final isSelected = currentMode == mode;
                final icon = getPlaylistModeIcon(mode);
                final name = getPlaylistModeName(mode, l10n);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.3)
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        audio.setPlaybackMode(mode);
                        Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : (isDark ? Colors.white70 : Colors.black87),
                              size: 24,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                name,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? theme.colorScheme.primary
                                      : (isDark ? Colors.white : Colors.black87),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: theme.colorScheme.primary,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
    );
  }
}
