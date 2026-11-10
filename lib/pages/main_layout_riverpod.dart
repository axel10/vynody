import 'dart:async';
import 'dart:math';

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

/// 远程媒体库二级分类的当前索引。
///
/// 与 [libraryActiveTabIndexProvider] 同构：`null` = 停在远程库概览页，
/// 其余为 `[0, 5]`（专辑 / 艺术家 / 流派 / 歌曲 / 播放列表 / 搜索）。
///
/// 这是 Rail 与远程库页面之间**唯一**的跨层信号：Rail 点击只改这里，
/// 页面 `ref.listen` 到非空值就切到对应子分类，Rail 再点主项则置 null 回概览。
class RemoteLibraryActiveTabIndexNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? value) {
    if (state != value) {
      state = value;
    }
  }
}

final remoteLibraryActiveTabIndexProvider =
    NotifierProvider<RemoteLibraryActiveTabIndexNotifier, int?>(
      RemoteLibraryActiveTabIndexNotifier.new,
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

class SelectedPlaylistIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) {
    if (!ref.mounted) return;
    state = value;
  }
}

final selectedPlaylistIdProvider =
    NotifierProvider<SelectedPlaylistIdNotifier, String?>(
  SelectedPlaylistIdNotifier.new,
);

final isCoverFlowImmersiveActiveProvider = Provider<bool>((ref) {
  final mainIndex = ref.watch(mainTabIndexProvider);
  final libIndex = ref.watch(libraryActiveTabIndexProvider);
  final is3D = ref.watch(isAlbum3DViewActiveProvider);
  return mainIndex == 2 && libIndex == 4 && is3D;
});

class IsAlbumDetailActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (!ref.mounted) return;
    if (state != value) {
      state = value;
    }
  }
}

final isAlbumDetailActiveProvider =
    NotifierProvider<IsAlbumDetailActiveNotifier, bool>(
  IsAlbumDetailActiveNotifier.new,
);

class LandscapeMiniPlayerExtraLeftNotifier extends Notifier<double> {
  @override
  double build() => 0.0;

  void set(double value) {
    if (!ref.mounted) return;
    if (state != value) {
      state = value;
    }
  }
}

final landscapeMiniPlayerExtraLeftProvider =
    NotifierProvider<LandscapeMiniPlayerExtraLeftNotifier, double>(
  LandscapeMiniPlayerExtraLeftNotifier.new,
);

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

class FloatingDockScrollOffsetNotifier extends Notifier<double> {
  @override
  double build() {
    // 订阅「随滚动移出」开关：关闭时位移恒为 0.0（完全在原位）。
    ref.watch(
      settingsServiceProvider.select(
        (s) => s.enableFloatingDockScrollCollapse,
      ),
    );
    return 0.0;
  }

  void setOffset(double value) {
    if (!ref.mounted) return;
    final clamped = value.clamp(0.0, FloatingDockScrollHelper.maxScrollOffset);
    if ((state - clamped).abs() > 0.01) {
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

final floatingDockScrollOffsetProvider =
    NotifierProvider<FloatingDockScrollOffsetNotifier, double>(
      FloatingDockScrollOffsetNotifier.new,
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

/// 辅助管理浮动 Dock 随向下滚动移出、以及向上滚动上移直至原位的手势跟随位移
class FloatingDockScrollHelper {
  FloatingDockScrollHelper({
    this.maxOffset = maxScrollOffset,
    this.collapseScrollThreshold = 72.0,
    this.expandScrollThreshold = 72.0,
    this.scrollEndResetDebounce = const Duration(milliseconds: 400),
  }) : instanceNo = ++_instanceCounter;

  static int _instanceCounter = 0;

  /// Dock 完全移出屏幕的最大位移 (逻辑像素)
  static const double maxScrollOffset = 220.0;

  /// 诊断开关
  static bool traceEnabled = false;

  /// 允许的最大移出距离
  final double maxOffset;

  final double collapseScrollThreshold;
  final double expandScrollThreshold;
  final Duration scrollEndResetDebounce;

  /// 日志用：区分 main_layout 与 mini_player_wrapper 的两个 helper 实例
  final int instanceNo;
  int _seq = 0;

  void _trace(String message) {
    if (!traceEnabled) return;
    _seq++;
    AppLog.log(
      '[DockTrace] helper#$instanceNo n=$_seq $message',
      mirrorToConsole: true,
    );
  }

  void dispose() {}

  void reset(WidgetRef ref) {
    _trace('reset() 位移清零');
    if (ref.context.mounted) {
      ref.read(floatingDockScrollOffsetProvider.notifier).reset();
      ref.read(floatingDockCollapseProgressProvider.notifier).reset();
      ref.read(floatingDockCollapsedProvider.notifier).setCollapsed(false);
    }
  }

  bool handleScrollNotification(
    ScrollNotification notification,
    WidgetRef ref,
  ) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    // 设置里关闭「随滚动移出」时，悬浮栏始终常驻在原位
    if (!ref.read(settingsServiceProvider).enableFloatingDockScrollCollapse) {
      reset(ref);
      return false;
    }

    final metrics = notification.metrics;
    final double pixels = metrics.pixels;
    final double maxScrollExtent = metrics.maxScrollExtent;

    // 当列表回到顶部（pixels <= 0）时，强制复位至原位
    if (pixels <= 0.0) {
      ref.read(floatingDockScrollOffsetProvider.notifier).reset();
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final dy = notification.scrollDelta ?? 0.0;
      if (dy != 0.0) {
        final currentOffset = ref.read(floatingDockScrollOffsetProvider);
        // dy > 0: 向下滚动，Dock 随滚动向下移出 (offset 增大)
        // dy < 0: 向上滚动，Dock 随滚动向上移入 (offset 减小直至 0)
        double newOffset = (currentOffset + dy).clamp(0.0, maxOffset);

        // 滚入列表底部填充区域：
        // remaining 表示距列表最底部的剩余距离。
        // Dock 的位移不能超过 remaining，向下滚动越接近最底，Dock 越向上浮现展开；
        // 滚动到最底部时 remaining <= 0，Dock 正好完全处于原位 (newOffset = 0)。
        if (maxScrollExtent > 0) {
          final remaining = (maxScrollExtent - pixels).clamp(0.0, maxOffset);
          newOffset = min(newOffset, remaining);
        }

        ref.read(floatingDockScrollOffsetProvider.notifier).setOffset(newOffset);
        _trace(
          'scrollUpdate dy=${dy.toStringAsFixed(1)} offset=${newOffset.toStringAsFixed(1)} px=${pixels.toStringAsFixed(1)} max=${maxScrollExtent.toStringAsFixed(1)}',
        );
      }
    } else if (notification is ScrollEndNotification) {
      if (maxScrollExtent > 0 && pixels >= maxScrollExtent) {
        ref.read(floatingDockScrollOffsetProvider.notifier).reset();
      }
    }

    return false;
  }
}


