import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../l10n/app_localizations.dart';
import '../player/lyrics_controller_state.dart';
import 'playback_ui_tuning.dart';

class LyricsPanelEmptyState extends StatelessWidget {
  const LyricsPanelEmptyState({
    super.key,
    required this.accentColor,
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
                  color: Colors.white.withValues(alpha: 0.7),
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
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
    required this.onContextMenu,
    required this.bottomSpacerHeight,
    this.bottomTabBarHeight = 0.0,
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
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final VoidCallback? onVerticalDragCancel;
  final void Function(Offset globalPosition) onContextMenu;
  final double bottomSpacerHeight;
  final double bottomTabBarHeight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: isAutoScrollPaused ? null : onVerticalDragStart,
      onVerticalDragUpdate: isAutoScrollPaused ? null : onVerticalDragUpdate,
      onVerticalDragEnd: isAutoScrollPaused ? null : onVerticalDragEnd,
      onVerticalDragCancel: isAutoScrollPaused ? null : onVerticalDragCancel,
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
                  child: ListView.builder(
                    controller: scrollController,
                    clipBehavior: Clip.none,
                    physics: hasTimedLyrics
                        ? (isAutoScrollPaused
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics())
                        : const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                    padding: EdgeInsets.only(
                      bottom: bottomSpacerHeight + bottomTabBarHeight + 500,
                    ),
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
                                  ? Colors.white
                                  : Colors.white.withValues(
                                      alpha: isNear ? 0.72 : 0.46,
                                    ),
                              fontSize: timedLyricFontSize,
                              fontWeight: isActive
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              height: 1.4,
                              leadingDistribution: TextLeadingDistribution.even,
                            )
                          : TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: plainLyricFontSize,
                              fontWeight: FontWeight.w400,
                              height: 1.6,
                              leadingDistribution: TextLeadingDistribution.even,
                            );

                      return RepaintBoundary(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: verticalItemPadding,
                          ),
                          child: Center(
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              scale: targetScale,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          line.text,
                                          textAlign: TextAlign.center,
                                          style: lineStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (hasTimedLyrics &&
                                      translated.isNotEmpty) ...[
                                    SizedBox(height: translatedSpacing),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Text(
                                        translated,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.62,
                                          ),
                                          fontSize: translationFontSize,
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
                          ),
                        ),
                      );
                    },
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

          // If bottomSpacerHeight is 0, we still want the top fade,
          // so we set bottomFadeStart to 1.0.
          final bottomFadeStart = bottomSpacerHeight > 0
              ? ((bounds.height - bottomSpacerHeight) / bounds.height).clamp(
                  0.0,
                  1.0,
                )
              : 1.0;

          // Ensure stops are in increasing order
          final stops = [
            0.0,
            topFadeEnd,
            bottomFadeStart.clamp(topFadeEnd, 1.0),
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
            ],
            stops: stops,
          ).createShader(bounds);
        },
        child: child,
      ),
    );
  }
}
