import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
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
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                      disabledBackgroundColor: accentColor.withValues(
                        alpha: 0.95,
                      ),
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
    required this.lineHeights,
    required this.hasTimedLyrics,
    required this.activeIndex,
    required this.lyricsFontScale,
    required this.scrollController,
    required this.scrollBehavior,
    required this.textColor,
    required this.secondaryTextColor,
    required this.onContextMenu,
    required this.bottomSpacerHeight,
    this.bottomTabBarHeight = 0.0,
    required this.isFocusMode,
    this.onLineTapped,
    required this.scrollDelta,
    required this.scrollTriggerTime,
    required this.isEnteringFocusMode,
    required this.firstVisibleIndex,
    required this.isSmallWin,
    required this.maxWidth,
    required this.isGenerating,
    this.isTranslating = false,
    this.isTranslationAppearing = false,
    this.isTransitioning = false,
    this.isLowMidEnd = false,
    this.lyricsFontFamily = '',
    this.latinFontFamily = '',
    this.cjkFontFamily = '',
    this.showTranslation = true,
    this.showWordByWord = true,
  });

  final MusicLyric? lyrics;
  final LyricsControllerState lyricsState;
  final List<LyricLine> displayLines;
  final List<double> lineHeights;
  final bool hasTimedLyrics;
  final int activeIndex;
  final double lyricsFontScale;
  final ScrollController scrollController;
  final ScrollBehavior scrollBehavior;
  final Color textColor;
  final Color secondaryTextColor;
  final void Function(Offset globalPosition) onContextMenu;
  final double bottomSpacerHeight;
  final double bottomTabBarHeight;
  final bool isFocusMode;
  final ValueChanged<int>? onLineTapped;
  final double scrollDelta;
  final int scrollTriggerTime;
  final bool isEnteringFocusMode;
  final int firstVisibleIndex;
  final bool isSmallWin;
  final double maxWidth;
  final bool isGenerating;
  final bool isTranslating;
  final bool isTranslationAppearing;
  final bool isTransitioning;
  final bool isLowMidEnd;
  final String lyricsFontFamily;
  final String latinFontFamily;
  final String cjkFontFamily;
  final bool showTranslation;
  final bool showWordByWord;

  @override
  State<LyricsPanelTimedLyricsView> createState() =>
      _LyricsPanelTimedLyricsViewState();
}

class _LyricsPanelTimedLyricsViewState
    extends State<LyricsPanelTimedLyricsView> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final targetLang = widget.lyricsState.lyricsTranslationLanguageCode;
    final effectiveLang =
        widget.lyrics?.getEffectiveTranslationLanguage(targetLang) ??
        targetLang;
    final isPortrait =
        (MediaQuery.of(context).orientation == Orientation.portrait) ||
        widget.isSmallWin;
    const isLeftAligned = true;
    final isApplePortrait = isPortrait;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) =>
          widget.onContextMenu(details.globalPosition),
      onLongPressStart: (details) {
        widget.onContextMenu(details.globalPosition);
      },
      child: Column(
        children: [
          Expanded(
            child: _LyricsFadeShaderMask(
              bottomSpacerHeight:
                  widget.bottomSpacerHeight + widget.bottomTabBarHeight,
              isSmallWin: widget.isSmallWin,
              lyricsFontScale: widget.lyricsFontScale,
              child: ClipRect(
                clipper: const _VerticalOnlyClipper(),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportHeight = constraints.maxHeight;
                    final double topPadding =
                        PlaybackPageUiTuning.appleLyricsTopPadding(
                          widget.lyricsFontScale,
                          isSmallWin: widget.isSmallWin,
                        );
                    final double extraBottomPadding;
                    if (widget.lineHeights.isNotEmpty) {
                      final offset =
                          PlaybackPageUiTuning.appleLyricsScrollOffset(
                            widget.lyricsFontScale,
                            isSmallWin: widget.isSmallWin,
                          );
                      final lastLineHeight = widget.lineHeights.last;
                      extraBottomPadding = math.max(
                        0.0,
                        viewportHeight -
                            topPadding -
                            offset -
                            lastLineHeight -
                            widget.bottomSpacerHeight -
                            widget.bottomTabBarHeight,
                      );
                    } else {
                      extraBottomPadding = math.max(
                        500.0,
                        viewportHeight - (isPortrait ? 25.0 : 100.0),
                      );
                    }

                    // 预计算所有歌词行的 Y 轴位置，用于视口可见性判定，避免为屏幕外的行生成昂贵的离屏高斯模糊层
                    final int lineCount = widget.displayLines.length;
                    final List<double> lineHeights = widget.lineHeights;
                    final List<double> lineTops = List<double>.filled(
                      lineCount,
                      0.0,
                    );
                    double currentY = topPadding;
                    for (var i = 0; i < lineCount; i++) {
                      lineTops[i] = currentY;
                      currentY += (i < lineHeights.length)
                          ? lineHeights[i]
                          : 40.0;
                    }
                    final bool hasClients = widget.scrollController.hasClients;
                    final double scrollOffset = hasClients
                        ? widget.scrollController.offset
                        : 0.0;
                    final double viewTop = scrollOffset - 50.0;
                    final double viewBottom =
                        scrollOffset + viewportHeight + 50.0;
                    return ScrollConfiguration(
                      behavior: widget.scrollBehavior,
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        clipBehavior: Clip.none,
                        physics: widget.hasTimedLyrics
                            ? const BouncingScrollPhysics()
                            : const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                        padding: EdgeInsets.only(
                          top: topPadding,
                          bottom:
                              widget.bottomSpacerHeight +
                              widget.bottomTabBarHeight +
                              extraBottomPadding,
                        ),
                        child: ExcludeSemantics(
                          child: Column(
                            children: List.generate(widget.displayLines.length, (
                              index,
                            ) {
                              final bool isFar =
                                  widget.isTransitioning &&
                                  (widget.hasTimedLyrics
                                      ? (index - widget.activeIndex).abs() > 8
                                      : index > 15);

                              if (isFar) {
                                double itemHeight = 40.0;
                                if (index < widget.lineHeights.length) {
                                  itemHeight = widget.lineHeights[index];
                                }
                                return SizedBox(
                                  key: ValueKey('lyric_placeholder_$index'),
                                  height: itemHeight,
                                );
                              }

                              final line = widget.displayLines[index];
                              final translated =
                                  widget.lyrics
                                      ?.translatedLineAt(index, effectiveLang)
                                      .trim() ??
                                  '';
                              final isActive =
                                  widget.hasTimedLyrics &&
                                  index == widget.activeIndex;
                              final isHovered = _hoveredIndex == index;
                              final timedLyricFontSize =
                                  16 * widget.lyricsFontScale;
                              final plainLyricFontSize =
                                  18 * widget.lyricsFontScale;
                              final translationFontSize =
                                  (isPortrait
                                          ? PlaybackPageUiTuning
                                                .appleLyricsTranslationFontSizePortrait
                                          : PlaybackPageUiTuning
                                                .appleLyricsTranslationFontSizeLandscape) *
                                  widget.lyricsFontScale;
                              final basePadding =
                                  PlaybackPageUiTuning.appleLyricsVerticalPadding;
                              final verticalItemPadding =
                                  basePadding * widget.lyricsFontScale;
                              final translatedSpacing =
                                  3 * widget.lyricsFontScale;
                              final fontToUse = widget.lyricsFontFamily.trim();
                              final effectiveFontFamily =
                                  fontToUse.isNotEmpty ? fontToUse : null;
                              final defaultFallback = (!kIsWeb &&
                                       (defaultTargetPlatform ==
                                               TargetPlatform.macOS ||
                                           defaultTargetPlatform ==
                                               TargetPlatform.iOS))
                                   ? const [
                                       'PingFang SC',
                                       'PingFang TC',
                                       'Heiti SC',
                                       'sans-serif',
                                     ]
                                   : const [
                                       'Microsoft YaHei UI',
                                       'Microsoft YaHei',
                                       'PingFang SC',
                                       'Heiti SC',
                                       'Noto Sans CJK SC',
                                       'Noto Sans SC',
                                       'Source Han Sans SC',
                                       'sans-serif',
                                     ];
                              final effectiveFontFamilyFallback =
                                  effectiveFontFamily != null
                                      ? [
                                          ...defaultFallback.where(
                                            (f) => f != effectiveFontFamily,
                                          ),
                                        ]
                                      : null;

                              final lineStyle = widget.hasTimedLyrics
                                  ? Theme.of(
                                      context,
                                    ).textTheme.bodyLarge!.copyWith(
                                      fontFamily: effectiveFontFamily,
                                      fontFamilyFallback:
                                          effectiveFontFamilyFallback,
                                      color: isActive
                                          ? widget.textColor
                                          : (isHovered
                                                ? widget.textColor.withValues(
                                                    alpha: 1.0,
                                                  )
                                                : widget.textColor.withValues(
                                                    alpha: PlaybackPageUiTuning
                                                          .appleLyricsInactiveOpacity,
                                                  )),
                                      fontSize: timedLyricFontSize,
                                      fontWeight: FontWeight.w700,
                                      height: 1.4,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                    )
                                  : Theme.of(
                                      context,
                                    ).textTheme.bodyLarge!.copyWith(
                                      fontFamily: effectiveFontFamily,
                                      fontFamilyFallback:
                                          effectiveFontFamilyFallback,
                                      color: widget.textColor,
                                      fontSize: plainLyricFontSize,
                                      fontWeight: FontWeight.w700,
                                      height: 1.6,
                                      leadingDistribution:
                                          TextLeadingDistribution.even,
                                    );

                              final double effectiveLeftPadding =
                                  isApplePortrait
                                  ? (widget.isSmallWin ? 16.0 : 0.0)
                                  : 24.0;
                              final double effectiveRightPadding = 24.0;
                              final double layoutMaxWidth =
                                  widget.maxWidth -
                                  (effectiveLeftPadding +
                                      effectiveRightPadding);

                              final animatedScaleChild = SizedBox(
                                width: layoutMaxWidth,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: AnimatedDefaultTextStyle(
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            style: lineStyle,
                                            textAlign: TextAlign.left,
                                            child:
                                                (line.words != null &&
                                                    line.words!.isNotEmpty &&
                                                    widget.showWordByWord)
                                                ? WordWordLyricsWidget(
                                                    words: line.words!,
                                                    lineStyle: lineStyle,
                                                    activeColor:
                                                        widget.textColor,
                                                    inactiveColor: widget
                                                        .textColor
                                                        .withValues(
                                                          alpha: isHovered
                                                              ? 1.0
                                                              : PlaybackPageUiTuning
                                                                    .appleLyricsInactiveOpacity,
                                                        ),
                                                    isActive: isActive,
                                                    isLeftAligned:
                                                        isLeftAligned,
                                                    layoutMaxWidth:
                                                        layoutMaxWidth,
                                                  )
                                                : Text(line.text),
                                          ),
                                        ),
                                      ],
                                    ),
                                      if (widget.hasTimedLyrics &&
                                          translated.isNotEmpty &&
                                          widget.showTranslation) ...[
                                        AppleLyricTranslationFadeIn(
                                          key: ValueKey(
                                            'apple_trans_${index}_$effectiveLang',
                                          ),
                                          animate: widget.isTranslating ||
                                              widget.isTranslationAppearing,
                                          index: index,
                                          activeIndex: widget.activeIndex,
                                          isLeftAligned: isLeftAligned,
                                          child: Column(
                                            mainAxisSize:
                                                MainAxisSize.min,
                                            crossAxisAlignment:
                                                isLeftAligned
                                                ? CrossAxisAlignment.start
                                                : CrossAxisAlignment
                                                      .center,
                                            children: [
                                              SizedBox(
                                                height: translatedSpacing,
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    isLeftAligned
                                                    ? MainAxisAlignment
                                                          .start
                                                    : MainAxisAlignment
                                                          .center,
                                                children: [
                                                  Expanded(
                                                    child: Padding(
                                                      padding:
                                                          isLeftAligned
                                                          ? const EdgeInsets.only(
                                                              right: 12,
                                                            )
                                                          : const EdgeInsets.symmetric(
                                                              horizontal:
                                                                  12,
                                                            ),
                                                      child: AnimatedDefaultTextStyle(
                                                        duration:
                                                            const Duration(
                                                              milliseconds:
                                                                  300,
                                                            ),
                                                        curve: Curves
                                                            .easeOutCubic,
                                                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                                          fontFamily:
                                                              effectiveFontFamily,
                                                          fontFamilyFallback:
                                                              effectiveFontFamilyFallback,
                                                          color: isHovered
                                                              ? widget
                                                                    .secondaryTextColor
                                                                    .withValues(
                                                                      alpha:
                                                                          1.0,
                                                                    )
                                                              : (isActive
                                                                    ? (line.words !=
                                                                              null &&
                                                                          line.words!.isNotEmpty &&
                                                                          widget.showWordByWord
                                                                          ? widget.secondaryTextColor.withValues(
                                                                              alpha: PlaybackPageUiTuning.appleLyricsActiveTranslationOpacity,
                                                                            )
                                                                          : widget.secondaryTextColor.withValues(
                                                                              alpha: 1.0,
                                                                            ))
                                                                    : widget
                                                                          .secondaryTextColor),
                                                          fontSize:
                                                              translationFontSize,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          height: 1.3,
                                                          leadingDistribution:
                                                              TextLeadingDistribution
                                                                  .even,
                                                        ),
                                                        textAlign:
                                                            isLeftAligned
                                                            ? TextAlign
                                                                  .left
                                                            : TextAlign
                                                                  .center,
                                                        child: Text(
                                                          translated,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );

                              final double lineTop = lineTops[index];
                              final double lineHeight =
                                  (index < lineHeights.length)
                                  ? lineHeights[index]
                                  : 40.0;
                              final double lineBottom = lineTop + lineHeight;
                              final bool isVisibleInViewport = hasClients
                                  ? (lineBottom >= viewTop &&
                                        lineTop <= viewBottom)
                                  : ((index - widget.activeIndex) >= -3 &&
                                        (index - widget.activeIndex) <= 7);

                              final bool shouldBlur =
                                  widget.hasTimedLyrics &&
                                  widget.activeIndex >= 0 &&
                                  widget.isFocusMode &&
                                  !isActive &&
                                  !isHovered &&
                                  isVisibleInViewport &&
                                  !widget.isTransitioning;
                              final double targetBlur;
                              if (shouldBlur) {
                                final int diff = index - widget.activeIndex;
                                targetBlur =
                                    (PlaybackPageUiTuning
                                                .appleLyricsBaseBlurSigma +
                                            diff *
                                                PlaybackPageUiTuning
                                                    .appleLyricsBlurGradientFactor)
                                        .clamp(
                                          PlaybackPageUiTuning
                                              .appleLyricsMinBlurSigma,
                                          PlaybackPageUiTuning
                                              .appleLyricsMaxBlurSigma,
                                        );
                              } else {
                                targetBlur = 0.0;
                              }

                              final Widget blurredChild;
                              if (widget.isFocusMode && widget.hasTimedLyrics) {
                                blurredChild =
                                    TweenAnimationBuilder<double>(
                                  tween: Tween<double>(
                                    begin: targetBlur,
                                    end: targetBlur,
                                  ),
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, blurSigma, child) {
                                    if (blurSigma <= 0.0) {
                                      return child!;
                                    }
                                    return ImageFiltered(
                                      imageFilter: ui.ImageFilter.blur(
                                        sigmaX: blurSigma,
                                        sigmaY: blurSigma,
                                      ),
                                      child: child,
                                    );
                                  },
                                  child: animatedScaleChild,
                                );
                              } else {
                                blurredChild = animatedScaleChild;
                              }

                              final lineContent = Padding(
                                padding: EdgeInsets.only(
                                  top: verticalItemPadding,
                                  bottom: verticalItemPadding,
                                  left: effectiveLeftPadding,
                                  right: effectiveRightPadding,
                                ),
                                child: Align(
                                  alignment: isLeftAligned
                                      ? Alignment.centerLeft
                                      : Alignment.center,
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
                                cursor: widget.hasTimedLyrics
                                    ? SystemMouseCursors.click
                                    : MouseCursor.defer,
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

                              Widget contentWidget = wrappedItemWidget;
                              if (widget.isGenerating) {
                                contentWidget = AppleLyricLineFadeIn(
                                  index: index,
                                  animate: true,
                                  isStaggered: false,
                                  child: contentWidget,
                                );
                              }

                              final Widget resultWidget;
                              final bool isInStaggerRange =
                                  !widget.isGenerating &&
                                  widget.isFocusMode &&
                                  index >= widget.firstVisibleIndex - 10 &&
                                  index <= widget.firstVisibleIndex + 30;

                              if (isInStaggerRange) {
                                resultWidget =
                                    StaggeredAppleLyricsScrollWrapper(
                                      index: index,
                                      activeIndex: widget.activeIndex,
                                      scrollDelta: widget.scrollDelta,
                                      scrollTriggerTime:
                                          widget.scrollTriggerTime,
                                      isEnteringFocusMode:
                                          widget.isEnteringFocusMode,
                                      firstVisibleIndex:
                                          widget.firstVisibleIndex,
                                      isTransitioning: widget.isTransitioning,
                                      child: contentWidget,
                                    );
                              } else {
                                resultWidget = contentWidget;
                              }

                              return KeyedSubtree(
                                key: ValueKey('lyric_active_$index'),
                                child: resultWidget,
                              );
                            }),
                          ),
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
    required this.isSmallWin,
    required this.lyricsFontScale,
    required this.child,
  });

  final double bottomSpacerHeight;
  final bool isSmallWin;
  final double lyricsFontScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final height = bounds.height > 0 ? bounds.height : 1.0;
            if (height <= 1.0) {
              return const LinearGradient(
                colors: [Colors.white, Colors.white],
              ).createShader(bounds);
            }

            final topFadeHeight =
                PlaybackPageUiTuning.appleLyricsTopFadeHeight(lyricsFontScale);
            final topFadeEnd = (topFadeHeight / height).clamp(0.0, 1.0);

            final isPortrait =
                (MediaQuery.of(context).orientation == Orientation.portrait) ||
                isSmallWin;

            final double bottomFadeEndHeight;
            final double bottomFadeStartHeight;

            if (isPortrait) {
              final effectiveBottomReserve = math.max(20.0, bottomSpacerHeight);
              bottomFadeEndHeight = effectiveBottomReserve;
              final fadeLength =
                  PlaybackPageUiTuning.appleLyricsBottomFadeLength;
              bottomFadeStartHeight = effectiveBottomReserve + fadeLength;
            } else {
              bottomFadeEndHeight = 0.0;
              bottomFadeStartHeight = math.max(40.0, bottomSpacerHeight + 40.0);
            }

            final bottomFadeStart =
                ((bounds.height - bottomFadeStartHeight) / bounds.height).clamp(
                  0.0,
                  1.0,
                );
            final bottomFadeEnd =
                ((bounds.height - bottomFadeEndHeight) / bounds.height).clamp(
                  0.0,
                  1.0,
                );

            final tEnd = topFadeEnd;
            final bStart = bottomFadeStart.clamp(tEnd, 1.0);
            final bEnd = bottomFadeEnd.clamp(bStart, 1.0);

            // Ensure stops are in increasing order
            final stops = [0.0, tEnd, bStart, bEnd, 1.0];

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
  final bool isTransitioning;

  const StaggeredAppleLyricsScrollWrapper({
    super.key,
    required this.child,
    required this.index,
    required this.activeIndex,
    required this.scrollDelta,
    required this.scrollTriggerTime,
    required this.isEnteringFocusMode,
    required this.firstVisibleIndex,
    required this.isTransitioning,
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
      curve: Curves.easeOutCubic,
    );

    final double maxDelta = widget.isEnteringFocusMode ? 1500.0 : 800.0;
    final timePassed =
        DateTime.now().millisecondsSinceEpoch - widget.scrollTriggerTime;
    if (widget.scrollTriggerTime > 0 &&
        !widget.isTransitioning &&
        timePassed < 700 &&
        widget.scrollDelta.abs() <= maxDelta) {
      _startOffset = widget.scrollDelta;
      _currentOffset = widget.scrollDelta;

      final int delayMs;
      if (widget.isEnteringFocusMode) {
        delayMs = math.min(
          350,
          math.max(0, widget.index - widget.firstVisibleIndex) * 15,
        );
      } else {
        if (widget.index > widget.activeIndex) {
          delayMs = math.min(300, (widget.index - widget.activeIndex) * 24);
        } else if (widget.index < widget.activeIndex) {
          delayMs = math.min(120, (widget.activeIndex - widget.index) * 12);
        } else {
          delayMs = 0;
        }
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

    final double maxDelta = widget.isEnteringFocusMode ? 1500.0 : 800.0;
    if (widget.isTransitioning ||
        widget.scrollTriggerTime <= 0 ||
        widget.scrollDelta.abs() > maxDelta) {
      _delayTimer?.cancel();
      _controller.stop();
      _currentOffset = 0.0;
      _startOffset = 0.0;
      return;
    }

    if (widget.scrollTriggerTime != oldWidget.scrollTriggerTime &&
        widget.scrollTriggerTime > 0) {
      _startAnimation();
    }
  }

  void _startAnimation() {
    _delayTimer?.cancel();
    _controller.stop();

    final double maxDelta = widget.isEnteringFocusMode ? 1500.0 : 800.0;
    if (widget.scrollDelta.abs() > maxDelta || widget.scrollTriggerTime <= 0) {
      _currentOffset = 0.0;
      _startOffset = 0.0;
      return;
    }

    final int delayMs;
    if (widget.isEnteringFocusMode) {
      delayMs = math.min(
        350,
        math.max(0, widget.index - widget.firstVisibleIndex) * 15,
      );
    } else {
      if (widget.index > widget.activeIndex) {
        delayMs = math.min(300, (widget.index - widget.activeIndex) * 24);
      } else if (widget.index < widget.activeIndex) {
        delayMs = math.min(120, (widget.activeIndex - widget.index) * 12);
      } else {
        delayMs = 0;
      }
    }

    _startOffset = widget.scrollDelta + _currentOffset;

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

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (context, child) {
          if (widget.isTransitioning) {
            return child!;
          }

          if (_controller.isAnimating) {
            _currentOffset = _startOffset * (1.0 - _animation.value);
          } else if (_delayTimer?.isActive ?? false) {
            _currentOffset = _startOffset;
          } else {
            _currentOffset = 0.0;
          }

          return Transform.translate(
            offset: Offset(0.0, _currentOffset),
            child: child,
          );
        },
      ),
    );
  }
}

class WordWordLyricsWidget extends ConsumerStatefulWidget {
  const WordWordLyricsWidget({
    super.key,
    required this.words,
    required this.lineStyle,
    required this.activeColor,
    required this.inactiveColor,
    required this.isLeftAligned,
    this.isActive = true,
    this.layoutMaxWidth,
  });

  final List<LyricWord> words;
  final TextStyle lineStyle;
  final Color activeColor;
  final Color inactiveColor;
  final bool isLeftAligned;
  final bool isActive;
  final double? layoutMaxWidth;

  @override
  ConsumerState<WordWordLyricsWidget> createState() =>
      _WordWordLyricsWidgetState();
}

class _WordWordLyricsWidgetState extends ConsumerState<WordWordLyricsWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _basePosition = Duration.zero;
  DateTime _baseWallClock = DateTime.now();
  Duration _pausedElapsed = Duration.zero;
  bool _isPlaying = false;
  bool _isBackgroundSuspended = false;
  bool _isInitialized = false;

  TextStyle _styleWithForeground(TextStyle base, Paint foreground) {
    return TextStyle(
      inherit: base.inherit,
      color: null,
      backgroundColor: base.backgroundColor,
      fontSize: base.fontSize,
      fontWeight: base.fontWeight,
      fontStyle: base.fontStyle,
      letterSpacing: base.letterSpacing,
      wordSpacing: base.wordSpacing,
      textBaseline: base.textBaseline,
      height: base.height,
      leadingDistribution: base.leadingDistribution,
      locale: base.locale,
      foreground: foreground,
      background: base.background,
      shadows: base.shadows,
      fontFeatures: base.fontFeatures,
      fontVariations: base.fontVariations,
      decoration: base.decoration,
      decorationColor: base.decorationColor,
      decorationStyle: base.decorationStyle,
      decorationThickness: base.decorationThickness,
      debugLabel: base.debugLabel,
      fontFamily: base.fontFamily,
      fontFamilyFallback: base.fontFamilyFallback,
      overflow: base.overflow,
    );
  }

  void _syncBaseline({Duration? seekPosition}) {
    _basePosition = seekPosition ?? ref.read(audioPositionProvider);
    _baseWallClock = DateTime.now();
    _pausedElapsed = Duration.zero;
    _isInitialized = true;
  }

  Duration _calculateCurrentPosition(double speed) {
    if (!_isInitialized) {
      return ref.read(audioPositionProvider);
    }
    final rawElapsed = _isPlaying
        ? _pausedElapsed + DateTime.now().difference(_baseWallClock)
        : _pausedElapsed;
    if ((speed - 1.0).abs() > 0.001 && speed > 0) {
      final scaledElapsedMs =
          (rawElapsed.inMicroseconds * speed / 1000).round();
      return _basePosition + Duration(milliseconds: scaledElapsedMs);
    }
    return _basePosition + rawElapsed;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((_) {
      if (mounted && !_isBackgroundSuspended && _isPlaying && widget.isActive) {
        setState(() {});
      }
    });
  }

  void _updateTickerState() {
    if (!_isBackgroundSuspended && _isPlaying && widget.isActive) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else {
      if (_ticker.isActive) {
        _ticker.stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        (!isDesktop && state == AppLifecycleState.inactive)) {
      if (!_isBackgroundSuspended) {
        _isBackgroundSuspended = true;
        if (_ticker.isActive) {
          _ticker.stop();
        }
      }
    } else if (state == AppLifecycleState.resumed ||
        (isDesktop && state == AppLifecycleState.inactive)) {
      if (_isBackgroundSuspended) {
        _isBackgroundSuspended = false;
        _updateTickerState();
      }
    }
  }

  DateTime _lastLogTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didUpdateWidget(covariant WordWordLyricsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _syncBaseline();
      } else {
        _isInitialized = false;
      }
      _updateTickerState();
    } else if (widget.isActive && oldWidget.words != widget.words) {
      _syncBaseline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validWords = <LyricWord>[];
    for (int i = 0; i < widget.words.length; i++) {
      final w = widget.words[i];
      if (w.text.trim().isEmpty) continue;
      if (validWords.isEmpty) {
        validWords.add(w.copyWith(text: w.text.trimLeft()));
      } else if (w.text.startsWith(RegExp(r'^\s+'))) {
        final last = validWords.removeLast();
        final lastText = last.text.endsWith(' ') ? last.text : '${last.text} ';
        validWords.add(last.copyWith(text: lastText));
        validWords.add(w.copyWith(text: w.text.trimLeft()));
      } else {
        validWords.add(w);
      }
    }

    if (validWords.isEmpty) {
      return Text(
        widget.words.map((w) => w.text).join().trim(),
        style: widget.lineStyle,
        textAlign: widget.isLeftAligned ? TextAlign.left : TextAlign.center,
      );
    }

    if (!widget.isActive) {
      return ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            children: validWords.map((word) {
              return TextSpan(
                text: word.text,
                style: widget.lineStyle.copyWith(color: widget.inactiveColor),
              );
            }).toList(growable: false),
          ),
          textAlign: widget.isLeftAligned ? TextAlign.left : TextAlign.center,
        ),
      );
    }

    final isPlaying = ref.watch(audioIsPlayingProvider);
    final speed =
        ref.watch(audioSnapshotProvider.select((s) => s.playbackSpeed));

    // Listen to major position jump (e.g. user drag seek bar or skip)
    // without triggering rebuilds on normal 120ms kernel ticks:
    ref.listen<Duration>(audioPositionProvider, (previous, next) {
      if (!widget.isActive || !_isInitialized) return;
      final currentPos = _calculateCurrentPosition(speed);
      final jump = (next - currentPos).inMilliseconds.abs();
      if (jump > 300) {
        _syncBaseline(seekPosition: next);
        if (mounted) {
          setState(() {});
        }
      }
    });

    if (!_isInitialized) {
      _syncBaseline();
      _isPlaying = isPlaying;
      _updateTickerState();
    } else if (isPlaying != _isPlaying) {
      if (!isPlaying) {
        _pausedElapsed += DateTime.now().difference(_baseWallClock);
      } else {
        _baseWallClock = DateTime.now();
      }
      _isPlaying = isPlaying;
      _updateTickerState();
    }

    final currentPosition = _calculateCurrentPosition(speed);

    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final timelineOffsetMs =
        currentMusic?.lyrics?.timelineOffset.inMilliseconds ?? 0;
    final currentMs = currentPosition.inMilliseconds - timelineOffsetMs;

    final logNow = DateTime.now();
    if (logNow.difference(_lastLogTime).inMilliseconds >= 250 &&
        validWords.isNotEmpty) {
      _lastLogTime = logNow;
    }

    // Check if any word is in active transition (0.0 < progress < 1.0)
    bool hasTransitioningWord = false;
    for (final word in validWords) {
      final startMs = word.timestamp.inMilliseconds;
      final durationMs = word.durationMs;
      if (currentMs > startMs && currentMs < startMs + durationMs && durationMs > 0) {
        hasTransitioningWord = true;
        break;
      }
    }

    final fullText = validWords.map((w) => w.text).join();
    TextPainter? textPainter;
    if (hasTransitioningWord) {
      final maxWidth = widget.layoutMaxWidth ?? double.infinity;
      textPainter = TextPainter(
        text: TextSpan(text: fullText, style: widget.lineStyle),
        textDirection: Directionality.of(context),
        textAlign: widget.isLeftAligned ? TextAlign.left : TextAlign.center,
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout(maxWidth: maxWidth.isFinite && maxWidth > 0 ? maxWidth : double.infinity);
    }

    int charOffset = 0;
    final spans = <InlineSpan>[];
    for (final word in validWords) {
      final wordLen = word.text.length;
      final startMs = word.timestamp.inMilliseconds;
      final durationMs = word.durationMs;

      double progress = 0.0;
      if (currentMs >= startMs + durationMs) {
        progress = 1.0;
      } else if (currentMs >= startMs && durationMs > 0) {
        progress = (currentMs - startMs) / durationMs;
      }

      if (progress <= 0.0) {
        spans.add(TextSpan(
          text: word.text,
          style: widget.lineStyle.copyWith(color: widget.inactiveColor),
        ));
      } else if (progress >= 1.0) {
        spans.add(TextSpan(
          text: word.text,
          style: widget.lineStyle.copyWith(color: widget.activeColor),
        ));
      } else {
        const double softEdge = 0.15;
        final double center = -softEdge + progress * (1.0 + 2 * softEdge);
        final double start = (center - softEdge / 2).clamp(0.0, 1.0);
        final double end = (center + softEdge / 2).clamp(0.0, 1.0);

        final boxes = textPainter?.getBoxesForSelection(
          TextSelection(
            baseOffset: charOffset,
            extentOffset: charOffset + wordLen,
          ),
        );

        if (boxes != null && boxes.isNotEmpty) {
          final box = boxes.first;
          final shader = ui.Gradient.linear(
            Offset(box.left, 0),
            Offset(box.right, 0),
            [
              widget.activeColor,
              widget.activeColor,
              widget.inactiveColor,
              widget.inactiveColor,
            ],
            [0.0, start, end, 1.0],
          );
          spans.add(TextSpan(
            text: word.text,
            style: _styleWithForeground(
              widget.lineStyle,
              Paint()..shader = shader,
            ),
          ));
        } else {
          final fallbackColor =
              Color.lerp(widget.inactiveColor, widget.activeColor, progress) ??
                  widget.inactiveColor;
          spans.add(TextSpan(
            text: word.text,
            style: widget.lineStyle.copyWith(color: fallbackColor),
          ));
        }
      }

      charOffset += wordLen;
    }

    return ExcludeSemantics(
      child: Text.rich(
        TextSpan(children: spans),
        textAlign: widget.isLeftAligned ? TextAlign.left : TextAlign.center,
      ),
    );
  }
}

class WordHighlightText extends StatelessWidget {
  const WordHighlightText({
    super.key,
    required this.text,
    required this.progress,
    required this.style,
    required this.activeColor,
    required this.inactiveColor,
  });

  final String text;
  final double progress;
  final TextStyle style;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.0) {
      return Text(text, style: style.copyWith(color: inactiveColor));
    }
    if (progress >= 1.0) {
      return Text(text, style: style.copyWith(color: activeColor));
    }

    // Smooth transition from left to right with a soft edge.
    // Map progress so that the soft edge fully clears the text boundary from 0.0 to 1.0.
    const double softEdge = 0.15;
    final double center = -softEdge + progress * (1.0 + 2 * softEdge);
    final double start = (center - softEdge / 2).clamp(0.0, 1.0);
    final double end = (center + softEdge / 2).clamp(0.0, 1.0);

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          colors: [activeColor, activeColor, inactiveColor, inactiveColor],
          stops: [0.0, start, end, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bounds);
      },
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// 苹果歌词面板在生成歌词时的整行淡入与微位移浮现动画组件
class AppleLyricLineFadeIn extends StatefulWidget {
  final Widget child;
  final bool animate;
  final int index;
  final bool isStaggered;

  const AppleLyricLineFadeIn({
    super.key,
    required this.child,
    this.animate = true,
    required this.index,
    this.isStaggered = true,
  });

  @override
  State<AppleLyricLineFadeIn> createState() => _AppleLyricLineFadeInState();
}

class _AppleLyricLineFadeInState extends State<AppleLyricLineFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 6),
      end: Offset.zero,
    ).animate(_opacityAnimation);

    if (widget.animate) {
      if (widget.isStaggered) {
        final delayMs = math.min(300, widget.index * 18);
        if (delayMs > 0) {
          _delayTimer = Timer(Duration(milliseconds: delayMs), () {
            if (mounted) {
              _controller.forward();
            }
          });
        } else {
          _controller.forward();
        }
      } else {
        _controller.forward();
      }
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AppleLyricLineFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate && !_controller.isCompleted) {
      _delayTimer?.cancel();
      _controller.value = 1.0;
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
    if (!widget.animate || _controller.isCompleted) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: _slideAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 苹果歌词面板在生成翻译时的逐行翻译淡入与微位移浮现动画组件
class AppleLyricTranslationFadeIn extends StatefulWidget {
  final Widget child;
  final bool animate;
  final int index;
  final int activeIndex;
  final bool isLeftAligned;

  const AppleLyricTranslationFadeIn({
    super.key,
    required this.child,
    this.animate = true,
    required this.index,
    this.activeIndex = -1,
    this.isLeftAligned = true,
  });

  @override
  State<AppleLyricTranslationFadeIn> createState() =>
      _AppleLyricTranslationFadeInState();
}

class _AppleLyricTranslationFadeInState
    extends State<AppleLyricTranslationFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sizeAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _delayTimer;

  bool get _shouldAnimateSize =>
      widget.activeIndex < 0 || widget.index >= widget.activeIndex;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _sizeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacityAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 1.0, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 4),
      end: Offset.zero,
    ).animate(_opacityAnimation);

    if (widget.animate) {
      if (!_shouldAnimateSize) {
        _controller.value = 1.0;
      } else {
        final baseIndex = widget.activeIndex >= 0 ? widget.activeIndex : 0;
        final delayMs = math.min(
          250,
          math.max(0, widget.index - baseIndex) * 12,
        );
        if (delayMs > 0) {
          _delayTimer = Timer(Duration(milliseconds: delayMs), () {
            if (mounted) {
              _controller.forward();
            }
          });
        } else {
          _controller.forward();
        }
      }
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(AppleLyricTranslationFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      if (!widget.animate) {
        _delayTimer?.cancel();
        _controller.value = 1.0;
      }
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
    if (!widget.animate || _controller.isCompleted) {
      return widget.child;
    }
    if (!_shouldAnimateSize) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.translate(
              offset: _slideAnimation.value,
              child: child,
            ),
          );
        },
        child: widget.child,
      );
    }
    return SizeTransition(
      sizeFactor: _sizeAnimation,
      alignment: widget.isLeftAligned ? Alignment.topLeft : Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.translate(
              offset: _slideAnimation.value,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}
