import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';

/// 触发间奏/前奏三点指示器的最短静默时长（毫秒）。
const int kLyricsInterludeMinDurationMs = 5000;

/// 描述一段可用于显示三点等待指示器的静默区间（前奏、自带空行或逐字句间长间奏）。
@immutable
class LyricsInterludeSpec {
  const LyricsInterludeSpec({
    required this.startMs,
    required this.endMs,
    this.isIntro = false,
    this.sourceLineIndex,
  });

  final int startMs;
  final int endMs;
  final bool isIntro;

  /// 若来源于 LRC 自带的空行，记录其原始行号；前奏或逐字自动推导的间奏为 null。
  final int? sourceLineIndex;

  int get durationMs => math.max(0, endMs - startMs);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LyricsInterludeSpec &&
        other.startMs == startMs &&
        other.endMs == endMs &&
        other.isIntro == isIntro &&
        other.sourceLineIndex == sourceLineIndex;
  }

  @override
  int get hashCode => Object.hash(startMs, endMs, isIntro, sourceLineIndex);
}

/// 歌词视图层的统一展示项：要么是原始歌词行，要么是间奏三点指示器。
///
/// 通过 [originalIndex] 保持与 `MusicLyric.syncedLines` 及译文数组的一一对齐，
/// 避免插入前奏或逐字句间间奏时错位。
@immutable
class LyricsDisplayEntry {
  const LyricsDisplayEntry.lyric({
    required LyricLine this.line,
    required int this.originalIndex,
  }) : interlude = null;

  const LyricsDisplayEntry.interlude({
    required LyricsInterludeSpec this.interlude,
  })  : line = null,
        originalIndex = null;

  final LyricLine? line;
  final int? originalIndex;
  final LyricsInterludeSpec? interlude;

  bool get isInterlude => interlude != null;

  int get timestampMs =>
      interlude?.startMs ?? line?.timestamp.inMilliseconds ?? 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LyricsDisplayEntry &&
        other.line == line &&
        other.originalIndex == originalIndex &&
        other.interlude == interlude;
  }

  @override
  int get hashCode => Object.hash(line, originalIndex, interlude);
}

/// 将原始歌词行列表转换为视图层展示项列表。
///
/// 触发三点间奏指示器的三类精确区间（均要求持续时长 >= [minDurationMs]）：
/// 1. **前奏**：`0ms` 到首句非空歌词之间；
/// 2. **LRC 自带空行**：带时间戳的空白行（连续空行合并）到下一句非空歌词之间；
/// 3. **逐字歌词句间长间奏**：当前句含 `words` 逐字数据、且下一条直接是非空歌词行时，
///    末字结束时刻（`lastWord.timestamp + durationMs`）到下一句开头之间。
List<LyricsDisplayEntry> buildLyricsDisplayEntries(
  List<LyricLine> lines, {
  int minDurationMs = kLyricsInterludeMinDurationMs,
}) {
  if (lines.isEmpty) return const [];

  final hasTimed = lines.any((l) => l.isTimed);
  if (!hasTimed) {
    return List<LyricsDisplayEntry>.generate(
      lines.length,
      (i) => LyricsDisplayEntry.lyric(line: lines[i], originalIndex: i),
      growable: false,
    );
  }

  final entries = <LyricsDisplayEntry>[];

  // 1. 前奏检测：若第一行本身是非空带时间戳歌词，且首句时间戳 >= 阈值，则插入前奏指示器。
  // 若第一行本身就是空行，则交由下方「自带空行」逻辑统一处理，避免重复生成两个前奏项。
  final firstLine = lines.first;
  if (firstLine.isTimed &&
      firstLine.text.trim().isNotEmpty &&
      firstLine.timestamp.inMilliseconds >= minDurationMs) {
    entries.add(
      LyricsDisplayEntry.interlude(
        interlude: LyricsInterludeSpec(
          startMs: 0,
          endMs: firstLine.timestamp.inMilliseconds,
          isIntro: true,
        ),
      ),
    );
  }

  int i = 0;
  while (i < lines.length) {
    final current = lines[i];

    // 2. 自带空行（合并连续空行）
    if (current.text.trim().isEmpty) {
      int nextIdx = i + 1;
      while (nextIdx < lines.length && lines[nextIdx].text.trim().isEmpty) {
        nextIdx++;
      }

      if (nextIdx < lines.length && current.isTimed && lines[nextIdx].isTimed) {
        final startMs = current.timestamp.inMilliseconds;
        final endMs = lines[nextIdx].timestamp.inMilliseconds;
        if (endMs - startMs >= minDurationMs) {
          entries.add(
            LyricsDisplayEntry.interlude(
              interlude: LyricsInterludeSpec(
                startMs: startMs,
                endMs: endMs,
                isIntro: i == 0 && startMs == 0,
                sourceLineIndex: i,
              ),
            ),
          );
        }
      }
      // 跳过已合并的空行；若为末尾尾奏空行（后无歌词）也直接忽略
      i = nextIdx;
      continue;
    }

    // 普通非空歌词行
    entries.add(LyricsDisplayEntry.lyric(line: current, originalIndex: i));

    // 3. 逐字歌词精确句间长间奏检测
    final words = current.words;
    if (current.isTimed &&
        words != null &&
        words.isNotEmpty &&
        i + 1 < lines.length) {
      final nextLine = lines[i + 1];
      if (nextLine.isTimed && nextLine.text.trim().isNotEmpty) {
        final lastWord = words.last;
        final prevEndMs = lastWord.timestamp.inMilliseconds +
            math.max<int>(0, lastWord.durationMs);
        final nextStartMs = nextLine.timestamp.inMilliseconds;
        if (prevEndMs >= current.timestamp.inMilliseconds &&
            nextStartMs - prevEndMs >= minDurationMs) {
          entries.add(
            LyricsDisplayEntry.interlude(
              interlude: LyricsInterludeSpec(
                startMs: prevEndMs,
                endMs: nextStartMs,
              ),
            ),
          );
        }
      }
    }

    i++;
  }

  return List<LyricsDisplayEntry>.unmodifiable(entries);
}

/// 单个圆点在当前帧的视觉状态。
@immutable
class InterludeDotState {
  const InterludeDotState({
    required this.opacity,
    required this.scale,
  });

  final double opacity;
  final double scale;
}

/// 三个圆点指示器在当前帧的完整渲染参数。
@immutable
class InterludeDotsFrame {
  const InterludeDotsFrame({
    required this.dots,
    required this.groupOpacity,
    required this.groupScale,
  });

  final List<InterludeDotState> dots;
  final double groupOpacity;
  final double groupScale;
}

/// 计算间奏三点指示器在 [elapsedMs] 时刻的动画帧。
///
/// 动效分三阶段：
/// 1. 入场淡入（前 `enterDurationMs`）：整体平滑浮现；
/// 2. 逐点渐亮（`0 .. durationMs - exitDurationMs`）：三个点依次从暗到亮；
/// 3. 退场衔接（最后 `exitDurationMs`）：三个点全部亮起后整体先变大、再变小并淡出消失。
InterludeDotsFrame computeInterludeDotsFrame({
  required int elapsedMs,
  required int durationMs,
}) {
  const double inactiveDotOpacity = 0.26;
  const double inactiveDotScale = 0.88;
  const int enterDurationMs = 360;
  const int maxExitDurationMs = 560;
  const double expandPhaseFraction = 0.38;
  const double peakScale = 1.22;
  const double endScale = 0.55;

  if (durationMs <= 0 || elapsedMs >= durationMs) {
    return const InterludeDotsFrame(
      dots: [
        InterludeDotState(opacity: 1.0, scale: 1.0),
        InterludeDotState(opacity: 1.0, scale: 1.0),
        InterludeDotState(opacity: 1.0, scale: 1.0),
      ],
      groupOpacity: 0.0,
      groupScale: endScale,
    );
  }

  final clampedElapsed = math.max(0, elapsedMs);
  final exitDurationMs = math.min(maxExitDurationMs, (durationMs * 0.25).round());
  final exitStartMs = math.max(1, durationMs - exitDurationMs);

  // 1. 入场淡入
  final double enterT = (clampedElapsed / enterDurationMs).clamp(0.0, 1.0);
  final double enterOpacity = Curves.easeOut.transform(enterT);
  final double enterScale =
      ui.lerpDouble(0.86, 1.0, Curves.easeOutCubic.transform(enterT))!;

  // 2. 三个点依次亮起
  final double segmentMs = exitStartMs / 3.0;
  final dots = List<InterludeDotState>.generate(3, (index) {
    final segStart = index * segmentMs;
    final rawProgress =
        ((clampedElapsed - segStart) / segmentMs).clamp(0.0, 1.0);
    final opacity = ui.lerpDouble(
      inactiveDotOpacity,
      1.0,
      Curves.easeInOut.transform(rawProgress),
    )!;
    final scale = ui.lerpDouble(
      inactiveDotScale,
      1.0,
      Curves.easeOutCubic.transform(rawProgress),
    )!;
    return InterludeDotState(opacity: opacity, scale: scale);
  }, growable: false);

  // 3. 结尾退场：先变大 -> 后变小并淡出消失
  double exitOpacity = 1.0;
  double exitScale = 1.0;
  if (clampedElapsed >= exitStartMs && exitDurationMs > 0) {
    final exitT =
        ((clampedElapsed - exitStartMs) / exitDurationMs).clamp(0.0, 1.0);
    if (exitT <= expandPhaseFraction) {
      final expandU = (exitT / expandPhaseFraction).clamp(0.0, 1.0);
      exitScale = ui.lerpDouble(
        1.0,
        peakScale,
        Curves.easeOutCubic.transform(expandU),
      )!;
      exitOpacity = 1.0;
    } else {
      final shrinkU =
          ((exitT - expandPhaseFraction) / (1.0 - expandPhaseFraction))
              .clamp(0.0, 1.0);
      exitScale = ui.lerpDouble(
        peakScale,
        endScale,
        Curves.easeInCubic.transform(shrinkU),
      )!;
      exitOpacity = ui.lerpDouble(
        1.0,
        0.0,
        Curves.easeInQuad.transform(shrinkU),
      )!;
    }
  }

  return InterludeDotsFrame(
    dots: dots,
    groupOpacity: (enterOpacity * exitOpacity).clamp(0.0, 1.0),
    groupScale: enterScale * exitScale,
  );
}

/// 间奏/前奏三点等待指示器组件。
///
/// 仅在 [isActive] 为 true 时启动 [Ticker] 做 60fps 音频时钟插值绘制；
/// 非激活态保持透明占位，零额外渲染与 CPU 开销。
class LyricsInterludeDotsWidget extends ConsumerStatefulWidget {
  const LyricsInterludeDotsWidget({
    super.key,
    required this.interlude,
    required this.isActive,
    required this.color,
    required this.fontScale,
    this.timelineOffsetMs = 0,
  });

  final LyricsInterludeSpec interlude;
  final bool isActive;
  final Color color;
  final double fontScale;
  final int timelineOffsetMs;

  static double containerHeightForFontScale(double fontScale) {
    return 16.0 * fontScale * 1.4;
  }

  @override
  ConsumerState<LyricsInterludeDotsWidget> createState() =>
      _LyricsInterludeDotsWidgetState();
}

class _LyricsInterludeDotsWidgetState
    extends ConsumerState<LyricsInterludeDotsWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;

  Duration _basePosition = Duration.zero;
  DateTime _baseWallClock = DateTime.now();
  Duration _pausedElapsed = Duration.zero;
  bool _isPlaying = false;
  bool _isBackgroundSuspended = false;
  bool _isInitialized = false;
  double _speed = 1.0;

  Duration _correction = Duration.zero;
  DateTime _correctionAt = DateTime.now();
  static const int _correctionWindowMs = 240;
  static const int _maxSoftCorrectionMs = 900;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((_) {
      if (mounted && !_isBackgroundSuspended && _isPlaying && widget.isActive) {
        setState(() {});
      }
    });
  }

  void _syncBaseline({Duration? seekPosition}) {
    final now = DateTime.now();
    final previousLocal =
        _isInitialized ? _calculateCurrentPosition(_speed) : null;
    final Duration target = seekPosition ?? ref.read(audioPositionProvider);

    var hard = true;
    var anchor = target;
    if (_isPlaying && previousLocal != null) {
      final errorMs = (target - previousLocal).inMilliseconds;
      if (errorMs.abs() <= _maxSoftCorrectionMs) {
        anchor = previousLocal;
        hard = false;
      }
    }

    _basePosition = anchor;
    _baseWallClock = now;
    _pausedElapsed = Duration.zero;
    _correction = hard ? Duration.zero : target - anchor;
    _correctionAt = now;
    _isInitialized = true;
  }

  Duration _calculateCurrentPosition(double speed) {
    if (!_isInitialized) {
      return ref.read(audioPositionProvider);
    }
    final now = DateTime.now();
    final rawElapsed = _isPlaying
        ? _pausedElapsed + now.difference(_baseWallClock)
        : _pausedElapsed;
    final Duration base;
    if ((speed - 1.0).abs() > 0.001 && speed > 0) {
      final scaledElapsedMs =
          (rawElapsed.inMicroseconds * speed / 1000).round();
      base = _basePosition + Duration(milliseconds: scaledElapsedMs);
    } else {
      base = _basePosition + rawElapsed;
    }
    if (_correction.inMilliseconds == 0) return base;
    final elapsed = now.difference(_correctionAt).inMilliseconds;
    if (elapsed >= _correctionWindowMs) {
      return base + _correction;
    }
    final progress = elapsed / _correctionWindowMs;
    return base +
        Duration(
          milliseconds: (_correction.inMilliseconds * progress).round(),
        );
  }

  void _updateTickerState() {
    if (!_isBackgroundSuspended && _isPlaying && widget.isActive) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else {
      if (_ticker.isActive) {
        _ticker.stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final suspended = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (suspended == _isBackgroundSuspended) return;
    _isBackgroundSuspended = suspended;
    if (suspended) {
      if (_isPlaying && _isInitialized) {
        _pausedElapsed += DateTime.now().difference(_baseWallClock);
      }
    } else if (widget.isActive) {
      _syncBaseline();
    }
    _updateTickerState();
  }

  @override
  void didUpdateWidget(covariant LyricsInterludeDotsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.interlude != widget.interlude) {
      if (widget.isActive) {
        _syncBaseline();
      }
      _updateTickerState();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final containerHeight =
        LyricsInterludeDotsWidget.containerHeightForFontScale(widget.fontScale);

    if (!widget.isActive) {
      if (_ticker.isActive) {
        _ticker.stop();
      }
      return SizedBox(height: containerHeight);
    }

    final isPlaying = ref.watch(audioIsPlayingProvider);
    final speed =
        ref.watch(audioSnapshotProvider.select((s) => s.playbackSpeed));
    _speed = speed;

    ref.listen<Duration>(audioPositionProvider, (prev, next) {
      if (!widget.isActive) return;
      _syncBaseline(seekPosition: next);
      if (!_isPlaying && mounted) {
        setState(() {});
      }
    });

    if (isPlaying != _isPlaying) {
      if (isPlaying) {
        _baseWallClock = DateTime.now();
        if (!_isInitialized) {
          _syncBaseline();
        }
      } else {
        if (_isInitialized) {
          _pausedElapsed += DateTime.now().difference(_baseWallClock);
        }
      }
      _isPlaying = isPlaying;
      _updateTickerState();
    } else if (!_isInitialized) {
      _syncBaseline();
      _updateTickerState();
    } else if (!_ticker.isActive && _isPlaying && !_isBackgroundSuspended) {
      _ticker.start();
    }

    final rawPosMs = _calculateCurrentPosition(speed).inMilliseconds;
    final adjustedPosMs = rawPosMs - widget.timelineOffsetMs;
    final elapsedMs = adjustedPosMs - widget.interlude.startMs;

    final frame = computeInterludeDotsFrame(
      elapsedMs: elapsedMs,
      durationMs: widget.interlude.durationMs,
    );

    final double dotDiameter = 9.0 * widget.fontScale;
    final double dotSpacing = 7.5 * widget.fontScale;
    final double totalWidth = dotDiameter * 3 + dotSpacing * 2;

    return SizedBox(
      height: containerHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: CustomPaint(
          size: Size(totalWidth, containerHeight),
          painter: _InterludeDotsPainter(
            frame: frame,
            color: widget.color,
            dotDiameter: dotDiameter,
            dotSpacing: dotSpacing,
          ),
        ),
      ),
    );
  }
}

class _InterludeDotsPainter extends CustomPainter {
  const _InterludeDotsPainter({
    required this.frame,
    required this.color,
    required this.dotDiameter,
    required this.dotSpacing,
  });

  final InterludeDotsFrame frame;
  final Color color;
  final double dotDiameter;
  final double dotSpacing;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.groupOpacity <= 0.001 || frame.groupScale <= 0.001) {
      return;
    }

    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(frame.groupScale, frame.groupScale);
    canvas.translate(-center.dx, -center.dy);

    final baseRadius = dotDiameter / 2;
    final paint = Paint()..isAntiAlias = true;

    for (int i = 0; i < frame.dots.length; i++) {
      final dot = frame.dots[i];
      final effectiveAlpha =
          (dot.opacity * frame.groupOpacity).clamp(0.0, 1.0);
      if (effectiveAlpha <= 0.001) continue;

      final cx = baseRadius + i * (dotDiameter + dotSpacing);
      final cy = size.height / 2;
      paint.color = color.withValues(alpha: effectiveAlpha);
      canvas.drawCircle(Offset(cx, cy), baseRadius * dot.scale, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InterludeDotsPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.color != color ||
        oldDelegate.dotDiameter != dotDiameter ||
        oldDelegate.dotSpacing != dotSpacing;
  }
}
