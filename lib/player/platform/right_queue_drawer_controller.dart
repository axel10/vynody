import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Display, FlutterView;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/utils/layout_constants.dart';

const double kDefaultRegularMinWindowWidth = 400.0;
const double kDefaultRegularMinWindowHeight = 650.0;
const Size kDefaultRegularMinWindowSize = Size(
  kDefaultRegularMinWindowWidth,
  kDefaultRegularMinWindowHeight,
);

/// 抽屉展开时，左侧内容区（主界面）必须保留的最小宽度。
/// 与 [kDefaultRegularMinWindowSize] 同宽：抽屉展开后主界面仍能按「常规最小窗口」
/// 的宽度排版，不会被挤成一条缝（曾因此把歌词面板压到 0 宽）。
const double kMinMainContentWidth = kDefaultRegularMinWindowWidth;

/// 给定抽屉宽度时，窗口至少应有的宽度 = 抽屉宽度 + 内容区最小宽度。
double minWindowWidthForDrawer(double drawerWidth) =>
    drawerWidth + kMinMainContentWidth;

/// 抽屉展开状态下的窗口最小尺寸（默认抽屉宽度 340 → 740）。
const Size kDrawerOpenMinWindowSize = Size(
  kDefaultRightQueueDrawerWidth + kMinMainContentWidth,
  kDefaultRegularMinWindowHeight,
);

class RightQueueDrawerNotifier extends Notifier<bool> {
  double? _expandedDeltaWidth;
  Size? _sizeBeforeAutoExpand;

  @override
  bool build() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        return ref.read(settingsServiceProvider).isRightQueueDrawerOpen;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  void _persistState(bool isOpen) {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        ref.read(settingsServiceProvider).isRightQueueDrawerOpen = isOpen;
      } catch (_) {}
    }
  }

  /// Toggles the drawer state
  Future<void> toggle() async {
    if (state) {
      await close();
    } else {
      await open();
    }
  }

  /// Opens the drawer. Before the drawer takes its width, makes sure the window
  /// is wide enough to keep the main content area at least [kMinMainContentWidth]
  /// wide (window width >= drawer width + content minimum). If the window was
  /// auto-expanded by this call, [close] restores the previous width.
  Future<void> open() async {
    if (state) return;

    if (_isDesktopPlatform) {
      try {
        final Size? sizeBefore = await _currentNormalWindowSize();
        final bool expanded = await ensureWindowFitsDrawer();
        if (expanded && sizeBefore != null) {
          final Size sizeAfter = await windowManager.getSize();
          _expandedDeltaWidth = sizeAfter.width - sizeBefore.width;
          _sizeBeforeAutoExpand = sizeBefore;
        }
      } catch (e) {
        debugPrint('[RightQueueDrawer] Error checking/expanding window size: $e');
      }
    }

    state = true;
    _persistState(true);
  }

  /// Ensures the window leaves at least [kMinMainContentWidth] for the main
  /// content while the drawer is open.
  ///
  /// Target window width = drawer width + [kMinMainContentWidth], capped at the
  /// current display's logical width so the window never grows off-screen. The
  /// window's minimum width is raised to the same value, otherwise the user (or
  /// the OS) could shrink it back to a state where the content is squeezed.
  ///
  /// Returns `true` when the window width was actually increased.
  Future<bool> ensureWindowFitsDrawer() async {
    if (!_isDesktopPlatform) return false;

    final double drawerWidth = ref.read(rightQueueDrawerWidthProvider);
    final double requiredWidth = minWindowWidthForDrawer(drawerWidth);
    final double displayWidth = _displayLogicalWidth() ?? double.infinity;
    // 显示器本身放不下时不硬撑（否则窗口会超出屏幕且再也缩不回来）。
    final double targetWidth = math.min(requiredWidth, displayWidth);

    try {
      await windowManager.setMinimumSize(
        Size(targetWidth, kDefaultRegularMinWindowSize.height),
      );

      if (await windowManager.isMaximized()) return false;
      if (await windowManager.isFullScreen()) return false;

      final Size currentSize = await windowManager.getSize();
      if (currentSize.width >= targetWidth - 0.5) return false;

      debugPrint(
        '[RightQueueDrawer] content area too narrow: '
        'window=${currentSize.width}, drawer=$drawerWidth, '
        'minContent=$kMinMainContentWidth → expanding window to $targetWidth',
      );
      await windowManager.setSize(Size(targetWidth, currentSize.height));
      return true;
    } catch (e) {
      debugPrint('[RightQueueDrawer] Error ensuring window width: $e');
      return false;
    }
  }

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Current window size in logical pixels, or `null` when maximized / fullscreen
  /// (in those states the content area is already as wide as it can get).
  Future<Size?> _currentNormalWindowSize() async {
    if (await windowManager.isMaximized()) return null;
    if (await windowManager.isFullScreen()) return null;
    return windowManager.getSize();
  }

  /// Logical width of the display hosting the main window, used as an upper
  /// bound so an expansion never pushes the window off-screen.
  double? _displayLogicalWidth() {
    try {
      final FlutterView? view =
          WidgetsBinding.instance.platformDispatcher.implicitView;
      final Display? display = view?.display;
      if (display == null) return null;
      final double dpr = display.devicePixelRatio;
      if (dpr <= 0) return null;
      return display.size.width / dpr;
    } catch (_) {
      return null;
    }
  }

  /// Closes the drawer. Restores the minimum window size to [kDefaultRegularMinWindowSize]
  /// and, if the window was previously auto-expanded, gracefully restores the original window width.
  Future<void> close({bool restoreWindowSize = true}) async {
    if (!state) return;

    state = false;
    _persistState(false);

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        await windowManager.setMinimumSize(kDefaultRegularMinWindowSize);
      } catch (e) {
        debugPrint('[RightQueueDrawer] Error restoring minimum window size: $e');
      }
    }

    if (restoreWindowSize &&
        _expandedDeltaWidth != null &&
        !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final delta = _expandedDeltaWidth!;
      final oldSize = _sizeBeforeAutoExpand;
      _expandedDeltaWidth = null;
      _sizeBeforeAutoExpand = null;

      try {
        final isMax = await windowManager.isMaximized();
        final isFull = await windowManager.isFullScreen();

        if (!isMax && !isFull) {
          final currentSize = await windowManager.getSize();
          // If the user didn't drastically change the width manually, restore it
          if (oldSize == null || (currentSize.width - (oldSize.width + delta)).abs() < 40.0) {
            final restoredWidth = (currentSize.width - delta).clamp(
              kDefaultRegularMinWindowSize.width,
              99999.0,
            );
            debugPrint(
              '[RightQueueDrawer] Restoring window width to $restoredWidth',
            );
            await windowManager.setSize(Size(restoredWidth, currentSize.height));
          }
        }
      } catch (e) {
        debugPrint('[RightQueueDrawer] Error restoring window size: $e');
      }
    } else {
      _expandedDeltaWidth = null;
      _sizeBeforeAutoExpand = null;
    }
  }
}

final rightQueueDrawerProvider =
    NotifierProvider<RightQueueDrawerNotifier, bool>(RightQueueDrawerNotifier.new);

/// 队列抽屉宽度 Notifier
class RightQueueDrawerWidthNotifier extends Notifier<double> {
  @override
  double build() {
    try {
      return ref.watch(
        settingsServiceProvider.select((s) => s.rightQueueDrawerWidth),
      );
    } catch (_) {
      return kDefaultRightQueueDrawerWidth;
    }
  }

  void setWidth(double width) {
    final clamped = width.clamp(
      kMinRightQueueDrawerWidth,
      kMaxRightQueueDrawerWidth,
    );
    ref.read(settingsServiceProvider).rightQueueDrawerWidth = clamped;
    state = clamped;
  }

  void reset() {
    setWidth(kDefaultRightQueueDrawerWidth);
  }
}

final rightQueueDrawerWidthProvider =
    NotifierProvider<RightQueueDrawerWidthNotifier, double>(
  RightQueueDrawerWidthNotifier.new,
);

/// 标记是否正在拖拽右侧抽屉边缘（拖拽时让 AnimatedSize 零延迟，实现丝滑跟手体验）
class DraggingStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool isDragging) {
    state = isDragging;
  }
}

final isDraggingRightQueueDrawerProvider =
    NotifierProvider<DraggingStateNotifier, bool>(DraggingStateNotifier.new);

/// 左侧导航栏当前实际宽度的响应式 Provider（输入当前窗口宽度）
final sidebarRailWidthProvider = Provider.family<double, double>((ref, windowWidth) {
  if (windowWidth < kSidebarRailExtendedMinWindowWidth) {
    return kSidebarRailWidthCollapsed;
  }
  return ref.watch(
    settingsServiceProvider.select((s) => s.sidebarRailCustomWidth),
  );
});

/// 标记是否正在拖拽 Rail 栏边缘
final isDraggingSidebarRailProvider =
    NotifierProvider<DraggingStateNotifier, bool>(DraggingStateNotifier.new);
