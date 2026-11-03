import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pages/main_layout_riverpod.dart';

enum AppOrientationMode {
  unrestricted,
  portraitOnly,
  landscapeOnly,
}

/// 屏幕旋转转场遮罩状态
class AppOrientationCurtainState {
  final double opacity;
  final int durationMs;
  final Color? color;
  final bool isTransitioning;

  const AppOrientationCurtainState({
    this.opacity = 0.0,
    this.durationMs = 140,
    this.color,
    this.isTransitioning = false,
  });

  AppOrientationCurtainState copyWith({
    double? opacity,
    int? durationMs,
    Color? color,
    bool? isTransitioning,
  }) {
    return AppOrientationCurtainState(
      opacity: opacity ?? this.opacity,
      durationMs: durationMs ?? this.durationMs,
      color: color ?? this.color,
      isTransitioning: isTransitioning ?? this.isTransitioning,
    );
  }
}

class AppOrientationCurtainNotifier extends Notifier<AppOrientationCurtainState> {
  @override
  AppOrientationCurtainState build() => const AppOrientationCurtainState();

  void fadeIn({required Color color, int durationMs = 140}) {
    state = AppOrientationCurtainState(
      opacity: 1.0,
      durationMs: durationMs,
      color: color,
      isTransitioning: true,
    );
  }

  void fadeOut({int durationMs = 180}) {
    state = state.copyWith(
      opacity: 0.0,
      durationMs: durationMs,
      isTransitioning: false,
    );
  }
}

final appOrientationCurtainProvider =
    NotifierProvider<AppOrientationCurtainNotifier, AppOrientationCurtainState>(
  AppOrientationCurtainNotifier.new,
);

/// 移动端屏幕方向自适应管理器
/// - 手机端（Android 手机 / iPhone，shortestSide < 600）：默认全局锁定竖屏；进入 3D 唱片封面墙（Cover Flow）时自动切为横屏，退出恢复竖屏。
/// - 平板与桌面模式（iPad、Android 平板、折叠屏展开态、Android 桌面模式，shortestSide >= 600）：允许所有方向自由旋转。
/// - 桌面平台（Windows / macOS / Linux）：不设限制。
class AppOrientationManager {
  static const double tabletShortestSideBreakpoint = 600.0;

  @visibleForTesting
  static AppOrientationMode? currentMode;

  @visibleForTesting
  static bool? isMobileOverride;

  @visibleForTesting
  static bool skipAnimationForTest = false;

  static bool get isMobile =>
      isMobileOverride ?? (Platform.isAndroid || Platform.isIOS);

  /// 应用启动时尽早初始化默认屏幕方向
  static void init() {
    if (!isMobile) {
      return;
    }

    try {
      final view = PlatformDispatcher.instance.views.firstOrNull;
      if (view != null) {
        final pixelRatio = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1.0;
        final logicalSize = view.physicalSize / pixelRatio;
        if (logicalSize.shortestSide < tabletShortestSideBreakpoint) {
          currentMode = AppOrientationMode.portraitOnly;
          SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          return;
        }
      }
      currentMode = AppOrientationMode.unrestricted;
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } catch (_) {
      // 避免早期初始化异常影响应用启动
    }
  }

  /// 依据当前屏幕尺寸及 Cover Flow 状态同步设置屏幕方向
  static void syncWithMetrics({
    required double shortestSide,
    required bool isCoverFlowActive,
  }) {
    if (!isMobile) {
      return;
    }

    final bool isTabletOrDesktop = shortestSide >= tabletShortestSideBreakpoint;

    final AppOrientationMode targetMode;
    if (isTabletOrDesktop) {
      targetMode = AppOrientationMode.unrestricted;
    } else if (isCoverFlowActive) {
      targetMode = AppOrientationMode.landscapeOnly;
    } else {
      targetMode = AppOrientationMode.portraitOnly;
    }

    if (currentMode == targetMode) {
      return;
    }

    currentMode = targetMode;

    switch (targetMode) {
      case AppOrientationMode.unrestricted:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        break;
      case AppOrientationMode.landscapeOnly:
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        break;
      case AppOrientationMode.portraitOnly:
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        break;
    }
  }

  /// 平滑切换 Cover Flow 沉浸模式（带暗转/亮转遮罩过渡）
  /// - 手机端：暗色模式淡入暗色遮罩，亮色模式淡入白色遮罩，在遮罩掩护下旋转屏幕并切换视图，渲染完成后淡出遮罩。
  /// - 平板/桌面端：无需强制横竖屏旋转，直接切换视图。
  static Future<void> toggleCoverFlow(
    WidgetRef ref,
    BuildContext context, {
    required bool target,
  }) async {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final bool isPhone = isMobile && shortestSide < tabletShortestSideBreakpoint;

    // 非手机端（平板或桌面），无需旋转屏幕，直接切换
    if (!isPhone || skipAnimationForTest) {
      ref.read(isAlbum3DViewActiveProvider.notifier).set(target);
      return;
    }

    final curtainState = ref.read(appOrientationCurtainProvider);
    if (curtainState.isTransitioning) {
      // 转场中避免重复触发
      return;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 暗色模式用纯黑遮罩，亮色模式用纯白遮罩
    final Color curtainColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

    final notifier = ref.read(appOrientationCurtainProvider.notifier);

    // 1. 遮罩淡入（画面快速变暗或变白，遮盖即将发生的拉伸变形）
    const int fadeInMs = 140;
    notifier.fadeIn(color: curtainColor, durationMs: fadeInMs);
    await Future.delayed(const Duration(milliseconds: fadeInMs));

    // 2. 此时屏幕已被完全遮盖，安全更新 3D 状态并请求系统屏幕旋转
    ref.read(isAlbum3DViewActiveProvider.notifier).set(target);
    syncWithMetrics(
      shortestSide: shortestSide,
      isCoverFlowActive: target,
    );

    // 3. 等待系统屏幕旋转与底层首帧布局完成
    // target 为 true 则等待横屏，false 则等待竖屏
    final stopwatch = Stopwatch()..start();
    const timeoutMs = 450;
    while (context.mounted && stopwatch.elapsedMilliseconds < timeoutMs) {
      final view = PlatformDispatcher.instance.views.firstOrNull;
      if (view != null) {
        final size = view.physicalSize;
        final bool isTargetReached = target
            ? (size.width > size.height)
            : (size.height >= size.width);
        if (isTargetReached) {
          break;
        }
      }
      await Future.delayed(const Duration(milliseconds: 20));
    }

    // 确保当前方向下的新布局与排版在 GPU 上渲染完成
    try {
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {
      // 避免在测试环境等特殊情况下由于 frame 未调度抛出异常
    }

    // 4. 遮罩平滑淡出，呈现排版完美的视图
    const int fadeOutMs = 180;
    notifier.fadeOut(durationMs: fadeOutMs);
    await Future.delayed(const Duration(milliseconds: fadeOutMs));
  }
}

/// 监听屏幕方向及 Riverpod 状态的 Widget
class AppOrientationWatcher extends ConsumerStatefulWidget {
  final Widget child;

  const AppOrientationWatcher({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<AppOrientationWatcher> createState() => _AppOrientationWatcherState();
}

class _AppOrientationWatcherState extends ConsumerState<AppOrientationWatcher> {
  @override
  Widget build(BuildContext context) {
    final isCoverFlowActive = ref.watch(isCoverFlowImmersiveActiveProvider);
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final curtain = ref.watch(appOrientationCurtainProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppOrientationManager.syncWithMetrics(
        shortestSide: shortestSide,
        isCoverFlowActive: isCoverFlowActive,
      );
    });

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final defaultCurtainColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final Color effectiveCurtainColor = curtain.color ?? defaultCurtainColor;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: curtain.opacity == 0.0,
            child: AnimatedOpacity(
              opacity: curtain.opacity,
              duration: Duration(milliseconds: curtain.durationMs),
              curve: Curves.easeInOut,
              child: ColoredBox(
                color: effectiveCurtainColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
