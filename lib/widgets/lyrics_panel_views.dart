import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../player/lyrics_controller_state.dart';
import 'auto_size_single_line_text.dart';

class LyricsPanelEmptyState extends StatelessWidget {
  const LyricsPanelEmptyState({
    super.key,
    required this.accentColor,
    required this.isLoading,
    required this.isGenerating,
    required this.canGenerateLyrics,
    required this.onGeneratePressed,
    required this.generateButtonLabel,
    required this.onSecondaryTapDown,
  });

  final Color accentColor;
  final bool isLoading;
  final bool isGenerating;
  final bool canGenerateLyrics;
  final Future<void> Function() onGeneratePressed;
  final String generateButtonLabel;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading && !isGenerating) ...[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    isLoading ? '正在查找歌词' : '暂无歌词',
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
                        onPressed: isGenerating
                            ? null
                            : () => onGeneratePressed(),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor.withValues(alpha: 0.95),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        icon: isGenerating
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(generateButtonLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LyricsPanelPlainLyricsView extends StatelessWidget {
  const LyricsPanelPlainLyricsView({
    super.key,
    required this.displayPlainLyrics,
    required this.onSecondaryTapDown,
  });

  final String displayPlainLyrics;
  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
                PointerDeviceKind.stylus,
              },
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(
                    displayPlainLyrics,
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
        ],
      ),
    );
  }
}

class LyricsPanelTimedLyricsView extends StatelessWidget {
  const LyricsPanelTimedLyricsView({
    super.key,
    required this.accentColor,
    required this.lyrics,
    required this.lyricsState,
    required this.displayLines,
    required this.hasTimedLyrics,
    required this.activeIndex,
    required this.seekPreviewIndex,
    required this.scrollController,
    required this.itemExtent,
    required this.scrollBehavior,
    required this.onSecondaryTapDown,
    required this.onScrollNotification,
  });

  final Color accentColor;
  final MusicLyric? lyrics;
  final LyricsControllerState lyricsState;
  final List<LyricLine> displayLines;
  final bool hasTimedLyrics;
  final int activeIndex;
  final int? seekPreviewIndex;
  final ScrollController scrollController;
  final double itemExtent;
  final ScrollBehavior scrollBehavior;
  final GestureTapDownCallback onSecondaryTapDown;
  final NotificationListenerCallback<ScrollNotification> onScrollNotification;

  static const double _lyricsListVerticalPadding = 16.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final edgePadding = _lyricsListEdgePadding(constraints.maxHeight);
              return NotificationListener<ScrollNotification>(
                onNotification: onScrollNotification,
                child: ScrollConfiguration(
                  behavior: scrollBehavior,
                  child: ListView.builder(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: edgePadding,
                    ),
                    itemExtent: itemExtent,
                    itemCount: displayLines.length,
                    itemBuilder: (context, index) {
                      final line = displayLines[index];
                      final translated =
                          lyrics
                              ?.translatedLineAt(
                                index,
                                lyricsState.lyricsTranslationLanguageCode,
                              )
                              .trim() ??
                          '';
                      final isSeekPreview =
                          hasTimedLyrics && index == seekPreviewIndex;
                      final distance = (index - activeIndex).abs();
                      final isActive =
                          hasTimedLyrics &&
                          index == activeIndex &&
                          !isSeekPreview;
                      final isNear =
                          hasTimedLyrics &&
                          distance <= 1 &&
                          !isSeekPreview &&
                          !isActive;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSeekPreview
                              ? accentColor.withValues(alpha: 0.22)
                              : isActive
                              ? accentColor.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 220),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge!
                                        .copyWith(
                                          color: isSeekPreview
                                              ? accentColor
                                              : isActive
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: isNear ? 0.72 : 0.46,
                                                ),
                                          fontSize: isSeekPreview || isActive
                                              ? 18
                                              : 16,
                                          fontWeight: isSeekPreview
                                              ? FontWeight.w800
                                              : isActive
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          height: 1.4,
                                          leadingDistribution:
                                              TextLeadingDistribution.even,
                                        ),
                                    child: AutoSizeSingleLineText(
                                      line.text,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (translated.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  translated,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isSeekPreview
                                        ? accentColor.withValues(alpha: 0.92)
                                        : Colors.white.withValues(alpha: 0.62),
                                    fontSize: 13,
                                    height: 1.3,
                                    leadingDistribution:
                                        TextLeadingDistribution.even,
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
              );
            },
          ),
        ],
      ),
    );
  }

  double _lyricsListEdgePadding(double viewportHeight) {
    if (!viewportHeight.isFinite || viewportHeight <= 0) {
      return _lyricsListVerticalPadding;
    }

    return math.max(
      _lyricsListVerticalPadding,
      viewportHeight / 2 - itemExtent / 2,
    );
  }
}
