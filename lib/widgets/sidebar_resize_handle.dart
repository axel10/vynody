import 'package:flutter/material.dart';

/// 侧边栏/抽屉边缘拖拽调整宽度的热区手柄。
///
/// 位于侧边栏或抽屉边缘，在鼠标悬停时展示列宽调整光标并呈现微光指示线，
/// 支持水平手势拖拽调节以及双击快速复位默认宽度。
class SidebarResizeHandle extends StatefulWidget {
  /// 是否位于右侧面板的左边缘（true 时为抽屉左边缘，false 时为左侧 Rail 栏右边缘）。
  final bool isLeft;

  /// 双击手柄触发的回调（通常用于恢复默认推荐宽度）。
  final VoidCallback? onDoubleTap;

  /// 开始拖拽回调。
  final GestureDragStartCallback? onDragStart;

  /// 拖拽更新回调。
  final GestureDragUpdateCallback? onDragUpdate;

  /// 拖拽结束回调。
  final GestureDragEndCallback? onDragEnd;

  /// 拖拽取消回调。
  final GestureDragCancelCallback? onDragCancel;

  /// 手柄热区宽度，默认为 8.0 逻辑像素。
  final double hitTestWidth;

  const SidebarResizeHandle({
    super.key,
    required this.isLeft,
    this.onDoubleTap,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.hitTestWidth = 8.0,
  });

  @override
  State<SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<SidebarResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final Color indicatorColor = (_isHovered || _isDragging)
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.75 : 0.85)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: (details) {
          setState(() => _isDragging = true);
          widget.onDragStart?.call(details);
        },
        onHorizontalDragUpdate: widget.onDragUpdate,
        onHorizontalDragEnd: (details) {
          setState(() => _isDragging = false);
          widget.onDragEnd?.call(details);
        },
        onHorizontalDragCancel: () {
          setState(() => _isDragging = false);
          widget.onDragCancel?.call();
        },
        child: SizedBox(
          width: widget.hitTestWidth,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: (_isHovered || _isDragging) ? 2.0 : 0.0,
              decoration: BoxDecoration(
                color: indicatorColor,
                borderRadius: BorderRadius.circular(1.0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
