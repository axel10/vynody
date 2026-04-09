import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../player/lyrics_generation_phase.dart';

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lines,
    required this.lyrics,
    required this.position,
    required this.isLoading,
    required this.isTranslating,
    required this.isGeneratingLyrics,
    required this.lyricsTranslationStatus,
    required this.lyricsGenerationPhase,
    required this.lyricsGenerationProgress,
    required this.hasLyrics,
    required this.lyricsSearchAttempted,
    required this.plainLyrics,
    required this.translationLanguageCode,
    this.onTranslateLyrics,
    this.onGenerateLyrics,
    this.onClearLyricsCache,
    this.onClearTranslationCache,
    this.onRequeryLyrics,
    this.accentColor,
  });

  final List<LyricLine> lines;
  final MusicLyric? lyrics;
  final Duration position;
  final bool isLoading;
  final bool isTranslating;
  final bool isGeneratingLyrics;
  final String lyricsTranslationStatus;
  final LyricsGenerationPhase lyricsGenerationPhase;
  final double lyricsGenerationProgress;
  final bool hasLyrics;
  final bool lyricsSearchAttempted;
  final String plainLyrics;
  final String translationLanguageCode;
  final VoidCallback? onTranslateLyrics;
  final VoidCallback? onGenerateLyrics;
  final VoidCallback? onClearLyricsCache;
  final VoidCallback? onClearTranslationCache;
  final Future<void> Function()? onRequeryLyrics;
  final Color? accentColor;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const double _itemExtent = 72.0;
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  bool _isAutoScrollPaused = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildTranslationIndicator(Color accent) {
    if (!widget.isTranslating) return const SizedBox.shrink();

    final status = widget.lyricsTranslationStatus.trim();
    return Positioned(
      top: 12,
      right: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
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
    Offset globalPosition, {
    bool requeryOnly = false,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final items = <PopupMenuEntry<String>>[
      if (!requeryOnly && _hasTimedLyrics)
        PopupMenuItem<String>(
          value: 'toggle_auto_scroll',
          child: Text(_isAutoScrollPaused ? '恢复自动滚动' : '暂停自动滚动'),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'translate',
          enabled: widget.onTranslateLyrics != null && !widget.isTranslating,
          child: const Text('翻译歌词'),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'clear_lyrics_cache',
          enabled: widget.onClearLyricsCache != null,
          child: const Text('清除当前歌词缓存'),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'clear_translation_cache',
          enabled: widget.onClearTranslationCache != null,
          child: const Text('清除当前翻译缓存'),
        ),
      if (requeryOnly)
        PopupMenuItem<String>(
          value: 'requery',
          enabled: widget.onRequeryLyrics != null,
          child: const Text('重新查询'),
        ),
    ];

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: items,
    );

    if (!mounted) return;

    if (selected == 'toggle_auto_scroll') {
      setState(() {
        _isAutoScrollPaused = !_isAutoScrollPaused;
      });
      if (!_isAutoScrollPaused) {
        _scheduleScrollIfNeeded(force: true);
      }
    } else if (selected == 'translate') {
      await Future<void>.microtask(() => widget.onTranslateLyrics?.call());
    } else if (selected == 'clear_lyrics_cache') {
      await Future<void>.microtask(() => widget.onClearLyricsCache?.call());
    } else if (selected == 'clear_translation_cache') {
      await Future<void>.microtask(
        () => widget.onClearTranslationCache?.call(),
      );
    } else if (selected == 'requery') {
      await widget.onRequeryLyrics?.call();
    }
  }

  String _buildGenerateButtonLabel() {
    final progress = widget.lyricsGenerationProgress.clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    switch (widget.lyricsGenerationPhase) {
      case LyricsGenerationPhase.uploading:
        return '上传中 $percent%';
      case LyricsGenerationPhase.processing:
        return '处理中...';
      case LyricsGenerationPhase.generating:
        return '生成中...';
      case LyricsGenerationPhase.idle:
        break;
    }

    return widget.isGeneratingLyrics ? '生成中...' : '生成歌词';
  }

  void _scheduleScrollIfNeeded({bool force = false}) {
    if (widget.lines.isEmpty || !_hasTimedLyrics || _isAutoScrollPaused) {
      return;
    }

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
    final hasRenderableLyrics =
        widget.hasLyrics &&
        (widget.lines.isNotEmpty || widget.plainLyrics.trim().isNotEmpty);

    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!hasRenderableLyrics) {
      // 只有在已经尝试过联网找歌词、但仍然没有结果时，才显示“生成歌词”按钮。
      // 这样避免用户在歌词还在加载中时误以为可以直接生成。
      final canGenerateLyrics =
          widget.lyricsSearchAttempted && widget.onGenerateLyrics != null;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: widget.onRequeryLyrics == null
            ? null
            : (details) {
                _showContextMenu(
                  context,
                  details.globalPosition,
                  requeryOnly: true,
                );
              },
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '暂无歌词',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 16,
                      ),
                    ),
                    if (canGenerateLyrics) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 42,
                        child: FilledButton.icon(
                          // 点击后只触发外部传入的回调，真正的生成流程由 AudioService 处理。
                          onPressed: widget.isGeneratingLyrics
                              ? null
                              : widget.onGenerateLyrics,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent.withValues(alpha: 0.95),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          icon: widget.isGeneratingLyrics
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                )
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: Text(_buildGenerateButtonLabel()),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.isTranslating) _buildTranslationIndicator(accent),
          ],
        ),
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
            if (widget.isTranslating) _buildTranslationIndicator(accent),
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
          if (widget.isTranslating) _buildTranslationIndicator(accent),
        ],
      ),
    );
  }
}
