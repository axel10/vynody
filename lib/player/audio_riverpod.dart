import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'lyrics_riverpod.dart';
import '../models/music_file.dart';
import 'playlist_service.dart';
import 'scanner_service.dart';
import 'settings_service.dart';

final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError(
    'settingsServiceProvider must be overridden before use',
  );
});

final audioServiceProvider = ChangeNotifierProvider<AudioService>((ref) {
  final settingsService = ref.watch(settingsServiceProvider);
  return AudioService(
    settingsService,
    readLyricsController: () => ref.read(lyricsControllerProvider.notifier),
    readLyricsControllerState: () => ref.read(lyricsControllerProvider),
  );
});

final scannerServiceProvider = ChangeNotifierProvider<ScannerService>((ref) {
  return ScannerService();
});

final playlistServiceProvider = ChangeNotifierProvider<PlaylistService>((ref) {
  return PlaylistService();
});

final audioServiceWiringProvider = Provider<void>((ref) {
  final audio = ref.watch(audioServiceProvider);
  final scanner = ref.watch(scannerServiceProvider);
  audio.setScannerService(scanner);
  scanner.setPlayerController(audio.playbackController);
});

final audioCurrentMusicProvider = Provider<MusicFile?>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.currentMusic));
});

final audioPlaybackQueueProvider = Provider<List<MusicFile>>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.playbackQueue));
});

final audioRandomHistoryProvider = Provider<List<MusicFile>>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.randomHistory));
});

final audioRandomQueueProvider = Provider<List<MusicFile>>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.randomQueue));
});

final audioCurrentIndexProvider = Provider<int>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.currentIndex));
});

final audioHistoryCursorProvider = Provider<int?>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.historyCursor));
});

final audioDeckCursorProvider = Provider<int?>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.deckCursor));
});

final audioIsPlayingProvider = Provider<bool>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.isPlaying));
});

final audioVolumeProvider = Provider<double>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.volume));
});

final audioPositionProvider = Provider<Duration>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.position));
});

final audioDurationProvider = Provider<Duration>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.duration));
});

final audioIsRandomModeProvider = Provider<bool>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.isRandomMode));
});

final audioIsShuffleRandomModeProvider = Provider<bool>((ref) {
  return ref.watch(
    audioServiceProvider.select((audio) => audio.isShuffleRandomMode),
  );
});

final audioPlaybackModeProvider = Provider<PlaylistMode>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.playbackMode));
});

final audioCurrentThemeColorsMapProvider = Provider<Map<String, Color>>((ref) {
  return ref.watch(
    audioServiceProvider.select((audio) => audio.currentThemeColorsMap),
  );
});

final audioDynamicStartColorProvider = Provider<Color?>((ref) {
  return ref.watch(
    audioServiceProvider.select((audio) => audio.dynamicStartColor),
  );
});

final audioDynamicEndColorProvider = Provider<Color?>((ref) {
  return ref.watch(
    audioServiceProvider.select((audio) => audio.dynamicEndColor),
  );
});

final audioIsLyricsActiveProvider = Provider<bool>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.isLyricsActive));
});

final audioProgressProvider = Provider<double>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.snapshot.progress));
});

final audioIsTransitioningProvider = Provider<bool>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.isTransitioning));
});

final audioLastActionNextProvider = Provider<bool?>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.isLastActionNext));
});

final audioIsVisualizerEnabledProvider = Provider<bool>((ref) {
  return ref.watch(audioServiceProvider.select((audio) => audio.isVisualizerEnabled));
});
