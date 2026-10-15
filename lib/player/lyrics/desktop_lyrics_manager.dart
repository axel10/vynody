import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_desktop_lyrics/flutter_desktop_lyrics.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/lyrics/lyrics_controller_state.dart';
import 'package:vynody/player/settings/settings_service.dart';

class DesktopLyricsManager {
  final Ref ref;

  ProviderSubscription<SettingsService>? _settingsSub;
  ProviderSubscription<bool>? _isPlayingSub;
  ProviderSubscription<MusicFile?>? _musicSub;
  ProviderSubscription<LyricsControllerState>? _lyricsSub;

  int _lastActiveLineIndex = -1;
  String? _lastSongPath;
  Duration _lastSentPosition = Duration.zero;
  DateTime _lastSentTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositionLogTime = DateTime.fromMillisecondsSinceEpoch(0);

  Duration _currentPosition = Duration.zero;

  DesktopLyricsManager(this.ref) {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    _init();
  }

  void _init() {
    final settings = ref.read(settingsServiceProvider);
    final audio = ref.read(audioServiceProvider);

    // 1. 设置从桌面歌词子窗口发回的操作监听
    DesktopLyrics.controller.setActionListener(_handleChildAction);

    // 2. 监听设置变化（开关、锁定、字号等）
    _settingsSub = ref.listen<SettingsService>(
      settingsServiceProvider,
      (previous, current) {
        _onSettingsChanged(current);
      },
    );

    // 3. 监听播放与切歌状态
    _isPlayingSub = ref.listen<bool>(
      audioIsPlayingProvider,
      (prev, next) => _syncPlaybackState(),
    );

    // 直接向 AudioService 注册原生高频播放位置监听
    // 确保无论 Navigator 覆盖多少层页面（如设置页、下载管理页），歌词时钟都不受 Widget 树生命周期影响
    audio.addPositionListener(_onPositionChanged);

    _musicSub = ref.listen<MusicFile?>(
      audioCurrentMusicProvider,
      (prev, next) => _onMusicChanged(next),
    );

    // 4. 监听歌词解析与加载完成状态，确保后台/异步拉取到歌词后立即刷新桌面歌词
    _lyricsSub = ref.listen<LyricsControllerState>(
      lyricsControllerProvider,
      (prev, next) {
        if (!DesktopLyrics.controller.isShowing) return;
        _syncCurrentLine(force: true);
      },
    );

    // 如果初始设置已经是开启桌面歌词，则直接显示
    if (settings.enableDesktopLyrics) {
      _openDesktopLyrics(settings);
    }
  }

  void _handleChildAction(DesktopLyricsAction action) {
    final audio = ref.read(audioServiceProvider);
    final settings = ref.read(settingsServiceProvider);

    switch (action.type) {
      case DesktopLyricsActionType.togglePlay:
        audio.togglePlay();
        break;
      case DesktopLyricsActionType.next:
        audio.next();
        break;
      case DesktopLyricsActionType.previous:
        audio.previous();
        break;
      case DesktopLyricsActionType.toggleLock:
        if (action.data != null && action.data!['locked'] is bool) {
          settings.desktopLyricsLocked = action.data!['locked'] as bool;
        } else {
          settings.desktopLyricsLocked = !settings.desktopLyricsLocked;
        }
        break;
      case DesktopLyricsActionType.toggleBackground:
        if (action.data != null && action.data!['showBackground'] is bool) {
          settings.desktopLyricsShowBackground = action.data!['showBackground'] as bool;
        } else {
          settings.desktopLyricsShowBackground = !settings.desktopLyricsShowBackground;
        }
        break;
      case DesktopLyricsActionType.increaseFontSize:
      case DesktopLyricsActionType.decreaseFontSize:
        if (action.data != null && action.data!['fontSize'] is num) {
          settings.desktopLyricsFontSize = (action.data!['fontSize'] as num).toDouble();
        }
        break;
      case DesktopLyricsActionType.windowMoved:
        if (action.data != null) {
          final x = (action.data!['x'] as num?)?.toDouble();
          final y = (action.data!['y'] as num?)?.toDouble();
          if (x != null && y != null) {
            settings.desktopLyricsWindowX = x;
            settings.desktopLyricsWindowY = y;
          }
        }
        break;
      case DesktopLyricsActionType.close:
        settings.enableDesktopLyrics = false;
        break;
    }
  }

  DesktopLyricsStyle _buildStyle(SettingsService settings) {
    final fontToUse = settings.lyricsFontFamily.trim();

    final defaultFallback = (Platform.isMacOS || Platform.isIOS)
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
    final fallback = fontToUse.isNotEmpty
        ? [
            ...defaultFallback.where((f) => f != fontToUse),
          ]
        : null;

    return DesktopLyricsStyle(
      fontSize: settings.desktopLyricsFontSize,
      translationFontSize: (settings.desktopLyricsFontSize * 0.68).clamp(14.0, 38.0),
      showBackground: settings.desktopLyricsShowBackground,
      fontFamily: fontToUse.isNotEmpty ? fontToUse : (Platform.isWindows ? 'Segoe UI' : null),
      fontFamilyFallback: fallback,
    );
  }

  void _onSettingsChanged(SettingsService settings) {
    if (settings.enableDesktopLyrics) {
      if (!DesktopLyrics.controller.isShowing) {
        _openDesktopLyrics(settings);
      } else {
        if (DesktopLyrics.controller.isLocked != settings.desktopLyricsLocked) {
          DesktopLyrics.controller.setLocked(settings.desktopLyricsLocked);
        }
        final newStyle = _buildStyle(settings);
        if (DesktopLyrics.controller.style != newStyle) {
          DesktopLyrics.controller.setStyle(newStyle);
        }
      }
    } else {
      if (DesktopLyrics.controller.isShowing) {
        DesktopLyrics.controller.hide();
      }
    }
  }

  Future<void> _openDesktopLyrics(SettingsService settings) async {
    final currentMusic = ref.read(audioCurrentMusicProvider);
    final isPlaying = ref.read(audioIsPlayingProvider);
    final position = _currentPosition != Duration.zero
        ? _currentPosition
        : ref.read(audioPositionProvider);

    await DesktopLyrics.controller.show(
      initialStyle: _buildStyle(settings),
      isLocked: settings.desktopLyricsLocked,
      initialX: settings.desktopLyricsWindowX,
      initialY: settings.desktopLyricsWindowY,
    );

    if (settings.desktopLyricsLocked) {
      await DesktopLyrics.controller.setLocked(true);
    }

    await DesktopLyrics.controller.updatePlaybackState(
      isPlaying: isPlaying,
      positionMs: position.inMilliseconds,
      title: currentMusic?.title ?? '',
      artist: currentMusic?.artist ?? '',
    );

    ref.read(audioServiceProvider).ensureLyricsLoadedForCurrentSong();
    _syncCurrentLine(currentPosition: position, force: true);
  }

  void _onMusicChanged(MusicFile? music) {
    if (music?.path != _lastSongPath) {
      _lastSongPath = music?.path;
      _lastActiveLineIndex = -1;
      _syncPlaybackState();
      _syncCurrentLine(force: true);
    }
  }

  void _syncPlaybackState({Duration? currentPosition}) {
    if (!DesktopLyrics.controller.isShowing) return;
    final isPlaying = ref.read(audioIsPlayingProvider);
    final Duration position = currentPosition ?? _currentPosition;
    final currentMusic = ref.read(audioCurrentMusicProvider);

    _lastSentPosition = position;
    _lastSentTime = DateTime.now();



    DesktopLyrics.controller.updatePlaybackState(
      isPlaying: isPlaying,
      positionMs: position.inMilliseconds,
      title: currentMusic?.title ?? '',
      artist: currentMusic?.artist ?? '',
    );
  }

  void _onPositionChanged(Duration position) {
    _currentPosition = position;
    final isShowing = DesktopLyrics.controller.isShowing;
    final now = DateTime.now();

    if (now.difference(_lastPositionLogTime) >= const Duration(seconds: 1)) {
      _lastPositionLogTime = now;
    }

    if (!isShowing) return;

    final isPlaying = ref.read(audioIsPlayingProvider);
    final elapsed = isPlaying ? now.difference(_lastSentTime) : Duration.zero;
    final expectedPos = _lastSentPosition + elapsed;
    // 检测是否发生跳转（Seek）：实际位置与按时间流逝推算的位置偏差大于 500ms
    final isSeek = (position - expectedPos).abs() > const Duration(milliseconds: 500);
    final needPeriodicSync = now.difference(_lastSentTime) > const Duration(seconds: 2);

    if (isSeek || needPeriodicSync) {
      _syncPlaybackState(currentPosition: position);
    }

    _syncCurrentLine(currentPosition: position, force: isSeek);
  }

  void _syncCurrentLine({Duration? currentPosition, bool force = false}) {
    final currentMusic = ref.read(audioCurrentMusicProvider);
    final lyricsState = ref.read(lyricsControllerProvider);
    final lyricsController = ref.read(lyricsControllerProvider.notifier);
    final settings = ref.read(settingsServiceProvider);

    final MusicLyric? baseLyrics = lyricsController.currentLyricsForCurrentSong() ?? currentMusic?.lyrics;
    final lines = lyricsState.currentLyricsLines.isNotEmpty
        ? lyricsState.currentLyricsLines
        : (baseLyrics?.syncedLines ?? const []);

    if (lines.isEmpty) {
      final placeholderTitle = currentMusic?.title ?? '';
      final isAlreadyPlaceholder = _lastActiveLineIndex == -1 &&
          DesktopLyrics.controller.currentLine?.text == placeholderTitle;
      if (!isAlreadyPlaceholder) {
        _lastActiveLineIndex = -1;
        DesktopLyrics.controller.updateLyricLine(
          currentMusic != null
              ? DesktopLyricLine(timestampMs: 0, text: placeholderTitle)
              : null,
        );
      }
      if (currentMusic != null && !lyricsState.hasLyrics && !lyricsState.isLyricsLoading) {
        ref.read(audioServiceProvider).ensureLyricsLoadedForCurrentSong();
      }
      return;
    }

    final position = currentPosition ?? _currentPosition;
    final timelineOffsetMs = baseLyrics?.timelineOffset.inMilliseconds ?? 0;
    final currentMs = position.inMilliseconds - timelineOffsetMs;

    // 二分查找当前激活行
    int activeIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (currentMs >= lines[i].timestamp.inMilliseconds) {
        activeIndex = i;
      } else {
        break;
      }
    }

    if (activeIndex == -1 && lines.isNotEmpty) {
      activeIndex = 0;
    }

    if (activeIndex != _lastActiveLineIndex || force) {
      // AppLog.log(
      //   '[DesktopLyrics] _syncCurrentLine: activeIndex=$activeIndex (prev=$_lastActiveLineIndex) '
      //   'force=$force text="${activeIndex >= 0 && activeIndex < lines.length ? lines[activeIndex].text : ''}"',
      //   mirrorToConsole: true,
      // );
      _lastActiveLineIndex = activeIndex;
      if (activeIndex >= 0 && activeIndex < lines.length) {
        final lyricLine = lines[activeIndex];

        // 获取翻译行（原文一行，翻译一行）
        String? translation;
        if (settings.desktopLyricsShowTranslation && baseLyrics != null) {
          final targetLang = lyricsState.lyricsTranslationLanguageCode;
          final effectiveLang = baseLyrics.getEffectiveTranslationLanguage(targetLang);
          if (effectiveLang.isNotEmpty) {
            final transText = baseLyrics.translatedLineAt(activeIndex, effectiveLang).trim();
            if (transText.isNotEmpty) {
              translation = transText;
            }
          }
        }

        // 转换逐字卡拉OK时间戳（若是逐字歌词）
        List<DesktopLyricWord>? desktopWords;
        if (lyricLine.words != null && lyricLine.words!.isNotEmpty) {
          desktopWords = lyricLine.words!.map((w) {
            return DesktopLyricWord(
              timestampMs: w.timestamp.inMilliseconds,
              durationMs: w.durationMs,
              text: w.text,
            );
          }).toList();
        }

        final desktopLine = DesktopLyricLine(
          timestampMs: lyricLine.timestamp.inMilliseconds,
          text: lyricLine.text,
          translation: translation,
          words: desktopWords,
        );

        // AppLog.log(
        //   '[DesktopLyrics] sending updateLyricLine -> "${desktopLine.text}"',
        //   mirrorToConsole: true,
        // );
        DesktopLyrics.controller.updateLyricLine(desktopLine);
        _syncPlaybackState(currentPosition: position);
      }
    }
  }

  void dispose() {
    // AppLog.log('[DesktopLyrics] DesktopLyricsManager dispose() CALLED!', mirrorToConsole: true);
    try {
      ref.read(audioServiceProvider).removePositionListener(_onPositionChanged);
    } catch (_) {}
    _settingsSub?.close();
    _isPlayingSub?.close();
    _musicSub?.close();
    _lyricsSub?.close();
    DesktopLyrics.controller.hide();
  }
}
