import codecs
import re

file_path = r'c:\Users\Administrator\Desktop\projects\player_project\vibe_flow\lib\widgets\playback_hero_card.dart'

with codecs.open(file_path, 'r', 'utf-8') as f:
    text = f.read()

# 1. Change StatelessWidget to StatefulWidget
text = text.replace('class PlaybackHeroCard extends StatelessWidget {', 'import \'dart:async\';\n\nclass PlaybackHeroCard extends StatefulWidget {')

# 2. Extract fields to put inside StatefulWidget, then define the State class
# We know `@override\n  Widget build(BuildContext context) {` is where the build method starts.
build_split = text.split('@override\n  Widget build(BuildContext context) {')
if len(build_split) != 2:
    print("Cannot find build method.")
    exit(1)

top_part = build_split[0]
build_part = build_split[1]

# Append createState to top_part
top_part = top_part + """
  @override
  State<PlaybackHeroCard> createState() => _PlaybackHeroCardState();
}

class _PlaybackHeroCardState extends State<PlaybackHeroCard> {
  Duration _animationDuration = Duration.zero;
  Timer? _animTimer;

  @override
  void didUpdateWidget(PlaybackHeroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLandscape != widget.isLandscape ||
        oldWidget.isLyricsMode != widget.isLyricsMode) {
      setState(() {
        _animationDuration = const Duration(milliseconds: 400);
      });
      _animTimer?.cancel();
      _animTimer = Timer(const Duration(milliseconds: 420), () {
        if (mounted) {
          setState(() {
            _animationDuration = Duration.zero;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _animTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {"""

# 3. Replace references to variables inside the build method and sub-methods with widget.varName
replacements = [
    'isMini', 'isLyricsMode', 'isLandscape', 'screenWidth', 'screenHeight',
    'isNext', 'showVisualizerToggle', 'onShowMoreMenu', 'onMiniTap', 
    'onCyclePlaylistMode', 'onShowPlaylistModeSelector', 'onShowRandomModeSelector',
    'onScrubbing', 'onSeek', 'onToggleVisualizer', 'onEqualizerTap',
    'onPrevious', 'onPlayPause', 'onNext', 'onVolumeTap', 'onVolumeDrag',
    'onVolumeScroll', 'onCoverTap', 'overrideProgress', 'overridePosition', 'overrideWaveform'
]

# Note: We must be careful not to replace local variables that might have these names, but actually there are no local variables with these names. 
# We'll use regex to ensure word boundaries.
new_build_part = build_part
for r in replacements:
    new_build_part = re.sub(r'\b' + r + r'\b', 'widget.' + r, new_build_part)

# Also we need to inject the timer's duration variable instead of the hardcoded one!
# We will replace `const transitionDuration = Duration(milliseconds: 400);` 
# with `final transitionDuration = _animationDuration;`
new_build_part = new_build_part.replace(
    'const transitionDuration = Duration(milliseconds: 400);',
    'final transitionDuration = _animationDuration;'
)

# And similarly for AnimatedDefaultTextStyle where duration was hardcoded:
# It used `duration: const Duration(milliseconds: 380)`
new_build_part = new_build_part.replace(
    'duration: const Duration(milliseconds: 380)',
    'duration: _animationDuration'
)

new_text = top_part + new_build_part

# One more fix: we added `import 'dart:async';` at the top, but we should actually add it to the imports section, not inside the class definition text.
# Let's fix that.
new_text = new_text.replace("import 'dart:async';\n\nclass PlaybackHeroCard", "class PlaybackHeroCard")
if "import 'dart:async';" not in new_text:
    new_text = "import 'dart:async';\n" + new_text

with codecs.open(file_path, 'w', 'utf-8') as f:
    f.write(new_text)

print("Widgets updated successfully.")
