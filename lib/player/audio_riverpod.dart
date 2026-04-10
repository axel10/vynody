import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'audio_service.dart';
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
