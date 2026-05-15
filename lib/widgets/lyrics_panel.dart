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
import 'lyrics_panel_toasts.dart';
import 'lyrics_panel_views.dart';

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
  static const double _itemExtent = 88.0;
  static const double _lyricsDragSeekThreshold = 24.0;
  static const double _timelineOffsetMinSeconds = -10.0;
  static const double _timelineOffsetMaxSeconds = 10.0;
  static const double _seekToastTopOffset = 88.0;
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
    _scrollController.dispose();
    super.dispose();
  }

  void _dismissSeekToast({bool showAnim = false}) {
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
        child: Text('选择在线歌词'),
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

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('正在查询在线歌词'), duration: Duration(days: 1)),
    );

    final service = ref.read(lyricsServiceProvider);
    final tracks = await service.searchTracksByTitle(title: songTitle);

    if (!mounted) return;
    messenger.hideCurrentSnackBar();

    if (tracks.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('无结果')));
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
      messenger.showSnackBar(const SnackBar(content: Text('无结果')));
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
      _scrollToLineIndex(activeIndex, animate: true);
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

    final targetIndex =
        (startLine - (_dragDistancePixels / _itemExtent).round())
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
    _syncSeekToast(displayLines[targetIndex].timestamp);
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
      unawaited(
        ref.read(audioServiceProvider).seek(displayLines[targetLine].timestamp),
      );
    }
    _scheduleScrollIfNeeded(force: true, displayLines: displayLines);
  }

  void _scrollToLineIndex(int index, {required bool animate}) {
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    if (!viewportHeight.isFinite || viewportHeight <= 0) return;

    final maxExtent = _scrollController.position.maxScrollExtent;
    final target = math.max(
      0.0,
      math.min(
        index * _itemExtent -
            viewportHeight / 2 +
            _itemExtent / 2 +
            50, // 50 is an empirical value to make the active line slightly above the center
        maxExtent,
      ),
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
      final canGenerateLyrics =
          lyricsState.isLyricsLoading ||
          lyricsState.lyricsSearchAttempted ||
          currentSongTaskState.isGenerationBusy;
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
            requeryOnly: true,
          );
        },
      );
    }

    final renderedLines = hasTimedLyrics
        ? displayLines
        : _plainLyricsLines(displayPlainLyrics);

    if (hasTimedLyrics) {
      _scheduleScrollIfNeeded(displayLines: displayLines);
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
      scrollController: _scrollController,
      itemExtent: _itemExtent,
      scrollBehavior: _lyricsScrollBehavior(context),
      onVerticalDragStart: hasTimedLyrics
          ? (_) => _beginLyricsDrag(displayLines)
          : null,
      onVerticalDragUpdate: hasTimedLyrics
          ? (details) => _updateLyricsDrag(details, displayLines)
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
        );
      },
      bottomSpacerHeight: widget.bottomSpacerHeight,
      bottomTabBarHeight: widget.bottomTabBarHeight,
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
