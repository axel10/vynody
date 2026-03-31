import codecs
import re

file_path = r'c:\Users\Administrator\Desktop\projects\player_project\vibe_flow\lib\widgets\playback_hero_card.dart'

with codecs.open(file_path, 'r', 'utf-8') as f:
    text = f.read()

match = re.search(r'(class PlaybackHeroCard extends StatefulWidget \{.*?)  Widget _buildAlbumArtCore', text, flags=re.DOTALL)
if not match:
    print("Could not find the bounds to replace.")
    exit(1)

old_body = match.group(1)

fields_match = re.search(r'const PlaybackHeroCard\(\{.*?\}\);(.*?)@override', old_body, flags=re.DOTALL)
fields = fields_match.group(1)

mini_card_match = re.search(r'Widget _buildMiniCard\(BuildContext context\) \{(.*?)\}\n\n  Widget _buildFullCard', text, flags=re.DOTALL)
build_mini_card_body = ""
if mini_card_match:
    build_mini_card_body = mini_card_match.group(1)
    build_mini_card_body = re.sub(r'\bwidget\.', '', build_mini_card_body)

replacement = """import 'dart:ui' show lerpDouble;

class PlaybackHeroCard extends StatelessWidget {
  const PlaybackHeroCard({
    super.key,
    required this.isMini,
    this.isLyricsMode = false,
    this.isLandscape = false,
    this.screenWidth,
    this.screenHeight,
    this.isNext = true,
    this.showVisualizerToggle = true,
    this.onShowMoreMenu,
    this.onMiniTap,
    this.onCyclePlaylistMode,
    this.onShowPlaylistModeSelector,
    this.onShowRandomModeSelector,
    this.onScrubbing,
    this.onSeek,
    this.onToggleVisualizer,
    this.onEqualizerTap,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeDrag,
    this.onVolumeScroll,
    this.onCoverTap,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
  });
__FIELDS__
  double _lerp2D(double pN, double pL, double lN, double lL, double tLyrics, double tLand) {
    final p = lerpDouble(pN, pL, tLyrics) ?? pN;
    final l = lerpDouble(lN, lL, tLyrics) ?? lN;
    return lerpDouble(p, l, tLand) ?? p;
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: playbackHeroTag,
      child: Material(
        type: MaterialType.transparency,
        child: isMini ? _buildMiniCard(context) : _buildFullCard(context),
      ),
    );
  }

  Widget _buildMiniCard(BuildContext context) {__MINICARD__}

  Widget _buildFullCard(BuildContext context) {
    const animDuration = Duration(milliseconds: 400);
    const animCurve = Curves.fastOutSlowIn;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(
        begin: isLandscape ? 1.0 : 0.0,
        end: isLandscape ? 1.0 : 0.0,
      ),
      duration: animDuration,
      curve: animCurve,
      builder: (context, tLand, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(
            begin: isLyricsMode ? 1.0 : 0.0,
            end: isLyricsMode ? 1.0 : 0.0,
          ),
          duration: animDuration,
          curve: animCurve,
          builder: (context, tLyrics, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;

                // ---------------- Portrait Normal ----------------
                final pNormalCoverSide = math.min(width * 0.85, height * 0.5);
                final pNormalCoverTop = height * 0.05 + (height * 0.45 - pNormalCoverSide) / 2;
                final pNormalCoverLeft = (width - pNormalCoverSide) / 2;

                final pNormalInfoTop = height * 0.52;
                final pNormalInfoLeft = 16.0;
                final pNormalInfoWidth = width - 32.0;
                final pNormalInfoHeight = 80.0;

                final pNormalControlsTop = pNormalInfoTop + pNormalInfoHeight + 8.0;
                final pNormalControlsLeft = 16.0;
                final pNormalControlsWidth = width - 32.0;
                final pNormalControlsHeight = height - pNormalControlsTop - 16.0;
                final pNormalControlsOpacity = 1.0;

                final pNormalLyricsTop = height;
                final pNormalLyricsLeft = 16.0;
                final pNormalLyricsWidth = width - 32.0;
                final pNormalLyricsHeight = height - pNormalInfoTop;
                final pNormalLyricsOpacity = 0.0;

                // ---------------- Portrait Lyrics ----------------
                final pLyricsCoverSide = math.min(104.0, width * 0.28);
                final pLyricsCoverTop = 16.0;
                final pLyricsCoverLeft = 16.0;

                final pLyricsInfoTop = 16.0;
                final pLyricsInfoLeft = 16.0 + pLyricsCoverSide + 14.0;
                final pLyricsInfoWidth = width - pLyricsInfoLeft - 16.0;
                final pLyricsInfoHeight = pLyricsCoverSide;

                final pLyricsControlsTop = height; 
                final pLyricsControlsLeft = 16.0;
                final pLyricsControlsWidth = width - 32.0;
                final pLyricsControlsHeight = pNormalControlsHeight; 
                final pLyricsControlsOpacity = 0.0;

                final pLyricsLyricsTop = pLyricsCoverTop + pLyricsCoverSide + 16.0;
                final pLyricsLyricsLeft = 16.0;
                final pLyricsLyricsWidth = width - 32.0;
                final pLyricsLyricsHeight = height - pLyricsLyricsTop - 16.0;
                final pLyricsLyricsOpacity = 1.0;

                // ---------------- Landscape Normal ----------------
                final lNormalCoverSide = math.min(width * 0.42, height * 0.85);
                final lNormalCoverTop = (height - lNormalCoverSide) / 2;
                final lNormalCoverLeft = width * 0.05 + (width * 0.45 - lNormalCoverSide) / 2;

                final lNormalInfoTop = height * 0.5 - 100 - 45;
                final lNormalInfoLeft = width * 0.5;
                final lNormalInfoWidth = width * 0.45;
                final lNormalInfoHeight = 90.0;

                final lNormalControlsTop = lNormalInfoTop + lNormalInfoHeight;
                final lNormalControlsLeft = width * 0.5;
                final lNormalControlsWidth = width * 0.45;
                final lNormalControlsHeight = 200.0;
                final lNormalControlsOpacity = 1.0;

                final lNormalLyricsTop = 16.0;
                final lNormalLyricsLeft = width; 
                final lNormalLyricsWidth = width * 0.45;
                final lNormalLyricsHeight = height - 32.0;
                final lNormalLyricsOpacity = 0.0;

                // ---------------- Landscape Lyrics ----------------
                final lColWidth = (width * 0.35).clamp(280.0, 420.0);

                final lLyricsCoverSide = math.min(lColWidth * 0.8, height * 0.45);
                final lLyricsCoverTop = 16.0;
                final lLyricsCoverLeft = (lColWidth - lLyricsCoverSide) / 2;

                final lLyricsInfoTop = lLyricsCoverTop + lLyricsCoverSide + 24.0;
                final lLyricsInfoLeft = 16.0;
                final lLyricsInfoWidth = lColWidth - 32.0;
                final lLyricsInfoHeight = 80.0;

                final lLyricsControlsTop = lLyricsInfoTop + lLyricsInfoHeight + 16.0;
                final lLyricsControlsLeft = 16.0;
                final lLyricsControlsWidth = lColWidth - 32.0;
                final lLyricsControlsHeight = height - lLyricsControlsTop - 16.0;
                final lLyricsControlsOpacity = 1.0;

                final lLyricsLyricsTop = 16.0;
                final lLyricsLyricsLeft = lColWidth + 16.0;
                final lLyricsLyricsWidth = width - lLyricsLyricsLeft - 32.0;
                final lLyricsLyricsHeight = height - 32.0;
                final lLyricsLyricsOpacity = 1.0;

                // ---------------- Execute 2D Interpolation ----------------
                final coverSide = _lerp2D(pNormalCoverSide, pLyricsCoverSide, lNormalCoverSide, lLyricsCoverSide, tLyrics, tLand);
                final coverTop = _lerp2D(pNormalCoverTop, pLyricsCoverTop, lNormalCoverTop, lLyricsCoverTop, tLyrics, tLand);
                final coverLeft = _lerp2D(pNormalCoverLeft, pLyricsCoverLeft, lNormalCoverLeft, lLyricsCoverLeft, tLyrics, tLand);

                final infoTop = _lerp2D(pNormalInfoTop, pLyricsInfoTop, lNormalInfoTop, lLyricsInfoTop, tLyrics, tLand);
                final infoLeft = _lerp2D(pNormalInfoLeft, pLyricsInfoLeft, lNormalInfoLeft, lLyricsInfoLeft, tLyrics, tLand);
                final infoWidth = _lerp2D(pNormalInfoWidth, pLyricsInfoWidth, lNormalInfoWidth, lLyricsInfoWidth, tLyrics, tLand);
                final infoHeight = _lerp2D(pNormalInfoHeight, pLyricsInfoHeight, lNormalInfoHeight, lLyricsInfoHeight, tLyrics, tLand);

                final controlsTop = _lerp2D(pNormalControlsTop, pLyricsControlsTop, lNormalControlsTop, lLyricsControlsTop, tLyrics, tLand);
                final controlsLeft = _lerp2D(pNormalControlsLeft, pLyricsControlsLeft, lNormalControlsLeft, lLyricsControlsLeft, tLyrics, tLand);
                final controlsWidth = _lerp2D(pNormalControlsWidth, pLyricsControlsWidth, lNormalControlsWidth, lLyricsControlsWidth, tLyrics, tLand);
                final controlsHeight = _lerp2D(pNormalControlsHeight, pLyricsControlsHeight, lNormalControlsHeight, lLyricsControlsHeight, tLyrics, tLand);
                final controlsOpacity = _lerp2D(pNormalControlsOpacity, pLyricsControlsOpacity, lNormalControlsOpacity, lLyricsControlsOpacity, tLyrics, tLand);

                final lyricsTop = _lerp2D(pNormalLyricsTop, pLyricsLyricsTop, lNormalLyricsTop, lLyricsLyricsTop, tLyrics, tLand);
                final lyricsLeft = _lerp2D(pNormalLyricsLeft, pLyricsLyricsLeft, lNormalLyricsLeft, lLyricsLyricsLeft, tLyrics, tLand);
                final lyricsWidth = _lerp2D(pNormalLyricsWidth, pLyricsLyricsWidth, lNormalLyricsWidth, lLyricsLyricsWidth, tLyrics, tLand);
                final lyricsHeight = _lerp2D(pNormalLyricsHeight, pLyricsLyricsHeight, lNormalLyricsHeight, lLyricsLyricsHeight, tLyrics, tLand);
                final lyricsOpacity = _lerp2D(pNormalLyricsOpacity, pLyricsLyricsOpacity, lNormalLyricsOpacity, lLyricsLyricsOpacity, tLyrics, tLand);

                final targetInfoAlign = isLandscape
                    ? TextAlign.center 
                    : (isLyricsMode ? TextAlign.left : TextAlign.center);

                return SizedBox(
                  width: width,
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: lyricsTop, left: lyricsLeft, width: lyricsWidth, height: lyricsHeight,
                        child: Opacity(
                          opacity: lyricsOpacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: lyricsOpacity < 0.5,
                            child: _buildLyricsPanelWidget(context),
                          ),
                        ),
                      ),
                      Positioned(
                        top: controlsTop, left: controlsLeft, width: controlsWidth, height: controlsHeight,
                        child: Opacity(
                          opacity: controlsOpacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: controlsOpacity < 0.5,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: isLandscape ? 450 : math.max(controlsWidth, 380.0),
                                child: _buildPlaybackControlsWidget(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: coverTop, left: coverLeft, width: coverSide, height: coverSide,
                        child: _buildAlbumArtCore(context, coverSide),
                      ),
                      Positioned(
                        top: infoTop, left: infoLeft, width: infoWidth, height: infoHeight,
                        child: _buildTrackInfo(context, targetInfoAlign, isLyricsMode),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

"""

replacement = replacement.replace('__FIELDS__', fields)
replacement = replacement.replace('__MINICARD__', build_mini_card_body)

new_text = text.replace(old_body, replacement)
new_text = re.sub(r'\bwidget\.', '', new_text)

with codecs.open(file_path, 'w', 'utf-8') as f:
    f.write(new_text)

print("Widgets updated to stateless double-tween successfully.")
