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

// 播放页
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

  @override
  void dispose() {
    _hudTimer?.cancel();
    _inactivityTimer?.cancel();
    context.read<SettingsService>().isUserInactive = false;
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

  Future<void> _toggleVisualizer(AudioService audio) async {
    final nextVisible = !_showVisualizer;
    setState(() {
      _showVisualizer = nextVisible;
    });
    await audio.player.setFftEnabled(nextVisible);
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
        child: Text('当前无播放内容', style: TextStyle(color: Colors.grey)),
      );
    }

    final currentIndex = audio.currentIndex;
    if (_lastIndex != null && currentIndex != _lastIndex) {
      if (_lastIndex == 0 && currentIndex > 1) {
        // 向前循环
        _isNext = false;
      } else if (currentIndex == 0 && _lastIndex! > 1) {
        // 向后循环
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

          // Use a generous maximum size based on screen dimensions
          final double maxDisplaySize = isLandscape
              ? screenHeight * 0.75
              : screenWidth * 0.85;

          final albumArt = Center(
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
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          final inAnimation =
                              Tween<Offset>(
                                begin: _isNext
                                    ? const Offset(0.7, 0.0)
                                    : const Offset(-0.7, 0.0),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOut,
                                ),
                              );
                          final outAnimation =
                              Tween<Offset>(
                                begin: _isNext
                                    ? const Offset(-0.7, 0.0)
                                    : const Offset(0.7, 0.0),
                                end: Offset.zero,
                              ).animate(
                                CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeIn,
                                ),
                              );

                          final isEntering =
                              child.key == ValueKey(audio.currentFilePath);
                          return SlideTransition(
                            position: isEntering ? inAnimation : outAnimation,
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
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
                              // offset: const Offset(0, 5),
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

          final controls = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isLandscape ? 450 : screenWidth * 0.9,
                ),
                child: Text(
                  audio.currentFileName ?? '未知',
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
              // Top menu bar for secondary controls
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.shrink(), // Placeholder if needed
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.more_horiz, color: Colors.white70),
                    onPressed: () => _showMoreMenu(context, audio),
                    tooltip: '更多选项',
                  ),
                ],
              ),
              SizedBox(height: isLandscape ? 8 : 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: sliderProgress,
                  onChangeStart: (val) {
                    _handleInteraction();
                    setState(() {
                      _isScrubbingProgress = true;
                      _scrubProgress = val;
                    });
                  },
                  onChanged: (val) {
                    setState(() {
                      _isScrubbingProgress = true;
                      _scrubProgress = val;
                    });
                  },
                  onChangeEnd: (val) {
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(previewPosition),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      _formatDuration(audio.duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
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
                      _showVisualizer
                          ? Icons.analytics
                          : Icons.analytics_outlined,
                      size: 28,
                      color: _showVisualizer ? Colors.white : Colors.white70,
                    ),
                    onPressed: () {
                      _toggleVisualizer(audio);
                    },
                    tooltip: '音频可视化',
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(
                      Icons.skip_previous_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                    onPressed: audio.previous,
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
                      onPressed: audio.togglePlay,
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
                    // onPressed: audio.next,
                    onPressed: () => toNextMusic(audio),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      _handleInteraction();
                      _adjustVolumeFromDrag(audio, details.primaryDelta ?? 0);
                    },
                    child: Listener(
                      onPointerSignal: (pointerSignal) {
                        if (pointerSignal is PointerScrollEvent) {
                          _handleInteraction();
                          _adjustVolumeFromScroll(
                            audio,
                            pointerSignal.scrollDelta.dy,
                          );
                        }
                      },
                      child: IconButton(
                        icon: Icon(
                          _getVolumeIcon(audio.volume),
                          size: 28,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          _handleInteraction();
                          setState(() {
                            _showVolumeSlider = !_showVolumeSlider;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );

          Widget content;
          if (isLandscape) {
            content = SafeArea(
              child: Column(
                children: [
                  if (Platform.isWindows) const SizedBox(height: 32),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Row(
                        children: [
                          const Spacer(flex: 1),
                          Expanded(flex: 8, child: albumArt),
                          const SizedBox(width: 48),
                          Expanded(
                            flex: 10,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(width: 450, child: controls),
                              ),
                            ),
                          ),
                          const Spacer(flex: 1),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          } else {
            content = SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    if (Platform.isWindows) const SizedBox(height: 32),
                    Expanded(child: albumArt),
                    const SizedBox(height: 24),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(width: screenWidth, child: controls),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

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
                                          Colors.black.withValues(alpha: 0.2),
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
                              color: Colors.black, // 退底颜色，防止闪烁
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
                              color: settings.visualizerColor,
                              opacity: settings.visualizerOpacity,
                              useGradient: settings.isVisualizerGradientEnabled,
                              startColor: settings.visualizerStartColor,
                              endColor: settings.visualizerEndColor,
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
                                    '音量',
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
        title: const Text('播放选项', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.settings_input_component,
                color: Colors.blueAccent,
              ),
              title: const Text(
                '设置音频可视化',
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
                        Tab(text: '算法'),
                        Tab(text: '外观'),
                      ],
                      labelColor: Colors.blueAccent,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.blueAccent,
                      dividerColor: Colors.transparent,
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 600, // 设置一个合适的宽度
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
                                label: '平滑系数 (Smoothing)',
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
                                label: '重力系数 (Gravity)',
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
                                label: '对数缩放 (Log Scale)',
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
                                label: '对比度 (Contrast)',
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
                                label: '总增益 (Multiplier)',
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
                                label: '跳过高频',
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
                                label: '频率分组 (Frequency Groups)',
                                value: options.frequencyGroups.toDouble(),
                                min: 8,
                                max: 128,
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
                                      '聚合模式 (Aggregation Mode)',
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
                      '重置算法',
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
                      '重置外观',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '确定',
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
          label: '透明度 (Opacity)',
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
            label: '起始颜色',
            color: settings.visualizerStartColor,
            onColorChanged: (c) {
              settings.visualizerStartColor = c;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          _buildColorPickerRow(
            context,
            label: '结束颜色',
            color: settings.visualizerEndColor,
            onColorChanged: (c) {
              settings.visualizerEndColor = c;
              setDialogState(() {});
            },
          ),
          const SizedBox(height: 16),
          _buildOptionSlider(
            label: '渐变范围 Stop 1',
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
            label: '渐变范围 Stop 2',
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
                '渐变重复模式 (TileMode)',
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
            label: '纯色',
            color: settings.visualizerColor,
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
  }) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
        const SizedBox(width: 16),
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
          title: const Text('选择颜色', style: TextStyle(color: Colors.white)),
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
              child: const Text('取消', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                onColorChanged(selectedColor);
                Navigator.pop(context);
              },
              child: const Text(
                '确定',
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

String _formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, "0")}';
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
