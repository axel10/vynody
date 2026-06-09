import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:vibe_flow/player/audio/audio_service.dart';
import 'package:vibe_flow/player/audio/audio_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/metadata/acoustid_service.dart';
import 'package:vibe_flow/player/metadata/metadata_database.dart';
import 'package:vibe_flow/player/ai/ai_api_key_service.dart';
import 'package:vibe_flow/player/ai/lyrics_model_catalog_service.dart';
import 'package:vibe_flow/player/ai/openrouter_api_key_service.dart';
import 'package:vibe_flow/player/library/playlist_service.dart';
import 'package:vibe_flow/player/scanner/scanner_service.dart';
import 'package:vibe_flow/player/settings/settings_service.dart';

final settingsServiceProvider = ChangeNotifierProvider<SettingsService>((ref) {
  throw UnimplementedError(
    'settingsServiceProvider must be overridden before use',
  );
});

final audioServiceStateProvider = NotifierProvider<AudioService, AudioSnapshot>(
  AudioService.new,
);

final audioServiceProvider = Provider<AudioService>((ref) {
  return ref.read(audioServiceStateProvider.notifier);
});

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
  final audio = ref.watch(audioServiceProvider);
  final scanner = ref.watch(scannerServiceProvider);
  final playlist = ref.watch(playlistServiceProvider);
  audio.setScannerService(scanner);
  audio.setPlaylistService(playlist);
  scanner.setPlayerController(audio.playbackController);
  scanner.setSongMissingStateHandler((path, isMissing) {
    audio.setSongMissingStateByPath(path, isMissing);
    playlist.setSongMissingStateByPath(path, isMissing);
  });
});

final audioSnapshotProvider = Provider<AudioSnapshot>((ref) {
  return ref.watch(audioServiceStateProvider);
});

final audioCurrentMusicProvider = Provider<MusicFile?>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.currentMusic),
  );
});

final audioPlaybackQueueProvider = Provider<List<MusicFile>>((ref) {
  return ref.watch(
    audioSnapshotProvider.select((snapshot) => snapshot.playbackQueue),
  );
});

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

final audioPlaybackModeProvider = Provider<PlaylistMode>((ref) {
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
