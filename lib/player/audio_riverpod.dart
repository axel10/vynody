import 'audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
  return AudioService(settingsService);
});

final scannerServiceProvider = ChangeNotifierProvider<ScannerService>((ref) {
  final scanner = ScannerService();
  final audio = ref.read(audioServiceProvider);
  scanner.setPlayerController(audio.playbackController);
  return scanner;
});

final playlistServiceProvider = ChangeNotifierProvider<PlaylistService>((ref) {
  return PlaylistService();
});
