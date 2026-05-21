import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rpod;
import 'package:oktoast/oktoast.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../l10n/app_localizations.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../dialogs/manual_lyrics_dialog.dart';
import '../dialogs/online_lyrics_search_dialog.dart';
import '../dialogs/timeline_adjustment_dialog.dart';
import '../player/audio_riverpod.dart';
import '../player/lyrics_cache_models.dart';
import '../player/lyrics_controller.dart';
import '../player/lyrics_controller_state.dart';
import '../player/lyrics_riverpod.dart';
import '../player/lyrics_song_task_state.dart';
import '../player/settings_service.dart';
import 'lyrics_panel_toasts.dart';
import 'lyrics_panel_views.dart';

bool shouldShowGenerateLyricsButton({required bool hasCurrentSong}) {
  return hasCurrentSong;
}

class LyricsPanel extends rpod.ConsumerStatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.position,
    this.accentColor,
    this.bottomSpacerHeight = 0.0,
    this.bottomTabBarHeight = 0.0,
  });

  final MusicLyric? lyrics;
  final Duration position;
  final Color? accentColor;
  final double bottomSpacerHeight;
  final double bottomTabBarHeight;

  @override
  rpod.ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends rpod.ConsumerState<LyricsPanel> {
  static const double _lyricsDragSeekThreshold = 24.0;
  static const double _timelineOffsetMinSeconds = -10.0;
  static const double _timelineOffsetMaxSeconds = 10.0;
  static const double _seekToastTopOffset = 88.0;
  static const Duration _seekToastAutoDismissDelay = Duration(
    milliseconds: 1200,
  );
  static const Duration _seekToastAnimationDuration = Duration(
    milliseconds: 160,
  );
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  bool _isAutoScrollPaused = false;
  bool _isDraggingLyrics = false;
  double _timelineOffsetSeconds = 0.0;
  double _dragDistancePixels = 0.0;
  double _dragTravelPixels = 0.0;
  int? _dragStartLine;
  int? _dragCurrentLine;
  int _lastDebugActiveIndex = -1;
  int _lastDebugPositionMs = -1;
  DateTime _lastDebugLogAt = DateTime.fromMillisecondsSinceEpoch(0);
  ToastFuture? _seekToast;
  String? _seekToastSignature;
  Timer? _seekToastAutoDismissTimer;
  List<double> _cachedCenters = const [];

  LyricsController get _lyricsControllerActions =>
      ref.read(lyricsControllerProvider.notifier);

  MusicLyric? _lyricsForDisplay() {
    return _lyricsControllerActions.currentLyricsForCurrentSong() ??
        widget.lyrics;
  }

  List<LyricLine> _displayLinesForCurrentLyrics() {
    return ref.read(lyricsDisplayLinesProvider(_lyricsForDisplay()));
  }

  List<LyricLine> _plainLyricsLines(String plainLyrics) {
    final normalized = plainLyrics.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    final lines = normalized.split(RegExp(r'\r?\n'));
    return lines
        .map(
          (line) =>
              LyricLine(timestamp: Duration.zero, text: line, isTimed: false),
        )
        .toList(growable: false);
  }

  void _calculateHeights({
    required List<LyricLine> lines,
    required MusicLyric? lyrics,
    required double maxWidth,
    required double lyricsFontScale,
    required bool hasTimedLyrics,
    required BuildContext context,
  }) {
    final timedLyricFontSize = 16 * lyricsFontScale;
    final plainLyricFontSize = 18 * lyricsFontScale;
    final translationFontSize = 13 * lyricsFontScale;
    final verticalItemPadding = 6 * lyricsFontScale;
    final translatedSpacing = 3 * lyricsFontScale;

    final lineStyle = hasTimedLyrics
        ? Theme.of(context).textTheme.bodyLarge!.copyWith(
            fontSize: timedLyricFontSize,
            fontWeight: FontWeight.w400,
            height: 1.4,
            leadingDistribution: TextLeadingDistribution.even,
          )
        : TextStyle(
            fontSize: plainLyricFontSize,
            fontWeight: FontWeight.w400,
            height: 1.6,
            leadingDistribution: TextLeadingDistribution.even,
          );

    final translationStyle = TextStyle(
      fontSize: translationFontSize,
      height: 1.3,
      leadingDistribution: TextLeadingDistribution.even,
    );

    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);

    final heights = <double>[];
    final centers = <double>[];
    double currentTop = 0.0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final translated = lyrics
          ?.translatedLineAt(
            i,
            ref.read(lyricsControllerProvider).lyricsTranslationLanguageCode,
          )
          .trim() ??
          '';

      // 1. Calculate main text height
      final textPainter = TextPainter(
        text: TextSpan(
          text: line.text,
          style: lineStyle,
        ),
        textDirection: textDirection,
        textScaler: textScaler,
      )..layout(maxWidth: maxWidth);
      double itemHeight = textPainter.height;

      // 2. Calculate translation height if present
      if (hasTimedLyrics && translated.isNotEmpty) {
        final transPainter = TextPainter(
          text: TextSpan(
            text: translated,
            style: translationStyle,
          ),
          textDirection: textDirection,
          textScaler: textScaler,
        )..layout(maxWidth: math.max(0.0, maxWidth - 24.0));
          itemHeight += translatedSpacing + transPainter.height;
      }

      // 3. Add vertical padding
      itemHeight += verticalItemPadding * 2;

      heights.add(itemHeight);
      centers.add(currentTop + itemHeight / 2);
      currentTop += itemHeight;
    }

    _cachedCenters = centers;
  }

  int _findClosestLineIndex(double targetCenter, List<double> centers) {
    if (centers.isEmpty) return 0;
    if (targetCenter <= centers.first) return 0;
    if (targetCenter >= centers.last) return centers.length - 1;

    int low = 0;
    int high = centers.length - 1;
    while (low < high) {
      int mid = (low + high) >> 1;
      if (centers[mid] < targetCenter) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    if (low > 0) {
      final diffCurrent = (centers[low] - targetCenter).abs();
      final diffPrev = (centers[low - 1] - targetCenter).abs();
      if (diffPrev < diffCurrent) {
        return low - 1;
      }
    }
    return low;
  }



  ScrollBehavior _lyricsScrollBehavior(BuildContext context) {
    return ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _timelineOffsetSeconds = _timelineOffsetToSeconds(
      widget.lyrics?.timelineOffset,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleScrollIfNeeded(force: true);
    });
  }

  @override
  void dispose() {
    _seekToastAutoDismissTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _dismissSeekToast({bool showAnim = false}) {
    _seekToastAutoDismissTimer?.cancel();
    _seekToastAutoDismissTimer = null;
    _seekToast?.dismiss(showAnim: showAnim);
    _seekToast = null;
    _seekToastSignature = null;
  }

  String _formatDuration(Duration duration) {
    final safe = duration < Duration.zero ? Duration.zero : duration;
    final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _syncSeekToast(Duration target) {
    final signature = target.inMilliseconds.toString();
    if (_seekToastSignature == signature && _seekToast?.mounted == true) {
      return;
    }

    _dismissSeekToast();
    _seekToastSignature = signature;
    final l10n = AppLocalizations.of(context);
    final timeText = _formatDuration(target);
    _seekToast = showToastWidget(
      LyricsSeekToast(
        target: target,
        timeLabel: l10n?.targetTimeLabel(timeText) ?? 'Target time $timeText',
        accentColor:
            widget.accentColor ?? Theme.of(context).colorScheme.primary,
      ),
      context: context,
      duration: Duration.zero,
      position: ToastPosition.top.copyWith(
        align: Alignment.topCenter,
        offset: _seekToastTopOffset,
      ),
      dismissOtherToast: false,
      handleTouch: false,
      animationDuration: _seekToastAnimationDuration,
      animationCurve: Curves.easeOutCubic,
    );

    _seekToastAutoDismissTimer?.cancel();
    _seekToastAutoDismissTimer = Timer(_seekToastAutoDismissDelay, () {
      if (!mounted) return;
      if (_seekToastSignature != signature) return;
      _dismissSeekToast(showAnim: true);
    });
  }

  Duration _audioSeekPositionForLyricTimestamp(Duration timestamp) {
    final targetMs = timestamp.inMilliseconds + _timelineOffsetMilliseconds;
    return Duration(milliseconds: math.max(0, targetMs));
  }

  Future<bool> _ensureLyricsApiKey() async {
    return ensureLyricsGenerationApiKey(context, ref);
  }

  Future<bool> _ensureGeminiApiKey() async {
    return ensureGeminiApiKey(context, ref);
  }

  void _showGenerationErrorSnack(String message) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message.trim())));
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldOffset = _timelineOffsetToSeconds(
      oldWidget.lyrics?.timelineOffset,
    );
    final newOffset = _timelineOffsetToSeconds(widget.lyrics?.timelineOffset);
    if (oldOffset != newOffset) {
      _timelineOffsetSeconds = newOffset;
    }
    _scheduleScrollIfNeeded();
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition, {
    required LyricsControllerState lyricsState,
    required LyricsSongTaskState taskState,
    required List<LyricLine> displayLines,
    required String displayPlainLyrics,
    required bool hasCurrentSong,
    required double lyricsFontScale,
    bool requeryOnly = false,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final l10n = AppLocalizations.of(context)!;

    final items = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'fill_lyrics',
        enabled: hasCurrentSong,
        child: Text(l10n.enterLyricsTitle),
      ),
      if (lyricsState.hasLyrics)
        PopupMenuItem<String>(
          value: 'generate',
          enabled: hasCurrentSong && !taskState.isGenerationBusy,
          child: Text(l10n.generateLyrics),
        ),
      if (lyricsState.hasLyrics)
        PopupMenuItem<String>(
          value: 'generate_timeline',
          enabled: hasCurrentSong && !taskState.isGenerationBusy,
          child: Text(l10n.generateTimeline),
        ),
      if (!requeryOnly &&
          _hasTimedLyrics(displayLines) &&
          lyricsState.hasLyrics)
        const PopupMenuDivider(),
      if (!requeryOnly &&
          _hasTimedLyrics(displayLines) &&
          lyricsState.hasLyrics)
        PopupMenuItem<String>(
          value: 'adjust_timeline',
          enabled: hasCurrentSong,
          child: Text(l10n.timelineAdjustmentTitle),
        ),
      if (!requeryOnly && _hasTimedLyrics(displayLines))
        PopupMenuItem<String>(
          value: 'toggle_auto_scroll',
          enabled: hasCurrentSong,
          child: Text(
            _isAutoScrollPaused ? l10n.resumeAutoScroll : l10n.pauseAutoScroll,
          ),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'translate',
          enabled: hasCurrentSong && !taskState.isTranslationBusy,
          child: Text(l10n.translateLyrics),
        ),
      PopupMenuItem<String>(
        value: 'search_online_lyrics',
        enabled: hasCurrentSong,
        child: Text(l10n.selectOnlineLyrics),
      ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'clear_lyrics_cache',
          enabled: hasCurrentSong && lyricsState.hasLyrics,
          child: Text(l10n.clearLyricsCache),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'clear_translation_cache',
          enabled: hasCurrentSong && lyricsState.hasLyrics,
          child: Text(l10n.clearTranslationCache),
        ),
      if (requeryOnly)
        PopupMenuItem<String>(
          value: 'requery',
          enabled:
              hasCurrentSong &&
              !lyricsState.isLyricsLoading &&
              !taskState.isGenerationBusy,
          child: Text(l10n.requery),
        ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        value: 'increase_lyrics_font',
        enabled: lyricsFontScale < SettingsService.maxLyricsFontScale,
        child: Text(l10n.increaseLyricsFont),
      ),
      PopupMenuItem<String>(
        value: 'decrease_lyrics_font',
        enabled: lyricsFontScale > SettingsService.minLyricsFontScale,
        child: Text(l10n.decreaseLyricsFont),
      ),
      PopupMenuItem<String>(
        value: 'reset_lyrics_font',
        enabled: lyricsFontScale != SettingsService.defaultLyricsFontScale,
        child: Text(l10n.restoreDefaultSize),
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
      } else {
        _dismissSeekToast();
      }
    } else if (selected == 'generate') {
      if (await _ensureLyricsApiKey()) {
        if (!mounted) return;
        final errorMessage = await _lyricsControllerActions
            .regenerateLyricsForCurrentSong();
        if (errorMessage != null) {
          _showGenerationErrorSnack(errorMessage);
        }
      }
    } else if (selected == 'generate_timeline') {
      if (await _ensureLyricsApiKey()) {
        if (!mounted) return;
        final errorMessage = await _lyricsControllerActions
            .generateTimelineForCurrentSong();
        if (errorMessage != null) {
          _showGenerationErrorSnack(errorMessage);
        }
      }
    } else if (selected == 'translate') {
      if (await _ensureGeminiApiKey()) {
        if (!mounted) return;
        final errorMessage = await _lyricsControllerActions
            .translateLyricsForCurrentSong();
        if (errorMessage != null) {
          _showGenerationErrorSnack(errorMessage);
        }
      }
    } else if (selected == 'search_online_lyrics') {
      await _searchOnlineLyrics();
    } else if (selected == 'clear_lyrics_cache') {
      await _lyricsControllerActions.clearLyricsCacheForCurrentSong();
    } else if (selected == 'clear_translation_cache') {
      await _lyricsControllerActions.clearTranslationCacheForCurrentSong();
    } else if (selected == 'requery') {
      await _lyricsControllerActions.requeryLyricsForCurrentSong();
    } else if (selected == 'adjust_timeline') {
      await _showTimelineAdjustmentPanel(displayLines);
    } else if (selected == 'fill_lyrics') {
      await _showManualLyricsDialog(displayPlainLyrics);
    } else if (selected == 'increase_lyrics_font') {
      ref.read(settingsServiceProvider).increaseLyricsFontScale();
    } else if (selected == 'decrease_lyrics_font') {
      ref.read(settingsServiceProvider).decreaseLyricsFontScale();
    } else if (selected == 'reset_lyrics_font') {
      ref.read(settingsServiceProvider).resetLyricsFontScale();
    }
  }

  Future<void> _showManualLyricsDialog(String initialLyrics) async {
    final submittedLyrics = await showManualLyricsDialog(
      context,
      initialLyrics: initialLyrics,
    );

    if (!mounted || submittedLyrics == null) return;

    await _lyricsControllerActions.fillLyricsForCurrentSong(submittedLyrics);
  }

  Future<void> _searchOnlineLyrics() async {
    final currentSong = ref.read(audioCurrentMusicProvider);
    final songTitle = currentSong?.displayName.trim() ?? '';
    if (currentSong == null || songTitle.isEmpty) {
      return;
    }
    final songArtist = currentSong.artist?.trim();
    final songAlbum = currentSong.album?.trim();

    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.searchingOnlineLyrics),
        duration: const Duration(days: 1),
      ),
    );

    final service = ref.read(lyricsServiceProvider);
    final tracks = await service.searchTracksByTitle(title: songTitle);

    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    if (tracks.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noMatchingResults)));
      return;
    }

    final selectedTrack = await showOnlineLyricsSearchDialog(
      context: context,
      queryTitle: songTitle,
      tracks: tracks,
      queryArtist: songArtist?.isNotEmpty == true ? songArtist : null,
      queryAlbum: songAlbum?.isNotEmpty == true ? songAlbum : null,
      searchTracks: ({required String title, String? artist, String? album}) {
        return service.searchTracksByQuery(
          title: title,
          artist: artist,
          album: album,
        );
      },
    );

    if (!mounted || selectedTrack == null) return;

    final lyricsText = selectedTrack.syncedLyrics?.trim().isNotEmpty == true
        ? selectedTrack.syncedLyrics!.trim()
        : selectedTrack.plainLyrics?.trim() ?? '';
    if (lyricsText.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noMatchingResults)));
      return;
    }

    await _lyricsControllerActions.fillLyricsForCurrentSong(
      lyricsText,
      source: LyricsCacheSource.lrclib,
    );
  }

  String _buildGenerateButtonLabel(
    AppLocalizations l10n,
    LyricsSongTaskState taskState,
  ) {
    final activeLabel = taskState.activeStatusLabel.trim();
    if (activeLabel.isNotEmpty) {
      return activeLabel;
    }

    return taskState.isGenerationBusy
        ? l10n.queueGenerateLyrics
        : l10n.generateLyrics;
  }

  void _scheduleScrollIfNeeded({
    bool force = false,
    List<LyricLine>? displayLines,
  }) {
    final lines = displayLines ?? _displayLinesForCurrentLyrics();
    if (lines.isEmpty ||
        !_hasTimedLyrics(lines) ||
        _isAutoScrollPaused ||
        _isDraggingLyrics) {
      return;
    }

    final activeIndex = _activeLineIndex(lines);
    if (!force && activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollToLineIndex(
        activeIndex,
        animate: true,
      );
    });
  }

  void _beginLyricsDrag(List<LyricLine> displayLines) {
    if (displayLines.isEmpty || !_hasTimedLyrics(displayLines)) return;

    final initialLine = _activeLineIndex(
      displayLines,
    ).clamp(0, displayLines.length - 1).toInt();

    if (mounted) {
      setState(() {
        _isDraggingLyrics = false;
        _dragDistancePixels = 0.0;
        _dragTravelPixels = 0.0;
        _dragStartLine = initialLine;
        _dragCurrentLine = initialLine;
      });
    } else {
      _isDraggingLyrics = false;
      _dragDistancePixels = 0.0;
      _dragTravelPixels = 0.0;
      _dragStartLine = initialLine;
      _dragCurrentLine = initialLine;
    }
  }

  void _updateLyricsDrag(
    DragUpdateDetails details,
    List<LyricLine> displayLines,
  ) {
    if (displayLines.isEmpty || !_hasTimedLyrics(displayLines)) {
      return;
    }

    final startLine = _dragStartLine;
    if (startLine == null) return;

    final delta = details.primaryDelta ?? 0.0;
    if (delta == 0.0) return;

    _dragDistancePixels += delta;
    _dragTravelPixels += delta.abs();

    if (!_isDraggingLyrics) {
      if (_dragTravelPixels < _lyricsDragSeekThreshold) {
        return;
      }

      if (mounted) {
        setState(() {
          _isDraggingLyrics = true;
        });
      } else {
        _isDraggingLyrics = true;
      }

      _dismissSeekToast();
    }

    if (startLine < _cachedCenters.length) {
      final startCenter = _cachedCenters[startLine];
      final targetCenter = startCenter - _dragDistancePixels;
      final targetIndex = _findClosestLineIndex(targetCenter, _cachedCenters)
          .clamp(0, displayLines.length - 1)
          .toInt();

      if (_dragCurrentLine != targetIndex) {
        if (mounted) {
          setState(() {
            _dragCurrentLine = targetIndex;
          });
        } else {
          _dragCurrentLine = targetIndex;
        }
      }

      _scrollToLineIndex(targetIndex, animate: false);
      _syncSeekToast(
        _audioSeekPositionForLyricTimestamp(displayLines[targetIndex].timestamp),
      );
    }
  }

  void _endLyricsDrag(List<LyricLine> displayLines) {
    final wasDraggingLyrics = _isDraggingLyrics;
    final targetLine = _dragCurrentLine;
    if (mounted) {
      setState(() {
        _isDraggingLyrics = false;
        _dragDistancePixels = 0.0;
        _dragTravelPixels = 0.0;
        _dragStartLine = null;
        _dragCurrentLine = null;
      });
    } else {
      _isDraggingLyrics = false;
      _dragDistancePixels = 0.0;
      _dragTravelPixels = 0.0;
      _dragStartLine = null;
      _dragCurrentLine = null;
    }

    if (targetLine == null || !_hasTimedLyrics(displayLines)) {
      _dismissSeekToast();
      return;
    }

    if (!wasDraggingLyrics) {
      _dismissSeekToast();
      return;
    }

    // 用户抬手后先立刻收掉进度提示，再异步执行 seek，避免 toast
    // 因为播放器跳转或后续重建而滞留在屏幕上。
    _dismissSeekToast();

    if (targetLine >= 0 && targetLine < displayLines.length) {
      final targetPosition = _audioSeekPositionForLyricTimestamp(
        displayLines[targetLine].timestamp,
      );
      unawaited(ref.read(audioServiceProvider).seek(targetPosition));
      _syncSeekToast(targetPosition);
    }
  }

  void _scrollToLineIndex(
    int index, {
    required bool animate,
  }) {
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= _cachedCenters.length) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final bottomSpacers = widget.bottomSpacerHeight + widget.bottomTabBarHeight;
    // 计算可见区域的中心（避开底部遮挡/渐变区）
    final visibleCenter = (viewportHeight - bottomSpacers) / 2;

    final targetCenter = _cachedCenters[index];
    final target = math.max(
      0.0,
      math.min(targetCenter - visibleCenter, maxExtent),
    );

    if (animate) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  int _activeLineIndex(List<LyricLine> displayLines) {
    if (displayLines.isEmpty || !_hasTimedLyrics(displayLines)) return -1;

    final current = _adjustedPositionMilliseconds;
    int low = 0;
    int high = displayLines.length - 1;
    int answer = 0;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final midMs = displayLines[mid].timestamp.inMilliseconds;
      if (midMs <= current) {
        answer = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return answer;
  }

  bool _hasTimedLyrics(List<LyricLine> displayLines) {
    return displayLines.any((line) => line.isTimed);
  }

  int get _adjustedPositionMilliseconds {
    return widget.position.inMilliseconds - _timelineOffsetMilliseconds;
  }

  int get _timelineOffsetMilliseconds {
    return (_timelineOffsetSeconds * 1000).round();
  }

  double _timelineOffsetToSeconds(Duration? offset) {
    final seconds = (offset?.inMilliseconds ?? 0) / 1000.0;
    return _normalizeTimelineOffsetSeconds(seconds);
  }

  double _normalizeTimelineOffsetSeconds(double value) {
    final clamped = value.clamp(
      _timelineOffsetMinSeconds,
      _timelineOffsetMaxSeconds,
    );
    return (clamped * 10).roundToDouble() / 10.0;
  }

  Future<void> _showTimelineAdjustmentPanel(
    List<LyricLine> displayLines,
  ) async {
    if (!_hasTimedLyrics(displayLines)) return;

    Future<void> commitOffset(double value) async {
      final normalized = _normalizeTimelineOffsetSeconds(value);
      if (!mounted) return;
      if (_timelineOffsetSeconds != normalized) {
        setState(() {
          _timelineOffsetSeconds = normalized;
        });
      }
      await _lyricsControllerActions.updateLyricsTimelineOffsetForCurrentSong(
        Duration(milliseconds: (normalized * 1000).round()),
      );
    }

    await showTimelineAdjustmentDialog(
      context,
      initialTimelineOffsetSeconds: _timelineOffsetSeconds,
      onPreviewChanged: (timelineOffsetSeconds) {
        if (!mounted) return;
        if (_timelineOffsetSeconds == timelineOffsetSeconds) {
          return;
        }
        setState(() {
          _timelineOffsetSeconds = timelineOffsetSeconds;
        });
      },
      onCommit: (timelineOffset) async {
        await commitOffset(timelineOffset.inMilliseconds / 1000.0);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lyricsState = ref.watch(lyricsControllerProvider);
    final currentSongTaskState = ref.watch(lyricsCurrentSongTaskStateProvider);
    final lyricsFontScale = ref.watch(
      settingsServiceProvider.select((settings) => settings.lyricsFontScale),
    );
    final lyricsForDisplay = _lyricsForDisplay();
    final displayLines = ref.watch(
      lyricsDisplayLinesProvider(lyricsForDisplay),
    );
    final displayPlainLyrics = ref.watch(
      lyricsDisplayPlainTextProvider(lyricsForDisplay),
    );
    final displayLyrics = ref.watch(
      lyricsDisplayLyricsProvider(lyricsForDisplay),
    );
    final hasRenderableLyrics = ref.watch(
      lyricsHasRenderableContentProvider(lyricsForDisplay),
    );
    final hasCurrentSong = ref.watch(audioCurrentMusicProvider) != null;
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final lyrics = displayLyrics;
    final hasTimedLyrics = _hasTimedLyrics(displayLines);

    if (!hasRenderableLyrics) {
      final canGenerateLyrics = shouldShowGenerateLyricsButton(
        hasCurrentSong: hasCurrentSong,
      );
      return LyricsPanelEmptyState(
        accentColor: accent,
        isLoading: lyricsState.isLyricsLoading,
        isGenerating: currentSongTaskState.isGenerationBusy,
        canGenerateLyrics: canGenerateLyrics,
        generateButtonLabel: _buildGenerateButtonLabel(
          l10n,
          currentSongTaskState,
        ),
        bottomSpacerHeight: widget.bottomSpacerHeight,
        bottomTabBarHeight: widget.bottomTabBarHeight,
        onGeneratePressed: () async {
          if (await _ensureLyricsApiKey()) {
            if (!mounted) return;
            final errorMessage = await _lyricsControllerActions
                .generateLyricsForCurrentSong();
            if (errorMessage != null) {
              _showGenerationErrorSnack(errorMessage);
            }
          }
        },
        onContextMenu: (position) {
          _showContextMenu(
            context,
            position,
            lyricsState: lyricsState,
            taskState: currentSongTaskState,
            displayLines: displayLines,
            displayPlainLyrics: displayPlainLyrics,
            hasCurrentSong: hasCurrentSong,
            lyricsFontScale: lyricsFontScale,
            requeryOnly: true,
          );
        },
      );
    }

    final renderedLines = hasTimedLyrics
        ? displayLines
        : _plainLyricsLines(displayPlainLyrics);

    return LayoutBuilder(
      builder: (context, constraints) {
        _calculateHeights(
          lines: renderedLines,
          lyrics: lyrics,
          maxWidth: constraints.maxWidth,
          lyricsFontScale: lyricsFontScale,
          hasTimedLyrics: hasTimedLyrics,
          context: context,
        );

        if (hasTimedLyrics) {
          _scheduleScrollIfNeeded(
            displayLines: displayLines,
          );
        }
        final activeIndex = hasTimedLyrics ? _activeLineIndex(displayLines) : -1;
        final focusedIndex = _isDraggingLyrics && _dragCurrentLine != null
            ? _dragCurrentLine!
            : activeIndex;
        _logLyricsDebug(
          displayLines: displayLines,
          activeIndex: focusedIndex,
          hasTimedLyrics: hasTimedLyrics,
        );

        return LyricsPanelTimedLyricsView(
          lyrics: lyrics,
          lyricsState: lyricsState,
          displayLines: renderedLines,
          hasTimedLyrics: hasTimedLyrics,
          activeIndex: focusedIndex,
          isAutoScrollPaused: _isAutoScrollPaused,
          lyricsFontScale: lyricsFontScale,
          scrollController: _scrollController,
          scrollBehavior: _lyricsScrollBehavior(context),
          onVerticalDragStart: hasTimedLyrics
              ? (_) => _beginLyricsDrag(displayLines)
              : null,
          onVerticalDragUpdate: hasTimedLyrics
              ? (details) =>
                    _updateLyricsDrag(details, displayLines)
              : null,
          onVerticalDragEnd: hasTimedLyrics
              ? (_) => _endLyricsDrag(displayLines)
              : null,
          onVerticalDragCancel: hasTimedLyrics
              ? () => _endLyricsDrag(displayLines)
              : null,
          onContextMenu: (position) {
            _showContextMenu(
              context,
              position,
              lyricsState: lyricsState,
              taskState: currentSongTaskState,
              displayLines: displayLines,
              displayPlainLyrics: displayPlainLyrics,
              hasCurrentSong: hasCurrentSong,
              lyricsFontScale: lyricsFontScale,
            );
          },
          bottomSpacerHeight: widget.bottomSpacerHeight,
          bottomTabBarHeight: widget.bottomTabBarHeight,
        );
      },
    );
  }

  void _logLyricsDebug({
    required List<LyricLine> displayLines,
    required int activeIndex,
    required bool hasTimedLyrics,
  }) {
    if (!kDebugMode) return;

    final adjustedMs = _adjustedPositionMilliseconds;
    final now = DateTime.now();
    final activeChanged = activeIndex != _lastDebugActiveIndex;
    final positionChanged = (adjustedMs - _lastDebugPositionMs).abs() >= 250;
    final timeElapsed = now.difference(_lastDebugLogAt);
    if (!activeChanged &&
        !positionChanged &&
        timeElapsed < const Duration(seconds: 1)) {
      return;
    }

    _lastDebugActiveIndex = activeIndex;
    _lastDebugPositionMs = adjustedMs;
    _lastDebugLogAt = now;

    // final activeTimestamp =
    //     (hasTimedLyrics &&
    //         activeIndex >= 0 &&
    //         activeIndex < displayLines.length)
    //     ? displayLines[activeIndex].timestamp.inMilliseconds
    //     : -1;
    // final offsetMs = _timelineOffsetMilliseconds;
    // final deltaMs = activeTimestamp >= 0 ? adjustedMs - activeTimestamp : 0;

    // debugPrint(
    //   '[LyricsPanel] pos=${_formatMs(adjustedMs)}ms '
    //   'raw=${_formatMs(widget.position.inMilliseconds)}ms '
    //   'offset=${_formatMs(offsetMs)}ms '
    //   'activeIndex=$activeIndex '
    //   'activeTs=${_formatMs(activeTimestamp)}ms '
    //   'delta=${_formatSignedMs(deltaMs)}ms '
    //   'lines=${displayLines.length}',
    // );
  }

  // String _formatMs(int value) {
  //   return value.toString();
  // }
  //
  // String _formatSignedMs(int value) {
  //   if (value >= 0) return value.toString();
  //   return '-${value.abs()}';
  // }
}
