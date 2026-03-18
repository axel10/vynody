import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';
import '../widgets/playback_hero_card.dart';
import '../widgets/visualizer_painter.dart';
import '../widgets/volume_controls.dart';
import '../widgets/dynamic_mesh_background.dart';
import '../utils/playback_utils.dart';
import '../dialogs/visualizer_options_dialog.dart';

// PlaybackPage is now cleaner as volume HUD is handled globally

class PlaybackPage extends StatefulWidget {
  const PlaybackPage({super.key});

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage>
    with SingleTickerProviderStateMixin {
  bool _showVolumeSlider = false;
  bool _showVisualizer = true;
  bool _isScrubbingProgress = false;
  double _scrubProgress = 0.0;
  Timer? _inactivityTimer;

  int? _lastIndex;
  bool _isNext = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audio = context.read<AudioService>();
      _showVisualizer = audio.player.fftEnabled;
      _startInactivityTimer();
      if (mounted) {
        setState(() {});
      }
    });
  }

  SettingsService? _settingsService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsService ??= context.read<SettingsService>();
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _settingsService?.isUserInactive = false;
    super.dispose();
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    final settings = context.read<SettingsService>();
    settings.isUserInactive = false;
    _inactivityTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        settings.isUserInactive = true;
      }
    });
  }

  void toNextMusic(AudioService audio) {
    audio.next();
  }

  void _handleInteraction() {
    _startInactivityTimer();
  }

  void _adjustVolumeFromDrag(AudioService audio, double dragDelta) {
    audio.setVolume((audio.volume - dragDelta * 0.2).roundToDouble());
  }

  void _adjustVolumeFromScroll(AudioService audio, double scrollDeltaY) {
    audio.setVolume((audio.volume - scrollDeltaY * 0.1).roundToDouble());
  }

  Future<void> _toggleVisualizer(AudioService audio) async {
    final nextVisible = !_showVisualizer;
    setState(() {
      _showVisualizer = nextVisible;
    });
    await audio.player.setFftEnabled(nextVisible);
  }

  void _cyclePlaylistMode(AudioService audio) {
    final currentMode = audio.player.playlistMode;
    final nextMode = PlaylistMode
        .values[(currentMode.index + 1) % PlaylistMode.values.length];
    audio.player.setPlaylistMode(nextMode);
  }

  void _showPlaylistModeSelector(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.playbackMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlaylistMode.values.map((mode) {
              return ListTile(
                leading: Icon(getPlaylistModeIcon(mode)),
                title: Text(getPlaylistModeName(mode, AppLocalizations.of(context)!)),
                selected: audio.player.playlistMode == mode,
                onTap: () {
                  audio.player.setPlaylistMode(mode);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showMoreMenu(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(AppLocalizations.of(context)!.playbackOptions, style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.settings_input_component,
                color: Colors.blueAccent,
              ),
              title: Text(
                AppLocalizations.of(context)!.setVisualizerDisplay,
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                final settings = context.read<SettingsService>();
                showVisualizerOptionsDialog(context, audio, settings);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
    final settings = context.watch<SettingsService>();
    final sliderProgress = _isScrubbingProgress
        ? _scrubProgress
        : audio.progress.clamp(0.0, 1.0);
    final previewPosition = _isScrubbingProgress
        ? Duration(
            milliseconds: (_scrubProgress * audio.duration.inMilliseconds)
                .round(),
          )
        : audio.position;

    if (audio.currentFilePath == null) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noPlaybackContent, style: TextStyle(color: Colors.grey)),
      );
    }

    final currentIndex = audio.currentIndex;
    if (_lastIndex != null && currentIndex != _lastIndex) {
      if (_lastIndex == 0 && currentIndex > 1) {
        _isNext = false;
      } else if (currentIndex == 0 && _lastIndex! > 1) {
        _isNext = true;
      } else {
        _isNext = currentIndex > _lastIndex!;
      }
    }
    _lastIndex = currentIndex;

    return Listener(
      onPointerDown: (event) {
        _handleInteraction();
      },
      onPointerMove: (event) => _handleInteraction(),
          onPointerHover: (event) => _handleInteraction(),
          child: OrientationBuilder(
            builder: (context, orientation) {
              final isLandscape = orientation == Orientation.landscape;

              final screenWidth = MediaQuery.of(context).size.width;
              final screenHeight = MediaQuery.of(context).size.height;

              final content = SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(isLandscape ? 32.0 : 24.0),
                  child: Column(
                    children: [
                      if (Platform.isWindows) const SizedBox(height: 32),
                      Expanded(
                        child: Center(
                          child: PlaybackHeroCard(
                            isMini: false,
                            isLandscape: isLandscape,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            isNext: _isNext,
                            waveform: audio.currentWaveform,
                            sliderProgress: sliderProgress,
                            previewPosition: previewPosition,
                            showVisualizerToggle: _showVisualizer,
                            onShowMoreMenu: () => _showMoreMenu(context, audio),
                            onCyclePlaylistMode: () => _cyclePlaylistMode(audio),
                            onShowPlaylistModeSelector: () =>
                                _showPlaylistModeSelector(context, audio),
                            onScrubbing: (val) {
                              _handleInteraction();
                              setState(() {
                                _isScrubbingProgress = true;
                                _scrubProgress = val;
                              });
                            },
                            onSeek: (val) {
                              final target = Duration(
                                milliseconds: (val * audio.duration.inMilliseconds)
                                    .round(),
                              );
                              setState(() {
                                _isScrubbingProgress = false;
                                _scrubProgress = val;
                              });
                              audio.seek(target);
                            },
                            onToggleVisualizer: () => _toggleVisualizer(audio),
                            onPrevious: audio.previous,
                            onPlayPause: audio.togglePlay,
                            onNext: () => toNextMusic(audio),
                            onVolumeTap: () {
                              _handleInteraction();
                              setState(() {
                                _showVolumeSlider = !_showVolumeSlider;
                              });
                            },
                            onVolumeDrag: (delta) {
                              _handleInteraction();
                              _adjustVolumeFromDrag(audio, delta);
                            },
                            onVolumeScroll: (deltaY) {
                              _handleInteraction();
                              _adjustVolumeFromScroll(audio, deltaY);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
            ),
          );

          return Container(
            color: Colors.black,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (settings.playbackBackgroundType == 1)
                  const Positioned.fill(child: DynamicMeshBackground())
                else
                  _buildBlurredBackground(audio),
                if (_showVisualizer) _buildVisualizerLayer(audio),
                content,
                if (_showVolumeSlider)
                  VolumeSliderOverlay(
                    volume: audio.volume,
                    onVolumeChanged: (val) {
                      _handleInteraction();
                      audio.setVolume(val.roundToDouble());
                    },
                    onDismiss: () => setState(() => _showVolumeSlider = false),
                    isLandscape: isLandscape,
                    getVolumeIcon: getVolumeIcon,
                    onDrag: (delta) => _adjustVolumeFromDrag(audio, delta),
                    onScroll: (deltaY) =>
                        _adjustVolumeFromScroll(audio, deltaY),
                    onInteraction: _handleInteraction,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBlurredBackground(AudioService audio) {
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 800),
        child:
            (audio.currentArtworkBytes != null ||
                audio.currentArtworkPath != null)
            ? KeyedSubtree(
                key: ValueKey(audio.currentFilePath ?? 'bg_art'),
                child: Transform.scale(
                  scale: 1.1,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(
                      sigmaX: 60,
                      sigmaY: 60,
                      tileMode: TileMode.mirror,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: audio.currentArtworkBytes != null
                              ? MemoryImage(audio.currentArtworkBytes!)
                              : FileImage(File(audio.currentArtworkPath!))
                                    as ImageProvider,
                          fit: BoxFit.cover,
                          colorFilter: ColorFilter.mode(
                            Colors.black.withValues(alpha: 0.4),
                            BlendMode.darken,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : Container(key: const ValueKey('bg_empty'), color: Colors.black),
      ),
    );
  }

  Widget _buildVisualizerLayer(AudioService audio) {
    return Positioned.fill(
      child: StreamBuilder<FftFrame>(
        stream: audio.player.optimizedFftStream,
        builder: (context, snapshot) {
          final frame = snapshot.data;
          if (frame == null) return const SizedBox.shrink();

          final settings = context.watch<SettingsService>();
          return CustomPaint(
            painter: FftPainter(
              values: frame.values,
              color: settings.isVisualizerDynamicColor
                  ? (audio.dynamicStartColor ?? settings.visualizerColor)
                  : settings.visualizerColor,
              opacity: settings.visualizerOpacity,
              useGradient: settings.isVisualizerGradientEnabled,
              startColor: settings.isVisualizerDynamicStartColor
                  ? (audio.dynamicStartColor ?? settings.visualizerStartColor)
                  : settings.visualizerStartColor,
              endColor: settings.isVisualizerDynamicEndColor
                  ? (audio.dynamicEndColor ?? settings.visualizerEndColor)
                  : settings.visualizerEndColor,
              gradientStop1: settings.visualizerGradientStop1,
              gradientStop2: settings.visualizerGradientStop2,
              gradientTileMode: settings.visualizerGradientTileMode,
            ),
          );
        },
      ),
    );
  }

  // Widget _buildTopGradient() {
  //   return Positioned(
  //     top: 0,
  //     left: 0,
  //     right: 0,
  //     height: 120,
  //     child: Container(
  //       decoration: BoxDecoration(
  //         gradient: LinearGradient(
  //           begin: Alignment.topCenter,
  //           end: Alignment.bottomCenter,
  //           colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
  //         ),
  //       ),
  //     ),
  //   );
  // }

  // Widget _buildBottomGradient() {
  //   return Positioned(
  //     bottom: 0,
  //     left: 0,
  //     right: 0,
  //     height: 160,
  //     child: Container(
  //       decoration: BoxDecoration(
  //         gradient: LinearGradient(
  //           begin: Alignment.bottomCenter,
  //           end: Alignment.topCenter,
  //           colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
  //         ),
  //       ),
  //     ),
  //   );
  // }
}
