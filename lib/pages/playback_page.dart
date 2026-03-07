import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../player/audio_service.dart';

// 播放页
class PlaybackPage extends StatefulWidget {
  const PlaybackPage({super.key});

  @override
  State<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends State<PlaybackPage> {
  bool _showVolumeHUD = false;
  bool _showVolumeSlider = false;
  Timer? _hudTimer;

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

        final isLargeCover =
            (audio.artworkWidth ?? 0) >= 640 ||
            (audio.artworkHeight ?? 0) >= 640;
        final screenWidth = MediaQuery.of(context).size.width;

        final double baseSize = isLandscape ? 260 : 300;
        final double maxDisplaySize = isLargeCover
            ? (isLandscape ? 600 : 500)
            : baseSize;

        final albumArt = AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.black87,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
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
              crossAxisAlignment: isLandscape
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Text(
                  audio.currentFileName ?? '未知',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: isLandscape ? TextAlign.left : TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isLandscape ? 24 : 48),
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
                      icon: const Icon(
                        Icons.skip_previous_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                      onPressed: () {},
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
                      onPressed: () {},
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
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxDisplaySize,
                          maxHeight: maxDisplaySize,
                        ),
                        child: albumArt,
                      ),
                    ),
                  ),
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
          );
        } else {
          content = SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: maxDisplaySize,
                          maxHeight: maxDisplaySize,
                        ),
                        child: albumArt,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(width: screenWidth - 48, child: controls),
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
                                          color: Colors.black.withOpacity(0.3),
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
                                                        .withOpacity(0.2),
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, "0")}';
  }

  Widget _buildCoverImage(AudioService audio, bool isLandscape) {
    if (audio.currentArtworkBytes != null) {
      return Image.memory(audio.currentArtworkBytes!, fit: BoxFit.cover);
    } else if (audio.currentArtworkPath != null) {
      final file = File(audio.currentArtworkPath!);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    }

    return Center(
      child: Container(
        width: isLandscape ? 60 : 80,
        height: isLandscape ? 60 : 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
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
