import 'package:flutter/material.dart';

/// 网格卡片的统一悬停反馈：指针进入时轻微放大。
///
/// 目录页、歌曲页、远程服务器页共用同一份实现，避免每处各写一个 `MouseRegion`。
class HoverableCard extends StatefulWidget {
  const HoverableCard({super.key, required this.child});
  final Widget child;

  @override
  State<HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<HoverableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
