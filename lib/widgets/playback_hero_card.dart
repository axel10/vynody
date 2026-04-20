import 'dart:ui' show lerpDouble;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';
import '../models/music_file.dart';
import '../utils/playback_utils.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/cover_carousel.dart';
import '../widgets/lyrics_panel.dart';
import '../widgets/mini_player_widgets.dart';
import '../widgets/waveform_progress_bar.dart';

const String playbackHeroTag = 'player_capsule';

enum _TrackInfoMenuTarget { title, artistAlbum }

class PlaybackHeroCard extends ConsumerWidget {
  const PlaybackHeroCard({
    super.key,
    required this.isMini,
    this.isLyricsMode = false,
    this.isLandscape = false,
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
    this.onTagCompletionTap,
    this.onTagCompletionLongPress,
    this.onSleepTimerTap,
    this.onEqualizerTap,
    this.onPrevious,
    this.onPlayPause,
    this.onNext,
    this.onVolumeTap,
    this.onVolumeDrag,
    this.onVolumeScroll,
    this.onCoverTap,
    this.onCarouselAnimationComplete,
    this.overrideProgress,
    this.overridePosition,
    this.overrideWaveform,
    this.lyricsBottomSpacerHeight = 0.0,
    this.lyricsBottomTabBarHeight = 0.0,
  });

  final bool isMini;
  final bool isLyricsMode;
  final bool isLandscape;
  final bool isNext;
  final List<double>? overrideWaveform;
  final double? overrideProgress;
  final Duration? overridePosition;
  final bool showVisualizerToggle;
  final VoidCallback? onShowMoreMenu;
  final VoidCallback? onMiniTap;
  final VoidCallback? onCyclePlaylistMode;
  final VoidCallback? onShowPlaylistModeSelector;
  final VoidCallback? onShowRandomModeSelector;
  final ValueChanged<double>? onScrubbing;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onToggleVisualizer;
  final VoidCallback? onTagCompletionTap;
  final VoidCallback? onTagCompletionLongPress;
  final VoidCallback? onSleepTimerTap;
  final VoidCallback? onEqualizerTap;
  final VoidCallback? onPrevious;
  final VoidCallback? onPlayPause;
  final VoidCallback? onNext;
  final VoidCallback? onVolumeTap;
  final ValueChanged<double>? onVolumeDrag;
  final ValueChanged<double>? onVolumeScroll;
  final VoidCallback? onCoverTap;
  final VoidCallback? onCarouselAnimationComplete;
  final double lyricsBottomSpacerHeight;
  final double lyricsBottomTabBarHeight;

  double _lerp2D(
    double pN,
    double pL,
    double lN,
    double lL,
    double tLyrics,
    double tLand,
  ) {
    final p = lerpDouble(pN, pL, tLyrics) ?? pN;
    final l = lerpDouble(lN, lL, tLyrics) ?? lN;
    return lerpDouble(p, l, tLand) ?? p;
  }

  Future<void> _showTrackInfoContextMenu(
    BuildContext context,
    Offset globalPosition, {
    required _TrackInfoMenuTarget target,
    required MusicFile? currentMusic,
  }) async {
    await showSongContextMenu(
      context,
      globalPosition,
      song: currentMusic,
      mode: target == _TrackInfoMenuTarget.title
          ? SongContextMenuMode.title
          : SongContextMenuMode.artistAlbum,
    );
  }

  String _formatSleepTimer(Duration duration) {
    final safe = duration < Duration.zero ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    return [
      hours.toString().padLeft(2, '0'),
      minutes.toString().padLeft(2, '0'),
      seconds.toString().padLeft(2, '0'),
    ].join(':');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Hero(
      tag: playbackHeroTag,
      child: Material(
        type: MaterialType.transparency,
        child: isMini
            ? _buildMiniCard(context, ref)
            : _buildFullCard(context, ref),
      ),
    );
  }

  Widget _buildMiniCard(BuildContext context, WidgetRef ref) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isPlaying = ref.watch(audioIsPlayingProvider);
    final progress = ref.watch(audioProgressProvider);
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.6,
                child: MiniSpectrumBackground(
                  audio: ref.read(audioServiceProvider),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onMiniTap,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MiniArtwork(),
                          const SizedBox(width: 12),
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    currentMusic?.displayName ??
                                        AppLocalizations.of(
                                          context,
                                        )!.notSelected,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall!
                                        .copyWith(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(999),
                                    child: LinearProgressIndicator(
                                      minHeight: 3,
                                      value: progress.clamp(0.0, 1.0),
                                      backgroundColor: Colors.white24,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiniControlButton(
                        icon: Icons.skip_previous_rounded,
                        onPressed: onPrevious,
                        tooltip: AppLocalizations.of(context)!.previous,
                      ),
                      const SizedBox(width: 8),
                      MiniControlButton(
                        icon: isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onPressed: onPlayPause,
                        tooltip: isPlaying
                            ? AppLocalizations.of(context)!.pause
                            : AppLocalizations.of(context)!.play,
                      ),
                      const SizedBox(width: 8),
                      MiniControlButton(
                        icon: Icons.skip_next_rounded,
                        onPressed: onNext,
                        tooltip: AppLocalizations.of(context)!.next,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context, WidgetRef ref) {
    const animDuration = Duration(milliseconds: 400);
    const animCurve = Curves.fastOutSlowIn;
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    // 核心动画容器：使用 TweenAnimationBuilder 对 2D 平面上的多个布局变量（尺寸、位置、不透明度）进行线性插值处理。
    // 这使得点击封面切换 `isLyricsMode` 后，UI 元素能平滑移动/缩放，例如：
    // - 封面从大变小并挪到角落
    // - 歌词面板从下而上“浮现”
    // - 播放控制按键在手机竖屏时向下滑出屏幕
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
            // tLyrics 即为 0.0（普通模式）到 1.0（歌词模式）的动画插值因子
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
                final pNormalCoverSide = math.min(width * 0.98, height * 0.55);
                final pNormalCoverTop =
                    (height * 0.03 + (height * 0.46 - pNormalCoverSide) / 2);
                final pNormalCoverLeft = (width - pNormalCoverSide) / 2;

                final pNormalInfoTop = height * 0.54;
                final pNormalInfoLeft = 16.0;
                final pNormalInfoWidth = width - 32.0;
                final pNormalInfoHeight = 80.0;

                final pNormalControlsTop =
                    pNormalInfoTop + pNormalInfoHeight + 4.0;
                final pNormalControlsLeft = 16.0;
                final pNormalControlsWidth = width - 32.0;
                final pNormalControlsHeight =
                    height - pNormalControlsTop - 16.0;
                final pNormalControlsOpacity = 1.0;

                final pNormalLyricsTop = height;
                final pNormalLyricsLeft = 16.0;
                final pNormalLyricsWidth = width - 32.0;
                final pNormalLyricsHeight = height - pNormalInfoTop;
                final pNormalLyricsOpacity = 0.0;

                // ---------------- Portrait Lyrics ----------------
                final pLyricsCoverSide = math.min(120.0, width * 0.32);
                const pLyricsCoverTop = 12.0;
                const pLyricsCoverLeft = 12.0;

                const pLyricsInfoTop = 12.0;
                final pLyricsInfoLeft =
                    pLyricsCoverLeft + pLyricsCoverSide + 14.0;
                final pLyricsInfoWidth = width - pLyricsInfoLeft - 16.0;
                final pLyricsInfoHeight = pLyricsCoverSide;

                final pLyricsControlsTop = height;
                final pLyricsControlsLeft = 16.0;
                final pLyricsControlsWidth = width - 32.0;
                final pLyricsControlsHeight = pNormalControlsHeight;
                final pLyricsControlsOpacity = 0.0;

                final pLyricsLyricsTop =
                    pLyricsCoverTop + pLyricsCoverSide + 16.0;
                final pLyricsLyricsLeft = 16.0;
                final pLyricsLyricsWidth = width - 32.0;
                final pLyricsLyricsHeight = height - pLyricsLyricsTop;
                final pLyricsLyricsOpacity = 1.0;

                // ---------------- Landscape Normal ----------------
                const landscapeNormalLift = 30.0;
                const landscapeLyricsLift = 0.0;
                final lNormalCoverSide = math.min(width * 0.42, height * 0.85);
                final lNormalCoverTop =
                    (height - lNormalCoverSide) / 2 - landscapeNormalLift;
                final lNormalCoverLeft =
                    width * 0.05 + (width * 0.45 - lNormalCoverSide) / 2;

                final lNormalInfoTop =
                    height * 0.5 - 100 - 45 - landscapeNormalLift;
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

                final lLyricsCoverSide = math.min(
                  lColWidth * 0.8,
                  height * 0.45,
                );
                final lLyricsCoverTop = 12.0 - landscapeLyricsLift;
                final lLyricsCoverLeft = (lColWidth - lLyricsCoverSide) / 2;

                final lLyricsInfoTop =
                    lLyricsCoverTop + lLyricsCoverSide + 24.0;
                final lLyricsInfoLeft = 16.0;
                final lLyricsInfoWidth = lColWidth - 32.0;
                final lLyricsInfoHeight = 80.0;

                final lLyricsControlsTop =
                    lLyricsInfoTop + lLyricsInfoHeight + 16.0;
                final lLyricsControlsLeft = 16.0;
                final lLyricsControlsWidth = lColWidth - 32.0;
                final lLyricsControlsHeight =
                    height - lLyricsControlsTop - 32.0; // 播放控件歌词模式下底部预留 32 的空白
                final lLyricsControlsOpacity = 1.0;

                final lLyricsLyricsTop = 16.0;
                final lLyricsLyricsLeft = lColWidth + 16.0;
                final lLyricsLyricsWidth = width - lLyricsLyricsLeft - 32.0;
                final lLyricsLyricsHeight = height - 32.0;
                final lLyricsLyricsOpacity = 1.0;

                // ---------------- 执行 2D 线性插值 (Execute 2D Interpolation) ----------------
                // 核心思路：通过 _lerp2D(A, B, C, D, tLyrics, tLand) 计算
                // UI 元素在 [竖屏普通, 竖屏歌词, 横屏普通, 横屏歌词] 四种具体布局配置下的合成坐标。
                // 这实现了点击封面后跨越多种状态的极其平等的变幻。

                final coverSide = _lerp2D(
                  pNormalCoverSide,
                  pLyricsCoverSide,
                  lNormalCoverSide,
                  lLyricsCoverSide,
                  tLyrics,
                  tLand,
                );
                final coverTop = _lerp2D(
                  pNormalCoverTop,
                  pLyricsCoverTop,
                  lNormalCoverTop,
                  lLyricsCoverTop,
                  tLyrics,
                  tLand,
                );
                final coverLeft = _lerp2D(
                  pNormalCoverLeft,
                  pLyricsCoverLeft,
                  lNormalCoverLeft,
                  lLyricsCoverLeft,
                  tLyrics,
                  tLand,
                );

                final infoTop = _lerp2D(
                  pNormalInfoTop,
                  pLyricsInfoTop,
                  lNormalInfoTop,
                  lLyricsInfoTop,
                  tLyrics,
                  tLand,
                );
                final infoLeft = _lerp2D(
                  pNormalInfoLeft,
                  pLyricsInfoLeft,
                  lNormalInfoLeft,
                  lLyricsInfoLeft,
                  tLyrics,
                  tLand,
                );
                final infoWidth = _lerp2D(
                  pNormalInfoWidth,
                  pLyricsInfoWidth,
                  lNormalInfoWidth,
                  lLyricsInfoWidth,
                  tLyrics,
                  tLand,
                );
                final infoHeight = _lerp2D(
                  pNormalInfoHeight,
                  pLyricsInfoHeight,
                  lNormalInfoHeight,
                  lLyricsInfoHeight,
                  tLyrics,
                  tLand,
                );

                final controlsTop = _lerp2D(
                  pNormalControlsTop,
                  pLyricsControlsTop,
                  lNormalControlsTop,
                  lLyricsControlsTop,
                  tLyrics,
                  tLand,
                );
                final controlsLeft = _lerp2D(
                  pNormalControlsLeft,
                  pLyricsControlsLeft,
                  lNormalControlsLeft,
                  lLyricsControlsLeft,
                  tLyrics,
                  tLand,
                );
                final controlsWidth = _lerp2D(
                  pNormalControlsWidth,
                  pLyricsControlsWidth,
                  lNormalControlsWidth,
                  lLyricsControlsWidth,
                  tLyrics,
                  tLand,
                );
                final controlsHeight = _lerp2D(
                  pNormalControlsHeight,
                  pLyricsControlsHeight,
                  lNormalControlsHeight,
                  lLyricsControlsHeight,
                  tLyrics,
                  tLand,
                );
                final controlsOpacity = _lerp2D(
                  pNormalControlsOpacity,
                  pLyricsControlsOpacity,
                  lNormalControlsOpacity,
                  lLyricsControlsOpacity,
                  tLyrics,
                  tLand,
                );

                final lyricsTop = _lerp2D(
                  pNormalLyricsTop,
                  pLyricsLyricsTop,
                  lNormalLyricsTop,
                  lLyricsLyricsTop,
                  tLyrics,
                  tLand,
                );
                final lyricsLeft = _lerp2D(
                  pNormalLyricsLeft,
                  pLyricsLyricsLeft,
                  lNormalLyricsLeft,
                  lLyricsLyricsLeft,
                  tLyrics,
                  tLand,
                );
                final lyricsWidth = _lerp2D(
                  pNormalLyricsWidth,
                  pLyricsLyricsWidth,
                  lNormalLyricsWidth,
                  lLyricsLyricsWidth,
                  tLyrics,
                  tLand,
                );
                final lyricsHeight = _lerp2D(
                  pNormalLyricsHeight,
                  pLyricsLyricsHeight,
                  lNormalLyricsHeight,
                  lLyricsLyricsHeight,
                  tLyrics,
                  tLand,
                );
                final lyricsOpacity = _lerp2D(
                  pNormalLyricsOpacity,
                  pLyricsLyricsOpacity,
                  lNormalLyricsOpacity,
                  lLyricsLyricsOpacity,
                  tLyrics,
                  tLand,
                );

                // 界面渲染层 (Rendering Layer)：
                // 使用 Stack + Positioned 承载各个 UI 组件。Positioned 的物理属性（top/left/width/height）
                // 均为上述插值计算所得，从而实现了流畅的一键切换体验。
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
                        top: lyricsTop,
                        left: lyricsLeft,
                        width: lyricsWidth,
                        height: lyricsHeight,
                        child: Opacity(
                          opacity: lyricsOpacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: lyricsOpacity < 0.5,
                            child: _buildLyricsPanelWidget(context, ref),
                          ),
                        ),
                      ),
                      Positioned(
                        top: controlsTop,
                        left: controlsLeft,
                        width: controlsWidth,
                        height: controlsHeight,
                        child: Opacity(
                          opacity: controlsOpacity.clamp(0.0, 1.0),
                          child: IgnorePointer(
                            ignoring: controlsOpacity < 0.5,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: isLandscape
                                    ? 450
                                    : math.max(controlsWidth, 380.0),
                                child: _buildPlaybackControlsWidget(
                                  context,
                                  ref,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: coverTop,
                        left: coverLeft,
                        width: coverSide,
                        height: coverSide,
                        child: _buildAlbumArtCore(context, ref, coverSide),
                      ),
                      Positioned(
                        top: infoTop,
                        left: infoLeft,
                        width: infoWidth,
                        height: infoHeight,
                        child: _buildTrackInfo(
                          context,
                          currentMusic,
                          targetInfoAlign,
                          tLyrics,
                        ),
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

  Widget _buildAlbumArtCore(
    BuildContext context,
    WidgetRef ref,
    double currentSize,
  ) {
    final playlist = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    if (playlist.isEmpty) {
      return Center(
        child: Container(
          width: currentSize * 0.8,
          height: currentSize * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: Colors.black87,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 50,
                spreadRadius: 15,
              ),
            ],
          ),
          child: const Icon(Icons.music_note, size: 80, color: Colors.white54),
        ),
      );
    }

    final cover = ExcludeSemantics(
      child: CoverCarousel(
        playlist: playlist,
        currentIndex: currentIndex,
        audioService: ref.read(audioServiceProvider),
        isNext: isNext,
        displaySize: currentSize,
        onPageChanged: (page) {
          final audio = ref.read(audioServiceProvider);
          if (page >= 0 && page < playlist.length && page != currentIndex) {
            audio.playAtIndex(page);
          }
        },
        onAnimationComplete: onCarouselAnimationComplete,
      ),
    );

    if (onCoverTap == null) return cover;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCoverTap,
      child: cover,
    );
  }

  Widget _buildTrackInfo(
    BuildContext context,
    MusicFile? currentMusic,
    TextAlign align,
    double lyricsModeT,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final title = currentMusic?.displayName ?? l10n.notSelected;
    final showArtistAlbum = currentMusic != null;

    final rawAlbum = currentMusic?.album?.trim() ?? '';
    final rawArtist = currentMusic?.artist?.trim() ?? '';

    bool isUnknown(String val) {
      if (val.isEmpty) return true;
      final lower = val.toLowerCase();
      return lower == 'unknown' ||
          lower == 'unknown artist' ||
          lower == 'unknown album';
    }

    final bool hasArtist = !isUnknown(rawArtist);
    final bool hasAlbum = !isUnknown(rawAlbum);
    final transition = lyricsModeT.clamp(0.0, 1.0);
    final titleAlignment = align == TextAlign.left
        ? Alignment.lerp(Alignment.center, Alignment.centerLeft, transition)!
        : Alignment.center;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: Align(
            alignment: titleAlignment,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: (details) {
                _showTrackInfoContextMenu(
                  context,
                  details.globalPosition,
                  target: _TrackInfoMenuTarget.title,
                  currentMusic: currentMusic,
                );
              },
              onLongPressStart: (details) {
                HapticFeedback.mediumImpact();
                _showTrackInfoContextMenu(
                  context,
                  details.globalPosition,
                  target: _TrackInfoMenuTarget.title,
                  currentMusic: currentMusic,
                );
              },
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400),
                curve: Curves.fastOutSlowIn,
                textAlign: TextAlign.start,
                style: Theme.of(context).textTheme.titleLarge!.copyWith(
                  color: Colors.white,
                  fontSize: lyricsModeT > 0.5 && !isLandscape ? 18 : 22,
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        if (showArtistAlbum)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: SizedBox(
              width: double.infinity,
              child: Align(
                alignment: titleAlignment,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) {
                    _showTrackInfoContextMenu(
                      context,
                      details.globalPosition,
                      target: _TrackInfoMenuTarget.artistAlbum,
                      currentMusic: currentMusic,
                    );
                  },
                  onLongPressStart: (details) {
                    HapticFeedback.mediumImpact();
                    _showTrackInfoContextMenu(
                      context,
                      details.globalPosition,
                      target: _TrackInfoMenuTarget.artistAlbum,
                      currentMusic: currentMusic,
                    );
                  },
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.fastOutSlowIn,
                    textAlign: TextAlign.start,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: Colors.white70,
                      fontSize: lyricsModeT > 0.5 && !isLandscape ? 13 : 15,
                      height: 1.3,
                    ),
                    child: Text(
                      hasArtist && hasAlbum
                          ? '$rawArtist — $rawAlbum'
                          : (hasArtist
                                ? rawArtist
                                : (hasAlbum ? rawAlbum : 'Unknown')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlaybackControlsWidget(BuildContext context, WidgetRef ref) {
    final playbackMode = ref.watch(audioPlaybackModeProvider);
    final isRandomMode = ref.watch(audioIsRandomModeProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final playlistService = ref.watch(playlistServiceProvider);
    final isFavorite =
        currentMusic != null && playlistService.isFavoriteSong(currentMusic);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final duration = ref.watch(audioDurationProvider);
    final sleepTimerRemaining = ref.watch(audioSleepTimerRemainingProvider);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white70),
              onPressed: onShowMoreMenu,
              tooltip: l10n.more,
            ),
            IconButton(
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 28,
                color: isFavorite ? Colors.redAccent : Colors.white70,
              ),
              onPressed: currentMusic == null
                  ? null
                  : () async {
                      final playlistService = ref.read(playlistServiceProvider);
                      await playlistService.toggleFavoriteSong(currentMusic);
                    },
              tooltip: isFavorite ? '取消收藏' : '收藏',
            ),
            GestureDetector(
              onLongPress: onShowPlaylistModeSelector,
              child: IconButton(
                icon: Icon(
                  getPlaylistModeIcon(playbackMode),
                  size: 28,
                  color: Colors.white70,
                ),
                onPressed: onCyclePlaylistMode,
                tooltip: getPlaylistModeName(playbackMode, l10n),
              ),
            ),
            GestureDetector(
              onLongPress: onShowRandomModeSelector,
              child: IconButton(
                icon: Icon(
                  Icons.shuffle_rounded,
                  size: 28,
                  color: isRandomMode
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white70,
                ),
                onPressed: () {
                  final audio = ref.read(audioServiceProvider);
                  if (audio.settingsService.randomRange == 1 && !isRandomMode) {
                    final playlistService = ref.read(playlistServiceProvider);
                    final List<MusicFile> allSongs = [];
                    final pathSet = <String>{};
                    for (final p in playlistService.playlists) {
                      for (final s in p.songs) {
                        if (pathSet.add(s.path)) allSongs.add(s);
                      }
                    }
                    audio.toggleRandomMode(globalSongs: allSongs);
                  } else {
                    audio.toggleRandomMode();
                  }
                },
                tooltip: l10n.randomMode,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.auto_fix_high_rounded,
                size: 28,
                color: Colors.white70,
              ),
              onPressed: onTagCompletionTap,
              onLongPress: onTagCompletionLongPress,
              tooltip: '歌曲标签补全',
            ),
            Tooltip(
              message: sleepTimerRemaining != null
                  ? '睡眠定时器 ${_formatSleepTimer(sleepTimerRemaining)}'
                  : '睡眠定时器',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSleepTimerTap,
                child: SizedBox(
                  width: 74,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bedtime_rounded,
                        size: 28,
                        color: sleepTimerRemaining != null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white70,
                      ),
                      if (sleepTimerRemaining != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatSleepTimer(sleepTimerRemaining),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 10,
                            height: 1.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.tune_rounded,
                size: 28,
                color: Colors.white70,
              ),
              onPressed: onEqualizerTap,
              tooltip: "均衡器",
            ),
          ],
        ),
        SizedBox(height: isLandscape ? 16 : 12),
        Builder(
          builder: (context) {
            final enabled = ref.watch(
              settingsServiceProvider.select(
                (s) => s.isWaveformProgressBarEnabled,
              ),
            );
            final waveform =
                overrideWaveform ?? currentMusic?.waveform ?? const [];
            final displayProgress =
                overrideProgress ??
                ref.watch(audioProgressProvider).clamp(0.0, 1.0);

            if (enabled) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: WaveformProgressBar(
                  waveform: waveform,
                  progress: displayProgress,
                  duration: duration,
                  onScrubbing: onScrubbing ?? (_) {},
                  onSeek: onSeek ?? (_) {},
                ),
              );
            }
            return _buildStandardSlider(context, displayProgress);
          },
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(
                  overridePosition ?? ref.watch(audioPositionProvider),
                ),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(height: isLandscape ? 16 : 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                showVisualizerToggle
                    ? Icons.analytics
                    : Icons.analytics_outlined,
                size: 28,
                color: showVisualizerToggle ? Colors.white : Colors.white70,
              ),
              onPressed: onToggleVisualizer,
              tooltip: AppLocalizations.of(context)!.visualizer,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(
                Icons.skip_previous_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onPrevious,
              tooltip: l10n.previous,
            ),
            const SizedBox(width: 16),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: IconButton(
                onPressed: onPlayPause,
                tooltip: ref.watch(audioIsPlayingProvider)
                    ? l10n.pause
                    : l10n.play,
                icon: Icon(
                  ref.watch(audioIsPlayingProvider)
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 40,
                  color:
                      currentThemeColorsMap['darkVibrant'] ??
                      currentThemeColorsMap['darkMuted'] ??
                      Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(
                Icons.skip_next_rounded,
                size: 48,
                color: Colors.white,
              ),
              onPressed: onNext,
              tooltip: l10n.next,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (details) {
                onVolumeDrag?.call(details.primaryDelta ?? 0);
              },
              child: Listener(
                onPointerSignal: (pointerSignal) {
                  if (pointerSignal is PointerScrollEvent) {
                    onVolumeScroll?.call(pointerSignal.scrollDelta.dy);
                  }
                },
                child: IconButton(
                  icon: Icon(
                    getVolumeIcon(ref.watch(audioVolumeProvider)),
                    size: 28,
                    color: Colors.white70,
                  ),
                  onPressed: onVolumeTap,
                  tooltip: l10n.volume,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLyricsPanelWidget(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final position = ref.watch(audioPositionProvider);
    final currentThemeColorsMap = ref.watch(audioCurrentThemeColorsMapProvider);
    final accent =
        currentThemeColorsMap['darkVibrant'] ??
        currentThemeColorsMap['darkMuted'] ??
        Colors.white;

    return LyricsPanel(
      key: ValueKey('$currentIndex:${currentMusic?.path ?? 'no-track'}'),
      lyrics: currentMusic?.lyrics,
      position: position,
      accentColor: accent,
      bottomSpacerHeight: lyricsBottomSpacerHeight,
      bottomTabBarHeight: lyricsBottomTabBarHeight,
    );
  }

  Widget _buildStandardSlider(BuildContext context, double displayProgress) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
          thumbColor: Colors.white,
          overlayColor: Colors.white.withValues(alpha: 0.1),
        ),
        child: Slider(
          value: displayProgress.clamp(0.0, 1.0),
          onChanged: onScrubbing,
          onChangeEnd: (value) {
            onSeek?.call(value);
          },
        ),
      ),
    );
  }
}
