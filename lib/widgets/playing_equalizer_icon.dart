import 'dart:async';
import 'dart:math' as math;

import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';

/// 柱条数量。
const int _kBarCount = 4;

/// 相对总宽：4 根柱 + 3 段间距。1/6.4 让 16px 图标里柱宽约 2.5px。
const double _kBarWidthFactor = 6.4;

/// 静音/暂停时的静态柱高比例，避免图标看起来像四个等宽方块。
const List<double> _kIdleHeights = [0.32, 0.62, 0.4, 0.52];

/// 从 FFT 频段里挑 4 个代表点的比例位置。
/// 低频能量最集中，也最贴近「跟着鼓点跳」的观感，所以集中在前 1/3。
const List<double> _kSampleRatios = [0.02, 0.09, 0.20, 0.36];

/// 柱条最小高度比例：静音时留一点存在感，而不是彻底消失。
const double _kMinBarRatio = 0.18;

/// 列表 / 队列中「当前播放」行的指示图标。
///
/// 优先订阅迷你播放器那一路真实 FFT 流（`AudioService.miniPlayerFftStream`），
/// 用 4 根垂直居中的柱条随音乐跳动；拿不到 FFT 数据时（未解锁 Pro、窗口最小化、
/// 音频内核尚未就绪）退回本地正弦动画，保证标识始终可见、始终有动感。
///
/// 数据路径刻意不走 setState / AnimatedBuilder：FFT 以 60Hz 输出，列表行
/// 若整行重建会直接吃掉滚动性能。这里用 [ValueNotifier] + `CustomPainter`
/// 的 `repaint` 增量重绘，外层再包 [RepaintBoundary] 把脏区限制在这个小图标内。
class PlayingEqualizerIcon extends ConsumerStatefulWidget {
  const PlayingEqualizerIcon({
    super.key,
    required this.color,
    this.size = 16.0,
    this.isPlaying = true,
  });

  final Color color;
  final double size;
  final bool isPlaying;

  @override
  ConsumerState<PlayingEqualizerIcon> createState() =>
      _PlayingEqualizerIconState();
}

class _PlayingEqualizerIconState extends ConsumerState<PlayingEqualizerIcon>
    with SingleTickerProviderStateMixin {
  /// 正弦兜底动画。`late final` 声明 + initState 赋值：声明处初始化会在
  /// dispose 时才首次求值，届时 `vsync: this` 取不到已 deactivate 的 element。
  late final AnimationController _fallback;

  /// 当前 4 根柱的高度比例；为空表示还没有拿到过真实 FFT 帧。
  final ValueNotifier<List<double>> _heights = ValueNotifier(const []);
  final List<double> _smoothed = List<double>.filled(_kBarCount, 0.0);

  StreamSubscription<FftFrame>? _fftSubscription;
  int _retryCount = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _fallback = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _syncFallback();
    _subscribeFft();
  }

  @override
  void didUpdateWidget(covariant PlayingEqualizerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      _syncFallback();
    }
  }

  /// 音频服务的可视化输出在首次 snapshot 之后才创建，这里允许前几帧重试。
  void _subscribeFft() {
    if (_disposed) return;

    Stream<FftFrame>? stream;
    try {
      stream = ref.read(audioServiceProvider).miniPlayerFftStream;
    } catch (_) {
      stream = null;
    }

    if (stream == null) {
      // 最多等约 3 秒，之后彻底退回正弦兜底，避免每帧无限重试。
      if (_retryCount++ > 180) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeFft());
      return;
    }

    _fftSubscription = stream.listen(
      _onFftFrame,
      onError: (Object _) {
        // 单帧异常不影响后续帧，保持最后一帧高度即可。
      },
    );
  }

  void _onFftFrame(FftFrame frame) {
    if (_disposed) return;
    final values = frame.values;
    if (values.isEmpty) return;

    final length = values.length;
    final next = List<double>.filled(_kBarCount, 0.0);
    for (var i = 0; i < _kBarCount; i++) {
      final index = (length * _kSampleRatios[i]).floor().clamp(0, length - 1);
      final target = values[index].clamp(0.0, 1.0);
      final previous = _smoothed[i];
      // 快攻慢放：原始帧在 60Hz 下抖得很快，直接画会像噪点闪烁。
      final rate = target > previous ? 0.6 : 0.16;
      final value = previous + (target - previous) * rate;
      _smoothed[i] = value;
      next[i] = value;
    }

    _heights.value = next;

    // 已经拿到真实数据，正弦兜底可以停掉，省一条每帧的 Ticker。
    if (_fallback.isAnimating) {
      _fallback.stop();
    }
  }

  void _syncFallback() {
    final needsFallback = widget.isPlaying && _heights.value.isEmpty;
    if (needsFallback) {
      if (!_fallback.isAnimating) {
        _fallback.repeat();
      }
    } else if (_fallback.isAnimating) {
      _fallback.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _fftSubscription?.cancel();
    _fftSubscription = null;
    _fallback.dispose();
    _heights.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _EqualizerBarsPainter(
            heights: _heights,
            fallback: _fallback,
            isPlaying: widget.isPlaying,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _EqualizerBarsPainter extends CustomPainter {
  _EqualizerBarsPainter({
    required this.heights,
    required this.fallback,
    required this.isPlaying,
    required this.color,
  }) : super(repaint: Listenable.merge([heights, fallback]));

  final ValueNotifier<List<double>> heights;
  final Animation<double> fallback;
  final bool isPlaying;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final ratios = _resolveRatios();
    final barWidth = size.width / _kBarWidthFactor;
    final gap = (size.width - barWidth * _kBarCount) / (_kBarCount - 1);
    final radius = Radius.circular(barWidth / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < _kBarCount; i++) {
      final ratio =
          _kMinBarRatio + (1 - _kMinBarRatio) * ratios[i].clamp(0.0, 1.0);
      final barHeight = math.max(barWidth, size.height * ratio);
      final x = i * (barWidth + gap);
      // 垂直居中：围绕中轴线上下对称跳动
      final y = (size.height - barHeight) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          radius,
        ),
        paint,
      );
    }
  }

  List<double> _resolveRatios() {
    if (!isPlaying) return _kIdleHeights;

    final live = heights.value;
    if (live.length == _kBarCount) return live;

    // 兜底：本地正弦，多频率错相，避免非 Pro 用户的图标完全静止。
    final t = fallback.value;
    return List<double>.generate(_kBarCount, (i) {
      final cycles = 2.0 + i;
      final phase = i * math.pi / 4;
      return 0.25 + 0.75 * (math.sin(t * 2 * math.pi * cycles + phase) + 1.0) / 2.0;
    });
  }

  @override
  bool shouldRepaint(covariant _EqualizerBarsPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isPlaying != isPlaying;
  }
}
