import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/models/music_lyric.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/lyrics/lyrics_controller_state.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'playback_ui_tuning.dart';

class LyricsPanelEmptyState extends StatelessWidget {
  const LyricsPanelEmptyState({
    super.key,
    required this.accentColor,
    required this.textColor,
    required this.isLoading,
    required this.isGenerating,
    required this.canGenerateLyrics,
    required this.onGeneratePressed,
    required this.generateButtonLabel,
    required this.onContextMenu,
    required this.bottomSpacerHeight,
    required this.bottomTabBarHeight,
  });

  final Color accentColor;
  final Color textColor;
  final bool isLoading;
  final bool isGenerating;
  final bool canGenerateLyrics;
  final Future<void> Function() onGeneratePressed;
  final String generateButtonLabel;
  final void Function(Offset globalPosition) onContextMenu;
  final double bottomSpacerHeight;
  final double bottomTabBarHeight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final buttonForegroundColor =
        ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        onContextMenu(details.globalPosition);
      },
      child: Center(
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
                isLoading ? l10n.searchingLyrics : l10n.noLyrics,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
              if (canGenerateLyrics) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 42,
                  child: FilledButton.icon(
                    onPressed: isGenerating ? null : () => onGeneratePressed(),
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor.withValues(alpha: 0.95),
                      foregroundColor: buttonForegroundColor,
                      disabledBackgroundColor: accentColor.withValues(alpha: 0.95),
                      disabledForegroundColor: buttonForegroundColor,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    icon: isGenerating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: buttonForegroundColor.withValues(
                                alpha: 0.8,
                              ),
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
    );
  }
}

class LyricsPanelTimedLyricsView extends StatefulWidget {
  const LyricsPanelTimedLyricsView({
    super.key,
    required this.lyrics,
    required this.lyricsState,
    required this.displayLines,
    required this.hasTimedLyrics,
    required this.activeIndex,
    required this.isAutoScrollPaused,
    required this.lyricsFontScale,
    required this.scrollController,
    required this.scrollBehavior,
    required this.textColor,
    required this.secondaryTextColor,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
    required this.onContextMenu,
    required this.bottomSpacerHeight,
    this.bottomTabBarHeight = 0.0,
    required this.lyricsStyle,
    required this.isFocusMode,
    this.onLineTapped,
    required this.scrollDelta,
    required this.scrollTriggerTime,
    required this.isEnteringFocusMode,
    required this.firstVisibleIndex,
    required this.isSmallWin,
    required this.maxWidth,
    required this.isGenerating,
  });

  final MusicLyric? lyrics;
  final LyricsControllerState lyricsState;
  final List<LyricLine> displayLines;
  final bool hasTimedLyrics;
  final int activeIndex;
  final bool isAutoScrollPaused;
  final double lyricsFontScale;
  final ScrollController scrollController;
  final ScrollBehavior scrollBehavior;
  final Color textColor;
  final Color secondaryTextColor;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final VoidCallback? onVerticalDragCancel;
  final void Function(Offset globalPosition) onContextMenu;
  final double bottomSpacerHeight;
  final double bottomTabBarHeight;
  final LyricsStyle lyricsStyle;
  final bool isFocusMode;
  final ValueChanged<int>? onLineTapped;
  final double scrollDelta;
  final int scrollTriggerTime;
  final bool isEnteringFocusMode;
  final int firstVisibleIndex;
  final bool isSmallWin;
  final double maxWidth;
  final bool isGenerating;

  @override
  State<LyricsPanelTimedLyricsView> createState() => _LyricsPanelTimedLyricsViewState();
}

class _LyricsPanelTimedLyricsViewState extends State<LyricsPanelTimedLyricsView> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final targetLang = widget.lyricsState.lyricsTranslationLanguageCode;
    final effectiveLang = widget.lyrics?.getEffectiveTranslationLanguage(targetLang) ?? targetLang;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: widget.isAutoScrollPaused || widget.lyricsStyle == LyricsStyle.apple ? null : widget.onVerticalDragStart,
      onVerticalDragUpdate: widget.isAutoScrollPaused || widget.lyricsStyle == LyricsStyle.apple ? null : widget.onVerticalDragUpdate,
      onVerticalDragEnd: widget.isAutoScrollPaused || widget.lyricsStyle == LyricsStyle.apple ? null : widget.onVerticalDragEnd,
      onVerticalDragCancel: widget.isAutoScrollPaused || widget.lyricsStyle == LyricsStyle.apple ? null : widget.onVerticalDragCancel,
      onSecondaryTapDown: (details) => widget.onContextMenu(details.globalPosition),
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        widget.onContextMenu(details.globalPosition);
      },
      child: Column(
        children: [
          Expanded(
            child: _LyricsFadeShaderMask(
              bottomSpacerHeight: widget.bottomSpacerHeight + widget.bottomTabBarHeight,
              child: ClipRect(
                clipper: const _VerticalOnlyClipper(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportHeight = constraints.maxHeight;
                    final extraBottomPadding = widget.lyricsStyle == LyricsStyle.apple
                        ? math.max(500.0, viewportHeight - (isPortrait ? 25.0 : 100.0))
                        : 500.0;
                    return ScrollConfiguration(
                      behavior: widget.scrollBehavior,
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        clipBehavior: Clip.none,
                        physics: widget.hasTimedLyrics
                            ? (widget.isAutoScrollPaused || widget.lyricsStyle == LyricsStyle.apple
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics())
                            : const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                        padding: EdgeInsets.only(
                          top: widget.lyricsStyle == LyricsStyle.apple
                              ? (widget.isSmallWin
                                  ? 30.0
                                  : (isPortrait ? 50.0 : 120.0))
                              : 0.0,
                          bottom: widget.bottomSpacerHeight + widget.bottomTabBarHeight + extraBottomPadding,
                        ),
                    child: Column(
                      children: List.generate(widget.displayLines.length, (index) {
                        final line = widget.displayLines[index];
                        final translated =
                            widget.lyrics
                                ?.translatedLineAt(
                                  index,
                                  effectiveLang,
                                )
                                .trim() ??
                            '';
                        final distance = (index - widget.activeIndex).abs();
                        final isActive = widget.hasTimedLyrics && index == widget.activeIndex;
                        final isHovered = _hoveredIndex == index;
                        final isNear =
                            widget.hasTimedLyrics && distance <= 1 && !isActive;
                        final targetScale = isActive && widget.lyricsStyle != LyricsStyle.apple ? 1.12 : 1.0;
                        final timedLyricFontSize = 16 * widget.lyricsFontScale;
                        final plainLyricFontSize = 18 * widget.lyricsFontScale;
                        final translationFontSize = 13 * widget.lyricsFontScale;
                        final basePadding = widget.lyricsStyle == LyricsStyle.apple
                            ? PlaybackPageUiTuning.appleLyricsVerticalPadding
                            : PlaybackPageUiTuning.traditionalLyricsVerticalPadding;
                        final verticalItemPadding = basePadding * widget.lyricsFontScale;
                        final translatedSpacing = 3 * widget.lyricsFontScale;
                        final lineStyle = widget.hasTimedLyrics
                            ? Theme.of(context).textTheme.bodyLarge!.copyWith(
                                color: isActive
                                    ? widget.textColor
                                    : (isHovered
                                        ? widget.textColor.withValues(alpha: 1.0)
                                        : widget.textColor.withValues(
                                            alpha: (isNear && widget.lyricsStyle != LyricsStyle.apple) ? 0.72 : 0.46,
                                          )),
                                fontSize: timedLyricFontSize,
                                fontWeight: (isActive || widget.lyricsStyle == LyricsStyle.apple)
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                height: 1.4,
                                leadingDistribution: TextLeadingDistribution.even,
                              )
                            : TextStyle(
                                color: widget.textColor,
                                fontSize: plainLyricFontSize,
                                fontWeight: widget.lyricsStyle == LyricsStyle.apple
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                height: 1.6,
                                leadingDistribution: TextLeadingDistribution.even,
                              );

                        final double layoutMaxWidth;
                        if (widget.lyricsStyle == LyricsStyle.apple) {
                          layoutMaxWidth = widget.maxWidth - 48.0;
                        } else {
                          layoutMaxWidth = widget.maxWidth - 48.0;
                        }

                        final animatedScaleChild = AnimatedScale(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          scale: targetScale,
                          alignment: widget.lyricsStyle == LyricsStyle.apple ? Alignment.centerLeft : Alignment.center,
                          child: SizedBox(
                            width: layoutMaxWidth,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: widget.lyricsStyle == LyricsStyle.apple ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: widget.lyricsStyle == LyricsStyle.apple ? MainAxisAlignment.start : MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        line.text,
                                        textAlign: widget.lyricsStyle == LyricsStyle.apple ? TextAlign.left : TextAlign.center,
                                        style: lineStyle,
                                      ),
                                    ),
                                  ],
                                ),
                                if (widget.hasTimedLyrics &&
                                    translated.isNotEmpty) ...[
                                  SizedBox(height: translatedSpacing),
                                  Padding(
                                    padding: widget.lyricsStyle == LyricsStyle.apple
                                        ? const EdgeInsets.only(right: 12)
                                        : const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      translated,
                                      textAlign: widget.lyricsStyle == LyricsStyle.apple ? TextAlign.left : TextAlign.center,
                                      style: TextStyle(
                                        color: isActive
                                            ? widget.secondaryTextColor.withValues(alpha: 1.0)
                                            : (isHovered
                                                ? widget.secondaryTextColor.withValues(alpha: 1.0)
                                                : widget.secondaryTextColor),
                                        fontSize: translationFontSize,
                                        fontWeight: (isActive || widget.lyricsStyle == LyricsStyle.apple)
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        height: 1.3,
                                        leadingDistribution:
                                            TextLeadingDistribution.even,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );

                        final bool shouldBlur = widget.hasTimedLyrics && widget.lyricsStyle == LyricsStyle.apple && widget.isFocusMode && !isActive && !isHovered;
                        final blurredChild = shouldBlur
                            ? ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                                child: animatedScaleChild,
                              )
                            : animatedScaleChild;

                        final lineContent = Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: verticalItemPadding,
                            horizontal: 24.0,
                          ),
                          child: Align(
                            alignment: widget.lyricsStyle == LyricsStyle.apple ? Alignment.centerLeft : Alignment.center,
                            child: blurredChild,
                          ),
                        );

                        final Widget itemWidget;
                        if (widget.onLineTapped != null) {
                          itemWidget = RepaintBoundary(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onLineTapped!(index),
                              child: lineContent,
                            ),
                          );
                        } else {
                          itemWidget = RepaintBoundary(
                            child: lineContent,
                          );
                        }

                        final wrappedItemWidget = MouseRegion(
                          hitTestBehavior: HitTestBehavior.opaque,
                          cursor: widget.hasTimedLyrics ? SystemMouseCursors.click : MouseCursor.defer,
                          onEnter: (_) {
                            setState(() {
                              _hoveredIndex = index;
                            });
                          },
                          onExit: (_) {
                            setState(() {
                              if (_hoveredIndex == index) {
                                _hoveredIndex = null;
                              }
                            });
                          },
                          child: itemWidget,
                        );

                        if (widget.lyricsStyle == LyricsStyle.apple && widget.isFocusMode && !widget.isGenerating) {
                          return StaggeredAppleLyricsScrollWrapper(
                            index: index,
                            activeIndex: widget.activeIndex,
                            scrollDelta: widget.scrollDelta,
                            scrollTriggerTime: widget.scrollTriggerTime,
                            isEnteringFocusMode: widget.isEnteringFocusMode,
                            firstVisibleIndex: widget.firstVisibleIndex,
                            child: wrappedItemWidget,
                          );
                        }
                        return wrappedItemWidget;
                      }),
                    ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalOnlyClipper extends CustomClipper<Rect> {
  const _VerticalOnlyClipper();

  @override
  Rect getClip(Size size) {
    const horizontalInset = 100000.0;
    return Rect.fromLTRB(
      -horizontalInset,
      0,
      size.width + horizontalInset,
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant _VerticalOnlyClipper oldClipper) => false;
}

class _LyricsFadeShaderMask extends StatelessWidget {
  const _LyricsFadeShaderMask({
    required this.bottomSpacerHeight,
    required this.child,
  });

  final double bottomSpacerHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) {
          final height = bounds.height > 0 ? bounds.height : 1.0;
          if (height <= 1.0) {
            return const LinearGradient(
              colors: [Colors.white, Colors.white],
            ).createShader(bounds);
          }

          const topFadeHeight = 30.0;
          final topFadeEnd = (topFadeHeight / height).clamp(0.0, 1.0);

          final isPortrait =
              MediaQuery.of(context).orientation == Orientation.portrait;

          final double bottomFadeEndHeight;
          final double bottomFadeStartHeight;

          if (isPortrait) {
            bottomFadeEndHeight =  20.0;
            bottomFadeStartHeight = 60.0;
          } else {
            bottomFadeEndHeight = 0.0;
            bottomFadeStartHeight = math.max(30.0, bottomSpacerHeight);
          }

          final bottomFadeStart =
              ((bounds.height - bottomFadeStartHeight) / bounds.height)
                  .clamp(0.0, 1.0);
          final bottomFadeEnd =
              ((bounds.height - bottomFadeEndHeight) / bounds.height)
                  .clamp(0.0, 1.0);

          final tEnd = topFadeEnd;
          final bStart = bottomFadeStart.clamp(tEnd, 1.0);
          final bEnd = bottomFadeEnd.clamp(bStart, 1.0);

          // Ensure stops are in increasing order
          final stops = [
            0.0,
            tEnd,
            bStart,
            bEnd,
            1.0,
          ];

          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
              Colors.transparent,
            ],
            stops: stops,
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}

class StaggeredAppleLyricsScrollWrapper extends StatefulWidget {
  final Widget child;
  final int index;
  final int activeIndex;
  final double scrollDelta;
  final int scrollTriggerTime;
  final bool isEnteringFocusMode;
  final int firstVisibleIndex;

  const StaggeredAppleLyricsScrollWrapper({
    super.key,
    required this.child,
    required this.index,
    required this.activeIndex,
    required this.scrollDelta,
    required this.scrollTriggerTime,
    required this.isEnteringFocusMode,
    required this.firstVisibleIndex,
  });

  @override
  State<StaggeredAppleLyricsScrollWrapper> createState() =>
      _StaggeredAppleLyricsScrollWrapperState();
}

class _StaggeredAppleLyricsScrollWrapperState
    extends State<StaggeredAppleLyricsScrollWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _startOffset = 0.0;
  double _currentOffset = 0.0;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuint,
    );

    if (widget.scrollTriggerTime > 0) {
      _startOffset = widget.scrollDelta;
      _currentOffset = widget.scrollDelta;

      final int delayMs;
      if (widget.isEnteringFocusMode) {
        delayMs = math.min(350, math.max(0, widget.index - widget.firstVisibleIndex) * 15);
      } else {
        final distance = (widget.index - widget.activeIndex).abs();
        delayMs = math.min(150, distance * 12);
      }

      if (delayMs == 0) {
        _controller.forward(from: 0.0);
      } else {
        _delayTimer = Timer(Duration(milliseconds: delayMs), () {
          if (mounted) {
            _controller.forward(from: 0.0);
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(StaggeredAppleLyricsScrollWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.scrollTriggerTime != oldWidget.scrollTriggerTime &&
        widget.scrollTriggerTime > 0) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _delayTimer?.cancel();
    _controller.stop();

    final int delayMs;
    if (widget.isEnteringFocusMode) {
      delayMs = math.min(350, math.max(0, widget.index - widget.firstVisibleIndex) * 15);
    } else {
      final distance = (widget.index - widget.activeIndex).abs();
      delayMs = math.min(150, distance * 12);
    }
    
    _startOffset = widget.scrollDelta + _currentOffset;

    if (delayMs == 0) {
      _controller.forward(from: 0.0);
    } else {
      setState(() {});
      _delayTimer = Timer(Duration(milliseconds: delayMs), () {
        if (mounted) {
          _controller.forward(from: 0.0);
        }
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        if (_controller.isAnimating) {
          _currentOffset = _startOffset * (1.0 - _animation.value);
        } else if (_delayTimer?.isActive ?? false) {
          _currentOffset = _startOffset;
        } else {
          _currentOffset = 0.0;
        }

        if (_currentOffset == 0.0) {
          return widget.child;
        }

        return Transform.translate(
          offset: Offset(0.0, _currentOffset),
          child: widget.child,
        );
      },
    );
  }
}
