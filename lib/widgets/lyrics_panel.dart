import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../player/lyrics_service.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lines,
    required this.position,
    required this.isLoading,
    required this.hasLyrics,
    required this.isSynced,
    required this.plainLyrics,
    this.accentColor,
  });

  final List<LyricLine> lines;
  final Duration position;
  final bool isLoading;
  final bool hasLyrics;
  final bool isSynced;
  final String plainLyrics;
  final Color? accentColor;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const double _itemExtent = 48.0;
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScrollIfNeeded();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleScrollIfNeeded(force: true);
    });
  }

  void _scheduleScrollIfNeeded({bool force = false}) {
    if (!widget.isSynced || widget.lines.isEmpty) return;

    final activeIndex = _activeLineIndex();
    if (!force && activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewportHeight = _scrollController.position.viewportDimension;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final target = math.max(
        0.0,
        math.min(
          activeIndex * _itemExtent - viewportHeight / 2 + _itemExtent / 2,
          maxExtent,
        ),
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  int _activeLineIndex() {
    if (widget.lines.isEmpty) return -1;

    final current = widget.position.inMilliseconds;
    int low = 0;
    int high = widget.lines.length - 1;
    int answer = 0;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final midMs = widget.lines[mid].timestamp.inMilliseconds;
      if (midMs <= current) {
        answer = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return answer;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!widget.hasLyrics) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
          ),
        ),
      );
    }

    if (!widget.isSynced || widget.lines.isEmpty) {
      return ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SelectableText(
            widget.plainLyrics,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 18,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    _scheduleScrollIfNeeded();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
        itemExtent: _itemExtent,
        itemCount: widget.lines.length,
        itemBuilder: (context, index) {
          final line = widget.lines[index];
          final activeIndex = _activeLineIndex();
          final distance = (index - activeIndex).abs();
          final isActive = index == activeIndex;
          final isNear = distance <= 1;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: isActive ? 6 : 0,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                if (isActive) const SizedBox(width: 8),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    style: TextStyle(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: isNear ? 0.72 : 0.46),
                      fontSize: isActive ? 18 : 16,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      height: 1.2,
                    ),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
