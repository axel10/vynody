import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A custom marquee text widget that automatically scrolls horizontally
/// back-and-forth if the text width exceeds the available container width.
///
/// 宽度收缩到文本自身宽度（与 [Text] 一致），横向对齐由调用方的
/// [Align] / 父级约束决定，因此内部不需要 [LayoutBuilder]。
/// 文本超出可用宽度时，内部的横向滚动视图负责跑马灯。
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration scrollDelay;
  final double velocity; // Speed in logical pixels per second

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.scrollDelay = const Duration(seconds: 2),
    this.velocity = 35.0,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;
  Timer? _debounceTimer;
  int _currentCycleId = 0;

  @override
  void initState() {
    super.initState();
    // 首帧布局完成后才有真实的视口尺寸，此时再决定要不要滚。
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestMeasure());
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      // 内容换了：滚动位置和周期都要从头算。
      _requestMeasure(resetScroll: true);
    } else if (!_hasSameHorizontalMetrics(oldWidget.style, widget.style)) {
      // 只有会影响水平排版的字段变了才需要重测溢出宽度。
      // 但不能跳回起点：歌词模式转场里字号每帧都在插值，
      // 每次都 jumpTo(0) 会把跑马灯反复弹回开头。
      _requestMeasure();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// 只比较会改变文本横向 advance 的字段。
  ///
  /// `height` / `color` / `leadingDistribution` 等纵向或装饰属性在转场动画里
  /// 每帧都在变，但它们不影响文本宽度，不应当作「需要重测」的信号。
  static bool _hasSameHorizontalMetrics(TextStyle a, TextStyle b) {
    return a.fontSize == b.fontSize &&
        a.fontWeight == b.fontWeight &&
        a.fontStyle == b.fontStyle &&
        a.letterSpacing == b.letterSpacing &&
        a.wordSpacing == b.wordSpacing &&
        a.fontFamily == b.fontFamily &&
        a.textBaseline == b.textBaseline &&
        a.locale == b.locale &&
        listEquals(a.fontFamilyFallback, b.fontFamilyFallback) &&
        listEquals(a.fontFeatures, b.fontFeatures);
  }

  /// 排一次溢出测量。已经有一次排队时直接复用，避免每帧 cancel/新建 Timer。
  void _requestMeasure({bool resetScroll = false}) {
    if (!mounted) return;
    if (resetScroll) {
      _resetScrollPosition();
    }
    if (_debounceTimer?.isActive ?? false) return;
    // 延迟测量，让转场等布局动画先跑完，避免中途反复起停。
    _debounceTimer = Timer(const Duration(milliseconds: 500), _measureAndScroll);
  }

  void _resetScrollPosition() {
    _scrollTimer?.cancel();
    _currentCycleId++;
    if (_scrollController.hasClients && _scrollController.offset != 0.0) {
      _scrollController.jumpTo(0.0);
    }
  }

  void _measureAndScroll() {
    if (!mounted) return;
    if (!_scrollController.hasClients) return;

    // 已经在滚（或有一轮滚动排着队）就不要重排。
    // 转场里字号每帧都在插值，会不断请求重测；每 500ms 打断一次
    // 会让跑马灯永远走不出起跑线。
    // 内容/文案换了那条路径会先 _resetScrollPosition()，走不到这里。
    if (_scrollController.position.isScrollingNotifier.value ||
        (_scrollTimer?.isActive ?? false)) {
      return;
    }

    _scrollTimer?.cancel();
    _currentCycleId++;
    final cycleId = _currentCycleId;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (maxScrollExtent > 0) {
      _startScrollCycle(cycleId, maxScrollExtent);
    }
  }

  void _startScrollCycle(int cycleId, double maxScrollExtent) {
    if (!mounted || cycleId != _currentCycleId) return;

    _scrollTimer = Timer(widget.scrollDelay, () async {
      if (!mounted || cycleId != _currentCycleId) return;

      final duration = Duration(
        milliseconds: (maxScrollExtent / widget.velocity * 1000).round(),
      );

      // Scroll to the end
      try {
        await _scrollController.animateTo(
          maxScrollExtent,
          duration: duration,
          curve: Curves.linear,
        );
      } catch (_) {
        // Animation was cancelled or failed (e.g. by jumpTo/animateTo elsewhere)
      }

      if (!mounted || cycleId != _currentCycleId) return;

      // Pause at the end
      _scrollTimer = Timer(widget.scrollDelay, () async {
        if (!mounted || cycleId != _currentCycleId) return;

        // Scroll back to the start
        try {
          await _scrollController.animateTo(
            0.0,
            duration: duration,
            curve: Curves.linear,
          );
        } catch (_) {
          // Animation was cancelled or failed
        }

        if (!mounted || cycleId != _currentCycleId) return;

        // Loop the cycle
        _startScrollCycle(cycleId, maxScrollExtent);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        // 视口或内容尺寸变化（窗口缩放、字号/文案变化）时才需要重测。
        // 滚动本身不改变 metrics，不会在这里形成回环。
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _requestMeasure();
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Text(widget.text, style: widget.style, maxLines: 1),
          ),
        ),
      ),
    );
  }
}
