import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart'
    show LibraryZoomScope, LibraryZoomScopeRange;
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

export 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart'
    show kFolderZoomPinchStepRatio, kFolderZoomWheelGestureGap;

/// 主项目与 [ZoomGestureLayer] 之间的薄适配层：
///
/// 仅负责将 [LibraryZoomScope] 对应的档位状态、档位范围以及混合视图锁定逻辑
/// 绑定到 Riverpod 的 [settingsServiceProvider]，所有跨平台手势识别、滚轮簇节流、
/// 双指欧氏距离跟手与捏合期无障碍语义屏蔽均统一收归插件内部实现。
class FolderZoomGestureLayer extends ConsumerWidget {
  const FolderZoomGestureLayer({
    super.key,
    required this.child,
    this.scope = LibraryZoomScope.folder,
    this.reorderActive,
    this.zoomGesturesEnabled = true,
  });

  final Widget child;
  final LibraryZoomScope scope;

  /// 拖拽排序进行中为 true。传 `ZoomReorderController.reorderActive` 即可。
  final ValueListenable<bool>? reorderActive;

  /// 整段禁用缩放手势（例如排序模式下槽位几何不应换档）。
  final bool zoomGesturesEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.zoomScaleFor(scope)),
    );
    final bool isHybridLocked = scope == LibraryZoomScope.folder &&
        ref.watch(
          settingsServiceProvider.select((s) => s.folderHybridView),
        );

    return ZoomGestureLayer(
      zoomScale: zoomScale,
      minScale: scope.minZoomTier,
      maxScale: scope.maxZoomTier,
      enabled: zoomGesturesEnabled && !isHybridLocked,
      reorderActive: reorderActive,
      onZoomScaleChanged: (next) {
        final settings = ref.read(settingsServiceProvider);
        settings.setZoomScale(scope, scope.clampZoomScale(next));
      },
      child: child,
    );
  }
}
