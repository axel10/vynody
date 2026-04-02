import 'dart:ui' show lerpDouble;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_snapshot.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';
import '../player/playlist_service.dart';
import '../models/music_file.dart';
import '../utils/playback_utils.dart';
import '../widgets/cover_carousel.dart';
import '../widgets/lyrics_panel.dart';
import '../widgets/mini_player_widgets.dart';
import '../widgets/waveform_progress_bar.dart';

const String playbackHeroTag = 'player_capsule';

class PlaybackHeroCard extends StatelessWidget {
  const PlaybackHeroCard({
    super.key,
    required this.isMini,
    this.isLyricsMode = false,
    this.isLandscape = false,
    this.screenWidth,
    this.screenHeight,
    this.isNext = true,
    this.showVisualizerToggle = true,
    this.onShowMoreMenu,
    this.onMiniTap,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onShowRandomModeSelector,
    this.onScrubbing,
    this.onSeek,
    this.onToggleVisualizer,
    this.onTagCompletionTap,
    this.onEqualizerTap,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeDrag,
    this.onVolumeScroll,
    this.onCoverTap,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
  });

  final bool isMini;
  final bool isLyricsMode;
  final bool isLandscape;
  final double? screenWidth;
  final double? screenHeight;
  final bool isNext;
  final List<double>? overrideWaveform;
  final double? overrideProgress;
  final Duration? overridePosition;
  final bool showVisualizerToggle;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onMiniTap;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final VoidCallback? onShowRandomModeSelector;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onToggleVisualizer;
  final VoidCallback? onTagCompletionTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;
  final VoidCallback? onCoverTap;

  double _lerp2D(
    double pN,
    double pL,
    double lN,
    double lL,
    double tLyrics,
    double tLand,
  ) {
    final p = lerpDouble(pN, pL, tLyrics) ?? pN;
    final l = lerpDouble(lN, lL, tLyrics) ?? lN;
    return lerpDouble(p, l, tLand) ?? p;
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: playbackHeroTag,
      child: Material(
        type: MaterialType.transparency,
        child: isMini ? _buildMiniCard(context) : _buildFullCard(context),
      ),
    );
  }

  Widget _buildMiniCard(BuildContext context) {
    final audio = context.read<AudioService>();
    final AudioSnapshot snapshot = context.select(
      (AudioService a) => a.snapshot,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.6,
                child: MiniSpectrumBackground(audio: audio),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onMiniTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MiniArtwork(audio: audio),
                          const SizedBox(width: 12),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    snapshot.currentMusic?.displayName ??
                                        AppLocalizations.of(
                                          context,
                                        )!.notSelected,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall!
                                        .copyWith(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      value: snapshot.progress.clamp(0.0, 1.0),
                                      backgroundColor: Colors.white24,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiniControlButton(
                        icon: Icons.skip_previous_rounded,
                        onPressed: onPrevious,
                        tooltip: AppLocalizations.of(context)!.previous,
                      ),
                      const SizedBox(width: 8),
                      MiniControlButton(
                        icon: snapshot.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: onPlayPause,
                        tooltip: snapshot.isPlaying
                            ? AppLocalizations.of(context)!.pause
                            : AppLocalizations.of(context)!.play,
                      ),
                      const SizedBox(width: 8),
                      MiniControlButton(
                        icon: Icons.skip_next_rounded,
                        onPressed: onNext,
                        tooltip: AppLocalizations.of(context)!.next,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context) {
    const animDuration = Duration(milliseconds: 400);
    const animCurve = Curves.fastOutSlowIn;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: isLandscape ? 1.0 : 0.0,
        end: isLandscape ? 1.0 : 0.0,
      ),
      duration: animDuration,
      curve: animCurve,
      builder: (context, tLand, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: isLyricsMode ? 1.0 : 0.0,
            end: isLyricsMode ? 1.0 : 0.0,
          ),
          duration: animDuration,
          curve: animCurve,
          builder: (context, tLyrics, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;

                // ---------------- Portrait Normal ----------------
                final pNormalCoverSide = math.min(width * 0.85, height * 0.5);
                final pNormalCoverTop =
                    height * 0.05 + (height * 0.45 - pNormalCoverSide) / 2;
                final pNormalCoverLeft = (width - pNormalCoverSide) / 2;

                final pNormalInfoTop = height * 0.52;
                final pNormalInfoLeft = 16.0;
                final pNormalInfoWidth = width - 32.0;
                final pNormalInfoHeight = 80.0;

                final pNormalControlsTop =
                    pNormalInfoTop + pNormalInfoHeight + 8.0;
                final pNormalControlsLeft = 16.0;
                final pNormalControlsWidth = width - 32.0;
                final pNormalControlsHeight =
                    height - pNormalControlsTop - 16.0;
                final pNormalControlsOpacity = 1.0;

                final pNormalLyricsTop = height;
                final pNormalLyricsLeft = 16.0;
                final pNormalLyricsWidth = width - 32.0;
                final pNormalLyricsHeight = height - pNormalInfoTop;
                final pNormalLyricsOpacity = 0.0;

                // ---------------- Portrait Lyrics ----------------
                final pLyricsCoverSide = math.min(104.0, width * 0.28);
                final pLyricsCoverTop = 16.0;
                final pLyricsCoverLeft = 16.0;

                final pLyricsInfoTop = 16.0;
                final pLyricsInfoLeft = 16.0 + pLyricsCoverSide + 14.0;
                final pLyricsInfoWidth = width - pLyricsInfoLeft - 16.0;
                final pLyricsInfoHeight = pLyricsCoverSide;

                final pLyricsControlsTop = height;
                final pLyricsControlsLeft = 16.0;
                final pLyricsControlsWidth = width - 32.0;
                final pLyricsControlsHeight = pNormalControlsHeight;
                final pLyricsControlsOpacity = 0.0;

                final pLyricsLyricsTop =
                    pLyricsCoverTop + pLyricsCoverSide + 16.0;
                final pLyricsLyricsLeft = 16.0;
                final pLyricsLyricsWidth = width - 32.0;
                final pLyricsLyricsHeight = height - pLyricsLyricsTop - 16.0;
                final pLyricsLyricsOpacity = 1.0;

                // ---------------- Landscape Normal ----------------
                final lNormalCoverSide = math.min(width * 0.42, height * 0.85);
                final lNormalCoverTop = (height - lNormalCoverSide) / 2;
                final lNormalCoverLeft =
                    width * 0.05 + (width * 0.45 - lNormalCoverSide) / 2;

                final lNormalInfoTop = height * 0.5 - 100 - 45;
                final lNormalInfoLeft = width * 0.5;
                final lNormalInfoWidth = width * 0.45;
                final lNormalInfoHeight = 90.0;

                final lNormalControlsTop = lNormalInfoTop + lNormalInfoHeight;
                final lNormalControlsLeft = width * 0.5;
                final lNormalControlsWidth = width * 0.45;
                final lNormalControlsHeight = 200.0;
                final lNormalControlsOpacity = 1.0;

                final lNormalLyricsTop = 16.0;
                final lNormalLyricsLeft = width;
                final lNormalLyricsWidth = width * 0.45;
                final lNormalLyricsHeight = height - 32.0;
                final lNormalLyricsOpacity = 0.0;

                // ---------------- Landscape Lyrics ----------------
                final lColWidth = (width * 0.35).clamp(280.0, 420.0);

                final lLyricsCoverSide = math.min(
                  lColWidth * 0.8,
                  height * 0.45,
                );
                final lLyricsCoverTop = 16.0;
                final lLyricsCoverLeft = (lColWidth - lLyricsCoverSide) / 2;

                final lLyricsInfoTop =
                    lLyricsCoverTop + lLyricsCoverSide + 24.0;
                final lLyricsInfoLeft = 16.0;
                final lLyricsInfoWidth = lColWidth - 32.0;
                final lLyricsInfoHeight = 80.0;

                final lLyricsControlsTop =
                    lLyricsInfoTop + lLyricsInfoHeight + 16.0;
                final lLyricsControlsLeft = 16.0;
                final lLyricsControlsWidth = lColWidth - 32.0;
                final lLyricsControlsHeight =
                    height - lLyricsControlsTop - 16.0;
                final lLyricsControlsOpacity = 1.0;

                final lLyricsLyricsTop = 16.0;
                final lLyricsLyricsLeft = lColWidth + 16.0;
                final lLyricsLyricsWidth = width - lLyricsLyricsLeft - 32.0;
                final lLyricsLyricsHeight = height - 32.0;
                final lLyricsLyricsOpacity = 1.0;

                // ---------------- Execute 2D Interpolation ----------------
                final coverSide = _lerp2D(
                  pNormalCoverSide,
                  pLyricsCoverSide,
                  lNormalCoverSide,
                  lLyricsCoverSide,
                  tLyrics,
                  tLand,
                );
                final coverTop = _lerp2D(
                  pNormalCoverTop,
                  pLyricsCoverTop,
                  lNormalCoverTop,
                  lLyricsCoverTop,
                  tLyrics,
                  tLand,
                );
                final coverLeft = _lerp2D(
                  pNormalCoverLeft,
                  pLyricsCoverLeft,
                  lNormalCoverLeft,
                  lLyricsCoverLeft,
                  tLyrics,
                  tLand,
                );

                final infoTop = _lerp2D(
                  pNormalInfoTop,
                  pLyricsInfoTop,
                  lNormalInfoTop,
                  lLyricsInfoTop,
                  tLyrics,
                  tLand,
                );
                final infoLeft = _lerp2D(
                  pNormalInfoLeft,
                  pLyricsInfoLeft,
                  lNormalInfoLeft,
                  lLyricsInfoLeft,
                  tLyrics,
                  tLand,
                );
                final infoWidth = _lerp2D(
                  pNormalInfoWidth,
                  pLyricsInfoWidth,
                  lNormalInfoWidth,
                  lLyricsInfoWidth,
                  tLyrics,
                  tLand,
                );
                final infoHeight = _lerp2D(
                  pNormalInfoHeight,
                  pLyricsInfoHeight,
                  lNormalInfoHeight,
                  lLyricsInfoHeight,
                  tLyrics,
                  tLand,
                );

                final controlsTop = _lerp2D(
                  pNormalControlsTop,
                  pLyricsControlsTop,
                  lNormalControlsTop,
                  lLyricsControlsTop,
                  tLyrics,
                  tLand,
                );
                final controlsLeft = _lerp2D(
                  pNormalControlsLeft,
                  pLyricsControlsLeft,
                  lNormalControlsLeft,
                  lLyricsControlsLeft,
                  tLyrics,
                  tLand,
                );
                final controlsWidth = _lerp2D(
                  pNormalControlsWidth,
                  pLyricsControlsWidth,
                  lNormalControlsWidth,
                  lLyricsControlsWidth,
                  tLyrics,
                  tLand,
                );
                final controlsHeight = _lerp2D(
                  pNormalControlsHeight,
                  pLyricsControlsHeight,
                  lNormalControlsHeight,
                  lLyricsControlsHeight,
                  tLyrics,
                  tLand,
                );
                final controlsOpacity = _lerp2D(
                  pNormalControlsOpacity,
                  pLyricsControlsOpacity,
                  lNormalControlsOpacity,
                  lLyricsControlsOpacity,
                  tLyrics,
                  tLand,
                );

                final lyricsTop = _lerp2D(
                  pNormalLyricsTop,
                  pLyricsLyricsTop,
                  lNormalLyricsTop,
                  lLyricsLyricsTop,
                  tLyrics,
                  tLand,
                );
                final lyricsLeft = _lerp2D(
                  pNormalLyricsLeft,
                  pLyricsLyricsLeft,
                  lNormalLyricsLeft,
                  lLyricsLyricsLeft,
                  tLyrics,
                  tLand,
                );
                final lyricsWidth = _lerp2D(
                  pNormalLyricsWidth,
                  pLyricsLyricsWidth,
                  lNormalLyricsWidth,
                  lLyricsLyricsWidth,
                  tLyrics,
                  tLand,
                );
                final lyricsHeight = _lerp2D(
                  pNormalLyricsHeight,
                  pLyricsLyricsHeight,
                  lNormalLyricsHeight,
                  lLyricsLyricsHeight,
                  tLyrics,
                  tLand,
                );
                final lyricsOpacity = _lerp2D(
                  pNormalLyricsOpacity,
                  pLyricsLyricsOpacity,
                  lNormalLyricsOpacity,
                  lLyricsLyricsOpacity,
                  tLyrics,
                  tLand,
                );

                final targetInfoAlign = isLandscape
                    ? TextAlign.center
                    : (isLyricsMode ? TextAlign.left : TextAlign.center);

                return SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: lyricsTop,
                        left: lyricsLeft,
                        width: lyricsWidth,
                        height: lyricsHeight,
                        child: Opacity(
                          opacity: lyricsOpacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: lyricsOpacity < 0.5,
                            child: _buildLyricsPanelWidget(context),
                          ),
                        ),
                      ),
                      Positioned(
                        top: controlsTop,
                        left: controlsLeft,
                        width: controlsWidth,
                        height: controlsHeight,
                        child: Opacity(
                          opacity: controlsOpacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: controlsOpacity < 0.5,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: isLandscape
                                    ? 450
                                    : math.max(controlsWidth, 380.0),
                                child: _buildPlaybackControlsWidget(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: coverTop,
                        left: coverLeft,
                        width: coverSide,
                        height: coverSide,
                        child: _buildAlbumArtCore(context, coverSide),
                      ),
                      Positioned(
                        top: infoTop,
                        left: infoLeft,
                        width: infoWidth,
                        height: infoHeight,
                        child: _buildTrackInfo(
                          context,
                          targetInfoAlign,
                          isLyricsMode,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumArtCore(BuildContext context, double currentSize) {
    final AudioSnapshot snapshot = context.select(
      (AudioService a) => a.snapshot,
    );
    final playlist = snapshot.playbackQueue;
    if (playlist.isEmpty) {
      return Center(
        child: Container(
          width: currentSize * 0.8,
          height: currentSize * 0.8,
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
        currentIndex: snapshot.currentIndex,
        audioService: context.read<AudioService>(),
        isNext: isNext,
        displaySize: currentSize,
        onPageChanged: (page) {
          final audio = context.read<AudioService>();
          if (page >= 0 &&
              page < playlist.length &&
              page != snapshot.currentIndex) {
            audio.playAtIndex(page);
          }
        },
      ),
    );

    if (onCoverTap == null) return cover;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCoverTap,
      child: cover,
    );
  }

  Widget _buildTrackInfo(BuildContext context, TextAlign align, bool isLyrics) {
    final AudioSnapshot snapshot = context.select(
      (AudioService a) => a.snapshot,
    );
    final l10n = AppLocalizations.of(context)!;
    final title =
        snapshot.currentLyricsTitle ??
        snapshot.currentMusic?.displayName ??
        l10n.notSelected;
    final album = snapshot.currentMusic?.album;
    final artist = snapshot.currentMusic?.artist;

    String subtitle = '';
    if (artist != null &&
        artist != 'Unknown' &&
        album != null &&
        album != 'Unknown') {
      subtitle = '$artist — $album';
    } else if (artist != null && artist != 'Unknown') {
      subtitle = artist;
    } else if (album != null && album != 'Unknown') {
      subtitle = album;
    }

    return Column(
      crossAxisAlignment: align == TextAlign.left
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 400),
          curve: Curves.fastOutSlowIn,
          textAlign: align,
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            color: Colors.white,
            fontSize: isLyrics && !isLandscape ? 18 : 22,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastOutSlowIn,
              textAlign: align,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: Colors.white70,
                fontSize: isLyrics && !isLandscape ? 13 : 16,
                height: 1.2,
              ),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaybackControlsWidget(BuildContext context) {
    final AudioSnapshot snapshot = context.select(
      (AudioService a) => a.snapshot,
    );
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              onPressed: onShowMoreMenu,
              tooltip: l10n.more,
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onLongPress: onShowPlaylistModeSelector,
              child: IconButton(
                icon: Icon(
                  getPlaylistModeIcon(snapshot.playbackMode),
                  size: 28,
                  color: Colors.white70,
                ),
                onPressed: onCyclePlaylistMode,
                tooltip: getPlaylistModeName(snapshot.playbackMode, l10n),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onLongPress: onShowRandomModeSelector,
              child: IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  size: 28,
                  color: snapshot.isRandomMode
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                ),
                onPressed: () {
                  final audio = context.read<AudioService>();
                  if (audio.settingsService.randomRange == 1 &&
                      !snapshot.isRandomMode) {
                    final playlistService = context.read<PlaylistService>();
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
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.auto_fix_high_rounded,
                size: 28,
                color: Colors.white70,
              ),
              onPressed: onTagCompletionTap,
              tooltip: '歌曲标签补全',
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.tune_rounded,
                size: 28,
                color: Colors.white70,
              ),
              onPressed: onEqualizerTap,
              tooltip: "均衡器",
            ),
          ],
        ),
        SizedBox(height: isLandscape ? 16 : 12),
        Selector<SettingsService, bool>(
          selector: (_, s) => s.isWaveformProgressBarEnabled,
          builder: (context, enabled, _) {
            final duration = snapshot.duration;
            final waveform =
                overrideWaveform ?? snapshot.currentMusic?.waveform ?? const [];
            final displayProgress =
                overrideProgress ?? snapshot.progress.clamp(0.0, 1.0);

            if (enabled) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: WaveformProgressBar(
                  waveform: waveform,
                  progress: displayProgress,
                  duration: duration,
                  onScrubbing: onScrubbing ?? (_) {},
                  onSeek: onSeek ?? (_) {},
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
                formatDuration(overridePosition ?? snapshot.position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                formatDuration(snapshot.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: isLandscape ? 16 : 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                showVisualizerToggle
                    ? Icons.analytics
                    : Icons.analytics_outlined,
                size: 28,
                color: showVisualizerToggle ? Colors.white : Colors.white70,
              ),
              onPressed: onToggleVisualizer,
              tooltip: AppLocalizations.of(context)!.visualizer,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(
                Icons.skip_previous_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onPrevious,
              tooltip: l10n.previous,
            ),
            const SizedBox(width: 16),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: IconButton(
                onPressed: onPlayPause,
                tooltip: snapshot.isPlaying ? l10n.pause : l10n.play,
                icon: Icon(
                  snapshot.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 40,
                  color:
                      snapshot.currentThemeColorsMap['darkVibrant'] ??
                      snapshot.currentThemeColorsMap['darkMuted'] ??
                      Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(
                Icons.skip_next_rounded,
                size: 48,
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
                    getVolumeIcon(snapshot.volume),
                    size: 28,
                    color: Colors.white70,
                  ),
                  onPressed: onVolumeTap,
                  tooltip: l10n.volume,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLyricsPanelWidget(BuildContext context) {
    final AudioSnapshot snapshot = context.select(
      (AudioService a) => a.snapshot,
    );
    final accent =
        snapshot.currentThemeColorsMap['darkVibrant'] ??
        snapshot.currentThemeColorsMap['darkMuted'] ??
        Colors.white;

    return LyricsPanel(
      key: ValueKey(
        '${snapshot.currentMusic?.path}_${snapshot.currentLyricsLines.length}_${snapshot.isLyricsLoading}_${snapshot.hasLyrics}',
      ),
      lines: snapshot.currentLyricsLines,
      position: snapshot.position,
      isLoading: snapshot.isLyricsLoading,
      hasLyrics: snapshot.hasLyrics,
      isSynced: snapshot.isLyricsSynced,
      plainLyrics: snapshot.currentLyricsText,
      accentColor: accent,
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
