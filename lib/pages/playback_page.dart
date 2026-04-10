import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_core/audio_core.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';
import '../player/audio_snapshot.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';
import '../player/musicbrainz_tag_completion_service.dart';
import '../player/metadata_helper.dart';
import '../player/metadata_database.dart';
import '../widgets/playback_hero_card.dart';
import '../widgets/visualizer_painter.dart';
import '../widgets/volume_controls.dart';
import '../widgets/dynamic_mesh_background.dart';
import '../utils/playback_utils.dart';
import '../player/playlist_service.dart';
import '../models/music_file.dart';
import '../dialogs/visualizer_options_dialog.dart';
import '../dialogs/song_tag_completion_dialog.dart';
import '../widgets/equalizer_panel.dart';

// PlaybackPage is now cleaner as volume HUD is handled globally

class PlaybackPage extends ConsumerStatefulWidget {
  const PlaybackPage({super.key});

  @override
  ConsumerState<PlaybackPage> createState() => _PlaybackPageState();
}

class _PlaybackPageState extends ConsumerState<PlaybackPage>
    with SingleTickerProviderStateMixin {
  bool _showVolumeSlider = false;
  bool _showVisualizer = true;
  bool _isLyricsMode = false;
  bool _isScrubbingProgress = false;
  double _scrubProgress = 0.0; // Added missing declaration
  Orientation? _lastOrientation;
  Timer? _inactivityTimer; // Added missing declaration
  Uint8List? _pendingArtworkBytes;

  SettingsService? _settingsService;
  AudioService? _audioService;

  @override
  void initState() {
    super.initState();
    _audioService = ref.read(audioServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final audio = _audioService;
      if (audio == null) return;
      _showVisualizer = audio.isVisualizerEnabled;
      _isLyricsMode = audio.isLyricsActive;
      _pendingArtworkBytes = audio.currentMusic?.artworkBytes;
      ref.read(settingsServiceProvider).resetInactivity();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsService ??= ref.read(settingsServiceProvider);
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
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

  void _onCarouselAnimationComplete() {
    if (!mounted) return;

    final audio = ref.read(audioServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _pendingArtworkBytes = audio.currentMusic?.artworkBytes;
      });
    });
  }

  /// 当用户点击专辑封面时触发，切换歌词模式显示状态。
  ///
  /// 此函数的执行流程如下：
  /// 1. 切换当前的 `_isLyricsMode` 布尔值（true -> false 或 false -> true）。
  /// 2. 调用 `setState()` 触发 UI 重绘。
  /// 3. 重绘过程中，`PlaybackHeroCard` 会接收到新的 `isLyricsMode` 状态。
  /// 4. `PlaybackHeroCard` 内部的 `TweenAnimationBuilder` 会启动一个 400ms 的动画。
  /// 5. 动画根据 `isLyricsMode` 线性插值计算封面、歌曲信息、控制栏及歌词面板的位置和尺寸，
  ///    实现从“普通模式”到“歌词模式”的平滑过渡效果（封面缩小并移至左上角，歌词面板从屏幕下方滑入并变亮）。
  void _toggleLyricsMode() {
    final nextLyricsMode = !_isLyricsMode;
    setState(() {
      _isLyricsMode = nextLyricsMode;
    });
    // 延后一帧再通知 Provider，避免和本次切换动画的重建过程抢占同一帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(audioServiceProvider).setLyricsActive(nextLyricsMode);
    });
  }

  void _adjustVolumeFromDrag(AudioService audio, double dragDelta) {
    audio.setVolume((audio.volume - dragDelta * 0.2).roundToDouble());
  }

  void _adjustVolumeFromScroll(AudioService audio, double scrollDeltaY) {
    audio.setVolume((audio.volume - scrollDeltaY * 0.1).roundToDouble());
  }

  Future<void> _toggleVisualizer(AudioService audio) async {
    final nextVisible = !_showVisualizer;
    setState(() {
      _showVisualizer = nextVisible;
    });
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

  Future<void> _showSongTagCompletionSheet(
    BuildContext context,
    AudioService audio,
  ) async {
    final snapshot = audio.snapshot;
    final song = snapshot.currentMusic;
    if (song == null) return;

    final result = await showModalBottomSheet<MusicBrainzTagSelectionResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SongTagCompletionSheet(
        songPath: song.path,
        currentTitle: song.displayName,
        currentArtist: song.artist,
        currentAlbum: song.album,
        durationMillis: snapshot.duration.inMilliseconds,
      ),
    );

    if (result == null || !context.mounted) return;

    final scanner = ref.read(scannerServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);

    await audio.applyUpdatedSongMetadata(
      result.metadata,
      artworkBytes: result.artworkBytes,
    );
    scanner.updateMetadataForPath(
      result.metadata,
      artworkBytes: result.artworkBytes,
    );
    await playlistService.updateSongMetadataByPath(
      result.metadata,
      artworkBytes: result.artworkBytes,
    );

    if (context.mounted && result.artworkBytes != null) {
      setState(() {
        _pendingArtworkBytes = result.artworkBytes;
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.artworkBytes != null ? '标签已补全并保存，封面已下载到临时目录' : '标签已补全并保存',
          ),
        ),
      );
    }
  }

  void _showTagSaveMenu(BuildContext context, AudioService audio) {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = audio.snapshot;
    final currentSong = snapshot.currentMusic;
    final queue = snapshot.playbackQueue;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          l10n.saveTagsToFile,
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.music_note, color: Colors.blueAccent),
              title: Text(
                l10n.saveCurrentTagsToFile,
                style: const TextStyle(color: Colors.white),
              ),
              enabled:
                  currentSong != null && isMetadataWritable(currentSong.path),
              onTap: () {
                Navigator.pop(dialogContext);
                _saveCurrentSongTags(context, audio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music, color: Colors.greenAccent),
              title: Text(
                l10n.saveQueueTagsToFile,
                style: const TextStyle(color: Colors.white),
              ),
              enabled: queue.isNotEmpty,
              onTap: () {
                Navigator.pop(dialogContext);
                _saveQueueTags(context, audio);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentSongTags(
    BuildContext context,
    AudioService audio,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final snapshot = audio.snapshot;
    final song = snapshot.currentMusic;
    if (song == null) return;

    // Check if format is supported
    if (!isMetadataWritable(song.path)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.unsupportedFormatSingle)));
      }
      return;
    }

    // Show loading
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.savingTags)));
    }

    try {
      // Get artwork bytes if available
      List<Picture>? pictures;
      if (song.artworkBytes != null) {
        pictures = [
          Picture(song.artworkBytes!, 'image/jpeg', PictureType.coverFront),
        ];
      }

      final success = await MetadataHelper.saveMetadataToFile(
        song.path,
        title: song.displayName,
        artist: song.artist,
        album: song.album,
        trackNumber: song.trackNumber,
        pictures: pictures,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? l10n.tagsSaved : l10n.tagsSaveFailed),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.tagsSaveFailed)));
      }
    }
  }

  Future<void> _saveQueueTags(BuildContext context, AudioService audio) async {
    final l10n = AppLocalizations.of(context)!;
    final queue = audio.playbackQueue;
    if (queue.isEmpty) return;

    // Show initial loading message
    ScaffoldMessenger.of(context).showSnackBar(
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

    for (final song in queue) {
      if (!isMetadataWritable(song.path)) continue;

      final metadata = metadataMap[song.path];
      if (metadata != null && metadata.isModified) {
        modifiedSongs.add(metadata);
        artworkBytesMap[song.path] = song.artworkBytes;
      }
    }

    if (modifiedSongs.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.noModifiedTagsToSave)));
      }
      return;
    }

    // Show initial snackbar with progress
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${l10n.savingTags} 0/${modifiedSongs.length}'),
        duration: Duration(seconds: modifiedSongs.length + 2),
      ),
    );

    // Start background saving task
    _runBackgroundSaveTask(modifiedSongs, artworkBytesMap, context, l10n);
  }

  void _runBackgroundSaveTask(
    List<SongMetadata> songs,
    Map<String, Uint8List?> artworkBytesMap,
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    int savedCount = 0;
    int unsupportedCount = 0;
    int failedCount = 0;

    for (int i = 0; i < songs.length; i++) {
      final song = songs[i];
      final artworkBytes = artworkBytesMap[song.path];

      List<Picture>? pictures;
      if (artworkBytes != null) {
        pictures = [
          Picture(artworkBytes, 'image/jpeg', PictureType.coverFront),
        ];
      }

      final success = await MetadataHelper.saveMetadataToFile(
        song.path,
        title: song.title,
        artist: song.artist,
        album: song.album,
        trackNumber: song.trackNumber,
        genres: song.genres,
        pictures: pictures,
      );

      if (success) {
        savedCount++;
      } else {
        if (isMetadataWritable(song.path)) {
          failedCount++;
        } else {
          unsupportedCount++;
        }
      }

      // Update progress snackbar
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.savingTags} ${i + 1}/${songs.length}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    // Show final result
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(messages.join(' '))));
    }
  }

  void _showRandomModeSelector(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final settings = ref.watch(settingsServiceProvider);
        return AlertDialog(
          title: Text(l10n.randomMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.randomRange,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              RadioListTile<int>(
                title: Text(l10n.currentQueue),
                value: 0,
                groupValue: settings.randomRange,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomRange = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      audio
                          .toggleRandomMode(); // Re-apply with new range (Current)
                    }
                  }
                },
              ),
              RadioListTile<int>(
                title: Text(l10n.globalRange),
                value: 1,
                groupValue: settings.randomRange,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomRange = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      final playlistService = ref.read(playlistServiceProvider);
                      final allSongs = _getGlobalSongs(playlistService);
                      audio.toggleRandomMode(globalSongs: allSongs);
                    }
                  }
                },
              ),
              const Divider(),
              Text(
                l10n.randomMethod,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              RadioListTile<int>(
                title: Text(l10n.completeRandom),
                value: 0,
                groupValue: settings.randomMethod,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomMethod = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      if (settings.randomRange == 1) {
                        final allSongs = _getGlobalSongs(
                          ref.read(playlistServiceProvider),
                        );
                        audio.toggleRandomMode(globalSongs: allSongs);
                      } else {
                        audio.toggleRandomMode();
                      }
                    }
                  }
                },
              ),
              RadioListTile<int>(
                title: Text(l10n.shuffleRandom),
                value: 1,
                groupValue: settings.randomMethod,
                onChanged: (val) {
                  if (val != null) {
                    settings.randomMethod = val;
                    if (audio.isRandomMode) {
                      audio.toggleRandomMode(); // Off
                      if (settings.randomRange == 1) {
                        final allSongs = _getGlobalSongs(
                          ref.read(playlistServiceProvider),
                        );
                        audio.toggleRandomMode(globalSongs: allSongs);
                      } else {
                        audio.toggleRandomMode();
                      }
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  List<MusicFile> _getGlobalSongs(PlaylistService playlistService) {
    final List<MusicFile> allSongs = [];
    final pathSet = <String>{};
    for (final p in playlistService.playlists) {
      for (final s in p.songs) {
        if (pathSet.add(s.path)) allSongs.add(s);
      }
    }
    return allSongs;
  }

  void _showPlaylistModeSelector(BuildContext context, AudioService audio) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.playbackMode),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: PlaylistMode.values.map((mode) {
              return ListTile(
                leading: Icon(getPlaylistModeIcon(mode)),
                title: Text(
                  getPlaylistModeName(mode, AppLocalizations.of(context)!),
                ),
                selected: audio.playbackMode == mode,
                onTap: () {
                  audio.setPlaybackMode(mode);
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showMoreMenu(BuildContext context, AudioService audio) {
    final settings = ref.read(settingsServiceProvider);
    showVisualizerOptionsDialog(context, audio, settings);
  }

  @override
  Widget build(BuildContext context) {
    // Separate UI status from rendering visibility to avoid flicker
    final AudioSnapshot snapshot = ref.watch(
      audioServiceProvider.select((a) => a.snapshot),
    );
    final isVisualizerEnabled = snapshot.isVisualizerEnabled;
    final isTransitioning = snapshot.isTransitioning;
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
          final isLandscape = orientation == Orientation.landscape;

          final screenWidth = MediaQuery.of(context).size.width;
          final screenHeight = MediaQuery.of(context).size.height;

          if (_lastOrientation != orientation) {
            _lastOrientation = orientation;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref
                  .read(audioServiceProvider)
                  .applyVisualizerSettings(orientation: orientation);
            });
          }

          final content = SafeArea(
            child: Padding(
              padding: EdgeInsets.all(isLandscape ? 32.0 : 24.0),
              child: Column(
                children: [
                  if (Platform.isWindows) const SizedBox(height: 32),
                  Expanded(
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final audio = ref.read(audioServiceProvider);
                          final playState = snapshot;
                          final isNext = playState.isLastActionNext ?? true;
                          final isVisualizerEnabled =
                              playState.isVisualizerEnabled;

                          return PlaybackHeroCard(
                            isMini: false,
                            isLandscape: isLandscape,
                            isLyricsMode: _isLyricsMode,
                            screenWidth: screenWidth,
                            screenHeight: screenHeight,
                            isNext: isNext,
                            overrideProgress: _isScrubbingProgress
                                ? _scrubProgress
                                : null,
                            overridePosition: _isScrubbingProgress
                                ? Duration(
                                    milliseconds:
                                        (_scrubProgress *
                                                playState
                                                    .duration
                                                    .inMilliseconds)
                                            .round(),
                                  )
                                : null,
                            showVisualizerToggle: isVisualizerEnabled,
                            onShowMoreMenu: () => _showMoreMenu(context, audio),
                            onCyclePlaylistMode: () =>
                                _cyclePlaylistMode(audio),
                            onShowPlaylistModeSelector: () =>
                                _showPlaylistModeSelector(context, audio),
                            onShowRandomModeSelector: () =>
                                _showRandomModeSelector(context, audio),
                            onScrubbing: (val) {
                              _handleInteraction();
                              setState(() {
                                _isScrubbingProgress = true;
                                _scrubProgress = val;
                              });
                            },
                            onSeek: (val) {
                              final target = Duration(
                                milliseconds:
                                    (val * playState.duration.inMilliseconds)
                                        .round(),
                              );
                              setState(() {
                                _isScrubbingProgress = false;
                                _scrubProgress = val;
                              });
                              audio.seek(target);
                            },
                            onToggleVisualizer: () => _toggleVisualizer(audio),
                            onTagCompletionTap: snapshot.currentMusic == null
                                ? null
                                : () => _showSongTagCompletionSheet(
                                    context,
                                    audio,
                                  ),
                            onTagCompletionLongPress:
                                snapshot.currentMusic == null
                                ? null
                                : () => _showTagSaveMenu(context, audio),
                            onEqualizerTap: () => _showEqualizerPanel(context),
                            onCoverTap: _toggleLyricsMode,
                            onPrevious: audio.previous,
                            onPlayPause: audio.togglePlay,
                            onNext: () => toNextMusic(audio),
                            onVolumeTap: () {
                              _handleInteraction();
                              setState(() {
                                _showVolumeSlider = !_showVolumeSlider;
                              });
                            },
                            onVolumeDrag: (delta) {
                              _handleInteraction();
                              _adjustVolumeFromDrag(audio, delta);
                            },
                            onVolumeScroll: (deltaY) {
                              _handleInteraction();
                              _adjustVolumeFromScroll(audio, deltaY);
                            },
                            onCarouselAnimationComplete:
                                _onCarouselAnimationComplete,
                          );
                        },
                      ),
                    ),
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
                if (backgroundType == 1)
                  const Positioned.fill(
                    child: RepaintBoundary(child: DynamicMeshBackground()),
                  )
                else
                  _buildBlurredBackground(context),
                if (!_isLyricsMode) _buildBackgroundScrim(),
                if (shouldDrawVisualizer)
                  _buildVisualizerLayer(context, orientation),
                if (_isLyricsMode) _buildLyricsModeScrim(),
                content,
                if (_showVolumeSlider)
                  Builder(
                    builder: (context) {
                      final volume = ref.watch(
                        audioServiceProvider.select((a) => a.volume),
                      );
                      final audio = ref.read(audioServiceProvider);
                      return VolumeSliderOverlay(
                        volume: volume,
                        onVolumeChanged: (val) {
                          _handleInteraction();
                          audio.setVolume(val.roundToDouble());
                        },
                        onDismiss: () =>
                            setState(() => _showVolumeSlider = false),
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

  Widget _buildBackgroundScrim() {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.20),
              ],
              stops: const [0.1, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsModeScrim() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
      ),
    );
  }

  /// 构建毛玻璃背景组件。
  ///
  /// 该组件实现了当音乐切换或封面更新时，背景图的平滑过渡效果。
  /// 使用 _pendingArtworkBytes，在轮播动画完成后才更新背景。
  Widget _buildBlurredBackground(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: Stack(
          children: [
            // 简化后的背景渲染逻辑：在轮播动画完成后才更新背景。
            // 拿到原始大图后，利用 Image.memory 的 cacheWidth/cacheHeight 属性
            // 在解码阶段即完成缩小，从而替代之前手动生成的低清图逻辑。
            Builder(
              builder: (context) {
                final bytes = _pendingArtworkBytes;
                final Widget content;

                if (bytes == null) {
                  // 如果封面字节尚未准备好（或不存在），则显示纯黑背景。
                  content = Container(
                    key: const ValueKey('bg_empty'),
                    color: Colors.black,
                    width: double.infinity,
                    height: double.infinity,
                  );
                } else {
                  // 使用 Image.memory 的高性能解码缩放：
                  // 通过设置 cacheWidth 或 cacheHeight (200px)，Flutter 会在解码图片时
                  // 就直接生成小尺寸的内存 Buffer，极大降低了内存占用并加速了后续的毛玻璃滤镜运算。
                  // 提高解码分辨率以减少边缘模糊导致的暗角问题
                  final imageProvider = Image.memory(
                    bytes,
                    width: double.infinity,
                    height: double.infinity,
                    cacheWidth: 300, // 提高解码分辨率以减少边缘暗角
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                  );

                  content = ImageFiltered(
                    // 使用字节流的哈希值作为 Key，确保切歌或更换封面时能正确触发平滑过渡动画。
                    key: ValueKey(bytes.hashCode),
                    // 减小模糊强度并增加缩放以更好地覆盖边缘
                    imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                    child: Transform.scale(scale: 1.2, child: imageProvider),
                  );
                }

                // 过渡动画逻辑：新封面直接淡入盖在旧封面之上。
                // 这种方式避免了传统的“双向淡入淡出（Cross-fade）”可能导致的背景短暂变暗或跳动。
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1000),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: content,
                );
              },
            ),
          ],
        ),
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
            final audio = ref.read(audioServiceProvider);
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
                      ? (audio.dynamicStartColor ?? settings.visualizerColor)
                      : settings.visualizerColor,
                  opacity: settings.visualizerOpacity,
                  useGradient: settings.isVisualizerGradientEnabled,
                  startColor: settings.isVisualizerDynamicStartColor
                      ? (audio.dynamicStartColor ??
                            settings.visualizerStartColor)
                      : settings.visualizerStartColor,
                  endColor: settings.isVisualizerDynamicEndColor
                      ? (audio.dynamicEndColor ?? settings.visualizerEndColor)
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
