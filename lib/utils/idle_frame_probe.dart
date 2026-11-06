import 'dart:async';

import 'package:flutter/scheduler.dart';

import 'app_log.dart';

/// 窗口最小化 / 后台时的帧率探针（临时诊断用，定位「最小化后 GPU 仍有占用」）。
///
/// 每 [interval] 打一行，回答三个问题：
///
/// 1. 最小化后 engine 还在不在出帧 —— `frames` / `fps`；
/// 2. 帧是被谁驱动的 —— `transient` 为 [SchedulerBinding.transientCallbackCount]，
///    大于 0 说明还有 Ticker / AnimationController 在跑（GPU 侧的动画）；
///    `scheduledFrame` 为 [SchedulerBinding.hasScheduledFrame]，
///    为 true 说明引擎仍被请求出新一帧（可能有 setState 在排队）。
/// 3. 绘制开销落在哪一段 —— `avgBuild` / `avgRaster` 平均耗时。
///
/// `frames=0` 且 `transient=0` 说明 UI 侧已经完全静默，此时若 GPU 仍有占用，
/// 就要往窗口外查（桌面歌词是独立 engine，任务管理器里是另一个进程）。
class IdleFrameProbe {
  IdleFrameProbe({
    this.interval = const Duration(seconds: 5),
  });

  final Duration interval;

  /// 上下文快照（最小化标记、生命周期状态等），由外部注入，
  /// 避免探针本身去依赖 provider 造成循环依赖。
  String Function()? contextProvider;

  Timer? _timer;
  int _frames = 0;
  Duration _rasterTotal = Duration.zero;
  Duration _buildTotal = Duration.zero;
  DateTime _windowStart = DateTime.now();
  bool _installed = false;

  void install() {
    if (_installed) return;
    _installed = true;
    _windowStart = DateTime.now();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // 独立定时器：即使一帧都没出也要打印，否则「无帧」和「探针死了」分不清。
    _timer = Timer.periodic(interval, (_) => _report());
  }

  void dispose() {
    if (!_installed) return;
    _installed = false;
    _timer?.cancel();
    _timer = null;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    _frames += timings.length;
    for (final FrameTiming timing in timings) {
      _rasterTotal += timing.rasterDuration;
      _buildTotal += timing.buildDuration;
    }
  }

  void _report() {
    final DateTime now = DateTime.now();
    final Duration elapsed = now.difference(_windowStart);
    final double fps =
        elapsed.inMilliseconds <= 0 ? 0 : _frames * 1000 / elapsed.inMilliseconds;
    final double rasterMs = _frames == 0
        ? 0
        : _rasterTotal.inMicroseconds / _frames / 1000;
    final double buildMs =
        _frames == 0 ? 0 : _buildTotal.inMicroseconds / _frames / 1000;
    final SchedulerBinding binding = SchedulerBinding.instance;

    AppLog.log(
      '[IdleProbe] ${contextProvider?.call() ?? ''} '
      'frames=$_frames fps=${fps.toStringAsFixed(1)} '
      'transient=${binding.transientCallbackCount} '
      'scheduledFrame=${binding.hasScheduledFrame} '
      'phase=${binding.schedulerPhase.name} '
      'avgBuild=${buildMs.toStringAsFixed(2)}ms '
      'avgRaster=${rasterMs.toStringAsFixed(2)}ms',
      mirrorToConsole: true,
    );

    _frames = 0;
    _rasterTotal = Duration.zero;
    _buildTotal = Duration.zero;
    _windowStart = now;
  }
}
