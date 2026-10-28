import 'package:flutter/material.dart';

/// 网格卡片的统一悬停反馈：指针进入时轻微放大。
///
/// 目录页、歌曲页、远程服务器页共用同一份实现，避免每处各写一个 `MouseRegion`。
class HoverableCard extends StatefulWidget {
  const HoverableCard({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// 是否启用悬停轻微放大反馈。
  ///
  /// 在列表与网格动态切换过渡时保持此组件始终挂载在树上（仅通过 [enabled] 开关），
  /// 避免 Widget 树根节点 RuntimeType 突变导致整屏条目 unmount / remount。
  final bool enabled;

  @override
  State<HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<HoverableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _isHovered = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _isHovered = false) : null,
      child: AnimatedScale(
        scale: (widget.enabled && _isHovered) ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
