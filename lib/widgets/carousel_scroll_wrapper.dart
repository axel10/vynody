import 'package:flutter/material.dart';

/// 胶囊翻页按钮方向
enum PillNavDirection { left, right }

/// 通用胶囊悬浮翻页按钮
class PillNavButton extends StatefulWidget {
  const PillNavButton({
    super.key,
    required this.direction,
    required this.visible,
    required this.onTap,
    this.height = 56.0,
  });

  final PillNavDirection direction;
  final bool visible;
  final VoidCallback onTap;

  /// 胶囊按钮高度。紧凑横条（如顶部快捷入口）传入较小值以免撑满整行。
  final double height;

  @override
  State<PillNavButton> createState() => _PillNavButtonState();
}

class _PillNavButtonState extends State<PillNavButton> {
  bool _isButtonHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 暗色模式：基础半透明深灰，悬停时加深至纯黑；亮色模式：基础半透明白，悬停时加深为沉着深灰
    final baseColor = isDark
        ? const Color(0xFF28282A).withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.90);
    final hoverColor = isDark
        ? const Color(0xFF101012).withValues(alpha: 0.98)
        : const Color(0xFFD1D5DB).withValues(alpha: 0.98);

    final borderColor = isDark
        ? Colors.white.withValues(alpha: _isButtonHovered ? 0.25 : 0.12)
        : Colors.black.withValues(alpha: _isButtonHovered ? 0.16 : 0.08);

    final iconColor = isDark
        ? Colors.white.withValues(alpha: _isButtonHovered ? 1.0 : 0.85)
        : (_isButtonHovered ? Colors.black : Colors.black87);

    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        opacity: widget.visible ? 1.0 : 0.0,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isButtonHovered = true),
          onExit: (_) => setState(() => _isButtonHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: widget.height,
              decoration: BoxDecoration(
                color: _isButtonHovered ? hoverColor : baseColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark
                          ? (_isButtonHovered ? 0.45 : 0.28)
                          : (_isButtonHovered ? 0.20 : 0.10),
                    ),
                    blurRadius: _isButtonHovered ? 12 : 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  widget.direction == PillNavDirection.left
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                  size: 22,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 支持鼠标悬停显示翻页按钮的横向滚动容器
class CarouselScrollWrapper extends StatefulWidget {
  const CarouselScrollWrapper({
    super.key,
    required this.height,
    required this.builder,
    this.centerHeight,
    this.buttonPadding = 12.0,
    this.leftButtonOffset = 0.0,
    this.buttonHeight = 56.0,
  });

  final double height;
  final Widget Function(BuildContext context, ScrollController controller) builder;
  final double? centerHeight;
  final double buttonPadding;
  final double leftButtonOffset;
  final double buttonHeight;

  @override
  State<CarouselScrollWrapper> createState() => _CarouselScrollWrapperState();
}

class _CarouselScrollWrapperState extends State<CarouselScrollWrapper> {
  final ScrollController _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void didUpdateWidget(covariant CarouselScrollWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.pixels > 6.0;
    final canRight = position.pixels < (position.maxScrollExtent - 6.0);
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scrollNext() {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    // 翻一页：滑动约 82% 视口宽度，保留上下文锚点
    final delta = (viewport * 0.82).clamp(120.0, double.infinity);
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollPrevious() {
    if (!_scrollController.hasClients) return;
    final viewport = _scrollController.position.viewportDimension;
    final delta = (viewport * 0.82).clamp(120.0, double.infinity);
    final target = (_scrollController.offset - delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final targetCenter = widget.centerHeight ?? widget.height;
    final btnHeight = widget.buttonHeight;
    final btnTop = ((targetCenter - btnHeight) / 2.0).clamp(0.0, double.infinity);

    return MouseRegion(
      onEnter: (_) {
        _updateScrollState();
        setState(() => _isHovered = true);
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification ||
              notification is OverscrollNotification ||
              notification is UserScrollNotification) {
            _updateScrollState();
          }
          return false;
        },
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              widget.builder(context, _scrollController),

              // 左侧往前翻一页按钮
              Positioned(
                left: widget.leftButtonOffset + widget.buttonPadding,
                top: btnTop,
                child: PillNavButton(
                  direction: PillNavDirection.left,
                  visible: _isHovered && _canScrollLeft,
                  onTap: _scrollPrevious,
                  height: widget.buttonHeight,
                ),
              ),

              // 右侧往后翻一页按钮
              Positioned(
                right: widget.buttonPadding,
                top: btnTop,
                child: PillNavButton(
                  direction: PillNavDirection.right,
                  visible: _isHovered && _canScrollRight,
                  onTap: _scrollNext,
                  height: widget.buttonHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
