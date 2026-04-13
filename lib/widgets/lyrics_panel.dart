import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as rpod;

import '../models/lyric_line.dart';
import '../models/music_lyric.dart';
import '../dialogs/gemini_api_key_dialog.dart';
import '../player/audio_riverpod.dart';
import '../player/lyrics_controller.dart';
import '../player/lyrics_controller_state.dart';
import '../player/lyrics_generation_phase.dart';
import '../player/lyrics_riverpod.dart';

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
  static const double _timelineOffsetMinSeconds = -10.0;
  static const double _timelineOffsetMaxSeconds = 10.0;
  static const double _timelineOffsetStepSeconds = 0.1;
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  bool _isAutoScrollPaused = false;
  double _timelineOffsetSeconds = 0.0;

  LyricsController get _lyricsControllerActions =>
      ref.read(lyricsControllerProvider.notifier);

  List<LyricLine> _displayLinesForCurrentLyrics() {
    return ref.read(lyricsDisplayLinesProvider(widget.lyrics));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildActivityIndicator(
    Color accent,
    LyricsControllerState lyricsState,
  ) {
    final status = lyricsState.isLyricsTranslating
        ? lyricsState.lyricsTranslationStatus.trim()
        : (lyricsState.isLyricsGenerating
              ? lyricsState.lyricsGenerationStatus.trim()
              : '');
    if (status.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 12,
      right: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
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

  String _buildGenerateMenuLabel() {
    final source = widget.lyrics?.source.trim().toLowerCase() ?? '';
    if (source.startsWith('gemini')) {
      return '重新生成歌词（来源gemini）';
    }
    return '使用AI生成歌词（来源是lrclib）';
  }

  String _buildGenerateTimelineMenuLabel() {
    final source = widget.lyrics?.source.trim().toLowerCase() ?? '';
    if (source.startsWith('gemini')) {
      return '重新生成时间轴（来源gemini）';
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

  @override
  void initState() {
    super.initState();
    _timelineOffsetSeconds = _timelineOffsetToSeconds(
      widget.lyrics?.timelineOffset,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleScrollIfNeeded(force: true);
    });
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
      }
    } else if (selected == 'generate') {
      if (await _ensureGeminiApiKey()) {
        if (!mounted) return;
        final errorMessage = await _lyricsControllerActions
            .regenerateLyricsForCurrentSong();
        if (errorMessage != null) {
          _showGenerationErrorSnack(errorMessage);
        }
      }
    } else if (selected == 'generate_timeline') {
      if (await _ensureGeminiApiKey()) {
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
    final controller = TextEditingController(text: initialLyrics);
    final submittedLyrics = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        var currentValue = initialLyrics;

        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final canSave = currentValue.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('填写歌词'),
              content: SizedBox(
                width: 520,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  maxLines: 14,
                  minLines: 8,
                  decoration: const InputDecoration(
                    hintText: '在这里粘贴或输入歌词，支持多行文本',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      currentValue = value;
                    });
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: canSave
                      ? () =>
                            Navigator.of(dialogContext).pop(currentValue.trim())
                      : null,
                  child: const Text('确认'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();

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
    if (lines.isEmpty || !_hasTimedLyrics(lines) || _isAutoScrollPaused) {
      return;
    }

    final activeIndex = _activeLineIndex(lines);
    if (!force && activeIndex == _lastActiveIndex) return;
    _lastActiveIndex = activeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final viewportHeight = _scrollController.position.viewportDimension;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final target = math.max(
        0.0,
        math.min(
          activeIndex * _itemExtent - viewportHeight / 2 + _itemExtent / 2,
          maxExtent,
        ),
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
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

  String _timelineOffsetLabel(double seconds) {
    final normalized = _normalizeTimelineOffsetSeconds(seconds);
    if (normalized == 0) {
      return '当前偏移：0.0 秒';
    }

    final direction = normalized > 0 ? '延后' : '提前';
    return '当前偏移：$direction ${normalized.abs().toStringAsFixed(1)} 秒';
  }

  Future<void> _showTimelineAdjustmentPanel(
    List<LyricLine> displayLines,
  ) async {
    if (!_hasTimedLyrics(displayLines)) return;

    final theme = Theme.of(context);
    final initialValue = _normalizeTimelineOffsetSeconds(
      _timelineOffsetSeconds,
    );
    var dialogValue = initialValue;
    StateSetter? dialogSetState;

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

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('手动调整时间轴'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              dialogSetState = setDialogState;
              final label = _timelineOffsetLabel(dialogValue);
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '向右拖动会让歌词整体延后，向左拖动会让歌词整体提前。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: dialogValue,
                      min: _timelineOffsetMinSeconds,
                      max: _timelineOffsetMaxSeconds,
                      divisions:
                          ((_timelineOffsetMaxSeconds -
                                      _timelineOffsetMinSeconds) /
                                  _timelineOffsetStepSeconds)
                              .round(),
                      label: label,
                      onChanged: (value) {
                        final snapped = _normalizeTimelineOffsetSeconds(value);
                        setDialogState(() {
                          dialogValue = snapped;
                        });
                        setState(() {
                          _timelineOffsetSeconds = snapped;
                        });
                      },
                      onChangeEnd: (value) {
                        unawaited(commitOffset(value));
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '提前 30.0 秒',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '延后 30.0 秒',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: dialogValue == 0
                  ? null
                  : () {
                      final snapped = _normalizeTimelineOffsetSeconds(0);
                      dialogSetState?.call(() {
                        dialogValue = snapped;
                      });
                      setState(() {
                        _timelineOffsetSeconds = snapped;
                      });
                      unawaited(commitOffset(snapped));
                    },
              child: const Text('重置'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
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
      // 正在查找、已经尝试过联网找歌词，或者当前正在 AI 生成中时，都显示按钮。
      // 这样在查找中也能切到 AI 生成流程。
      final canGenerateLyrics =
          lyricsState.isLyricsLoading ||
          lyricsState.lyricsSearchAttempted ||
          lyricsState.isLyricsGenerating;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
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
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (lyricsState.isLyricsLoading &&
                        !lyricsState.isLyricsGenerating) ...[
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      lyricsState.isLyricsLoading ? '正在查找歌词' : '暂无歌词',
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
                          // 这里直接调 controller，避免再经由 AudioService 兜一层。
                          onPressed: lyricsState.isLyricsGenerating
                              ? null
                              : () async {
                                  if (await _ensureGeminiApiKey()) {
                                    if (!mounted) return;
                                    final errorMessage =
                                        await _lyricsControllerActions
                                            .generateLyricsForCurrentSong();
                                    if (errorMessage != null) {
                                      _showGenerationErrorSnack(errorMessage);
                                    }
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: accent.withValues(alpha: 0.95),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          icon: lyricsState.isLyricsGenerating
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                )
                              : const Icon(Icons.auto_awesome, size: 18),
                          label: Text(_buildGenerateButtonLabel(lyricsState)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (lyricsState.isLyricsTranslating ||
                lyricsState.isLyricsGenerating)
              _buildActivityIndicator(accent, lyricsState),
          ],
        ),
      );
    }

    if (displayLines.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
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
        child: Stack(
          children: [
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectableText(
                      displayPlainLyrics,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 18,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (lyricsState.isLyricsTranslating ||
                lyricsState.isLyricsGenerating)
              _buildActivityIndicator(accent, lyricsState),
          ],
        ),
      );
    }

    _scheduleScrollIfNeeded(displayLines: displayLines);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
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
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
              itemExtent: _itemExtent,
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
                final activeIndex = _activeLineIndex(displayLines);
                final distance = (index - activeIndex).abs();
                final isActive = hasTimedLyrics && index == activeIndex;
                final isNear = hasTimedLyrics && distance <= 1;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: isActive ? 6 : 0,
                            height: 28,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          if (isActive) const SizedBox(width: 8),
                          Expanded(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: Theme.of(context).textTheme.bodyLarge!
                                  .copyWith(
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white.withValues(
                                            alpha: isNear ? 0.72 : 0.46,
                                          ),
                                    fontSize: isActive ? 18 : 16,
                                    fontWeight: isActive
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    height: 1.2,
                                  ),
                              child: Text(
                                line.text,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (translated.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            translated,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 13,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          if (lyricsState.isLyricsTranslating || lyricsState.isLyricsGenerating)
            _buildActivityIndicator(accent, lyricsState),
        ],
      ),
    );
  }
}
