import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import '../player/audio_riverpod.dart';
import '../player/audio_service.dart';

class MiniArtwork extends ConsumerWidget {
  const MiniArtwork({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        image: currentMusic?.artworkBytes != null
            ? DecorationImage(
                image: MemoryImage(currentMusic!.artworkBytes!),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
            : currentMusic?.artworkPath != null
            ? DecorationImage(
                image: FileImage(File(currentMusic!.artworkPath!)),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              )
            : null,
        color: Colors.grey[900],
      ),
      child:
          (currentMusic?.artworkBytes == null &&
              currentMusic?.artworkPath == null)
          ? const Icon(Icons.music_note, color: Colors.white, size: 20)
          : null,
    );
  }
}

class MiniControlButton extends StatelessWidget {
  const MiniControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 24),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

class MiniSpectrumBackground extends ConsumerWidget {
  final AudioService audio;

  const MiniSpectrumBackground({super.key, required this.audio});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 使用独立的 FFT 流（专用于迷你播放器）
    final fftStream = audio.miniPlayerFftStream;
    if (fftStream == null) return const SizedBox.shrink();
    final isPlaying = ref.watch(audioIsPlayingProvider);

    return StreamBuilder<FftFrame>(
      stream: fftStream,
      builder: (context, snapshot) {
        final frame = snapshot.data;
        if (frame == null || !isPlaying) return const SizedBox.shrink();
        return RepaintBoundary(
          child: CustomPaint(
            painter: _MiniSpectrumPainter(
              values: frame.values,
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
        );
      },
    );
  }
}

class _MiniSpectrumPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _MiniSpectrumPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // displayCount 控制迷你播放器显示的频段（条形图）数量
    // 增加此数值会让频谱更细腻，减小则更简约
    const int displayCount = 64;
    final double barWidth = size.width / displayCount;
    const double gap = 3.0;

    for (int i = 0; i < displayCount; i++) {
      // 从频率数据中采样
      // 这里将采样范围限制在低中频段（values.length / 1.5），因为这些频段的跳动在视觉上更活跃
      int index = (i * values.length / (displayCount * 1.5)).floor();
      if (index >= values.length) index = values.length - 1;

      double value = values[index];

      // Amplify and clamp height
      double barHeight = (value * size.height * 1.2).clamp(3.0, size.height);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * barWidth + gap / 2,
            (size.height - barHeight) / 2, // Symmetric vertical centering
            barWidth - gap,
            barHeight,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniSpectrumPainter oldDelegate) => true;
}
