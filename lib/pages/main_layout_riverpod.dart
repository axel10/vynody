import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/utils/app_log.dart';

class MainLayoutUiState {
  const MainLayoutUiState({
    this.showVolumeHud = false,
    this.showImmersiveTabBar = true,
    this.snackBarOffset = 0.0,
  });

  final bool showVolumeHud;
  final bool showImmersiveTabBar;
  final double snackBarOffset;

  MainLayoutUiState copyWith({
    bool? showVolumeHud,
    bool? showImmersiveTabBar,
    double? snackBarOffset,
  }) {
    return MainLayoutUiState(
      showVolumeHud: showVolumeHud ?? this.showVolumeHud,
      showImmersiveTabBar: showImmersiveTabBar ?? this.showImmersiveTabBar,
      snackBarOffset: snackBarOffset ?? this.snackBarOffset,
    );
  }
}

class MainLayoutUiController extends Notifier<MainLayoutUiState> {
  Timer? _hudTimer;
  Timer? _immersiveTabBarTimer;
  bool _disposed = false;

  @override
  MainLayoutUiState build() {
    ref.onDispose(() {
      _disposed = true;
      _hudTimer?.cancel();
      _immersiveTabBarTimer?.cancel();
    });
    return const MainLayoutUiState();
  }

  void setVolumeHudVisible(bool visible) {
    _hudTimer?.cancel();
    if (!visible) {
      state = state.copyWith(showVolumeHud: false);
      return;
    }

    state = state.copyWith(showVolumeHud: true);
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      state = state.copyWith(showVolumeHud: false);
    });
  }

  void showImmersiveTabBar() {
    _immersiveTabBarTimer?.cancel();
    state = state.copyWith(showImmersiveTabBar: true);
  }

  void hideImmersiveTabBarAfter(Duration delay) {
    _immersiveTabBarTimer?.cancel();
    _immersiveTabBarTimer = Timer(delay, () {
      if (_disposed) return;
      state = state.copyWith(showImmersiveTabBar: false);
    });
  }

  void setSnackBarOffset(double offset) {
    state = state.copyWith(snackBarOffset: offset);
  }
}

final mainLayoutUiControllerProvider =
    NotifierProvider.autoDispose<MainLayoutUiController, MainLayoutUiState>(
      MainLayoutUiController.new,
    );

class MainTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    if (state != index) {
      state = index;
    }
  }
}

final mainTabIndexProvider =
    NotifierProvider<MainTabIndexNotifier, int>(MainTabIndexNotifier.new);

class PreviousMainTabIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    if (state != index) {
      state = index;
    }
  }
}

final previousMainTabIndexProvider =
    NotifierProvider<PreviousMainTabIndexNotifier, int>(
      PreviousMainTabIndexNotifier.new,
    );

class IsPlaybackDrawerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void open() {
    if (!state) {
      state = true;
    }
  }

  void close() {
    if (state) {
      state = false;
    }
  }

  void toggle() {
    state = !state;
  }

  void setOpen(bool open) {
    if (state != open) {
      state = open;
    }
  }
}

final isPlaybackDrawerOpenProvider =
    NotifierProvider<IsPlaybackDrawerOpenNotifier, bool>(
  IsPlaybackDrawerOpenNotifier.new,
);

class IsAlbum3DViewActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) {
      state = value;
    }
  }
}

final isAlbum3DViewActiveProvider =
    NotifierProvider<IsAlbum3DViewActiveNotifier, bool>(
      IsAlbum3DViewActiveNotifier.new,
    );

/// 媒体库二级分类的当前索引。
///
/// `null` 表示「当前不在任何二级页」（即停在媒体库仪表盘），其余情况恒为
/// `[0, 8]` 区间内的合法索引。此前用 `-1` 同时兼任「不在二级页」与「索引」
/// 两种语义，导致宿主页把 `-1` clamp 成 `0`（播放列表）后出现离场闪烁；
/// 改为可空类型后二者彻底分离，索引不再可能出现非法负值。
class LibraryActiveTabIndexNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? value) {
    if (state != value) {
      state = value;
    }
  }
}

final libraryActiveTabIndexProvider =
    NotifierProvider<LibraryActiveTabIndexNotifier, int?>(
      LibraryActiveTabIndexNotifier.new,
    );

class SelectedGenreKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    if (!ref.mounted) return;
    state = value;
  }
}

final selectedGenreKeyProvider =
    NotifierProvider<SelectedGenreKeyNotifier, String?>(
  SelectedGenreKeyNotifier.new,
);

class SelectedYearKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    if (!ref.mounted) return;
    state = value;
  }
}

final selectedYearKeyProvider =
    NotifierProvider<SelectedYearKeyNotifier, String?>(
  SelectedYearKeyNotifier.new,
);

class SelectedArtistKeyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    if (!ref.mounted) return;
    state = value;
  }
}

final selectedArtistKeyProvider =
    NotifierProvider<SelectedArtistKeyNotifier, String?>(
  SelectedArtistKeyNotifier.new,
);

final isCoverFlowImmersiveActiveProvider = Provider<bool>((ref) {
  final mainIndex = ref.watch(mainTabIndexProvider);
  final libIndex = ref.watch(libraryActiveTabIndexProvider);
  final is3D = ref.watch(isAlbum3DViewActiveProvider);
  return mainIndex == 2 && libIndex == 4 && is3D;
});

class IsSettingsPageActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (!ref.mounted) return;
    if (state != value) {
      state = value;
    }
  }
}

final isSettingsPageActiveProvider =
    NotifierProvider<IsSettingsPageActiveNotifier, bool>(
      IsSettingsPageActiveNotifier.new,
    );

class FloatingDockCollapseProgressNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  void setProgress(double value) {
    if (!ref.mounted) return;
    final clamped = value.clamp(0.0, 1.0);
    if ((state - clamped).abs() > 0.002) {
      state = clamped;
    }
  }

  void reset() {
    if (!ref.mounted) return;
    if (state != 0.0) {
      state = 0.0;
    }
  }
}

final floatingDockCollapseProgressProvider =
    NotifierProvider<FloatingDockCollapseProgressNotifier, double>(
      FloatingDockCollapseProgressNotifier.new,
    );

class FloatingDockCollapsedNotifier extends Notifier<bool> {
  static int _buildCounter = 0;

  @override
  bool build() {
    // 订阅「滚动收起」开关：关闭时收起态恒为 false（完整展开）。
    // 开关翻转会让本 provider 重建，因此关闭的那一刻收起状态即被复位，
    // 重新开启时不会残留上一次的收起态。
    ref.watch(
      settingsServiceProvider.select(
        (s) => s.enableFloatingDockScrollCollapse,
      ),
    );
    // if (FloatingDockScrollHelper.traceEnabled) {
    //   AppLog.log(
    //     '[DockTrace] collapsedProvider.build() #${++_buildCounter} → 强制复位为 false',
    //     mirrorToConsole: true,
    //   );
    // }
    return false;
  }

  void setCollapsed(bool value, {String reason = 'unknown'}) {
    if (!ref.mounted) return;
    final changed = state != value;
    // if (FloatingDockScrollHelper.traceEnabled) {
    //   AppLog.log(
    //     '[DockTrace] setCollapsed($state → $value) changed=$changed reason=$reason',
    //     mirrorToConsole: true,
    //   );
    // }
    if (changed) {
      state = value;
    }
    ref.read(floatingDockCollapseProgressProvider.notifier).reset();
  }
}

final floatingDockCollapsedProvider =
    NotifierProvider<FloatingDockCollapsedNotifier, bool>(
      FloatingDockCollapsedNotifier.new,
    );

/// 辅助管理浮动 Dock 随向下滚动收起与缩小指示、以及向上滚动展开的手势判定
class FloatingDockScrollHelper {
  FloatingDockScrollHelper({
    this.collapseScrollThreshold = 72.0,
    this.expandScrollThreshold = 72.0,
    this.scrollEndResetDebounce = const Duration(milliseconds: 400),
  }) : instanceNo = ++_instanceCounter;

  static int _instanceCounter = 0;

  /// 诊断开关：定位「切页后先展开再收起」时保持 true，问题定位完再关掉
  static bool traceEnabled = true;

  /// 日志用：区分 main_layout 与 mini_player_wrapper 的两个 helper 实例
  final int instanceNo;
  int _seq = 0;

  void _trace(String message) {
    if (!traceEnabled) return;
    _seq++;
    // AppLog.log(
    //   '[DockTrace] helper#$instanceNo n=$_seq $message',
    //   mirrorToConsole: true,
    // );
  }

  /// 触发收起所需的向下累计滚动距离 (逻辑像素)
  final double collapseScrollThreshold;

  /// 触发展开所需的向上累计滚动距离 (逻辑像素)
  final double expandScrollThreshold;

  /// 滚动间歇清空累计距离的防抖时长 (兼容脉冲式的鼠标滚轮连续滚动累加)
  final Duration scrollEndResetDebounce;

  double _accumulatedDownScroll = 0.0;
  double _accumulatedUpScroll = 0.0;

  /// 上一次通知里的滚动位置，用于把「滚入顶部/底部缓冲区」做成边沿触发。
  double? _lastPixels;

  /// 上一次通知的来源 Scrollable。边沿触发只对同一个列表成立：
  /// 切主 tab、进子目录、返回上一页都会换一个 Scrollable，此时
  /// 新列表的 pixels 与旧列表的 pixels 不可比（run.log 实测：
  /// 旧列表 px=107 → 新列表 px=0 被误判成「从下方滚回顶部」而展开）。
  BuildContext? _lastScrollableContext;

  Timer? _resetDebounceTimer;

  void dispose() {
    _resetDebounceTimer?.cancel();
    _resetDebounceTimer = null;
  }

  void reset(WidgetRef ref) {
    _resetDebounceTimer?.cancel();
    _trace(
      'reset() 累计清零 (down=${_accumulatedDownScroll.toStringAsFixed(1)} '
      'up=${_accumulatedUpScroll.toStringAsFixed(1)} '
      'lastPixels=${_lastPixels?.toStringAsFixed(1)})',
    );
    _accumulatedDownScroll = 0.0;
    _accumulatedUpScroll = 0.0;
    _lastPixels = null;
    _lastScrollableContext = null;
    if (ref.context.mounted) {
      ref.read(floatingDockCollapseProgressProvider.notifier).reset();
    }
  }

  void _scheduleReset(WidgetRef ref) {
    _resetDebounceTimer?.cancel();
    _resetDebounceTimer = Timer(scrollEndResetDebounce, () {
      _accumulatedDownScroll = 0.0;
      _accumulatedUpScroll = 0.0;
      if (ref.context.mounted) {
        ref.read(floatingDockCollapseProgressProvider.notifier).reset();
      }
    });
  }

  bool handleScrollNotification(
    ScrollNotification notification,
    WidgetRef ref,
  ) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    // 设置里关闭「滚动收起」时，悬浮栏始终完整展开：
    // 清空滚动累计与缩小指示，避免残留半收起的小幅缩放。
    if (!ref.read(settingsServiceProvider).enableFloatingDockScrollCollapse) {
      reset(ref);
      return false;
    }

    final isCollapsed = ref.read(floatingDockCollapsedProvider);

    final metrics = notification.metrics;
    final double pixels = metrics.pixels;
    final double maxScrollExtent = metrics.maxScrollExtent;

    // 边沿触发只在同一个 Scrollable 内成立：换列表后第一条通知视为「无前值」
    final BuildContext? scrollableContext = notification.context;
    final double? previousPixels =
        identical(scrollableContext, _lastScrollableContext)
        ? _lastPixels
        : null;
    _lastScrollableContext = scrollableContext;
    _lastPixels = pixels;

    final double delta =
        notification is ScrollUpdateNotification
        ? (notification.scrollDelta ?? 0.0)
        : 0.0;
    final String context =
        'px=${pixels.toStringAsFixed(1)} '
        'prev=${previousPixels?.toStringAsFixed(1) ?? 'null'} '
        'max=${maxScrollExtent.toStringAsFixed(1)} '
        'dy=${delta.toStringAsFixed(1)} '
        'collapsed=$isCollapsed '
        'down=${_accumulatedDownScroll.toStringAsFixed(1)} '
        'up=${_accumulatedUpScroll.toStringAsFixed(1)} '
        'depth=${notification.depth} '
        '${notification.runtimeType}';

    if (notification is ScrollStartNotification) {
      _trace('scrollStart ($context)');
    }

    // 顶部缓冲区的展开只在「刚刚从下方滚回顶部」的那一刻触发（边沿触发）。
    // 若对 pixels <= 20 的每一帧都无条件展开：收起态下切到一个仍停在顶部的
    // 新页面再往下滑，会先被这里展开、滚满收起阈值又被收回，
    // 视觉上就是「先展开一下再收起」。
    // 底部缓冲区不收起（到达末尾后无法再下滑），因此仍无条件展开。
    final bool enteredTopBuffer =
        previousPixels != null && previousPixels > 20.0 && pixels <= 20.0;
    final bool isNearBottom =
        maxScrollExtent > 0 && pixels >= maxScrollExtent - 20.0;

    // 顶部 / 底部缓冲区内清空累计距离，避免在边界处攒出一次收起
    if (pixels <= 20.0 || isNearBottom) {
      _trace(
        '缓冲区 hit($context) top=${pixels <= 20.0} bottom=$isNearBottom '
        'enteredTopBuffer=$enteredTopBuffer',
      );
      _resetDebounceTimer?.cancel();
      _accumulatedDownScroll = 0.0;
      _accumulatedUpScroll = 0.0;
      ref.read(floatingDockCollapseProgressProvider.notifier).reset();
      if (isCollapsed && (enteredTopBuffer || isNearBottom)) {
        ref
            .read(floatingDockCollapsedProvider.notifier)
            .setCollapsed(
              false,
              reason: enteredTopBuffer ? 'top-buffer-edge' : 'near-bottom',
            );
      }
      return false;
    }

    // 若已经收起，判断向上滚动展开（防抖窗口期内累计达到阈值展开，向下滚动或超时清零）
    if (isCollapsed) {
      if (_accumulatedDownScroll != 0.0) {
        _accumulatedDownScroll = 0.0;
        ref.read(floatingDockCollapseProgressProvider.notifier).reset();
      }

      if (notification is ScrollUpdateNotification) {
        final dy = notification.scrollDelta ?? 0.0;
        if (dy > 0) {
          // 向下滚动：重置向上累计
          _resetDebounceTimer?.cancel();
          _accumulatedUpScroll = 0.0;
        } else if (dy < 0) {
          // 向上滚动（dy < 0，对应内容向下移动）
          _resetDebounceTimer?.cancel();
          _accumulatedUpScroll += -dy;
          if (_accumulatedUpScroll >= expandScrollThreshold) {
            _accumulatedUpScroll = 0.0;
            ref
                .read(floatingDockCollapsedProvider.notifier)
                .setCollapsed(false, reason: 'up-scroll-threshold');
          } else {
            _scheduleReset(ref);
          }
        }
      } else if (notification is ScrollEndNotification) {
        if (_accumulatedUpScroll > 0.0) {
          _scheduleReset(ref);
        }
      }
      return false;
    }

    // 若当前处于展开状态：重置向上累计，计算向下滚动收起与缩小指示
    _accumulatedUpScroll = 0.0;

    if (notification is ScrollUpdateNotification) {
      final dy = notification.scrollDelta ?? 0.0;
      if (notification.metrics.pixels > 20.0) {
        if (dy > 0) {
          _resetDebounceTimer?.cancel();
          _accumulatedDownScroll += dy;
          if (_accumulatedDownScroll >= collapseScrollThreshold) {
            _accumulatedDownScroll = 0.0;
            ref.read(floatingDockCollapseProgressProvider.notifier).reset();
            ref
                .read(floatingDockCollapsedProvider.notifier)
                .setCollapsed(true, reason: 'down-scroll-threshold');
          } else {
            final progress = (_accumulatedDownScroll / collapseScrollThreshold)
                .clamp(0.0, 1.0);
            ref
                .read(floatingDockCollapseProgressProvider.notifier)
                .setProgress(progress);
            _trace('展开态下滑 progress=${progress.toStringAsFixed(2)} ($context)');
            _scheduleReset(ref);
          }
        } else if (dy < 0) {
          _resetDebounceTimer?.cancel();
          _accumulatedDownScroll = (_accumulatedDownScroll + dy * 1.5)
              .clamp(0.0, collapseScrollThreshold);
          final progress = (_accumulatedDownScroll / collapseScrollThreshold)
              .clamp(0.0, 1.0);
          ref
              .read(floatingDockCollapseProgressProvider.notifier)
              .setProgress(progress);
          if (_accumulatedDownScroll > 0.0) {
            _scheduleReset(ref);
          }
        }
      }
    } else if (notification is ScrollEndNotification) {
      // 滚动停止时视觉缩小进度立即复位，累计位移通过防抖延时清零（兼顾脉冲式滚轮连续累加）
      _trace('scrollEnd ($context)');
      ref.read(floatingDockCollapseProgressProvider.notifier).reset();
      if (_accumulatedDownScroll > 0.0) {
        _scheduleReset(ref);
      }
    }

    return false;
  }
}


