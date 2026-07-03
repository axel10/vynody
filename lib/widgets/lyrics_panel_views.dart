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

class LyricsPanelTimedLyricsView extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final targetLang = lyricsState.lyricsTranslationLanguageCode;
    final effectiveLang = lyrics?.getEffectiveTranslationLanguage(targetLang) ?? targetLang;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: isAutoScrollPaused || lyricsStyle == LyricsStyle.apple ? null : onVerticalDragStart,
      onVerticalDragUpdate: isAutoScrollPaused || lyricsStyle == LyricsStyle.apple ? null : onVerticalDragUpdate,
      onVerticalDragEnd: isAutoScrollPaused || lyricsStyle == LyricsStyle.apple ? null : onVerticalDragEnd,
      onVerticalDragCancel: isAutoScrollPaused || lyricsStyle == LyricsStyle.apple ? null : onVerticalDragCancel,
      onSecondaryTapDown: (details) => onContextMenu(details.globalPosition),
      onLongPressStart: (details) {
        HapticFeedback.mediumImpact();
        onContextMenu(details.globalPosition);
      },
      child: Column(
        children: [
          Expanded(
            child: _LyricsFadeShaderMask(
              bottomSpacerHeight: bottomSpacerHeight + bottomTabBarHeight,
              child: ClipRect(
                clipper: const _VerticalOnlyClipper(),
                child: ScrollConfiguration(
                  behavior: scrollBehavior,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    clipBehavior: Clip.none,
                    physics: hasTimedLyrics
                        ? (isAutoScrollPaused || lyricsStyle == LyricsStyle.apple
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics())
                        : const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                    padding: EdgeInsets.only(
                      top: lyricsStyle == LyricsStyle.apple ? 120.0 : 0.0,
                      bottom: bottomSpacerHeight + bottomTabBarHeight + 500,
                    ),
                    child: Column(
                      children: List.generate(displayLines.length, (index) {
                        final line = displayLines[index];
                        final translated =
                            lyrics
                                ?.translatedLineAt(
                                  index,
                                  effectiveLang,
                                )
                                .trim() ??
                            '';
                        final distance = (index - activeIndex).abs();
                        final isActive = hasTimedLyrics && index == activeIndex;
                        final isNear =
                            hasTimedLyrics && distance <= 1 && !isActive;
                        final targetScale = isActive ? 1.12 : 1.0;
                        final timedLyricFontSize = 16 * lyricsFontScale;
                        final plainLyricFontSize = 18 * lyricsFontScale;
                        final translationFontSize = 13 * lyricsFontScale;
                        final verticalItemPadding = PlaybackPageUiTuning.lyricsVerticalPadding * lyricsFontScale;
                        final translatedSpacing = 3 * lyricsFontScale;
                        final lineStyle = hasTimedLyrics
                            ? Theme.of(context).textTheme.bodyLarge!.copyWith(
                                color: isActive
                                    ? textColor
                                    : textColor.withValues(
                                        alpha: (isNear && lyricsStyle != LyricsStyle.apple) ? 0.72 : 0.46,
                                      ),
                                fontSize: timedLyricFontSize,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                height: 1.4,
                                leadingDistribution: TextLeadingDistribution.even,
                              )
                            : TextStyle(
                                color: textColor.withValues(alpha: 0.92),
                                fontSize: plainLyricFontSize,
                                fontWeight: FontWeight.w400,
                                height: 1.6,
                                leadingDistribution: TextLeadingDistribution.even,
                              );

                        final animatedScaleChild = AnimatedScale(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          scale: targetScale,
                          alignment: lyricsStyle == LyricsStyle.apple ? Alignment.centerLeft : Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: lyricsStyle == LyricsStyle.apple ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: lyricsStyle == LyricsStyle.apple ? MainAxisAlignment.start : MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      line.text,
                                      textAlign: lyricsStyle == LyricsStyle.apple ? TextAlign.left : TextAlign.center,
                                      style: lineStyle,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasTimedLyrics &&
                                  translated.isNotEmpty) ...[
                                SizedBox(height: translatedSpacing),
                                Padding(
                                  padding: lyricsStyle == LyricsStyle.apple
                                      ? const EdgeInsets.only(right: 12)
                                      : const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    translated,
                                    textAlign: lyricsStyle == LyricsStyle.apple ? TextAlign.left : TextAlign.center,
                                    style: TextStyle(
                                      color: isActive
                                          ? secondaryTextColor.withValues(alpha: 1.0)
                                          : secondaryTextColor,
                                      fontSize: translationFontSize,
                                      fontWeight: isActive
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
                        );

                        final bool shouldBlur = lyricsStyle == LyricsStyle.apple && isFocusMode && !isActive;
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
                            alignment: lyricsStyle == LyricsStyle.apple ? Alignment.centerLeft : Alignment.center,
                            child: blurredChild,
                          ),
                        );

                        if (lyricsStyle == LyricsStyle.apple && onLineTapped != null) {
                          return RepaintBoundary(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onLineTapped!(index),
                              child: lineContent,
                            ),
                          );
                        } else {
                          return RepaintBoundary(
                            child: lineContent,
                          );
                        }
                      }),
                    ),
                  ),
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
