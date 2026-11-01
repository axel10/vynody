import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/player/audio/audio_riverpod.dart' show settingsServiceProvider;
import 'package:vynody/player/lastfm/lastfm_api_client.dart';
import 'package:vynody/player/lastfm/lastfm_auth_service.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_service.dart';

final lastFmApiClientProvider = Provider<LastFmApiClient>((ref) {
  return LastFmApiClient();
});

final lastFmAuthServiceProvider = Provider<LastFmAuthService>((ref) {
  return LastFmAuthService(client: ref.read(lastFmApiClientProvider));
});

/// 上报服务是单例：状态机、节流窗口、冲刷定时器都必须只有一份。
final lastFmScrobbleServiceProvider = Provider<LastFmScrobbleService>((ref) {
  final service = LastFmScrobbleService(
    client: ref.read(lastFmApiClientProvider),
    auth: ref.read(lastFmAuthServiceProvider),
    settings: ref.read(settingsServiceProvider),
  );
  service.start();
  ref.onDispose(service.dispose);
  return service;
});
