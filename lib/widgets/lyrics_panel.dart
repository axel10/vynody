import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rpod;
import 'package:oktoast/oktoast.dart';

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../dialogs/manual_lyrics_dialog.dart';
import '../dialogs/timeline_adjustment_dialog.dart';
import '../player/audio_riverpod.dart';
import '../player/lyrics_controller.dart';
import '../player/lyrics_controller_state.dart';
import '../player/lyrics_generation_phase.dart';
import '../player/lyrics_riverpod.dart';
import 'lyrics_panel_toasts.dart';
import 'lyrics_panel_views.dart';

class LyricsPanel extends rpod.ConsumerStatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.position,
    this.accentColor,
  });

  final MusicLyric? lyrics;
  final Duration position;
  final Color? accentColor;

  @override
  rpod.ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends rpod.ConsumerState<LyricsPanel> {
  static const double _itemExtent = 72.0;
  static const double _lyricsListVerticalPadding = 16.0;
  static const double _timelineOffsetMinSeconds = -10.0;
  static const double _timelineOffsetMaxSeconds = 10.0;
  static const double _lyricsSeekActivationThreshold = 12.0;
  static const double _statusToastTopOffset = 30.0;
  static const double _seekToastTopOffset = 88.0;
  static const Duration _statusToastAnimationDuration = Duration(
    milliseconds: 180,
  );
  static const Duration _seekToastAnimationDuration = Duration(
    milliseconds: 160,
  );
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  bool _isAutoScrollPaused = false;
  bool _isUserScrubbingLyrics = false;
  double _timelineOffsetSeconds = 0.0;
  double? _scrubStartPixels;
  int? _seekPreviewIndex;
  rpod.ProviderSubscription<LyricsControllerState>? _lyricsStateSubscription;
  ToastFuture? _statusToast;
  String? _statusToastSignature;
  ToastFuture? _seekToast;
  String? _seekToastSignature;

  LyricsController get _lyricsControllerActions =>
      ref.read(lyricsControllerProvider.notifier);

  List<LyricLine> _displayLinesForCurrentLyrics() {
    return ref.read(lyricsDisplayLinesProvider(widget.lyrics));
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
    _lyricsStateSubscription = ref.listenManual(lyricsControllerProvider, (
      previous,
      next,
    ) {
      _syncStatusToast(next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncStatusToast(ref.read(lyricsControllerProvider));
      _scheduleScrollIfNeeded(force: true);
    });
  }

  @override
  void dispose() {
    _lyricsStateSubscription?.close();
    _dismissStatusToast();
    _scrollController.dispose();
    super.dispose();
  }

  void _dismissStatusToast({bool showAnim = false}) {
    _statusToast?.dismiss(showAnim: showAnim);
    _statusToast = null;
    _statusToastSignature = null;
  }

  void _dismissSeekToast({bool showAnim = false}) {
    _seekToast?.dismiss(showAnim: showAnim);
    _seekToast = null;
    _seekToastSignature = null;
  }

  void _syncStatusToast(LyricsControllerState lyricsState) {
    final payload = _buildStatusToastPayload(lyricsState);
    if (payload == null) {
      if (_statusToast != null || _statusToastSignature != null) {
        _dismissStatusToast();
      }
      return;
    }

    if (_statusToastSignature == payload.signature &&
        _statusToast?.mounted == true) {
      return;
    }

    _dismissStatusToast();
    _statusToastSignature = payload.signature;
    _statusToast = showToastWidget(
      LyricsStatusToast(
        modelLabel: payload.modelLabel,
        statusLabel: payload.statusLabel,
        accentColor:
            widget.accentColor ?? Theme.of(context).colorScheme.primary,
      ),
      context: context,
      duration: Duration.zero,
      position: ToastPosition.top.copyWith(
        align: Alignment.topCenter,
        offset: _statusToastTopOffset,
      ),
      dismissOtherToast: false,
      handleTouch: false,
      animationDuration: _statusToastAnimationDuration,
      animationCurve: Curves.easeOutCubic,
    );
  }

  _LyricsStatusToastPayload? _buildStatusToastPayload(
    LyricsControllerState lyricsState,
  ) {
    if (!lyricsState.isLyricsGenerating && !lyricsState.isLyricsTranslating) {
      return null;
    }

    if (lyricsState.isLyricsTranslating) {
      final status = lyricsState.lyricsTranslationStatus.trim().isNotEmpty
          ? lyricsState.lyricsTranslationStatus.trim()
          : '正在翻译歌词';
      const modelLabel = 'Gemma 4 31B IT';
      return _LyricsStatusToastPayload(
        signature: 'translate|$modelLabel|$status',
        modelLabel: modelLabel,
        statusLabel: status,
      );
    }

    final modelLabel = ref.read(lyricsAiServiceProvider).activeModelLabel;
    final taskLabel = lyricsState.lyricsGenerationStatus.trim().isNotEmpty
        ? lyricsState.lyricsGenerationStatus.trim()
        : '正在生成歌词';
    final phaseLabel = switch (lyricsState.lyricsGenerationPhase) {
      LyricsGenerationPhase.uploading => '上传中',
      LyricsGenerationPhase.processing => '处理中',
      LyricsGenerationPhase.generating => '生成中',
      LyricsGenerationPhase.idle => '',
    };
    final statusLabel = phaseLabel.isEmpty
        ? taskLabel
        : '$taskLabel · $phaseLabel';
    return _LyricsStatusToastPayload(
      signature: 'generate|$modelLabel|$statusLabel',
      modelLabel: modelLabel,
      statusLabel: statusLabel,
    );
  }

  void _syncSeekToast(Duration target) {
    final signature = target.inMilliseconds.toString();
    if (_seekToastSignature == signature && _seekToast?.mounted == true) {
      return;
    }

    _dismissSeekToast();
    _seekToastSignature = signature;
    _seekToast = showToastWidget(
      LyricsSeekToast(
        target: target,
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

  String _lyricsSourceLabel() {
    final source = widget.lyrics?.source.trim().toLowerCase() ?? '';
    if (source.startsWith('openrouter')) {
      return 'OpenRouter';
    }
    if (source.startsWith('ai') ||
        source.startsWith('google') ||
        source.startsWith('gemini')) {
      return 'AI';
    }
    return 'AI';
  }

  String _buildGenerateMenuLabel() {
    final sourceLabel = _lyricsSourceLabel();
    if (sourceLabel != 'AI') {
      return '重新生成歌词（来源$sourceLabel）';
    }
    return '使用AI生成歌词（来源是lrclib）';
  }

  String _buildGenerateTimelineMenuLabel() {
    final sourceLabel = _lyricsSourceLabel();
    if (sourceLabel != 'AI') {
      return '重新生成时间轴（来源$sourceLabel）';
    }
    return '使用AI生成时间轴';
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
    required List<LyricLine> displayLines,
    required String displayPlainLyrics,
    required bool hasCurrentSong,
    bool requeryOnly = false,
  }) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final items = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        value: 'fill_lyrics',
        enabled: hasCurrentSong,
        child: const Text('填写歌词'),
      ),
      if (lyricsState.hasLyrics)
        PopupMenuItem<String>(
          value: 'generate',
          enabled: hasCurrentSong && !lyricsState.isLyricsGenerating,
          child: Text(_buildGenerateMenuLabel()),
        ),
      if (lyricsState.hasLyrics)
        PopupMenuItem<String>(
          value: 'generate_timeline',
          enabled: hasCurrentSong && !lyricsState.isLyricsGenerating,
          child: Text(_buildGenerateTimelineMenuLabel()),
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
          child: Text('手动调整时间轴'),
        ),
      if (!requeryOnly && _hasTimedLyrics(displayLines))
        PopupMenuItem<String>(
          value: 'toggle_auto_scroll',
          enabled: hasCurrentSong,
          child: Text(_isAutoScrollPaused ? '恢复自动滚动' : '暂停自动滚动'),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'translate',
          enabled: hasCurrentSong && !lyricsState.isLyricsTranslating,
          child: const Text('翻译歌词'),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'clear_lyrics_cache',
          enabled: hasCurrentSong && lyricsState.hasLyrics,
          child: const Text('清除当前歌词缓存'),
        ),
      if (!requeryOnly)
        PopupMenuItem<String>(
          value: 'clear_translation_cache',
          enabled: hasCurrentSong && lyricsState.hasLyrics,
          child: const Text('清除当前翻译缓存'),
        ),
      if (requeryOnly)
        PopupMenuItem<String>(
          value: 'requery',
          enabled:
              hasCurrentSong &&
              !lyricsState.isLyricsLoading &&
              !lyricsState.isLyricsGenerating,
          child: const Text('重新查询'),
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
        _clearLyricsScrubPreview();
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
        await _lyricsControllerActions.translateLyricsForCurrentSong();
      }
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

  String _buildGenerateButtonLabel(LyricsControllerState lyricsState) {
    final progress = lyricsState.lyricsGenerationProgress.clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    switch (lyricsState.lyricsGenerationPhase) {
      case LyricsGenerationPhase.uploading:
        return '上传中 $percent%';
      case LyricsGenerationPhase.processing:
        return '处理中...';
      case LyricsGenerationPhase.generating:
        return '生成中...';
      case LyricsGenerationPhase.idle:
        break;
    }

    return lyricsState.isLyricsGenerating ? '生成中...' : '生成歌词';
  }

  void _scheduleScrollIfNeeded({
    bool force = false,
    List<LyricLine>? displayLines,
  }) {
    final lines = displayLines ?? _displayLinesForCurrentLyrics();
    if (lines.isEmpty ||
        !_hasTimedLyrics(lines) ||
        _isAutoScrollPaused ||
        _isUserScrubbingLyrics) {
      return;
    }

    final activeIndex = _activeLineIndex(lines);
    if (!force && activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewportHeight = _scrollController.position.viewportDimension;
      final edgePadding = _lyricsListEdgePadding(viewportHeight);
      final maxExtent = _scrollController.position.maxScrollExtent;
      final target = math.max(
        0.0,
        math.min(
          edgePadding +
              activeIndex * _itemExtent -
              viewportHeight / 2 +
              _itemExtent / 2,
          maxExtent,
        ),
      );
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _beginLyricsScrub(ScrollMetrics metrics) {
    _scrubStartPixels = metrics.pixels;
    _seekPreviewIndex = null;
    _dismissSeekToast();
  }

  void _clearLyricsScrubPreview({bool dismissToast = true}) {
    _scrubStartPixels = null;

    if (_isUserScrubbingLyrics) {
      if (mounted) {
        setState(() {
          _isUserScrubbingLyrics = false;
        });
      } else {
        _isUserScrubbingLyrics = false;
      }
    }

    if (_seekPreviewIndex != null) {
      if (mounted) {
        setState(() {
          _seekPreviewIndex = null;
        });
      } else {
        _seekPreviewIndex = null;
      }
    }

    if (dismissToast) {
      _dismissSeekToast();
    }
  }

  void _updateLyricsScrubPreview(
    ScrollMetrics metrics,
    List<LyricLine> displayLines,
  ) {
    if (_isAutoScrollPaused) return;

    final startPixels = _scrubStartPixels;
    if (startPixels == null) return;

    final draggedDistance = (metrics.pixels - startPixels).abs();
    if (draggedDistance < _lyricsSeekActivationThreshold) {
      return;
    }

    final targetIndex = _seekLineIndexForScrollMetrics(metrics, displayLines);
    if (targetIndex == null) return;

    final target = displayLines[targetIndex].timestamp;
    if (!_isUserScrubbingLyrics) {
      if (mounted) {
        setState(() {
          _isUserScrubbingLyrics = true;
        });
      } else {
        _isUserScrubbingLyrics = true;
      }
    }

    if (_seekPreviewIndex != targetIndex) {
      if (mounted) {
        setState(() {
          _seekPreviewIndex = targetIndex;
        });
      } else {
        _seekPreviewIndex = targetIndex;
      }
    }

    _syncSeekToast(target);
  }

  bool _handleLyricsScrollNotification(
    ScrollNotification notification,
    List<LyricLine> displayLines,
  ) {
    if (!_hasTimedLyrics(displayLines)) return false;

    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      if (_isAutoScrollPaused) {
        return false;
      }
      _beginLyricsScrub(notification.metrics);
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _updateLyricsScrubPreview(notification.metrics, displayLines);
      return false;
    }

    if (notification is ScrollEndNotification) {
      if (_isUserScrubbingLyrics && !_isAutoScrollPaused) {
        final target = _seekPositionForScrollMetrics(
          notification.metrics,
          displayLines,
        );
        _clearLyricsScrubPreview();
        if (target != null) {
          unawaited(ref.read(audioServiceProvider).seek(target));
        }
        return false;
      }

      _clearLyricsScrubPreview();
      return false;
    }

    return false;
  }

  Duration? _seekPositionForScrollMetrics(
    ScrollMetrics metrics,
    List<LyricLine> displayLines,
  ) {
    final centeredIndex = _seekLineIndexForScrollMetrics(metrics, displayLines);
    if (centeredIndex == null) return null;

    return displayLines[centeredIndex].timestamp;
  }

  int? _seekLineIndexForScrollMetrics(
    ScrollMetrics metrics,
    List<LyricLine> displayLines,
  ) {
    if (displayLines.isEmpty || !_hasTimedLyrics(displayLines)) return null;

    final edgePadding = _lyricsListEdgePadding(metrics.viewportDimension);
    final centeredOffset =
        metrics.pixels +
        metrics.viewportDimension / 2 -
        edgePadding -
        _itemExtent / 2;
    return ((centeredOffset / _itemExtent).round()).clamp(
      0,
      displayLines.length - 1,
    );
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

  double _lyricsListEdgePadding(double viewportHeight) {
    if (!viewportHeight.isFinite || viewportHeight <= 0) {
      return _lyricsListVerticalPadding;
    }

    return math.max(
      _lyricsListVerticalPadding,
      viewportHeight / 2 - _itemExtent / 2,
    );
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
    final lyricsState = ref.watch(lyricsControllerProvider);
    final displayLines = ref.watch(lyricsDisplayLinesProvider(widget.lyrics));
    final displayPlainLyrics = ref.watch(
      lyricsDisplayPlainTextProvider(widget.lyrics),
    );
    final displayLyrics = ref.watch(lyricsDisplayLyricsProvider(widget.lyrics));
    final hasRenderableLyrics = ref.watch(
      lyricsHasRenderableContentProvider(widget.lyrics),
    );
    final hasCurrentSong = ref.watch(audioCurrentMusicProvider) != null;
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final lyrics = displayLyrics;
    final hasTimedLyrics = _hasTimedLyrics(displayLines);

    if (!hasRenderableLyrics) {
      final canGenerateLyrics =
          lyricsState.isLyricsLoading ||
          lyricsState.lyricsSearchAttempted ||
          lyricsState.isLyricsGenerating;
      return LyricsPanelEmptyState(
        accentColor: accent,
        isLoading: lyricsState.isLyricsLoading,
        isGenerating: lyricsState.isLyricsGenerating,
        canGenerateLyrics: canGenerateLyrics,
        generateButtonLabel: _buildGenerateButtonLabel(lyricsState),
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
        onSecondaryTapDown: (details) {
          _showContextMenu(
            context,
            details.globalPosition,
            lyricsState: lyricsState,
            displayLines: displayLines,
            displayPlainLyrics: displayPlainLyrics,
            hasCurrentSong: hasCurrentSong,
            requeryOnly: true,
          );
        },
      );
    }

    if (displayLines.isEmpty) {
      return LyricsPanelPlainLyricsView(
        displayPlainLyrics: displayPlainLyrics,
        onSecondaryTapDown: (details) {
          _showContextMenu(
            context,
            details.globalPosition,
            lyricsState: lyricsState,
            displayLines: displayLines,
            displayPlainLyrics: displayPlainLyrics,
            hasCurrentSong: hasCurrentSong,
          );
        },
      );
    }

    _scheduleScrollIfNeeded(displayLines: displayLines);
    final activeIndex = _activeLineIndex(displayLines);
    final seekPreviewIndex = _seekPreviewIndex;

    return LyricsPanelTimedLyricsView(
      accentColor: accent,
      lyrics: lyrics,
      lyricsState: lyricsState,
      displayLines: displayLines,
      hasTimedLyrics: hasTimedLyrics,
      activeIndex: activeIndex,
      seekPreviewIndex: seekPreviewIndex,
      scrollController: _scrollController,
      itemExtent: _itemExtent,
      scrollBehavior: _lyricsScrollBehavior(context),
      onSecondaryTapDown: (details) {
        _showContextMenu(
          context,
          details.globalPosition,
          lyricsState: lyricsState,
          displayLines: displayLines,
          displayPlainLyrics: displayPlainLyrics,
          hasCurrentSong: hasCurrentSong,
        );
      },
      onScrollNotification: (notification) =>
          _handleLyricsScrollNotification(notification, displayLines),
    );
  }
}

class _LyricsStatusToastPayload {
  const _LyricsStatusToastPayload({
    required this.signature,
    required this.modelLabel,
    required this.statusLabel,
  });

  final String signature;
  final String modelLabel;
  final String statusLabel;
}
