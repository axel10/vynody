import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:window_manager/window_manager.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/metadata/musicbrainz_tag_completion_service.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import '../widgets/playback_hero_card.dart';
import '../widgets/visualizer_painter.dart';
import '../widgets/volume_controls.dart';
import '../widgets/dynamic_mesh_background.dart';
import 'package:vynody/utils/playback_utils.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/models/music_file.dart';
import '../dialogs/visualizer_options_dialog.dart';
import '../dialogs/song_tag_edit_dialog.dart';
import '../dialogs/song_tag_completion_dialog.dart';
import '../dialogs/sleep_timer_sheet.dart';
import '../dialogs/playlist_mode_sheet.dart';
import '../widgets/equalizer_panel.dart';
import '../widgets/lyrics_task_status_banner.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/mini_queue_view.dart';
import '../widgets/mini_lyrics_view.dart';
import 'main_layout_riverpod.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:oktoast/oktoast.dart';

// PlaybackPage is now cleaner as volume HUD is handled globally

class PlaybackPage extends ConsumerStatefulWidget {
  const PlaybackPage({super.key});

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage> {
  bool _showVolumeSlider = false;
  bool _isScrubbingProgress = false;
  double _scrubProgress = 0.0; // Added missing declaration
  Orientation? _lastOrientation;
  Uint8List? _pendingArtworkBytes;
  String? _pendingArtworkPath;
  Timer? _heroWarmupTimer;

  SettingsService? _settingsService;
  AudioService? _audioService;
  bool? _lastIsSmallWindow;

  MainLayoutUiController get _ui =>
      ref.read(mainLayoutUiControllerProvider.notifier);

  void _logPlaybackPageTrace(String message) {
    if (!kDebugMode) return;
    debugPrint('[PlaybackPage][Trace] $message');
  }

  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingArtworkBytes = ref.read(audioCurrentMusicProvider)?.artworkBytes;
      _pendingArtworkPath = ref.read(audioCurrentMusicProvider)?.path;
      ref.read(settingsServiceProvider).resetInactivity();
      if (mounted) {
        setState(() {});
      }
    });

    // Keep the hero flight smooth: defer background warmup until after the
    // route transition finishes. The current main layout transition is 320ms.
    _heroWarmupTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _audioService?.completeHeroTransition();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsService ??= ref.read(settingsServiceProvider);
  }

  @override
  void dispose() {
    _heroWarmupTimer?.cancel();
    // 延迟重置，避免在 dispose 过程中触发 notifyListeners 导致的 "locked" 错误
    final settings = _settingsService;
    if (settings != null) {
      Future.microtask(() {
        settings.isUserInactive = false;
      });
    }
    // 离开播放页时，显式关闭 AudioService 的歌词激活标记。
    // 这将停止在歌曲切换时自动从网络抓取歌词，从而节省网络资源。
    // 使用已缓存的服务实例，避免在 dispose 时查找 ref/context
    final audio = _audioService;
    if (audio != null) {
      Future.microtask(() {
        audio.setLyricsActive(false);
      });
    }
    super.dispose();
  }

  void _startInactivityTimer() {
    ref.read(settingsServiceProvider).resetInactivity();
  }

  void toNextMusic(AudioService audio) {
    audio.next();
  }

  void _handleInteraction() {
    _startInactivityTimer();
  }

  void _onCarouselAnimationComplete(
    Uint8List? artworkBytes,
    String? sourcePath,
  ) {
    if (!mounted) return;
    if (sourcePath == _pendingArtworkPath &&
        artworkBytes?.length == _pendingArtworkBytes?.length) {
      return;
    }
    _logPlaybackPageTrace(
      'carousel animation complete | source=$sourcePath '
      'bytes=${artworkBytes?.length ?? 0} '
      'pendingBefore=${_pendingArtworkPath ?? '-'}',
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _pendingArtworkBytes = artworkBytes;
        _pendingArtworkPath = sourcePath;
      });
      _logPlaybackPageTrace(
        'pending artwork updated from carousel | source=$sourcePath '
        'bytes=${artworkBytes?.length ?? 0}',
      );
    });
  }

  /// 当用户点击专辑封面时触发，切换歌词模式显示状态。
  ///
  /// 此函数的执行流程如下：
  /// 1. 切换当前的歌词模式布尔值（true -> false 或 false -> true）。
  /// 2. 调用 `setState()` 触发 UI 重绘。
  /// 3. 重绘过程中，`PlaybackHeroCard` 会接收到新的 `isLyricsMode` 状态。
  /// 4. `PlaybackHeroCard` 内部的 `TweenAnimationBuilder` 会启动一个 400ms 的动画。
  /// 5. 动画根据 `isLyricsMode` 线性插值计算封面、歌曲信息、控制栏及歌词面板的位置和尺寸，
  ///    实现从“普通模式”到“歌词模式”的平滑过渡效果（封面缩小并移至左上角，歌词面板从屏幕下方滑入并变亮）。
  void _toggleLyricsMode() {
    final nextLyricsMode = !ref.read(audioIsLyricsActiveProvider);
    // 延后一帧再通知 Provider，避免和本次切换动画的重建过程抢占同一帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _audioService?.setLyricsActive(nextLyricsMode);
    });
  }

  void _flushLyricsTranslationsAfterSmallWindowExit(bool isSmallWindow) {
    final previousIsSmallWindow = _lastIsSmallWindow;
    _lastIsSmallWindow = isSmallWindow;

    if (previousIsSmallWindow != true || isSmallWindow) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(lyricsControllerProvider.notifier)
            .flushPendingLyricsTranslationUpdates(),
      );
    });
  }

  void _adjustVolumeFromDrag(AudioService audio, double dragDelta) {
    _ui.setVolumeHudVisible(true);
    audio.setVolume((audio.volume - dragDelta * 0.2).roundToDouble());
  }

  void _adjustVolumeFromScroll(AudioService audio, double scrollDeltaY) {
    _ui.setVolumeHudVisible(true);
    audio.setVolume((audio.volume - scrollDeltaY * 0.1).roundToDouble());
  }

  Future<void> _toggleVisualizer(AudioService audio) async {
    final nextVisible = !ref.read(audioIsVisualizerEnabledProvider);
    audio.setVisualizerEnabled(nextVisible);
  }

  void _cyclePlaylistMode(AudioService audio) {
    final currentMode = audio.playbackMode;
    final nextMode = PlaylistMode
        .values[(currentMode.index + 1) % PlaylistMode.values.length];
    audio.setPlaybackMode(nextMode);
  }

  void _showEqualizerPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const EqualizerPanel(),
    );
  }

  void _showSleepTimerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const SleepTimerSheet(),
    );
  }

  Future<void> _showSongTagCompletionSheet(
    BuildContext context,
    AudioService audio,
  ) async {
    final song = ref.read(audioCurrentMusicProvider);
    if (song == null) return;
    final duration = ref.read(audioDurationProvider);
    final messenger = ScaffoldMessenger.of(context);

    final l10n = AppLocalizations.of(context)!;
    final popped =
        await showModalBottomSheet<(MusicBrainzTagSelectionResult, bool)>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => SongTagCompletionSheet(
            songPath: song.path,
            currentTitle: song.displayName,
            currentArtist: song.artist,
            currentAlbum: song.album,
            durationMillis: duration.inMilliseconds,
          ),
        );

    if (popped == null || !mounted) return;
    final result = popped.$1;
    final savedToSourceFile = popped.$2;

    await _applySongMetadataResult(
      messenger,
      audio: audio,
      metadata: result.metadata,
      artworkBytes: result.artworkBytes,
      successMessage: savedToSourceFile
          ? l10n.songTagsSavedToSourceFileAndApp
          : (result.artworkBytes != null
                ? l10n.tagCompletionSuccessWithCover
                : l10n.tagCompletionSuccess),
    );
  }

  Future<void> _showSongTagEditSheet(
    BuildContext context,
    AudioService audio,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final song = ref.read(audioCurrentMusicProvider);
    if (song == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final result = await showSongTagEditSheet(context, song: song);
    if (result == null || !mounted) return;

    await _applySongMetadataResult(
      messenger,
      audio: audio,
      metadata: result.metadata,
      artworkBytes: result.artworkBytes,
      successMessage: result.savedToSourceFile
          ? l10n.songTagsSavedToSourceFileAndApp
          : l10n.songTagsSavedToApp,
    );
  }

  Future<void> _applySongMetadataResult(
    ScaffoldMessengerState messenger, {
    required AudioService audio,
    required SongMetadata metadata,
    required Uint8List? artworkBytes,
    required String successMessage,
  }) async {
    final scanner = ref.read(scannerServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    await audio.applyUpdatedSongMetadata(metadata, artworkBytes: artworkBytes);
    scanner.updateMetadataForPath(metadata, artworkBytes: artworkBytes);
    await playlistService.updateSongMetadataByPath(
      metadata,
      artworkBytes: artworkBytes,
    );

    if (mounted) {
      setState(() {
        _pendingArtworkBytes = artworkBytes;
      });
    }

    if (mounted) {
      AppSnackBar.show(context, ref, SnackBar(content: Text(successMessage)));
    }
  }

  void _showTagSaveMenu(
    BuildContext context,
    AudioService audio, {
    required bool isModified,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final currentSong = ref.read(audioCurrentMusicProvider);
    final queue = ref.read(audioPlaybackQueueProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isEditEnabled = currentSong != null;
    final isSaveEnabled =
        currentSong != null &&
        isMetadataWritable(currentSong.path) &&
        isModified;
    final isQueueEnabled = queue.isNotEmpty;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? Colors.grey[900] : theme.colorScheme.surface,
        title: Text(
          l10n.saveTagsToFile,
          style: TextStyle(
            color: isDark ? Colors.white : theme.colorScheme.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.edit_rounded,
                color: isEditEnabled
                    ? Colors.orangeAccent
                    : (isDark ? Colors.white30 : theme.disabledColor),
              ),
              title: Text(
                l10n.editSongTagsTitle,
                style: TextStyle(
                  color: isEditEnabled
                      ? (isDark ? Colors.white : theme.colorScheme.onSurface)
                      : (isDark ? Colors.white38 : theme.disabledColor),
                ),
              ),
              enabled: isEditEnabled,
              onTap: () {
                Navigator.pop(dialogContext);
                _showSongTagEditSheet(context, audio);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.music_note,
                color: isSaveEnabled
                    ? Colors.blueAccent
                    : (isDark ? Colors.white30 : theme.disabledColor),
              ),
              title: Text(
                l10n.saveCurrentTagsToFile,
                style: TextStyle(
                  color: isSaveEnabled
                      ? (isDark ? Colors.white : theme.colorScheme.onSurface)
                      : (isDark ? Colors.white38 : theme.disabledColor),
                ),
              ),
              enabled: isSaveEnabled,
              onTap: () {
                Navigator.pop(dialogContext);
                _saveCurrentSongTags(audio);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.queue_music,
                color: isQueueEnabled
                    ? Colors.greenAccent
                    : (isDark ? Colors.white30 : theme.disabledColor),
              ),
              title: Text(
                l10n.saveQueueTagsToFile,
                style: TextStyle(
                  color: isQueueEnabled
                      ? (isDark ? Colors.white : theme.colorScheme.onSurface)
                      : (isDark ? Colors.white38 : theme.disabledColor),
                ),
              ),
              enabled: isQueueEnabled,
              onTap: () {
                Navigator.pop(dialogContext);
                _saveQueueTags(audio);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentSongTags(AudioService audio) async {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = ref.read(audioSnapshotProvider);
    final song = snapshot.currentMusic;
    if (song == null) return;

    // Check if format is supported
    if (!isMetadataWritable(song.path)) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          ref,
          SnackBar(content: Text(l10n.unsupportedFormatSingle)),
        );
      }
      return;
    }

    // Show loading
    if (mounted) {
      AppSnackBar.show(context, ref, SnackBar(content: Text(l10n.savingTags)));
    }

    try {
      final success = await MetadataHelper.saveDatabaseMetadataToFile(
        song.path,
        fallbackMediaUri: song.mediaUri,
      );

      if (success) {
        final db = MetadataDatabase();
        final updatedMetadata = await db.getSongMetadata(song.path);
        if (updatedMetadata != null) {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.of(context);
          await _applySongMetadataResult(
            messenger,
            audio: audio,
            metadata: updatedMetadata,
            artworkBytes: song.artworkBytes,
            successMessage: l10n.tagsSaved,
          );
        }
      } else {
        if (!mounted) return;
        final isOccupied = MetadataHelper.lastWriteError == 'file_occupied';
        showToast(
          isOccupied ? l10n.fileOccupiedByOtherApp : l10n.tagsSaveFailed,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final isOccupied = MetadataHelper.lastWriteError == 'file_occupied';
      showToast(isOccupied ? l10n.fileOccupiedByOtherApp : l10n.tagsSaveFailed);
    }
  }

  Future<void> _saveQueueTags(AudioService audio) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final queue = ref.read(audioPlaybackQueueProvider);
    if (queue.isEmpty) return;

    // Show initial loading message
    AppSnackBar.show(
      context,
      ref,
      SnackBar(
        content: Text(l10n.savingTags),
        duration: const Duration(seconds: 5),
      ),
    );

    // First, get metadata from database for each song
    final db = MetadataDatabase();
    final queuePaths = queue.map((s) => s.path).toList();
    final metadataMap = <String, SongMetadata>{};

    for (final path in queuePaths) {
      final metadata = await db.getSongMetadata(path);
      if (metadata != null) {
        metadataMap[path] = metadata;
      }
    }

    // Filter songs that are modified and have writable format
    final modifiedSongs = <SongMetadata>[];
    final artworkBytesMap = <String, Uint8List?>{};
    final mediaUriMap = <String, String?>{};

    for (final song in queue) {
      if (!isMetadataWritable(song.path)) continue;

      final metadata = metadataMap[song.path];
      if (metadata != null && metadata.isModified) {
        modifiedSongs.add(metadata);
        artworkBytesMap[song.path] = song.artworkBytes;
        mediaUriMap[song.path] = song.mediaUri;
      }
    }

    if (modifiedSongs.isEmpty) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      AppSnackBar.show(
        context,
        ref,
        SnackBar(content: Text(l10n.noModifiedTagsToSave)),
      );
      return;
    }

    // Show initial snackbar with progress
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    AppSnackBar.show(
      context,
      ref,
      SnackBar(
        content: Text('${l10n.savingTags} 0/${modifiedSongs.length}'),
        duration: Duration(seconds: modifiedSongs.length + 2),
      ),
    );

    // Start background saving task
    _runBackgroundSaveTask(
      modifiedSongs,
      artworkBytesMap,
      mediaUriMap,
      messenger,
      l10n,
    );
  }

  void _runBackgroundSaveTask(
    List<SongMetadata> songs,
    Map<String, Uint8List?> artworkBytesMap,
    Map<String, String?> mediaUriMap,
    ScaffoldMessengerState messenger,
    AppLocalizations l10n,
  ) async {
    int savedCount = 0;
    int unsupportedCount = 0;
    int failedCount = 0;

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final artworkBytes = artworkBytesMap[song.path];
      final mediaUri = mediaUriMap[song.path];

      final success = await MetadataHelper.saveDatabaseMetadataToFile(
        song.path,
        fallbackMediaUri: mediaUri,
      );

      if (success) {
        savedCount++;
        final db = MetadataDatabase();
        final updatedMetadata = await db.getSongMetadata(song.path);
        if (updatedMetadata != null) {
          final audio = ref.read(audioServiceProvider);
          final scanner = ref.read(scannerServiceProvider);
          final playlistService = ref.read(playlistServiceProvider);

          await audio.applyUpdatedSongMetadata(
            updatedMetadata,
            artworkBytes: artworkBytes,
          );
          scanner.updateMetadataForPath(
            updatedMetadata,
            artworkBytes: artworkBytes,
          );
          await playlistService.updateSongMetadataByPath(
            updatedMetadata,
            artworkBytes: artworkBytes,
          );
        }
      } else {
        if (isMetadataWritable(song.path)) {
          if (MetadataHelper.lastWriteError == 'file_occupied') {
            showToast(
              '${p.basename(song.path)}: ${l10n.fileOccupiedByOtherApp}',
            );
          }
          failedCount++;
        } else {
          unsupportedCount++;
        }
      }

      // Update progress snackbar
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      AppSnackBar.show(
        context,
        ref,
        SnackBar(
          content: Text('${l10n.savingTags} ${i + 1}/${songs.length}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Show final result
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    final messages = <String>[];
    if (savedCount > 0) {
      messages.add(l10n.tagsSavedCount(savedCount));
    }
    if (failedCount > 0) {
      messages.add(l10n.tagsSaveFailedCount(failedCount));
    }
    if (unsupportedCount > 0) {
      messages.add(l10n.unsupportedFormat(unsupportedCount));
    }

    AppSnackBar.show(context, ref, SnackBar(content: Text(messages.join(' '))));
  }

  void _showPlaylistModeSelector(BuildContext context, AudioService audio) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const PlaylistModeSheet(),
    );
  }

  void _showMoreMenu(BuildContext context, AudioService audio) {
    final settings = ref.read(settingsServiceProvider);
    showVisualizerOptionsDialog(context, audio, settings);
  }

  @override
  Widget build(BuildContext context) {
    // Separate UI status from rendering visibility to avoid flicker
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    ref.listen<MusicFile?>(audioCurrentMusicProvider, (previous, next) {
      if (!mounted) return;
      final size = MediaQuery.of(context).size;
      final settings = ref.read(settingsServiceProvider);
      final bool isSmallWin = PlaybackPageUiTuning.isSmallWindow(
        size,
        isWaveformEnabled: settings.isWaveformProgressBarEnabled,
        isSmallWindowMode: settings.isSmallWindowMode,
      );
      if (isSmallWin) {
        if (next?.path == _pendingArtworkPath &&
            next?.artworkBytes?.length == _pendingArtworkBytes?.length) {
          return;
        }
        _logPlaybackPageTrace(
          'currentMusic listener | prev=${previous?.path ?? '-'} '
          'next=${next?.path ?? '-'} '
          'prevBytes=${previous?.artworkBytes?.length ?? 0} '
          'nextBytes=${next?.artworkBytes?.length ?? 0} '
          'pendingBefore=${_pendingArtworkPath ?? '-'}',
        );
        setState(() {
          _pendingArtworkBytes = next?.artworkBytes;
          _pendingArtworkPath = next?.path;
        });
        _logPlaybackPageTrace(
          'currentMusic listener applied pending | pendingAfter=${_pendingArtworkPath ?? '-'} '
          'bytes=${_pendingArtworkBytes?.length ?? 0}',
        );
      }
    });
    final currentMetadataAsync = currentMusic != null
        ? ref.watch(songMetadataProvider(currentMusic.path))
        : null;
    final isModified = currentMetadataAsync?.value?.isModified ?? false;
    final isLyricsMode = ref.watch(audioIsLyricsActiveProvider);
    final isVisualizerEnabled = ref.watch(audioIsVisualizerEnabledProvider);
    final isTransitioning = ref.watch(audioIsTransitioningProvider);
    final shouldDrawVisualizer = isVisualizerEnabled && !isTransitioning;
    final backgroundType = ref.watch(
      settingsServiceProvider.select((s) => s.playbackBackgroundType),
    );

    return Listener(
      onPointerDown: (event) {
        _handleInteraction();
      },
      onPointerMove: (event) => _handleInteraction(),
      onPointerHover: (event) => _handleInteraction(),
      child: OrientationBuilder(
        builder: (context, orientation) {
          final size = MediaQuery.of(context).size;
          final settings = ref.watch(settingsServiceProvider);
          final bool isSmallWin = PlaybackPageUiTuning.isSmallWindow(
            size,
            isWaveformEnabled: settings.isWaveformProgressBarEnabled,
            isSmallWindowMode: settings.isSmallWindowMode,
          );
          _flushLyricsTranslationsAfterSmallWindowExit(isSmallWin);
          final isLandscape =
              !isSmallWin && (orientation == Orientation.landscape);

          if (_lastOrientation != orientation) {
            _lastOrientation = orientation;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              audio.applyVisualizerSettings(orientation: orientation);
            });
          }
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final isImmersiveTabBarEnabled = settings.isImmersiveTabBarEnabled;

          final shouldReserveBottomNavSpace =
              !isLyricsMode && !isLandscape && !isSmallWin;

          // When immersive tab bar is enabled, the NavigationBar in MainLayout
          // is positioned in a Stack over the content with height (60 + bottomPadding).
          double effectiveBottomPadding = bottomPadding;
          final lyricsBottomSpacerHeight = 0.0;
          double lyricsBottomTabBarHeight = 0.0;

          if (isImmersiveTabBarEnabled && !isLandscape && !isSmallWin) {
            // For lyrics mode, we want the background to be immersive (full screen),
            // so we don't pad the whole page. Instead, we pass the tab bar height
            // to the lyrics panel so it can add internal scrolling space.
            lyricsBottomTabBarHeight = 60.0;

            // For normal mode (controls visible), we pad the whole page to keep
            // the layout stable and avoid overlap with the tab bar.
            if (shouldReserveBottomNavSpace) {
              effectiveBottomPadding = 60.0 + bottomPadding;
            }
          }

          final smallWindowPanelMode = settings.smallWindowBottomPanelMode;
          final showMiniPanel =
              isSmallWin &&
              smallWindowPanelMode != SmallWindowBottomPanelMode.collapsed;

          Widget buildPlayerCard() {
            return Builder(
              builder: (context) {
                final isNext = ref.watch(audioLastActionNextProvider) ?? true;
                final currentMusic = ref.watch(audioCurrentMusicProvider);
                final duration = ref.watch(audioDurationProvider);
                final isVisualizerEnabled = ref.watch(
                  audioIsVisualizerEnabledProvider,
                );

                return PlaybackHeroCard(
                  isMini: false,
                  isLandscape: isLandscape,
                  isLyricsMode: isLyricsMode,
                  isNext: isNext,
                  lyricsBottomSpacerHeight: lyricsBottomSpacerHeight,
                  lyricsBottomTabBarHeight: lyricsBottomTabBarHeight,
                  overrideProgress: _isScrubbingProgress
                      ? _scrubProgress
                      : null,
                  overridePosition: _isScrubbingProgress
                      ? Duration(
                          milliseconds:
                              (_scrubProgress * duration.inMilliseconds)
                                  .round(),
                        )
                      : null,
                  showVisualizerToggle: isVisualizerEnabled,
                  onShowMoreMenu: () => _showMoreMenu(context, audio),
                  onCyclePlaylistMode: () => _cyclePlaylistMode(audio),
                  onShowPlaylistModeSelector: () =>
                      _showPlaylistModeSelector(context, audio),
                  onScrubbing: (val) {
                    _handleInteraction();
                    setState(() {
                      _isScrubbingProgress = true;
                      _scrubProgress = val;
                    });
                  },
                  onSeek: (val) {
                    final target = Duration(
                      milliseconds: (val * duration.inMilliseconds).round(),
                    );
                    setState(() {
                      _isScrubbingProgress = false;
                      _scrubProgress = val;
                    });
                    audio.seek(target);
                  },
                  onToggleVisualizer: () => _toggleVisualizer(audio),
                  onTagCompletionTap: currentMusic == null
                      ? null
                      : () => _showSongTagCompletionSheet(context, audio),
                  onTagCompletionLongPress: currentMusic == null
                      ? null
                      : () => _showTagSaveMenu(
                          context,
                          audio,
                          isModified: isModified,
                        ),
                  onSleepTimerTap: () => _showSleepTimerSheet(context),
                  onEqualizerTap: () => _showEqualizerPanel(context),
                  onCoverTap: _toggleLyricsMode,
                  onPrevious: audio.previous,
                  onPlayPause: audio.togglePlay,
                  onNext: () => toNextMusic(audio),
                  onVolumeTap: () {
                    _handleInteraction();
                    _ui.setVolumeHudVisible(true);
                    setState(() => _showVolumeSlider = !_showVolumeSlider);
                  },
                  onVolumeDrag: (delta) {
                    _handleInteraction();
                    _adjustVolumeFromDrag(audio, delta);
                  },
                  onVolumeScroll: (deltaY) {
                    _handleInteraction();
                    _adjustVolumeFromScroll(audio, deltaY);
                  },
                  onCarouselAnimationComplete: _onCarouselAnimationComplete,
                );
              },
            );
          }

          final content = SafeArea(
            bottom: false,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastOutSlowIn,
              padding: PlaybackPageUiTuning.contentPadding(
                isLandscape: isLandscape,
                isLyricsMode: isLyricsMode,
                bottomPadding: effectiveBottomPadding,
                reserveBottomNavSpace: shouldReserveBottomNavSpace,
                isSmallWin: isSmallWin,
              ),
              child: Column(
                children: [
                  if (Platform.isWindows ||
                      Platform.isMacOS ||
                      Platform.isLinux)
                    const DragToMoveArea(
                      child: SizedBox(
                        height: PlaybackPageUiTuning.desktopTopSpacer,
                      ),
                    ),
                  if (showMiniPanel) ...[
                    SizedBox(
                      height: 360.0 - PlaybackPageUiTuning.desktopTopSpacer,
                      child: Center(child: buildPlayerCard()),
                    ),
                    Expanded(
                      child: switch (smallWindowPanelMode) {
                        SmallWindowBottomPanelMode.queue =>
                          const MiniQueueView(),
                        SmallWindowBottomPanelMode.lyrics =>
                          const MiniLyricsView(),
                        SmallWindowBottomPanelMode.collapsed =>
                          const SizedBox.shrink(),
                      },
                    ),
                  ] else
                    Expanded(child: Center(child: buildPlayerCard())),
                  if (isLandscape &&
                      (Platform.isWindows ||
                          Platform.isMacOS ||
                          Platform.isLinux))
                    const SizedBox(
                      height: PlaybackPageUiTuning.desktopTopSpacer,
                    ),
                ],
              ),
            ),
          );

          return Container(
            color: Colors.black,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      opacity: isSmallWin ? 0.0 : 1.0,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 800),
                        child: _buildBackgroundWidget(
                          context,
                          backgroundType,
                          settings,
                          forceSmallWin: false,
                          keySuffix: 'normal',
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !isSmallWin,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      opacity: isSmallWin ? 1.0 : 0.0,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: ClipRect(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 800),
                                child: _buildBackgroundWidget(
                                  context,
                                  backgroundType,
                                  settings,
                                  forceSmallWin: true,
                                  keySuffix: 'small_clear',
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isWaveformEnabled =
                                    settings.isWaveformProgressBarEnabled;
                                const double scaleFactor = 0.82;

                                final pNormalControlsBaseIdealHeight =
                                    (PlaybackHeroCardUiTuning
                                            .controlsTopButtonsHeight +
                                        (isWaveformEnabled
                                            ? PlaybackHeroCardUiTuning
                                                  .waveformStandardTimeRowSpacing
                                            : PlaybackHeroCardUiTuning
                                                  .controlsRowPortraitGap) +
                                        (isWaveformEnabled
                                            ? PlaybackHeroCardUiTuning
                                                  .waveformOverlayHeight
                                            : 48.0) +
                                        (isWaveformEnabled
                                            ? 0.0
                                            : (8.0 +
                                                  PlaybackHeroCardUiTuning
                                                      .controlsTimeRowHeight +
                                                  PlaybackHeroCardUiTuning
                                                      .controlsRowPortraitGap +
                                                  PlaybackHeroCardUiTuning
                                                      .controlsMainButtonsHeight))) *
                                    scaleFactor;

                                final pNormalScale =
                                    (size.width /
                                            PlaybackHeroCardUiTuning
                                                .pControlsScaleBase)
                                        .clamp(0.9, 1.15) *
                                    scaleFactor;
                                final double maxControlsHeightFactor =
                                    isSmallWin
                                    ? 0.85
                                    : PlaybackHeroCardUiTuning
                                          .pControlsHeightFactor;
                                final pNormalControlsHeight =
                                    (pNormalControlsBaseIdealHeight *
                                            pNormalScale)
                                        .clamp(
                                          0.0,
                                          size.height * maxControlsHeightFactor,
                                        )
                                        .ceilToDouble();
                                final pNormalInfoHeight =
                                    PlaybackHeroCardUiTuning.pInfoHeight *
                                    pNormalScale;
                                final pNormalBottomLimit =
                                    size.height -
                                    PlaybackHeroCardUiTuning
                                        .portraitBottomReservedSpace;

                                const double bottomPadding = 12.0;
                                final pNormalControlsTop =
                                    pNormalBottomLimit -
                                    pNormalControlsHeight -
                                    bottomPadding;
                                final pNormalInfoTop =
                                    pNormalControlsTop -
                                    pNormalInfoHeight -
                                    4.0;

                                final double fadeStart =
                                    (pNormalInfoTop - 48.0) / size.height;
                                final double fadeEnd =
                                    pNormalInfoTop / size.height;
                                final double clampedStart = fadeStart.clamp(
                                  0.0,
                                  1.0,
                                );
                                final double clampedEnd = fadeEnd.clamp(
                                  0.0,
                                  1.0,
                                );

                                if (showMiniPanel) {
                                  // 小窗队列 / 小窗歌词模式统一对整块小窗做模糊，
                                  // 上下两个面板共享同一层背景，不再做分区处理。
                                  return ClipRect(
                                    child: BackdropFilter(
                                      filter: ui.ImageFilter.blur(
                                        sigmaX: 20.0,
                                        sigmaY: 20.0,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  );
                                }

                                final Widget blurredBackground = ImageFiltered(
                                  imageFilter: ui.ImageFilter.blur(
                                    sigmaX: 20.0,
                                    sigmaY: 20.0,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 800),
                                    child: _buildBackgroundWidget(
                                      context,
                                      backgroundType,
                                      settings,
                                      forceSmallWin: true,
                                      keySuffix: 'small_blurred',
                                    ),
                                  ),
                                );

                                return ClipRect(
                                  child: ShaderMask(
                                    shaderCallback: (rect) {
                                      return LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: const [
                                          Colors.transparent,
                                          Colors.black,
                                        ],
                                        stops: [clampedStart, clampedEnd],
                                      ).createShader(rect);
                                    },
                                    blendMode: BlendMode.dstIn,
                                    child: blurredBackground,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildBackgroundScrim(
                  isLyricsMode,
                  backgroundType,
                  settings,
                  isSmallWin,
                ),
                if (shouldDrawVisualizer)
                  _buildVisualizerLayer(context, orientation),
                _buildLyricsModeScrim(
                  isLyricsMode,
                  backgroundType,
                  settings,
                  isSmallWin,
                ),
                RepaintBoundary(child: content),
                Positioned(
                  left: 0,
                  right: 0,
                  top: PlaybackPageUiTuning.statusBannerTop,
                  child: SafeArea(
                    bottom: false,
                    child: LyricsTaskStatusBanner(
                      key: const ValueKey('lyrics_task_status_banner'),
                    ),
                  ),
                ),
                if (_showVolumeSlider)
                  Builder(
                    builder: (context) {
                      final volume = ref.watch(audioVolumeProvider);
                      return VolumeSliderOverlay(
                        volume: volume,
                        onVolumeChanged: (val) {
                          _handleInteraction();
                          _ui.setVolumeHudVisible(true);
                          audio.setVolume(val.roundToDouble());
                        },
                        onDismiss: () {
                          setState(() => _showVolumeSlider = false);
                        },
                        isLandscape: isLandscape,
                        getVolumeIcon: getVolumeIcon,
                        onDrag: (delta) => _adjustVolumeFromDrag(audio, delta),
                        onScroll: (deltaY) =>
                            _adjustVolumeFromScroll(audio, deltaY),
                        onInteraction: _handleInteraction,
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBackgroundWidget(
    BuildContext context,
    int backgroundType,
    SettingsService settings, {
    bool? forceSmallWin,
    String? keySuffix,
  }) {
    switch (backgroundType) {
      case 1:
        return RepaintBoundary(
          key: ValueKey('fluid_bg_${keySuffix ?? 'default'}'),
          child: const DynamicMeshBackground(),
        );
      case 2:
        return Container(
          key: ValueKey(
            'solid_color_bg_${settings.playbackBackgroundColor}_${keySuffix ?? 'default'}',
          ),
          color: Color(settings.playbackBackgroundColor),
          width: double.infinity,
          height: double.infinity,
        );
      case 3:
        final path = settings.playbackBackgroundCustomImagePath;
        if (path.isEmpty || !File(path).existsSync()) {
          return Container(
            key: ValueKey('custom_image_empty_${keySuffix ?? 'default'}'),
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
          );
        }
        final imageWidget = Image.file(
          File(path),
          key: ValueKey('custom_image_bg_${path}_${keySuffix ?? 'default'}'),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              child: const Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white24,
                  size: 48,
                ),
              ),
            );
          },
        );
        final size = MediaQuery.of(context).size;
        final bool isSmallWinValue =
            forceSmallWin ??
            PlaybackPageUiTuning.isSmallWindow(
              size,
              isWaveformEnabled: settings.isWaveformProgressBarEnabled,
              isSmallWindowMode: settings.isSmallWindowMode,
            );
        final blur = settings.playbackCustomImageBlurSigma;
        if (blur > 0.0 && !isSmallWinValue) {
          return ImageFiltered(
            key: ValueKey(
              'custom_image_bg_blurred_${path}_${keySuffix ?? 'default'}',
            ),
            imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Transform.scale(scale: 1.2, child: imageWidget),
          );
        }
        return Transform.scale(scale: 1.2, child: imageWidget);
      case 0:
      default:
        return _buildBlurredBackground(
          context,
          settings,
          forceSmallWin: forceSmallWin,
          keySuffix: keySuffix,
        );
    }
  }

  Widget _buildBackgroundScrim(
    bool isLyricsMode,
    int backgroundType,
    SettingsService settings,
    bool isSmallWin,
  ) {
    double opacity = 0.30;
    if (backgroundType == 0 || backgroundType == 2 || backgroundType == 3) {
      opacity = settings.playbackBackgroundNormalOpacity;
    }

    final double targetOpacity = isSmallWin ? 0.0 : (isLyricsMode ? 0.0 : 1.0);

    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        opacity: targetOpacity,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: settings.playbackRadialGradientEnabled
                  ? null
                  : Colors.black.withValues(alpha: opacity),
              gradient: settings.playbackRadialGradientEnabled
                  ? RadialGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: opacity),
                      ],
                      stops: const [0.1, 1.0],
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsModeScrim(
    bool isLyricsMode,
    int backgroundType,
    SettingsService settings,
    bool isSmallWin,
  ) {
    double opacity = 0.40;
    if (backgroundType == 0 || backgroundType == 2 || backgroundType == 3) {
      opacity = settings.playbackBackgroundLyricsOpacity;
    }

    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        opacity: isSmallWin || !isLyricsMode ? 0.0 : 1.0,
        child: IgnorePointer(
          child: ColoredBox(color: Colors.black.withValues(alpha: opacity)),
        ),
      ),
    );
  }

  /// 构建毛玻璃背景组件。
  ///
  /// 该组件实现了当音乐切换或封面更新时，背景图的平滑过渡效果。
  /// 使用 _pendingArtworkBytes，在轮播动画完成后才更新背景。
  Widget _buildBlurredBackground(
    BuildContext context,
    SettingsService settings, {
    bool? forceSmallWin,
    String? keySuffix,
  }) {
    final String finalSuffix =
        keySuffix ??
        (forceSmallWin == null ? 'auto' : (forceSmallWin ? 'small' : 'normal'));
    final size = MediaQuery.of(context).size;
    final bool isSmallWinValue =
        forceSmallWin ??
        PlaybackPageUiTuning.isSmallWindow(
          size,
          isWaveformEnabled: settings.isWaveformProgressBarEnabled,
          isSmallWindowMode: settings.isSmallWindowMode,
        );

    return RepaintBoundary(
      key: ValueKey('blurred_bg_$finalSuffix'),
      child: Stack(
        children: [
          // 简化后的背景渲染逻辑：在轮播动画完成后才更新背景。
          // 拿到原始大图后，利用 Image.memory 的 cacheWidth/cacheHeight 属性
          // 在解码阶段即完成缩小，从而替代之前手动生成的低清图逻辑。
          Builder(
            builder: (context) {
              final Widget content;

              if (isSmallWinValue) {
                final currentMusic = ref.watch(audioCurrentMusicProvider);
                final originalBytes = currentMusic?.artworkBytes;
                final originalPath = currentMusic?.artworkPath;
                final songKey = currentMusic?.path ?? 'empty';

                if (originalBytes != null && originalBytes.isNotEmpty) {
                  content = ImageFiltered(
                    key: ValueKey('${songKey}_$finalSuffix'),
                    imageFilter: ui.ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0),
                    child: Transform.scale(
                      scale: 1.2,
                      child: Image.memory(
                        originalBytes,
                        width: double.infinity,
                        height: double.infinity,
                        cacheWidth: (Platform.isAndroid || Platform.isIOS)
                            ? 300
                            : 600,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      ),
                    ),
                  );
                } else if (originalPath != null &&
                    originalPath.isNotEmpty &&
                    File(originalPath).existsSync()) {
                  content = ImageFiltered(
                    key: ValueKey('${songKey}_$finalSuffix'),
                    imageFilter: ui.ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0),
                    child: Transform.scale(
                      scale: 1.2,
                      child: Image.file(
                        File(originalPath),
                        width: double.infinity,
                        height: double.infinity,
                        cacheWidth: (Platform.isAndroid || Platform.isIOS)
                            ? 300
                            : 600,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        excludeFromSemantics: true,
                      ),
                    ),
                  );
                } else {
                  content = Container(
                    key: ValueKey('bg_empty_$finalSuffix'),
                    color: Colors.black,
                    width: double.infinity,
                    height: double.infinity,
                  );
                }
              } else {
                final bytes = _pendingArtworkBytes;
                if (bytes == null || bytes.isEmpty) {
                  // 如果封面字节尚未准备好（或不存在），则显示纯黑背景。
                  content = Container(
                    key: ValueKey(
                      'bg_empty_${_pendingArtworkPath}_$finalSuffix',
                    ),
                    color: Colors.black,
                  );
                } else {
                  // 使用 Image.memory 的高性能解码缩放：
                  // 对于 Android 和 iOS，通过设置 cacheWidth (300px) 在解码阶段完成缩小，以降低内存并加速滤镜运算；
                  // 对于桌面端，使用原图（cacheWidth 为 null）以提供更清晰的背景。
                  final currentMusic = ref.watch(audioCurrentMusicProvider);
                  final String songKey =
                      _pendingArtworkPath ??
                      currentMusic?.path ??
                      bytes.hashCode.toString();
                  final imageProvider = Image.memory(
                    bytes,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: (Platform.isAndroid || Platform.isIOS)
                        ? 300
                        : 600,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  );

                  content = ImageFiltered(
                    // 使用歌曲路径或哈希值作为 Key，确保切歌时触发过渡动画，但封面精度提升时不触发
                    key: ValueKey('${songKey}_$finalSuffix'),
                    // 减小模糊强度并增加缩放以更好地覆盖边缘
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: settings.playbackBlurredArtworkBlurSigma,
                      sigmaY: settings.playbackBlurredArtworkBlurSigma,
                    ),
                    child: Transform.scale(scale: 1.2, child: imageProvider),
                  );
                }
              }

              // 过渡动画逻辑：新封面直接淡入盖在旧封面之上。
              // 这种方式避免了传统的“双向淡入淡出（Cross-fade）”可能导致的背景短暂变暗或跳动。
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 1000),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  final isIncoming = child.key == content.key;
                  if (isIncoming) {
                    return FadeTransition(opacity: animation, child: child);
                  } else {
                    return child;
                  }
                },
                child: content,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVisualizerLayer(BuildContext context, Orientation orientation) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: StreamBuilder<FftFrame>(
          stream: ref.read(audioServiceProvider).visualizerStream,
          builder: (context, snapshot) {
            final frame = snapshot.data;
            if (frame == null) return const SizedBox.shrink();

            final settings = ref.watch(settingsServiceProvider);
            final dynamicStartColor = ref.watch(audioDynamicStartColorProvider);
            final dynamicEndColor = ref.watch(audioDynamicEndColorProvider);
            final isLandscape = orientation == Orientation.landscape;
            final gap = isLandscape
                ? settings.landscapeGap
                : settings.portraitGap;

            return ExcludeSemantics(
              child: CustomPaint(
                painter: FftPainter(
                  values: frame.values,
                  gap: gap,
                  color: settings.isVisualizerDynamicColor
                      ? (dynamicStartColor ?? settings.visualizerColor)
                      : settings.visualizerColor,
                  opacity: settings.visualizerOpacity,
                  useGradient: settings.isVisualizerGradientEnabled,
                  startColor: settings.isVisualizerDynamicStartColor
                      ? (dynamicStartColor ?? settings.visualizerStartColor)
                      : settings.visualizerStartColor,
                  endColor: settings.isVisualizerDynamicEndColor
                      ? (dynamicEndColor ?? settings.visualizerEndColor)
                      : settings.visualizerEndColor,
                  gradientStop1: settings.visualizerGradientStop1,
                  gradientStop2: settings.visualizerGradientStop2,
                  gradientTileMode: settings.visualizerGradientTileMode,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
