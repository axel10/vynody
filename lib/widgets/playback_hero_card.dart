import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/audio_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/cover_carousel.dart';
import '../widgets/mini_player_widgets.dart';
import '../widgets/waveform_progress_bar.dart';

const String playbackHeroTag = 'player_capsule';

class PlaybackHeroCard extends StatelessWidget {
  const PlaybackHeroCard({
    super.key,
    required this.isMini,
    this.isLandscape = false,
    this.screenWidth,
    this.screenHeight,
    this.isNext = true,
    this.waveform = const [],
    this.sliderProgress = 0,
    this.previewPosition = Duration.zero,
    this.showVisualizerToggle = true,
    this.onShowMoreMenu,
    this.onMiniTap,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onScrubbing,
    this.onSeek,
    this.onToggleVisualizer,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeDrag,
    this.onVolumeScroll,
  });

  final bool isMini;
  final bool isLandscape;
  final double? screenWidth;
  final double? screenHeight;
  final bool isNext;
  final List<double> waveform;
  final double sliderProgress;
  final Duration previewPosition;
  final bool showVisualizerToggle;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onMiniTap;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onToggleVisualizer;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    if (audio.currentFilePath == null) {
      return const SizedBox.shrink();
    }

    return Hero(
      tag: playbackHeroTag,
      child: Material(
        type: MaterialType.transparency,
        child: isMini
            ? _buildMiniCard(context, audio)
            : _buildFullCard(context, audio),
      ),
    );
  }

  Widget _buildMiniCard(BuildContext context, AudioService audio) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            audio.currentFileName ?? 'Unknown',
                            style: const TextStyle(
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
                              value: audio.progress.clamp(0.0, 1.0),
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
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
          const SizedBox(width: 12),
          MiniControlButton(
            icon: Icons.skip_previous_rounded,
            onPressed: onPrevious,
          ),
          const SizedBox(width: 8),
          MiniControlButton(
            icon: audio.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            onPressed: onPlayPause,
          ),
          const SizedBox(width: 8),
          MiniControlButton(icon: Icons.skip_next_rounded, onPressed: onNext),
        ],
      ),
    );
  }

  Widget _buildFullCard(BuildContext context, AudioService audio) {
    final width = screenWidth ?? MediaQuery.of(context).size.width;
    final height = screenHeight ?? MediaQuery.of(context).size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDisplaySize = isLandscape ? height * 0.75 : width * 0.85;
        final content = isLandscape
            ? Row(
                children: [
                  const Spacer(flex: 1),
                  Expanded(
                    flex: 8,
                    child: _buildAlbumArt(audio, maxDisplaySize),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 10,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: 450,
                          child: _buildControls(context, audio, width),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 1),
                ],
              )
            : Column(
                children: [
                  Expanded(child: _buildAlbumArt(audio, maxDisplaySize)),
                  const SizedBox(height: 24),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: width,
                        child: _buildControls(context, audio, width),
                      ),
                    ),
                  ),
                ],
              );

        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: content,
        );
      },
    );
  }

  Widget _buildAlbumArt(AudioService audio, double maxDisplaySize) {
    if (audio.playlist.isEmpty) {
      return Center(
        child: Container(
          width: 200,
          height: 200,
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
          child: const Icon(
            Icons.music_note,
            size: 80,
            color: Colors.white54,
          ),
        ),
      );
    }

    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = [
            maxDisplaySize,
            constraints.maxWidth,
            constraints.maxHeight,
          ].reduce((a, b) => a < b ? a : b);
          return SizedBox.square(
            dimension: side,
            child: CoverCarousel(
              playlist: audio.playlist,
              currentIndex: audio.currentIndex,
              audioService: audio,
              onPageChanged: (page) {
                if (page >= 0 && page < audio.playlist.length && page != audio.currentIndex) {
                  audio.playAtIndex(page);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    AudioService audio,
    double width,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 450 : width * 0.9,
          ),
          child: Text(
            audio.currentFileName ?? 'Unknown',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              onPressed: onShowMoreMenu,
              tooltip: 'More',
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onLongPress: onShowPlaylistModeSelector,
              child: IconButton(
                icon: Icon(
                  getPlaylistModeIcon(audio.player.playlistMode),
                  size: 28,
                  color: Colors.white70,
                ),
                onPressed: onCyclePlaylistMode,
                tooltip: getPlaylistModeName(audio.player.playlistMode),
              ),
            ),
          ],
        ),
        SizedBox(height: isLandscape ? 8 : 16),
        WaveformProgressBar(
          waveform: waveform,
          progress: sliderProgress,
          onScrubbing: onScrubbing ?? (_) {},
          onSeek: onSeek ?? (_) {},
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(previewPosition),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                formatDuration(audio.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
              tooltip: 'Visualizer',
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(
                Icons.skip_previous_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onPrevious,
            ),
            const SizedBox(width: 24),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: IconButton(
                onPressed: onPlayPause,
                icon: Icon(
                  audio.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 40,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 24),
            IconButton(
              icon: const Icon(
                Icons.skip_next_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onNext,
            ),
            const SizedBox(width: 16),
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
                    getVolumeIcon(audio.volume),
                    size: 28,
                    color: Colors.white70,
                  ),
                  onPressed: onVolumeTap,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}