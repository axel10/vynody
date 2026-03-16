import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';
import '../widgets/waveform_progress_bar.dart';

const String playbackHeroTag = 'player_capsule';

// 鎾斁椤?
class PlaybackPage extends StatefulWidget {
  const PlaybackPage({super.key});

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage>
    with SingleTickerProviderStateMixin {
  bool _showVolumeHUD = false;
  bool _showVolumeSlider = false;
  bool _showVisualizer = true;
  bool _isScrubbingProgress = false;
  double _scrubProgress = 0.0;
  List<double> _waveform = [];
  String? _lastWaveformPath;
  Timer? _hudTimer;
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
    _hudTimer?.cancel();
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

  void _triggerHUD() {
    setState(() {
      _showVolumeHUD = true;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showVolumeHUD = false;
        });
      }
    });
  }

  void _adjustVolumeFromDrag(AudioService audio, double dragDelta) {
    audio.setVolume(audio.volume - dragDelta * 0.2);
    _triggerHUD();
  }

  void _adjustVolumeFromScroll(AudioService audio, double scrollDeltaY) {
    audio.setVolume(audio.volume - scrollDeltaY * 0.1);
    _triggerHUD();
  }

  Future<void> _updateWaveform(AudioService audio) async {
    final path = audio.currentFilePath;
    if (path == null || path == _lastWaveformPath) return;

    _lastWaveformPath = path;
    // Request 80 chunks for the waveform visualization
    final waveform = await audio.getWaveform(
      expectedChunks: 80,
      sampleStride: 3,
    );
    if (mounted && path == audio.currentFilePath) {
      setState(() {
        _waveform = waveform;
      });
    }
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
          title: const Text('閫夋嫨鎾斁妯″紡'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlaylistMode.values.map((mode) {
              return ListTile(
                leading: Icon(_getPlaylistModeIcon(mode)),
                title: Text(_getPlaylistModeName(mode)),
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

  IconData _getPlaylistModeIcon(PlaylistMode mode) {
    switch (mode) {
      case PlaylistMode.single:
        return Icons.looks_one_outlined;
      case PlaylistMode.singleLoop:
        return Icons.repeat_one_rounded;
      case PlaylistMode.queue:
        return Icons.reorder_rounded;
      case PlaylistMode.queueLoop:
        return Icons.repeat_rounded;
      case PlaylistMode.autoQueueLoop:
        return Icons.all_inclusive_rounded;
    }
  }

  String _getPlaylistModeName(PlaylistMode mode) {
    switch (mode) {
      case PlaylistMode.single:
        return '鍗曟洸鎾斁';
      case PlaylistMode.singleLoop:
        return '鍗曟洸寰幆';
      case PlaylistMode.queue:
        return '闃熷垪鎾斁';
      case PlaylistMode.queueLoop:
        return '闃熷垪寰幆';
      case PlaylistMode.autoQueueLoop:
        return '鑷姩闃熷垪寰幆';
    }
  }

  IconData _getVolumeIcon(double volume) {
    if (volume <= 0) return Icons.volume_mute;
    if (volume < 75) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();
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
      return const Center(
        child: Text('当前没有播放内容', style: TextStyle(color: Colors.grey)),
      );
    }

    final currentIndex = audio.currentIndex;
    if (_lastIndex != null && currentIndex != _lastIndex) {
      if (_lastIndex == 0 && currentIndex > 1) {
        // 鍚戝墠寰幆
        _isNext = false;
      } else if (currentIndex == 0 && _lastIndex! > 1) {
        // 鍚戝悗寰幆
        _isNext = true;
      } else {
        _isNext = currentIndex > _lastIndex!;
      }
    }
    _lastIndex = currentIndex;

    _updateWaveform(audio);

    return Listener(
      onPointerDown: (event) {
        _handleInteraction();
      },
      onPointerMove: (event) {
        _handleInteraction();
      },
      onPointerHover: (event) {
        _handleInteraction();
      },
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
                        waveform: _waveform,
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

          return ClipRect(
            child: Container(
              color: Colors.black,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Blurred Background
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 800),
                      child:
                          (audio.currentArtworkBytes != null ||
                              audio.currentArtworkPath != null)
                          ? KeyedSubtree(
                              key: ValueKey(audio.currentFilePath ?? 'bg_art'),
                              child: Transform.scale(
                                scale: 1.1, // Slight scale for safety
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
                                            ? MemoryImage(
                                                audio.currentArtworkBytes!,
                                              )
                                            : FileImage(
                                                    File(
                                                      audio.currentArtworkPath!,
                                                    ),
                                                  )
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
                          : Container(
                              key: const ValueKey('bg_empty'),
                              color: Colors.black, // 閫€搴曢鑹诧紝闃叉闂儊
                            ),
                    ),
                  ),

                  // Visualizer layer
                  if (_showVisualizer)
                    Positioned.fill(
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
                                  ? (audio.dynamicStartColor ??
                                        settings.visualizerColor)
                                  : settings.visualizerColor,
                              opacity: settings.visualizerOpacity,
                              useGradient: settings.isVisualizerGradientEnabled,
                              startColor: settings.isVisualizerDynamicStartColor
                                  ? (audio.dynamicStartColor ??
                                        settings.visualizerStartColor)
                                  : settings.visualizerStartColor,
                              endColor: settings.isVisualizerDynamicEndColor
                                  ? (audio.dynamicEndColor ??
                                        settings.visualizerEndColor)
                                  : settings.visualizerEndColor,
                              gradientStop1: settings.visualizerGradientStop1,
                              gradientStop2: settings.visualizerGradientStop2,
                              gradientTileMode:
                                  settings.visualizerGradientTileMode,
                            ),
                          );
                        },
                      ),
                    ),

                  content,
                  if (_showVolumeSlider)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _showVolumeSlider = false),
                        child: Container(
                          color: Colors.transparent,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: isLandscape ? 100 : 160,
                                  ),
                                  child: GestureDetector(
                                    onTap: () {}, // Prevent dismissal
                                    child: Container(
                                      width: 300,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(30),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 10,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _getVolumeIcon(audio.volume),
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onVerticalDragUpdate: (details) {
                                                _handleInteraction();
                                                _adjustVolumeFromDrag(
                                                  audio,
                                                  details.primaryDelta ?? 0,
                                                );
                                              },
                                              child: Listener(
                                                onPointerSignal: (pointerSignal) {
                                                  if (pointerSignal
                                                      is PointerScrollEvent) {
                                                    _handleInteraction();
                                                    _adjustVolumeFromScroll(
                                                      audio,
                                                      pointerSignal
                                                          .scrollDelta
                                                          .dy,
                                                    );
                                                  }
                                                },
                                                child: SliderTheme(
                                                  data: SliderTheme.of(context)
                                                      .copyWith(
                                                        activeTrackColor:
                                                            Colors.white,
                                                        inactiveTrackColor:
                                                            Colors.white24,
                                                        thumbColor:
                                                            Colors.white,
                                                        overlayColor: Colors
                                                            .white
                                                            .withValues(
                                                              alpha: 0.2,
                                                            ),
                                                      ),
                                                  child: Slider(
                                                    value: audio.volume,
                                                    min: 0,
                                                    max: 100,
                                                    onChanged: (val) {
                                                      _handleInteraction();
                                                      audio.setVolume(val);
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${audio.volume.round()}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_showVolumeHUD)
                    Positioned(
                      top: 100,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                audio.volume > 0
                                    ? Icons.volume_up
                                    : Icons.volume_off,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '闊抽噺',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${audio.volume.toInt()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMoreMenu(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('鎾斁閫夐」', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.settings_input_component,
                color: Colors.blueAccent,
              ),
              title: const Text(
                '设置频谱显示',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _showVisualizerOptions(context, audio);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showVisualizerOptions(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final options = audio.player.visualOptions;
              final settings = context.watch<SettingsService>();

              return AlertDialog(
                backgroundColor: Colors.grey[900],
                title: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('可视化设置', style: TextStyle(color: Colors.white)),
                    SizedBox(height: 10),
                    TabBar(
                      tabs: [
                        Tab(text: '绠楁硶'),
                        Tab(text: '澶栬'),
                      ],
                      labelColor: Colors.blueAccent,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.blueAccent,
                      dividerColor: Colors.transparent,
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 600, // 璁剧疆涓€涓悎閫傜殑瀹藉害
                  height: 400,
                  child: TabBarView(
                    children: [
                      SingleChildScrollView(
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '骞虫粦绯绘暟 (Smoothing)',
                                value: options.smoothingCoefficient,
                                min: 0.0,
                                max: 0.99,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(smoothingCoefficient: val),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '閲嶅姏绯绘暟 (Gravity)',
                                value: options.gravityCoefficient,
                                min: 0.1,
                                max: 5.0,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(gravityCoefficient: val),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '瀵规暟缂╂斁 (Log Scale)',
                                value: options.logarithmicScale,
                                min: 1.0,
                                max: 5.0,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(logarithmicScale: val),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '瀵规瘮搴?(Contrast)',
                                value: options.groupContrastExponent,
                                min: 0.5,
                                max: 3.0,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(
                                      groupContrastExponent: val,
                                    ),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '褰掍竴鍖?(Normalization)',
                                value: options.normalizationFloorDb,
                                min: -100.0,
                                max: 0.0,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(normalizationFloorDb: val),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '鎬诲鐩?(Multiplier)',
                                value: options.overallMultiplier,
                                min: 0.5,
                                max: 5.0,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(overallMultiplier: val),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '璺宠繃楂橀',
                                value: options.skipHighFrequencyGroups
                                    .toDouble(),
                                min: 0,
                                max: 20,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(
                                      skipHighFrequencyGroups: val.toInt(),
                                    ),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: _buildOptionSlider(
                                label: '棰戠巼鍒嗙粍 (Frequency Groups)',
                                value: options.frequencyGroups.toDouble(),
                                min: 8,
                                max: 512,
                                divisions: 15,
                                onChanged: (val) {
                                  audio.updateVisualOptions(
                                    options.copyWith(
                                      frequencyGroups: val.toInt(),
                                    ),
                                  );
                                  setDialogState(() {});
                                },
                                onChangeEnd: () =>
                                    audio.saveVisualizerOptions(),
                              ),
                            ),
                            SizedBox(
                              width: 270,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(
                                      top: 16,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      '鑱氬悎妯″紡 (Aggregation Mode)',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DropdownButtonFormField<FftAggregationMode>(
                                    value: options.aggregationMode,
                                    dropdownColor: Colors.grey[900],
                                    decoration: const InputDecoration(
                                      enabledBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: Colors.white12,
                                        ),
                                      ),
                                    ),
                                    style: const TextStyle(color: Colors.white),
                                    items: FftAggregationMode.values.map((
                                      mode,
                                    ) {
                                      return DropdownMenuItem(
                                        value: mode,
                                        child: Text(mode.name.toUpperCase()),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        audio.updateVisualOptions(
                                          options.copyWith(
                                            aggregationMode: val,
                                          ),
                                        );
                                        setDialogState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SingleChildScrollView(
                        child: _buildAppearanceOptions(
                          context,
                          settings,
                          setDialogState,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      audio.updateVisualOptions(
                        const VisualizerOptimizationOptions(),
                      );
                      setDialogState(() {});
                    },
                    child: const Text(
                      '閲嶇疆绠楁硶',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      context
                          .read<SettingsService>()
                          .resetVisualizerAppearance();
                      setDialogState(() {});
                    },
                    child: const Text(
                      '閲嶇疆澶栬',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '纭畾',
                      style: TextStyle(color: Colors.blueAccent),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAppearanceOptions(
    BuildContext context,
    SettingsService settings,
    StateSetter setDialogState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildOptionSlider(
          label: '閫忔槑搴?(Opacity)',
          value: settings.visualizerOpacity,
          min: 0.0,
          max: 1.0,
          onChanged: (val) {
            settings.visualizerOpacity = val;
            setDialogState(() {});
          },
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text(
            '启用渐变色',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          value: settings.isVisualizerGradientEnabled,
          activeColor: Colors.blueAccent,
          onChanged: (val) {
            settings.isVisualizerGradientEnabled = val;
            setDialogState(() {});
          },
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        if (settings.isVisualizerGradientEnabled) ...[
          _buildColorPickerRow(
            context,
            label: '璧峰棰滆壊',
            color: settings.visualizerStartColor,
            isDynamic: settings.isVisualizerDynamicStartColor,
            onDynamicChanged: (val) {
              settings.isVisualizerDynamicStartColor = val;
              if (val) {
                context.read<AudioService>().updateDynamicColors();
              }
              setDialogState(() {});
            },
            onColorChanged: (c) {
              settings.visualizerStartColor = c;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          _buildColorPickerRow(
            context,
            label: '缁撴潫棰滆壊',
            color: settings.visualizerEndColor,
            isDynamic: settings.isVisualizerDynamicEndColor,
            onDynamicChanged: (val) {
              settings.isVisualizerDynamicEndColor = val;
              if (val) {
                context.read<AudioService>().updateDynamicColors();
              }
              setDialogState(() {});
            },
            onColorChanged: (c) {
              settings.visualizerEndColor = c;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          _buildOptionSlider(
            label: '娓愬彉鑼冨洿 Stop 1',
            value: settings.visualizerGradientStop1,
            min: 0.0,
            max: 1.0,
            onChanged: (val) {
              settings.visualizerGradientStop1 = val;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          _buildOptionSlider(
            label: '娓愬彉鑼冨洿 Stop 2',
            value: settings.visualizerGradientStop2,
            min: 0.0,
            max: 1.0,
            onChanged: (val) {
              settings.visualizerGradientStop2 = val;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                '娓愬彉閲嶅妯″紡 (TileMode)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(width: 16),
              DropdownButton<int>(
                value: settings.visualizerGradientTileMode,
                dropdownColor: Colors.grey[800],
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (int? newValue) {
                  if (newValue != null) {
                    settings.visualizerGradientTileMode = newValue;
                    setDialogState(() {});
                  }
                },
                items: TileMode.values.map<DropdownMenuItem<int>>((
                  TileMode mode,
                ) {
                  return DropdownMenuItem<int>(
                    value: mode.index,
                    child: Text(mode.name),
                  );
                }).toList(),
              ),
            ],
          ),
        ] else ...[
          _buildColorPickerRow(
            context,
            label: '绾壊',
            color: settings.visualizerColor,
            isDynamic: settings.isVisualizerDynamicColor,
            onDynamicChanged: (val) {
              settings.isVisualizerDynamicColor = val;
              if (val) {
                context.read<AudioService>().updateDynamicColors();
              }
              setDialogState(() {});
            },
            onColorChanged: (c) {
              settings.visualizerColor = c;
              setDialogState(() {});
            },
          ),
        ],
      ],
    );
  }

  Widget _buildColorPickerRow(
    BuildContext context, {
    required String label,
    required Color color,
    required ValueChanged<Color> onColorChanged,
    bool isDynamic = false,
    ValueChanged<bool>? onDynamicChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(width: 16),
            if (!isDynamic)
              InkWell(
                onTap: () => _pickColor(context, color, onColorChanged),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: Colors.white70, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
        if (onDynamicChanged != null)
          Row(
            children: [
              const Text(
                '跟随封面变色',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Switch(
                value: isDynamic,
                activeTrackColor: Colors.blueAccent,
                onChanged: onDynamicChanged,
              ),
            ],
          ),
      ],
    );
  }

  void _pickColor(
    BuildContext context,
    Color initialColor,
    ValueChanged<Color> onColorChanged,
  ) {
    Color selectedColor = initialColor;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('閫夋嫨棰滆壊', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: initialColor,
              onColorChanged: (c) => selectedColor = c,
              pickerAreaHeightPercent: 0.8,
              enableAlpha: false,
              displayThumbColor: true,
              paletteType: PaletteType.hsv,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('鍙栨秷', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                onColorChanged(selectedColor);
                Navigator.pop(context);
              },
              child: const Text(
                '纭畾',
                style: TextStyle(color: Colors.blueAccent),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptionSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
    VoidCallback? onChangeEnd,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            '$label: ${value.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        SliderTheme(
          data: const SliderThemeData(
            activeTrackColor: Colors.blueAccent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.blueAccent,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: (val) => onChangeEnd?.call(),
          ),
        ),
      ],
    );
  }
}

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
          _MiniArtwork(audio: audio),
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
          const SizedBox(width: 12),
          _MiniControlButton(
            icon: Icons.skip_previous_rounded,
            onPressed: onPrevious,
          ),
          const SizedBox(width: 8),
          _MiniControlButton(
            icon: audio.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            onPressed: onPlayPause,
          ),
          const SizedBox(width: 8),
          _MiniControlButton(icon: Icons.skip_next_rounded, onPressed: onNext),
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (Widget child, Animation<double> animation) {
                final inAnimation =
                    Tween<Offset>(
                      begin: isNext
                          ? const Offset(0.7, 0.0)
                          : const Offset(-0.7, 0.0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeOut),
                    );
                final outAnimation =
                    Tween<Offset>(
                      begin: isNext
                          ? const Offset(-0.7, 0.0)
                          : const Offset(0.7, 0.0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeIn),
                    );

                final isEntering = child.key == ValueKey(audio.currentFilePath);
                return SlideTransition(
                  position: isEntering ? inAnimation : outAnimation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(audio.currentFilePath),
                child: Container(
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
                  clipBehavior: Clip.antiAlias,
                  child: _buildCoverImage(audio, isLandscape),
                ),
              ),
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
                  _playlistModeIcon(audio.player.playlistMode),
                  size: 28,
                  color: Colors.white70,
                ),
                onPressed: onCyclePlaylistMode,
                tooltip: _playlistModeName(audio.player.playlistMode),
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
                _formatDuration(previewPosition),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _formatDuration(audio.duration),
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
                    _volumeIcon(audio.volume),
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

class _MiniArtwork extends StatelessWidget {
  const _MiniArtwork({required this.audio});

  final AudioService audio;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        image: audio.currentArtworkBytes != null
            ? DecorationImage(
                image: MemoryImage(audio.currentArtworkBytes!),
                fit: BoxFit.cover,
              )
            : audio.currentArtworkPath != null
            ? DecorationImage(
                image: FileImage(File(audio.currentArtworkPath!)),
                fit: BoxFit.cover,
              )
            : null,
        color: Colors.grey[900],
      ),
      child:
          (audio.currentArtworkBytes == null &&
              audio.currentArtworkPath == null)
          ? const Icon(Icons.music_note, color: Colors.white, size: 20)
          : null,
    );
  }
}

class _MiniControlButton extends StatelessWidget {
  const _MiniControlButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 24),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
    );
  }
}

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, "0")}';
}

IconData _playlistModeIcon(PlaylistMode mode) {
  switch (mode) {
    case PlaylistMode.single:
      return Icons.looks_one_outlined;
    case PlaylistMode.singleLoop:
      return Icons.repeat_one_rounded;
    case PlaylistMode.queue:
      return Icons.reorder_rounded;
    case PlaylistMode.queueLoop:
      return Icons.repeat_rounded;
    case PlaylistMode.autoQueueLoop:
      return Icons.all_inclusive_rounded;
  }
}

String _playlistModeName(PlaylistMode mode) {
  switch (mode) {
    case PlaylistMode.single:
      return 'Single';
    case PlaylistMode.singleLoop:
      return 'Single Loop';
    case PlaylistMode.queue:
      return 'Queue';
    case PlaylistMode.queueLoop:
      return 'Queue Loop';
    case PlaylistMode.autoQueueLoop:
      return 'Auto Queue Loop';
  }
}

IconData _volumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_mute;
  if (volume < 75) return Icons.volume_down;
  return Icons.volume_up;
}

Widget _buildCoverImage(AudioService audio, bool isLandscape) {
  if (audio.currentArtworkBytes != null) {
    return Image.memory(
      audio.currentArtworkBytes!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
    );
  } else if (audio.currentArtworkPath != null) {
    final file = File(audio.currentArtworkPath!);
    if (file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      );
    }
  }

  return Center(
    child: Container(
      width: isLandscape ? 60 : 80,
      height: isLandscape ? 60 : 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Icon(
        Icons.music_note,
        size: isLandscape ? 30 : 40,
        color: Colors.white54,
      ),
    ),
  );
}

class FftPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double opacity;
  final bool useGradient;
  final Color? startColor;
  final Color? endColor;
  final double? gradientStop1;
  final double? gradientStop2;
  final int? gradientTileMode;

  FftPainter({
    required this.values,
    required this.color,
    this.opacity = 0.2,
    this.useGradient = false,
    this.startColor,
    this.endColor,
    this.gradientStop1,
    this.gradientStop2,
    this.gradientTileMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    if (useGradient && startColor != null && endColor != null) {
      paint.shader = LinearGradient(
        colors: [
          startColor!.withOpacity(opacity),
          endColor!.withOpacity(opacity),
        ],
        stops: gradientStop1 != null && gradientStop2 != null
            ? [gradientStop1!, gradientStop2!]
            : null,
        tileMode: gradientTileMode != null
            ? TileMode.values[gradientTileMode!]
            : TileMode.clamp,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    }

    final barCount = values.length;
    final gap = 2.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (size.width - totalGap) / barCount;

    for (var i = 0; i < barCount; i++) {
      final barHeight = values[i] * size.height * 0.5;
      final x = i * (barWidth + gap);
      final y = size.height - barHeight;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FftPainter oldDelegate) => true;
}
