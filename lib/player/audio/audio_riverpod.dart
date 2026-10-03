import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/metadata/acoustid_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/ai/ai_api_key_service.dart';
import 'package:vynody/player/ai/lyrics_model_catalog_service.dart';
import 'package:vynody/player/ai/openrouter_api_key_service.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/platform/standalone_queue_window_manager.dart';
import 'package:vynody/utils/device_info_utils.dart';

final settingsServiceProvider = ChangeNotifierProvider<SettingsService>((ref) {
  throw UnimplementedError(
    'settingsServiceProvider must be overridden before use',
  );
});

final _asyncLowMidEndDeviceProvider = FutureProvider<bool>((ref) async {
  return DevicePerformanceHelper.isLowMidEndDevice();
});

final isLowMidEndDeviceProvider = Provider<bool>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return false;
  }
  return ref.watch(_asyncLowMidEndDeviceProvider).asData?.value ?? true;
});

final audioServiceStateProvider = NotifierProvider<AudioService, AudioSnapshot>(
  AudioService.new,
);

final audioServiceProvider = Provider<AudioService>((ref) {
  return ref.read(audioServiceStateProvider.notifier);
});

final isWindowMinimizedProvider = StateProvider<bool>((ref) => false);

final isWindowFullScreenProvider = StateProvider<bool>((ref) => false);

final scannerServiceProvider = ChangeNotifierProvider<ScannerService>((ref) {
  return ScannerService();
});

final playlistServiceProvider = ChangeNotifierProvider<PlaylistService>((ref) {
  return PlaylistService();
});

final geminiApiKeyServiceProvider = Provider<AIApiKeyService>((ref) {
  return AIApiKeyService();
});

final openRouterApiKeyServiceProvider = Provider<OpenRouterApiKeyService>((
  ref,
) {
  return OpenRouterApiKeyService();
});

final lyricsModelCatalogServiceProvider = Provider<LyricsModelCatalogService>((
  ref,
) {
  return LyricsModelCatalogService();
});

final acoustidServiceProvider = Provider<AcoustIDService>((ref) {
  return AcoustIDService(
    apiKey: ref.read(settingsServiceProvider).acoustidApiKey,
  );
});

final audioServiceWiringProvider = Provider<void>((ref) {
  final audio = ref.read(audioServiceProvider);
  final scanner = ref.read(scannerServiceProvider);
  final playlist = ref.read(playlistServiceProvider);
  audio.setScannerService(scanner);
  audio.setPlaylistService(playlist);
  scanner.setPlayerController(audio.playbackController);
  scanner.setSongMissingStateHandler((path, isMissing) {
    audio.setSongMissingStateByPath(path, isMissing);
    playlist.setSongMissingStateByPath(path, isMissing);
  });
  scanner.setSongsPurgedHandler((paths, rootPaths) {
    unawaited(audio.purgeSongsFromQueue(paths: paths, rootPaths: rootPaths));
  });
  ref.read(standaloneQueueWindowManagerProvider);
});

final audioSnapshotProvider = Provider<AudioSnapshot>((ref) {
  return ref.watch(audioServiceStateProvider);
});

final audioCurrentMusicProvider = Provider<MusicFile?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.currentMusic),
  );
});

class AudioPlaybackQueueNotifier extends Notifier<List<MusicFile>> {
  @override
  List<MusicFile> build() {
    ref.listen<AudioSnapshot>(audioSnapshotProvider, (previous, next) {
      if (previous == null ||
          !listEquals(previous.playbackQueue, next.playbackQueue)) {
        state = next.playbackQueue;
      }
    });
    return ref.read(audioSnapshotProvider).playbackQueue;
  }
}

final audioPlaybackQueueProvider =
    NotifierProvider<AudioPlaybackQueueNotifier, List<MusicFile>>(
  AudioPlaybackQueueNotifier.new,
);

final audioRandomHistoryProvider = Provider<List<MusicFile>>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.randomHistory),
  );
});

final audioRandomQueueProvider = Provider<List<MusicFile>>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.randomQueue),
  );
});

final audioCurrentIndexProvider = Provider<int>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.currentIndex),
  );
});

final audioHistoryCursorProvider = Provider<int?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.historyCursor),
  );
});

final audioDeckCursorProvider = Provider<int?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.deckCursor),
  );
});

final audioIsPlayingProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isPlaying),
  );
});

final audioVolumeProvider = Provider<double>((ref) {
  return ref.watch(audioSnapshotProvider.select((snapshot) => snapshot.volume));
});

final audioIsMutedProvider = Provider<bool>((ref) {
  return ref.watch(audioSnapshotProvider.select((snapshot) => snapshot.isMuted));
});

final audioPositionProvider = Provider<Duration>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.position),
  );
});

final audioDurationProvider = Provider<Duration>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.duration),
  );
});

final audioIsRandomModeProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isRandomMode),
  );
});

final audioIsShuffleRandomModeProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isShuffleRandomMode),
  );
});

final audioPlaybackModeProvider = Provider<AppPlaybackMode>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.playbackMode),
  );
});

final audioCurrentThemeColorsMapProvider = Provider<Map<String, Color>>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.currentThemeColorsMap),
  );
});

final audioDynamicStartColorProvider = Provider<Color?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.dynamicStartColor),
  );
});

final audioDynamicEndColorProvider = Provider<Color?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.dynamicEndColor),
  );
});

final audioIsLyricsActiveProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isLyricsActive),
  );
});

final audioHasSleepTimerProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select(
      (snapshot) => snapshot.sleepTimerRemaining != null,
    ),
  );
});

final audioSleepTimerRemainingProvider = Provider<Duration?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.sleepTimerRemaining),
  );
});

final audioSleepTimerDurationProvider = Provider<Duration?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.sleepTimerDuration),
  );
});

final audioProgressProvider = Provider<double>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.progress),
  );
});

final audioIsTransitioningProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isTransitioning),
  );
});

final audioIsBufferingProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isBuffering),
  );
});

final audioLastActionNextProvider = Provider<bool?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isLastActionNext),
  );
});

final audioIsVisualizerEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.isVisualizerEnabled),
  );
});

final audioCurrentVisualizerOptionsProvider =
    Provider<VisualizerOptimizationOptions>((ref) {
      return ref.watch(
        audioSnapshotProvider.select(
          (snapshot) => snapshot.currentVisualizerOptions,
        ),
      );
    });

final songMetadataProvider = StreamProvider.family<SongMetadata?, String>((ref, path) {
  return MetadataDatabase().watchSongMetadata(path);
});

class CurrentAudioDetailsNotifier extends Notifier<AudioDetails?> {
  Timer? _debounceTimer;
  String? _currentPath;
  int? _currentLastModifiedTime;

  static AudioDetails buildFastAudioDetails(MusicFile music) {
    var ext = p.extension(music.path).replaceAll('.', '').toLowerCase();
    if (ext.contains('?')) ext = ext.split('?').first;
    if (ext.isEmpty || ext == 'cache' || ext == 'tmp') {
      ext = p.extension(music.name).replaceAll('.', '').toLowerCase();
      if (ext.contains('?')) ext = ext.split('?').first;
    }
    if (ext == 'cache' || ext == 'tmp') ext = '';
    final formatName = (ext == 'mpeg') ? 'mp3' : (ext == 'mp4' ? 'm4a' : (ext.isNotEmpty ? ext : ''));
    String codecName = formatName;
    if (formatName == 'mp3' || formatName == 'mpeg') {
      codecName = 'mp3';
    } else if (formatName == 'm4a' || formatName == 'mp4') {
      codecName = 'aac';
    }
    final duration = music.durationMillis != null && music.durationMillis! > 0
        ? Duration(milliseconds: music.durationMillis!)
        : Duration.zero;

    return AudioDetails(
      formatName: formatName,
      codecName: codecName,
      duration: duration,
      bitrate: 0,
      sampleRate: 0,
      channels: 0,
      bitrateMode: '',
      fileSize: 0,
    );
  }

  @override
  AudioDetails? build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    final currentMusic = ref.watch(audioCurrentMusicProvider);
    if (currentMusic == null) {
      _currentPath = null;
      _currentLastModifiedTime = null;
      _debounceTimer?.cancel();
      return null;
    }

    // 若同一首歌曲（路径及修改时间未改变），且当前已经持有有效解析结果（无论是 fast 还是 refined），
    // 则直接保留现有状态，避免因后台队列更新（波形/封面/主题色等变更）触发无意义的重置与闪烁
    if (_currentPath == currentMusic.path &&
        _currentLastModifiedTime == currentMusic.lastModifiedTime &&
        state != null) {
      return state;
    }

    _currentPath = currentMusic.path;
    _currentLastModifiedTime = currentMusic.lastModifiedTime;
    _debounceTimer?.cancel();

    final audioService = ref.read(audioServiceProvider);
    final cached = audioService.getCachedAudioDetails(
      currentMusic.path,
      lastModifiedTime: currentMusic.lastModifiedTime,
    );

    // 如果内存缓存已有且包含采样率等精细信息，并且文件修改时间匹配，直接秒开
    if (cached != null && cached.sampleRate > 0) {
      return cached;
    }

    // 优先秒开展示 Fast AudioDetails，完全不走任何 TagLib FFI，0ms 阻塞保证轮播动画丝滑
    final fastDetails = cached ?? buildFastAudioDetails(currentMusic);

    // 延迟 350ms（等待轮播动画结束并防抖用户快速划歌），随后后台异步读取 TagLib 详细信息
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _loadRefinedDetails(currentMusic);
    });

    return fastDetails;
  }

  /// 供外部在轮播动画完成（onCarouselAnimationComplete）时立即唤起深度解析，无需等待剩余防抖时间
  void loadRefinedImmediately() {
    _debounceTimer?.cancel();
    final currentMusic = ref.read(audioCurrentMusicProvider);
    if (currentMusic != null) {
      if (state == null || state?.sampleRate == 0) {
        _loadRefinedDetails(currentMusic);
      }
    }
  }

  Future<void> _loadRefinedDetails(MusicFile music) async {
    final audioService = ref.read(audioServiceProvider);

    final cached = audioService.getCachedAudioDetails(
      music.path,
      lastModifiedTime: music.lastModifiedTime,
    );
    if (cached != null && cached.sampleRate > 0) {
      if (ref.read(audioCurrentMusicProvider)?.path == music.path) {
        state = cached;
      }
      return;
    }

    try {
      final details = await audioService.getAudioDetails(
        path: music.path,
        fallbackMediaUri: music.name,
        forceRefresh: true,
        lastModifiedTime: music.lastModifiedTime,
      );

      var formatName = details.formatName.trim();
      var codecName = details.codecName.trim();
      if (formatName.toLowerCase() == 'cache' || formatName.toLowerCase() == 'tmp') {
        formatName = '';
      }
      if (codecName.toLowerCase() == 'cache' || codecName.toLowerCase() == 'tmp') {
        codecName = '';
      }

      if (formatName.isEmpty || codecName.isEmpty) {
        var ext = p.extension(music.name).replaceAll('.', '').toLowerCase();
        if (ext.contains('?')) ext = ext.split('?').first;
        if (ext == 'cache' || ext == 'tmp') ext = '';
        if (ext.isNotEmpty) {
          if (formatName.isEmpty) {
            formatName = (ext == 'mpeg') ? 'mp3' : (ext == 'mp4' ? 'm4a' : ext);
          }
          if (codecName.isEmpty) {
            if (ext == 'mp3' || ext == 'mpeg') {
              codecName = 'mp3';
            } else if (ext == 'm4a' || ext == 'mp4') {
              codecName = 'aac';
            } else {
              codecName = ext;
            }
          }
        }
      }

      final refined = details.copyWith(
        formatName: formatName,
        codecName: codecName,
      );

      audioService.setCachedAudioDetails(
        music.path,
        refined,
        lastModifiedTime: music.lastModifiedTime,
      );

      // 若从文件读取到的真实时长与数据库记录存在显著差异（>1秒）或数据库缺失时长，以文件为准校准数据库
      if (refined.duration.inMilliseconds > 0) {
        final scanner = ref.read(scannerServiceProvider);
        final existing = scanner.metadataMap[music.path];
        if (existing != null &&
            (existing.duration == null ||
                (existing.duration! - refined.duration.inMilliseconds).abs() > 1000)) {
          final updated = existing.copyWith(
            duration: refined.duration.inMilliseconds,
          );
          unawaited(MetadataDatabase().insertOrUpdateSong(updated));
          scanner.updateMetadataForPath(updated);
        }
      }

      if (ref.read(audioCurrentMusicProvider)?.path == music.path) {
        state = refined;
      }
    } catch (_) {
      // 出错时保持原有 fastDetails，不影响播放
    }
  }
}

final currentAudioDetailsProvider =
    NotifierProvider<CurrentAudioDetailsNotifier, AudioDetails?>(
  CurrentAudioDetailsNotifier.new,
);

String formatAudioSpec(AudioDetails? details) {
  if (details == null) return '';

  final parts = <String>[];

  // 1. Format
  final rawFormat = details.formatName.isNotEmpty
      ? details.formatName
      : details.codecName;
  if (rawFormat.isNotEmpty) {
    parts.add(rawFormat.toUpperCase());
  }

  // 2. Bit depth (e.g. 16bit, 24bit)
  if (details.bitDepth != null && details.bitDepth! > 0) {
    parts.add('${details.bitDepth}bit');
  }

  // 3. Sample rate (e.g. 44.1 kHz, 48 kHz, 96 kHz)
  if (details.sampleRate > 0) {
    final inKhz = details.sampleRate / 1000.0;
    final formattedSr = details.sampleRate % 1000 == 0
        ? inKhz.toInt().toString()
        : inKhz.toStringAsFixed(1);
    parts.add('$formattedSr kHz');
  }

  // 4. Bitrate (e.g. 320 kbps, 1411 kbps)
  if (details.bitrate > 0) {
    final kbps = (details.bitrate / 1000).round();
    parts.add('$kbps kbps');
  }

  return parts.join(' · ');
}
