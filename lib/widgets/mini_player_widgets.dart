import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/utils/playback_utils.dart';
import '../l10n/app_localizations.dart';

import 'song_thumbnail.dart';

class MiniArtwork extends ConsumerWidget {
  final double size;
  final double borderRadius;

  const MiniArtwork({
    super.key,
    this.size = 36.0,
    this.borderRadius = 6.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallbackWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[200],
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.music_note,
        color: isDark ? Colors.white : Colors.black54,
        size: (size * 0.55).clamp(16.0, 32.0),
      ),
    );

    if (currentMusic == null) {
      return fallbackWidget;
    }

    final audioService = ref.watch(audioServiceProvider);
    final memoryBytes = currentMusic.artworkBytes ??
        audioService.getCachedArtwork(currentMusic.path);

    final songForThumbnail = memoryBytes != null && memoryBytes.isNotEmpty
        ? currentMusic.copyWith(artworkBytes: memoryBytes)
        : currentMusic;

    return SongThumbnail.fromSong(
      songForThumbnail,
      key: ValueKey('${currentMusic.path}_${memoryBytes?.hashCode ?? 0}'),
      size: size,
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(borderRadius),
      fallbackWidget: fallbackWidget,
    );
  }
}

class MiniControlButton extends StatelessWidget {
  const MiniControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize = 24.0,
    this.padding = const EdgeInsets.all(6.0),
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = color ?? (isDark ? Colors.white : Colors.black87);
    final Widget buttonWidget = IconButton(
      icon: Icon(icon, color: iconColor, size: iconSize),
      padding: padding,
      constraints: const BoxConstraints(),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return AppTooltip(
        message: tooltip!,
        child: buttonWidget,
      );
    }

    return buttonWidget;
  }
}


class MiniInlineVolumeControl extends StatelessWidget {
  const MiniInlineVolumeControl({
    super.key,
    required this.volume,
    this.isMuted = false,
    required this.showSlider,
    required this.onTap,
    required this.onChanged,
    this.onScroll,
    this.tooltip,
    this.iconSize = 18.0,
  });

  final double volume;
  final bool isMuted;
  final bool showSlider;
  final VoidCallback? onTap;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onScroll;
  final String? tooltip;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final buttonTooltip = tooltip ?? l10n?.volume ?? 'Volume';

    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent && onScroll != null) {
          onScroll!(pointerSignal.scrollDelta.dy);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MiniControlButton(
            icon: getVolumeIcon(volume, isMuted: isMuted),
            onPressed: onTap,
            tooltip: buttonTooltip,
            iconSize: iconSize,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: showSlider
                ? SizedBox(
                    key: const ValueKey('mini-inline-volume-slider'),
                    width: 118,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                        inactiveTrackColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Colors.white24
                            : Colors.black12,
                        thumbColor:
                            Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                        overlayColor:
                            (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white
                                    : Colors.black)
                                .withValues(alpha: 0.15),
                      ),
                      child: Slider(
                        value: (isMuted ? 0.0 : volume).clamp(0.0, 100.0),
                        min: 0,
                        max: 100,
                        onChanged: onChanged,
                      ),
                    ),
                  )
                : const SizedBox(
                    key: ValueKey('mini-inline-volume-slider-collapsed'),
                  ),
          ),
        ],
      ),
    );
  }
}

class MiniSpectrumBackground extends ConsumerStatefulWidget {
  final AudioService audio;

  const MiniSpectrumBackground({super.key, required this.audio});

  @override
  ConsumerState<MiniSpectrumBackground> createState() =>
      _MiniSpectrumBackgroundState();
}

class _MiniSpectrumBackgroundState
    extends ConsumerState<MiniSpectrumBackground> {
  final ValueNotifier<List<double>> _fftNotifier =
      ValueNotifier<List<double>>(const []);
  StreamSubscription<FftFrame>? _subscription;

  @override
  void initState() {
    super.initState();
    _updateSubscription();
  }

  @override
  void didUpdateWidget(covariant MiniSpectrumBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audio != widget.audio) {
      _updateSubscription();
    }
  }

  void _updateSubscription({bool isPlaying = true}) {
    _subscription?.cancel();
    _subscription = null;
    if (!isPlaying) {
      _fftNotifier.value = const [];
      return;
    }
    final fftStream = widget.audio.miniPlayerFftStream;
    if (fftStream != null) {
      _subscription = fftStream.listen(
        (frame) {
          _fftNotifier.value = frame.values;
        },
        onError: (_) {
          _fftNotifier.value = const [];
        },
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _fftNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(audioIsPlayingProvider);
    if (!isPlaying) {
      if (_subscription != null) {
        _updateSubscription(isPlaying: false);
      }
      return const SizedBox.shrink();
    } else if (_subscription == null) {
      _updateSubscription(isPlaying: true);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 0.15 * 0.6 = 0.09：将原本在外层 Opacity(0.6) 产生的半透明效果内聚到画笔颜色中，
    // 彻底消除 GPU saveLayer 离屏渲染开销
    final color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.09);

    return ExcludeSemantics(
      excluding: true,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _MiniSpectrumPainter(
            listenable: _fftNotifier,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _MiniSpectrumPainter extends CustomPainter {
  final ValueListenable<List<double>> listenable;
  final Color color;

  _MiniSpectrumPainter({
    required this.listenable,
    required this.color,
  }) : super(repaint: listenable);

  @override
  void paint(Canvas canvas, Size size) {
    final values = listenable.value;
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;

    // displayCount 控制迷你播放器显示的频段（条形图）数量，80 根条形图视觉细腻
    const int displayCount = 80;
    final double barWidth = size.width / displayCount;
    const double gap = 3.0;
    final double actualBarWidth = math.max(1.0, barWidth - gap);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    final double samplingFactor = values.length / (displayCount * 1.5);

    for (int i = 0; i < displayCount; i++) {
      int index = (i * samplingFactor).floor();
      if (index >= values.length) index = values.length - 1;

      final double value = values[index];
      final double barHeight = (value * size.height * 1.2).clamp(3.0, size.height);
      final double x = i * barWidth + gap / 2;
      final double y = (size.height - barHeight) / 2;

      path.addRRect(
        RRect.fromRectXY(
          Rect.fromLTWH(x, y, actualBarWidth, barHeight),
          2.0,
          2.0,
        ),
      );
    }

    // 单次绘制所有条柱，大幅削减 Skia draw 指令
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniSpectrumPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
