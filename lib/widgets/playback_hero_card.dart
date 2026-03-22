import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';
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
    this.onEqualizerTap,
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
  final VoidCallback? onEqualizerTap;
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
                opacity: 0.6, // Slightly dimmer when full screen to not distract
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
                                    audio.currentFileName ?? AppLocalizations.of(context)!.unknown,
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
                        icon: audio.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: onPlayPause,
                        tooltip: audio.isPlaying
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

  Widget _buildFullCard(BuildContext context, AudioService audio) {
    final width = screenWidth ?? MediaQuery.of(context).size.width;
    final height = screenHeight ?? MediaQuery.of(context).size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDisplaySize = isLandscape ? height : width;
        final content = isLandscape
            ? Row(
                children: [
                  const Spacer(flex: 1),
                  Expanded(
                    flex: 10,
                    child: _buildAlbumArt(audio, maxDisplaySize),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 11,
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
                  Expanded(
                    flex: 14,  // 封面宽度
                    child: Padding(
                      padding: const EdgeInsets.only(
                        // left: 0, // ← 封面左边距
                        // right: 0, // ← 封面右边距
                        top: 0, // ← 封面顶边距
                        bottom: 36, // ← 封面底边距
                      ),
                      child: _buildAlbumArt(audio, maxDisplaySize),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    flex: 10,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: width,
                          child: _buildControls(context, audio, width),
                        ),
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
          child: const Icon(Icons.music_note, size: 80, color: Colors.white54),
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
                if (page >= 0 &&
                    page < audio.playlist.length &&
                    page != audio.currentIndex) {
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
            maxWidth: isLandscape ? 450 : width * 0.95,
          ),
          child: Text(
            audio.currentFileName ?? AppLocalizations.of(context)!.unknown,
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
        if ((audio.currentArtist != null && audio.currentArtist != 'Unknown') ||
            (audio.currentAlbum != null && audio.currentAlbum != 'Unknown'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLandscape ? 400 : width * 0.9,
              ),
              child: Text(
                '${audio.currentArtist ?? AppLocalizations.of(context)!.unknown} — ${audio.currentAlbum ?? AppLocalizations.of(context)!.unknown}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        SizedBox(height: isLandscape ? 16 : 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              onPressed: onShowMoreMenu,
              tooltip: AppLocalizations.of(context)!.more,
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onLongPress: onShowPlaylistModeSelector,
              child: IconButton(
                icon: Icon(
                  getPlaylistModeIcon(audio.player.playlist.mode),
                  size: 28,
                  color: Colors.white70,
                ),
                onPressed: onCyclePlaylistMode,
                tooltip: getPlaylistModeName(
                  audio.player.playlist.mode,
                  AppLocalizations.of(context)!,
                ),
              ),
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
        SizedBox(height: isLandscape ? 8 : 4),
        if (context.watch<SettingsService>().isWaveformProgressBarEnabled)
          WaveformProgressBar(
            waveform: waveform,
            progress: sliderProgress,
            duration: audio.duration,
            onScrubbing: onScrubbing ?? (_) {},
            onSeek: onSeek ?? (_) {},
          )
        else
          _buildStandardSlider(context, audio),
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
        SizedBox(height: isLandscape ? 16 : 6),
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

            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.skip_previous_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onPrevious,
              tooltip: AppLocalizations.of(context)!.previous,
            ),
            const SizedBox(width: 24),
            Builder(
              builder: (context) {
                final darkThemeColor =
                    audio.currentThemeColorsMap['darkVibrant'] ??
                    audio.currentThemeColorsMap['darkMuted'];
                final l10n = AppLocalizations.of(context)!;
                return Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: IconButton(
                    onPressed: onPlayPause,
                    tooltip: audio.isPlaying ? l10n.pause : l10n.play,
                    icon: Icon(
                      audio.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 40,
                      color: darkThemeColor ?? Colors.black,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 24),
            IconButton(
              icon: const Icon(
                Icons.skip_next_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onNext,
              tooltip: AppLocalizations.of(context)!.next,
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
                  tooltip: AppLocalizations.of(context)!.volume,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStandardSlider(BuildContext context, AudioService audio) {
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
          value: sliderProgress.clamp(0.0, 1.0),
          onChanged: onScrubbing,
          onChangeEnd: (value) {
            onSeek?.call(value);
          },
        ),
      ),
    );
  }
}
