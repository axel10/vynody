import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../player/audio_service.dart';

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
  Timer? _hudTimer;

  late AnimationController _animationController;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  void toNextMusic(AudioService audio) {
    audio.next();
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    // 1. 初始化控制器
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this, // 绑定心跳
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // 2. 设置动画曲线与路径
    _offsetAnimation =
        Tween<Offset>(
          begin: Offset.zero, // 初始位置（原位）
          end: const Offset(-1.0, 0.0), // 结束位置（向左滑出屏幕，-1.0 是滑出一个身位）
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeIn, // 设置动画曲线
          ),
        );
  }

  @override
  void dispose() {
    _hudTimer?.cancel();
    super.dispose();
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

  IconData _getVolumeIcon(double volume) {
    if (volume <= 0) return Icons.volume_mute;
    if (volume < 75) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioService>();

    if (audio.currentFilePath == null) {
      return const Center(
        child: Text('当前无播放内容', style: TextStyle(color: Colors.grey)),
      );
    }

    return OrientationBuilder(
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
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.black87,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildCoverImage(audio, isLandscape),
                ),
              );
            },
          ),
        );

        final controls = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            final delta = details.primaryDelta ?? 0;
            audio.setVolume(audio.volume - delta * 0.2);
            _triggerHUD();
          },
          child: Listener(
            onPointerSignal: (pointerSignal) {
              if (pointerSignal is PointerScrollEvent) {
                audio.setVolume(
                  audio.volume - pointerSignal.scrollDelta.dy * 0.1,
                );
                _triggerHUD();
              }
            },
            child: Column(
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
                    value: audio.progress,
                    onChanged: (val) {
                      final position = Duration(
                        milliseconds: (val * audio.duration.inMilliseconds)
                            .toInt(),
                      );
                      audio.seek(position);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(audio.position),
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
                        setState(() {
                          _showVisualizer = !_showVisualizer;
                        });
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
                    IconButton(
                      icon: Icon(
                        _getVolumeIcon(audio.volume),
                        size: 28,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _showVolumeSlider = !_showVolumeSlider;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
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
                        Expanded(flex: 4, child: albumArt),
                        const SizedBox(width: 32),
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(width: 450, child: controls),
                            ),
                          ),
                        ),
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
                if (audio.currentArtworkBytes != null ||
                    audio.currentArtworkPath != null)
                  Positioned.fill(
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
                  ),

                // Visualizer layer
                if (_showVisualizer)
                  Positioned.fill(
                    child: StreamBuilder<FftFrame>(
                      stream: audio.player.optimizedFftStream,
                      builder: (context, snapshot) {
                        final frame = snapshot.data;
                        if (frame == null) return const SizedBox.shrink();
                        return CustomPaint(
                          painter: FftPainter(
                            values: frame.values,
                            color: Colors.white.withValues(alpha: 0.2),
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
                                          child: Listener(
                                            onPointerSignal: (pointerSignal) {
                                              if (pointerSignal
                                                  is PointerScrollEvent) {
                                                audio.setVolume(
                                                  audio.volume -
                                                      pointerSignal
                                                              .scrollDelta
                                                              .dy *
                                                          0.1,
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
                                                    thumbColor: Colors.white,
                                                    overlayColor: Colors.white
                                                        .withValues(alpha: 0.2),
                                                  ),
                                              child: Slider(
                                                value: audio.volume,
                                                min: 0,
                                                max: 100,
                                                onChanged: (val) =>
                                                    audio.setVolume(val),
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final options = audio.player.visualOptions;

            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text('可视化设置', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildOptionSlider(
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
                    ),
                    _buildOptionSlider(
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
                    ),
                    _buildOptionSlider(
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
                    ),
                    _buildOptionSlider(
                      label: '对比度 (Contrast)',
                      value: options.groupContrastExponent,
                      min: 0.5,
                      max: 3.0,
                      onChanged: (val) {
                        audio.updateVisualOptions(
                          options.copyWith(groupContrastExponent: val),
                        );
                        setDialogState(() {});
                      },
                    ),
                    _buildOptionSlider(
                      label: '总体倍数',
                      value: options.overallMultiplier,
                      min: 0.1,
                      max: 10.0,
                      divisions: 99,
                      onChanged: (val) {
                        audio.updateVisualOptions(
                          options.copyWith(overallMultiplier: val),
                        );
                        setDialogState(() {});
                      },
                    ),

                    _buildOptionSlider(
                      label: '跳过高频',
                      value: options.skipHighFrequencyGroups.toDouble(),
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
                    ),
                    _buildOptionSlider(
                      label: '频率分组 (Frequency Groups)',
                      value: options.frequencyGroups.toDouble(),
                      min: 8,
                      max: 128,
                      divisions: 15,
                      onChanged: (val) {
                        audio.updateVisualOptions(
                          options.copyWith(frequencyGroups: val.toInt()),
                        );
                        setDialogState(() {});
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(
                        '聚合模式 (Aggregation Mode)',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    DropdownButtonFormField<FftAggregationMode>(
                      value: options.aggregationMode,
                      dropdownColor: Colors.grey[900],
                      decoration: const InputDecoration(
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white12),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                      items: FftAggregationMode.values.map((mode) {
                        return DropdownMenuItem(
                          value: mode,
                          child: Text(mode.name.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          audio.updateVisualOptions(
                            options.copyWith(aggregationMode: val),
                          );
                          setDialogState(() {});
                        }
                      },
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
                    '重置',
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
          ),
        ),
      ],
    );
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
      );
    } else if (audio.currentArtworkPath != null) {
      final file = File(audio.currentArtworkPath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
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
}

class FftPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  FftPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

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
