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
    this.showVisualizerToggle = true,
    this.onShowMoreMenu,
    this.onMiniTap,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onShowRandomModeSelector,
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
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
  });

  final bool isMini;
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
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;

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
                                    snapshot.currentFileName ??
                                        AppLocalizations.of(
                                          context,
                                        )!.notSelected,
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
                    child: _buildAlbumArt(context, maxDisplaySize),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 11,
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: 450,
                          child: _buildControls(context, width),
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
                    flex: 14,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _buildAlbumArt(context, maxDisplaySize),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    flex: 10,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                          width: width,
                          child: _buildControls(context, width),
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

  Widget _buildAlbumArt(BuildContext context, double maxDisplaySize) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = [
            maxDisplaySize,
            constraints.maxWidth,
            constraints.maxHeight,
          ].reduce((a, b) => a < b ? a : b);

          final AudioSnapshot snapshot = context.select(
            (AudioService a) => a.snapshot,
          );
          final playlist = snapshot.playbackQueue;
          if (playlist.isEmpty) {
            return _buildArtworkPlaceholder();
          }
          return SizedBox.square(
            dimension: side,
            child: CoverCarousel(
              playlist: playlist,
              currentIndex: snapshot.currentIndex,
              audioService: context.read<AudioService>(),
              isNext: isNext,
              displaySize: side,
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
        },
      ),
    );
  }

  Widget _buildArtworkPlaceholder() {
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

  Widget _buildControls(BuildContext context, double width) {
    final AudioSnapshot snapshot = context.select(
      (AudioService a) => a.snapshot,
    );
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 450 : width * 0.95,
          ),
          child: Text(
            snapshot.currentFileName ?? l10n.notSelected,
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
        if ((snapshot.currentArtist != null &&
                snapshot.currentArtist != 'Unknown') ||
            (snapshot.currentAlbum != null &&
                snapshot.currentAlbum != 'Unknown'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLandscape ? 400 : width * 0.9,
              ),
              child: Text(
                '${snapshot.currentArtist ?? l10n.unknown} — ${snapshot.currentAlbum ?? l10n.unknown}',
                style: const TextStyle(fontSize: 16, color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        SizedBox(height: isLandscape ? 16 : 12),
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
            final waveform = overrideWaveform ?? snapshot.currentWaveform;
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
