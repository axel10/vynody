import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/widgets/lyrics_panel.dart';

class MiniLyricsView extends ConsumerStatefulWidget {
  const MiniLyricsView({super.key});

  @override
  ConsumerState<MiniLyricsView> createState() => _MiniLyricsViewState();
}

class _MiniLyricsViewState extends ConsumerState<MiniLyricsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(audioServiceProvider).setLyricsActive(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final position = ref.watch(audioPositionProvider);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final accent =
        currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.42),
        border: Border(
          top: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            width: 1.0,
          ),
        ),
      ),
      child: LyricsPanel(
        key: ValueKey('mini-lyrics-${currentMusic?.path ?? 'no-track'}'),
        lyrics: currentMusic?.lyrics,
        position: position,
        accentColor: accent,
        textColor: Colors.black,
        secondaryTextColor: Colors.black.withValues(alpha: 0.62),
        bottomSpacerHeight: 0.0,
        bottomTabBarHeight: 0.0,
      ),
    );
  }
}
