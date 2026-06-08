import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/lyrics/lyrics_riverpod.dart';
import 'package:vibe_flow/widgets/lyrics_panel.dart';

class MiniLyricsView extends ConsumerStatefulWidget {
  const MiniLyricsView({super.key});

  @override
  ConsumerState<MiniLyricsView> createState() => _MiniLyricsViewState();
}

class _MiniLyricsViewState extends ConsumerState<MiniLyricsView> {
  static const Color _panelBackgroundColor = Color(0xCC000000);
  static const Color _panelBorderColor = Color(0x14FFFFFF);
  static const Color _lyricsTextColor = Colors.white;
  static const Color _lyricsSecondaryTextColor = Color(0x9EFFFFFF);
  String? _lastRequestedLyricsPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestLyricsForCurrentSong();
    });
  }

  void _requestLyricsForCurrentSong() {
    final currentMusic = ref.read(audioCurrentMusicProvider);
    if (currentMusic == null || currentMusic.lyrics != null) {
      return;
    }

    final duration = ref.read(audioDurationProvider);
    if (duration.inMilliseconds <= 0) {
      return;
    }

    if (_lastRequestedLyricsPath == currentMusic.path) {
      return;
    }

    _lastRequestedLyricsPath = currentMusic.path;
    ref.read(lyricsControllerProvider.notifier).scheduleFetch(currentMusic);
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    ref.listen<MusicFile?>(
      audioCurrentMusicProvider,
      (_, _) => _requestLyricsForCurrentSong(),
    );
    ref.listen<Duration>(
      audioDurationProvider,
      (_, _) => _requestLyricsForCurrentSong(),
    );
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final position = ref.watch(audioPositionProvider);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final accent =
        currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: _panelBackgroundColor,
        border: Border(top: BorderSide(color: _panelBorderColor, width: 1.0)),
      ),
      child: LyricsPanel(
        key: ValueKey('mini-lyrics-${currentMusic?.path ?? 'no-track'}'),
        lyrics: currentMusic?.lyrics,
        position: position,
        accentColor: accent,
        textColor: _lyricsTextColor,
        secondaryTextColor: _lyricsSecondaryTextColor,
        bottomSpacerHeight: 0.0,
        bottomTabBarHeight: 0.0,
      ),
    );
  }
}
