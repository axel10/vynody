import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lines,
    required this.lyrics,
    required this.position,
    required this.isLoading,
    required this.isTranslating,
    required this.hasLyrics,
    required this.plainLyrics,
    required this.translationLanguageCode,
    this.onTranslateLyrics,
    this.accentColor,
  });

  final List<LyricLine> lines;
  final MusicLyric? lyrics;
  final Duration position;
  final bool isLoading;
  final bool isTranslating;
  final bool hasLyrics;
  final String plainLyrics;
  final String translationLanguageCode;
  final VoidCallback? onTranslateLyrics;
  final Color? accentColor;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const double _itemExtent = 72.0;
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

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'translate',
          enabled: widget.onTranslateLyrics != null && !widget.isTranslating,
          child: const Text('翻译歌词'),
        ),
      ],
    );

    if (selected == 'translate') {
      await Future<void>.microtask(() => widget.onTranslateLyrics?.call());
    }
  }

  void _scheduleScrollIfNeeded({bool force = false}) {
    if (widget.lines.isEmpty || !_hasTimedLyrics) return;

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
    if (widget.lines.isEmpty || !_hasTimedLyrics) return -1;

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

  bool get _hasTimedLyrics {
    return widget.lines.any((line) => line.isTimed);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;

    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!widget.hasLyrics) {
      return Stack(
        children: [
          Center(
            child: Text(
              '暂无歌词',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ),
          if (widget.isTranslating)
            const Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      );
    }

    if (widget.lines.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) {
          _showContextMenu(context, details.globalPosition);
        },
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      widget.plainLyrics,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 18,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.isTranslating)
              const Positioned(
                top: 12,
                right: 12,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      );
    }

    _scheduleScrollIfNeeded();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) {
        _showContextMenu(context, details.globalPosition);
      },
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
              itemExtent: _itemExtent,
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = widget.lines[index];
                final translated =
                    widget.lyrics
                        ?.translatedLineAt(
                          index,
                          widget.translationLanguageCode,
                        )
                        .trim() ??
                    '';
                final activeIndex = _activeLineIndex();
                final distance = (index - activeIndex).abs();
                final isActive = _hasTimedLyrics && index == activeIndex;
                final isNear = _hasTimedLyrics && distance <= 1;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
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
                              style: Theme.of(context).textTheme.bodyLarge!
                                  .copyWith(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white.withValues(
                                            alpha: isNear ? 0.72 : 0.46,
                                          ),
                                    fontSize: isActive ? 18 : 16,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w400,
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
                      if (translated.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            translated,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 13,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          if (widget.isTranslating)
            const Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
