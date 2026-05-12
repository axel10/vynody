import 'dart:typed_data';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';
import '../player/settings_service.dart';
import '../player/playlist_service.dart';
import '../models/music_file.dart';
import '../utils/playback_utils.dart';
import '../utils/song_context_menu_utils.dart';
import 'cover_carousel.dart';
import 'lyrics_panel.dart';
import 'waveform_progress_bar.dart';

// Shared components for Playback UI to avoid duplication between Portrait and Landscape views

class PlaybackAlbumArt extends ConsumerWidget {
  final bool isNext;
  final double displaySize;
  final VoidCallback? onCoverTap;
  final ValueChanged<Uint8List?>? onCarouselAnimationComplete;

  const PlaybackAlbumArt({
    super.key,
    required this.isNext,
    required this.displaySize,
    this.onCoverTap,
    this.onCarouselAnimationComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);

    if (playlist.isEmpty) {
      return Center(
        child: Container(
          width: displaySize * 0.8,
          height: displaySize * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black87,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 50,
                spreadRadius: 15,
              ),
            ],
          ),
          child: const Icon(Icons.music_note, size: 80, color: Colors.white54),
        ),
      );
    }

    final cover = ExcludeSemantics(
      child: CoverCarousel(
        playlist: playlist,
        currentIndex: currentIndex,
        audioService: ref.read(audioServiceProvider),
        isNext: isNext,
        displaySize: displaySize,
        onPageChanged: (page) {
          final audio = ref.read(audioServiceProvider);
          if (page >= 0 && page < playlist.length && page != currentIndex) {
            audio.playAtIndex(page);
          }
        },
        onAnimationComplete: onCarouselAnimationComplete,
      ),
    );

    if (onCoverTap == null) return cover;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCoverTap,
      child: cover,
    );
  }
}

class PlaybackTrackInfo extends ConsumerWidget {
  final MusicFile? currentMusic;
  final TextAlign align;
  final double lyricsModeT;
  final double height;
  final bool isLandscape;

  const PlaybackTrackInfo({
    super.key,
    required this.currentMusic,
    required this.align,
    required this.lyricsModeT,
    required this.height,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final title = currentMusic?.displayName ?? l10n.notSelected;
    final showArtistAlbum = currentMusic != null;

    final rawAlbum = currentMusic?.album?.trim() ?? '';
    final rawArtist = currentMusic?.artist?.trim() ?? '';

    bool isUnknown(String val) {
      if (val.isEmpty) return true;
      final lower = val.toLowerCase();
      return lower == 'unknown' ||
          lower == 'unknown artist' ||
          lower == 'unknown album';
    }

    final bool hasArtist = !isUnknown(rawArtist);
    final bool hasAlbum = !isUnknown(rawAlbum);
    final transition = lyricsModeT.clamp(0.0, 1.0);
    final titleAlignment = align == TextAlign.left
        ? Alignment.lerp(Alignment.center, Alignment.centerLeft, transition)!
        : Alignment.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: titleAlignment,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                showSongContextMenu(
                  context,
                  details.globalPosition,
                  song: currentMusic,
                  mode: SongContextMenuMode.title,
                );
              },
              onLongPressStart: (details) {
                HapticFeedback.mediumImpact();
                showSongContextMenu(
                  context,
                  details.globalPosition,
                  song: currentMusic,
                  mode: SongContextMenuMode.title,
                );
              },
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                curve: Curves.fastOutSlowIn,
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      color: Colors.white,
                      fontSize: lyricsModeT > 0.5 && !isLandscape
                          ? 18
                          : (isLandscape && height > 1000 ? 30 : 22),
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        if (showArtistAlbum)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              width: double.infinity,
              child: Align(
                alignment: titleAlignment,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) {
                    showSongContextMenu(
                      context,
                      details.globalPosition,
                      song: currentMusic,
                      mode: SongContextMenuMode.artistAlbum,
                    );
                  },
                  onLongPressStart: (details) {
                    HapticFeedback.mediumImpact();
                    showSongContextMenu(
                      context,
                      details.globalPosition,
                      song: currentMusic,
                      mode: SongContextMenuMode.artistAlbum,
                    );
                  },
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.fastOutSlowIn,
                    textAlign: TextAlign.start,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: Colors.white70,
                          fontSize: lyricsModeT > 0.5 && !isLandscape
                              ? 13
                              : (isLandscape && height > 1000 ? 18 : 15),
                          height: 1.3,
                        ),
                    child: Text(
                      hasArtist && hasAlbum
                          ? '$rawArtist — $rawAlbum'
                          : (hasArtist
                              ? rawArtist
                              : (hasAlbum ? rawAlbum : l10n.unknown)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PlaybackControls extends ConsumerWidget {
  final bool isLandscape;
  final bool isLyricsMode;
  final bool isLarge;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final VoidCallback? onShowRandomModeSelector;
  final VoidCallback? onTagCompletionTap;
  final VoidCallback? onTagCompletionLongPress;
  final VoidCallback? onSleepTimerTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onToggleVisualizer;
  final bool showVisualizerToggle;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;
  final double? overrideProgress;
  final Duration? overridePosition;
  final List<double>? overrideWaveform;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;

  const PlaybackControls({
    super.key,
    required this.isLandscape,
    required this.isLyricsMode,
    this.isLarge = false,
    this.onShowMoreMenu,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onShowRandomModeSelector,
    this.onTagCompletionTap,
    this.onTagCompletionLongPress,
    this.onSleepTimerTap,
    this.onEqualizerTap,
    this.onToggleVisualizer,
    required this.showVisualizerToggle,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeDrag,
    this.onVolumeScroll,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
    this.onScrubbing,
    this.onSeek,
  });

  String _formatSleepTimer(Duration duration) {
    final safe = duration < Duration.zero ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackMode = ref.watch(audioPlaybackModeProvider);
    final isRandomMode = ref.watch(audioIsRandomModeProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final isFavorite = currentMusic != null && playlistService.isFavoriteSong(currentMusic);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final duration = ref.watch(audioDurationProvider);
    final sleepTimerRemaining = ref.watch(audioSleepTimerRemainingProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final progress = ref.watch(audioProgressProvider);
    final l10n = AppLocalizations.of(context)!;

    final isWaveformEnabled = ref.watch(
      settingsServiceProvider.select((s) => s.isWaveformProgressBarEnabled),
    );

    final useOverlayStyle = !isLandscape && !isLyricsMode && isWaveformEnabled;

    final topButtonsRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          icon: const Icon(Icons.more_horiz, color: Colors.white70),
          onPressed: onShowMoreMenu,
          tooltip: l10n.more,
        ),
        IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: isLarge ? 36 : 28,
            color: isFavorite ? Colors.redAccent : Colors.white70,
          ),
          onPressed: currentMusic == null
              ? null
              : () async {
                  final playlistService = ref.read(playlistServiceProvider);
                  await playlistService.toggleFavoriteSong(currentMusic);
                },
          tooltip: isFavorite ? l10n.removeFromFavorites : l10n.addToFavorites,
        ),
        GestureDetector(
          onLongPress: onShowPlaylistModeSelector,
          child: IconButton(
            icon: Icon(
              getPlaylistModeIcon(playbackMode),
              size: isLarge ? 36 : 28,
              color: Colors.white70,
            ),
            onPressed: onCyclePlaylistMode,
            tooltip: getPlaylistModeName(playbackMode, l10n),
          ),
        ),
        GestureDetector(
          onLongPress: onShowRandomModeSelector,
          child: IconButton(
            icon: Icon(
              Icons.shuffle_rounded,
              size: isLarge ? 36 : 28,
              color: isRandomMode ? Theme.of(context).colorScheme.primary : Colors.white70,
            ),
            onPressed: () {
              final audio = ref.read(audioServiceProvider);
              if (audio.settingsService.randomRange == 1 && !isRandomMode) {
                final playlistService = ref.read(playlistServiceProvider);
                final List<MusicFile> allSongs = [];
                final pathSet = <String>{};
                for (final p in playlistService.playlists) {
                  for (final s in p.songs) {
                    if (pathSet.add(s.path)) allSongs.add(s);
                  }
                }
                audio.toggleRandomMode(globalSongs: allSongs);
              } else {
                audio.toggleRandomMode();
              }
            },
            tooltip: l10n.randomMode,
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.auto_fix_high_rounded,
            size: isLarge ? 36 : 28,
            color: Colors.white70,
          ),
          onPressed: onTagCompletionTap,
          onLongPress: onTagCompletionLongPress,
          tooltip: l10n.tagCompletion,
        ),
        Tooltip(
          message: sleepTimerRemaining != null ? l10n.sleepTimerRemaining(_formatSleepTimer(sleepTimerRemaining)) : l10n.sleepTimer,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSleepTimerTap,
            child: SizedBox(
              width: 74,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bedtime_rounded,
                    size: isLarge ? 36 : 28,
                    color: sleepTimerRemaining != null ? Theme.of(context).colorScheme.primary : Colors.white70,
                  ),
                  if (sleepTimerRemaining != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatSleepTimer(sleepTimerRemaining),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.tune_rounded,
            size: isLarge ? 36 : 28,
            color: Colors.white70,
          ),
          onPressed: onEqualizerTap,
          tooltip: l10n.equalizer,
        ),
      ],
    );

    final mainControlsRow = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: Icon(
            showVisualizerToggle ? Icons.analytics : Icons.analytics_outlined,
            size: isLarge ? 36 : 28,
            color: showVisualizerToggle ? Colors.white : Colors.white70,
          ),
          onPressed: onToggleVisualizer,
          tooltip: AppLocalizations.of(context)!.visualizer,
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(
            Icons.skip_previous_rounded,
            size: isLarge ? 64 : 48,
            color: Colors.white,
          ),
          onPressed: onPrevious,
          tooltip: l10n.previous,
        ),
        const SizedBox(width: 16),
        Container(
          width: isLarge ? 96 : 72,
          height: isLarge ? 96 : 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            onPressed: onPlayPause,
            tooltip: isPlaying ? l10n.pause : l10n.play,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: isLarge ? 56 : 40,
              color: currentThemeColorsMap['darkVibrant'] ?? currentThemeColorsMap['darkMuted'] ?? Colors.black,
            ),
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: Icon(
            Icons.skip_next_rounded,
            size: isLarge ? 64 : 48,
            color: Colors.white,
          ),
          onPressed: onNext,
          tooltip: l10n.next,
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            onVolumeDrag?.call(details.primaryDelta ?? 0);
          },
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                onVolumeScroll?.call(pointerSignal.scrollDelta.dy);
              }
            },
            child: IconButton(
              icon: Icon(
                getVolumeIcon(ref.watch(audioVolumeProvider)),
                size: isLarge ? 36 : 28,
                color: Colors.white70,
              ),
              onPressed: onVolumeTap,
              tooltip: l10n.volume,
            ),
          ),
        ),
      ],
    );

    if (useOverlayStyle) {
      final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
      final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

      return Column(
        key: const ValueKey('overlay_controls_column'),
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          topButtonsRow,
          const SizedBox(height: 8),
          Stack(
            key: const ValueKey('overlay_controls_stack'),
            alignment: Alignment.center,
            children: [
              WaveformProgressBar(
                waveform: waveform,
                progress: displayProgress,
                duration: duration,
                onScrubbing: onScrubbing ?? (_) {},
                onSeek: onSeek ?? (_) {},
                height: 240,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: mainControlsRow,
              ),
              Positioned(
                left: 20,
                bottom: 10,
                child: Text(
                  formatDuration(overridePosition ?? ref.watch(audioPositionProvider)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 10,
                child: Text(
                  formatDuration(duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('default_controls_column'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        topButtonsRow,
        SizedBox(height: isLandscape ? 16 : 12),
        Builder(
          builder: (context) {
            final waveform = overrideWaveform ?? currentMusic?.waveform ?? const [];
            final displayProgress = overrideProgress ?? progress.clamp(0.0, 1.0);

            if (isWaveformEnabled) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: WaveformProgressBar(
                  waveform: waveform,
                  progress: displayProgress,
                  duration: duration,
                  onScrubbing: onScrubbing ?? (_) {},
                  onSeek: onSeek ?? (_) {},
                  height: 100,
                ),
              );
            }
            return _buildStandardSlider(context, displayProgress);
          },
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(overridePosition ?? ref.watch(audioPositionProvider)),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: isLandscape ? 16 : 12),
        mainControlsRow,
      ],
    );
  }

  Widget _buildStandardSlider(BuildContext context, double displayProgress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
          thumbColor: Colors.white,
          overlayColor: Colors.white.withValues(alpha: 0.1),
        ),
        child: Slider(
          value: displayProgress.clamp(0.0, 1.0),
          onChanged: onScrubbing,
          onChangeEnd: (value) {
            onSeek?.call(value);
          },
        ),
      ),
    );
  }
}

class PlaybackLyricsPanel extends ConsumerWidget {
  final MusicFile? currentMusic;
  final double bottomSpacerHeight;
  final double bottomTabBarHeight;

  const PlaybackLyricsPanel({
    super.key,
    required this.currentMusic,
    required this.bottomSpacerHeight,
    required this.bottomTabBarHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final position = ref.watch(audioPositionProvider);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final accent = currentThemeColorsMap['darkVibrant'] ?? currentThemeColorsMap['darkMuted'] ?? Colors.white;

    return LyricsPanel(
      key: ValueKey('$currentIndex:${currentMusic?.path ?? 'no-track'}'),
      lyrics: currentMusic?.lyrics,
      position: position,
      accentColor: accent,
      bottomSpacerHeight: bottomSpacerHeight,
      bottomTabBarHeight: bottomTabBarHeight,
    );
  }
}
