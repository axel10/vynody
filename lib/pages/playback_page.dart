import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
import '../player/playlist_service.dart';
import '../models/music_file.dart';
import '../dialogs/visualizer_options_dialog.dart';
import '../widgets/equalizer_panel.dart';

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
  double _scrubProgress = 0.0; // Added missing declaration
  Orientation? _lastOrientation;
  Timer? _inactivityTimer; // Added missing declaration

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final audio = context.read<AudioService>();
      _showVisualizer = audio.player.visualizer.enabled;
      context.read<SettingsService>().resetInactivity();
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
    // 延迟重置，避免在 dispose 过程中触发 notifyListeners 导致的 "locked" 错误
    final settings = _settingsService;
    if (settings != null) {
      Future.microtask(() {
        settings.isUserInactive = false;
      });
    }
    super.dispose();
  }

  void _startInactivityTimer() {
    context.read<SettingsService>().resetInactivity();
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
    audio.player.visualizer.setEnabled(nextVisible);
  }

  void _cyclePlaylistMode(AudioService audio) {
    final currentMode = audio.player.playlist.mode;
    final nextMode = PlaylistMode
        .values[(currentMode.index + 1) % PlaylistMode.values.length];
    audio.player.playlist.setMode(nextMode);
  }

  void _showEqualizerPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const EqualizerPanel(),
    );
  }

  void _showRandomModeSelector(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final settings = context.watch<SettingsService>();
        return AlertDialog(
          title: Text(l10n.randomMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.randomRange, style: const TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<int>(
                title: Text(l10n.currentQueue),
                value: 0,
                groupValue: settings.randomRange,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomRange = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      audio.toggleRandomMode(); // Re-apply with new range (Current)
                    }
                  }
                },
              ),
              RadioListTile<int>(
                title: Text(l10n.globalRange),
                value: 1,
                groupValue: settings.randomRange,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomRange = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      final playlistService = context.read<PlaylistService>();
                      final allSongs = _getGlobalSongs(playlistService);
                      audio.toggleRandomMode(globalSongs: allSongs);
                    }
                  }
                },
              ),
              const Divider(),
              Text(l10n.randomMethod, style: const TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<int>(
                title: Text(l10n.completeRandom),
                value: 0,
                groupValue: settings.randomMethod,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomMethod = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      if (settings.randomRange == 1) {
                         final allSongs = _getGlobalSongs(context.read<PlaylistService>());
                         audio.toggleRandomMode(globalSongs: allSongs);
                      } else {
                         audio.toggleRandomMode();
                      }
                    }
                  }
                },
              ),
              RadioListTile<int>(
                title: Text(l10n.shuffleRandom),
                value: 1,
                groupValue: settings.randomMethod,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomMethod = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      if (settings.randomRange == 1) {
                         final allSongs = _getGlobalSongs(context.read<PlaylistService>());
                         audio.toggleRandomMode(globalSongs: allSongs);
                      } else {
                         audio.toggleRandomMode();
                      }
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  List<MusicFile> _getGlobalSongs(PlaylistService playlistService) {
    final List<MusicFile> allSongs = [];
    final pathSet = <String>{};
    for (final p in playlistService.playlists) {
      for (final s in p.songs) {
        if (pathSet.add(s.path)) allSongs.add(s);
      }
    }
    return allSongs;
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
                selected: audio.player.playlist.mode == mode,
                onTap: () {
                  audio.player.playlist.setMode(mode);
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
        title: Text(AppLocalizations.of(context)!.playbackOptions, style: const TextStyle(color: Colors.white)),
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
                style: const TextStyle(color: Colors.white),
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
    final currentFilePath = context.select((AudioService a) => a.currentFilePath);

    if (currentFilePath == null) {
      return Center(
        child: Text(AppLocalizations.of(context)!.noPlaybackContent, style: const TextStyle(color: Colors.grey)),
      );
    }
    
    // Separate UI status from rendering visibility to avoid flicker
    final isVisualizerEnabled = context.select((AudioService a) => a.player.visualizer.enabled);
    final isTransitioning = context.select((AudioService a) => a.isTransitioning);
    final shouldDrawVisualizer = isVisualizerEnabled && !isTransitioning;
    final backgroundType = context.select((SettingsService s) => s.playbackBackgroundType);

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

              if (_lastOrientation != orientation) {
                _lastOrientation = orientation;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  context.read<AudioService>().applyVisualizerSettings(orientation: orientation);
                });
              }

              final content = SafeArea(
                child: Padding(
                  padding: EdgeInsets.all(isLandscape ? 32.0 : 24.0),
                  child: Column(
                    children: [
                      if (Platform.isWindows) const SizedBox(height: 32),
                      Expanded(
                        child: Center(
                          child: Builder(
                            builder: (context) {
                              final audio = context.read<AudioService>();
                              final isNext = context.select((AudioService a) => a.isLastActionNext ?? true);
                              final isVisualizerEnabled = context.select((AudioService a) => a.player.visualizer.enabled);
                              
                              return PlaybackHeroCard(
                                isMini: false,
                                isLandscape: isLandscape,
                                screenWidth: screenWidth,
                                screenHeight: screenHeight,
                                isNext: isNext,
                                overrideProgress: _isScrubbingProgress ? _scrubProgress : null,
                                overridePosition: _isScrubbingProgress
                                    ? Duration(
                                        milliseconds: (_scrubProgress * (audio.duration.inMilliseconds)).round(),
                                      )
                                    : null,
                                showVisualizerToggle: isVisualizerEnabled,
                                onShowMoreMenu: () => _showMoreMenu(context, audio),
                                onCyclePlaylistMode: () => _cyclePlaylistMode(audio),
                                onShowPlaylistModeSelector: () =>
                                    _showPlaylistModeSelector(context, audio),
                                onShowRandomModeSelector: () =>
                                    _showRandomModeSelector(context, audio),
                                onScrubbing: (val) {
                                  _handleInteraction();
                                  setState(() {
                                    _isScrubbingProgress = true;
                                    _scrubProgress = val;
                                  });
                                },
                                onSeek: (val) {
                                  final target = Duration(
                                    milliseconds: (val * (audio.duration.inMilliseconds)).round(),
                                  );
                                  setState(() {
                                    _isScrubbingProgress = false;
                                    _scrubProgress = val;
                                  });
                                  audio.seek(target);
                                },
                                onToggleVisualizer: () => _toggleVisualizer(audio),
                                onEqualizerTap: () => _showEqualizerPanel(context),
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
                              );
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
                    if (backgroundType == 1)
                      const Positioned.fill(child: RepaintBoundary(child: DynamicMeshBackground()))
                    else
                      _buildBlurredBackground(context),
                    if (shouldDrawVisualizer) _buildVisualizerLayer(context, orientation),
                    content,
                    if (_showVolumeSlider)
                      Selector<AudioService, double>(
                        selector: (_, a) => a.volume,
                        builder: (context, volume, _) {
                          final audio = context.read<AudioService>();
                          return VolumeSliderOverlay(
                            volume: volume,
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
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),
    );
  }

  Widget _buildBlurredBackground(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: Stack(
          children: [
            Selector<AudioService, Uint8List?>(
              selector: (_, a) => a.currentBlurredArtworkBytes,
              builder: (context, blurredBytes, _) {
                final Widget content;
                if (blurredBytes == null) {
                  content = Container(
                    key: const ValueKey('bg_empty'),
                    color: Colors.black,
                    width: double.infinity,
                    height: double.infinity,
                  );
                } else {
                  content = Image.memory(
                    blurredBytes,
                    key: ValueKey(blurredBytes.hashCode),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  );
                }

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1200),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      ),
                      child: child,
                    );
                  },
                  child: content,
                );
              },
            ),
            // 静态暗化遮罩：避免在动画每一帧进行复杂的 BlendMode 计算
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualizerLayer(BuildContext context, Orientation orientation) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: StreamBuilder<FftFrame>(
          stream: context.read<AudioService>().player.visualizer.optimizedStream,
          builder: (context, snapshot) {
            final frame = snapshot.data;
            if (frame == null) return const SizedBox.shrink();

            return Selector<SettingsService, bool>(
              selector: (_, s) => s.isAutoMode, // Just pick something so it rebuilds on auto mode change
              builder: (context, _, __) {
                // Re-read settings more cleanly or use the data tuple
                final settings = context.read<SettingsService>();
                final audio = context.read<AudioService>();
                final isLandscape = orientation == Orientation.landscape;
                final gap = isLandscape ? settings.landscapeGap : settings.portraitGap;

                return CustomPaint(
                  painter: FftPainter(
                    values: frame.values,
                    gap: gap,
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
            );
          },
        ),
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
