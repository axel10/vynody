import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/lastfm/lastfm_api_client.dart';
import 'package:vynody/player/lastfm/lastfm_auth_service.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_entry.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/secure_storage.dart';

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

class _NowPlayingCall {
  const _NowPlayingCall(this.sessionKey, this.entry);

  final String sessionKey;
  final LastFmScrobbleEntry entry;
}

class _ScrobbleCall {
  const _ScrobbleCall(this.sessionKey, this.entries);

  final String sessionKey;
  final List<LastFmScrobbleEntry> entries;
}

class _FakeLastFmApiClient extends Fake implements LastFmApiClient {
  bool configured = true;
  String tokenToReturn = 'req-token-1';
  LastFmSession sessionToReturn = const LastFmSession(
    key: 'sk-valid-1',
    username: 'vynody_user',
  );

  final List<_NowPlayingCall> nowPlayingCalls = [];
  final List<_ScrobbleCall> scrobbleCalls = [];

  Future<LastFmScrobbleAck> Function(
    String sessionKey,
    List<LastFmScrobbleEntry> entries,
  )?
  scrobbleHandler;

  Future<void> Function(String sessionKey, LastFmScrobbleEntry entry)?
  nowPlayingHandler;

  @override
  bool get isConfigured => configured;

  @override
  Future<String> fetchAuthToken() async => tokenToReturn;

  @override
  Uri buildAuthorizationUri(String token) =>
      Uri.parse('https://www.last.fm/api/auth/?api_key=test&token=$token');

  @override
  Future<LastFmSession> fetchSession(String token) async => sessionToReturn;

  @override
  Future<void> updateNowPlaying({
    required String sessionKey,
    required LastFmScrobbleEntry entry,
  }) async {
    nowPlayingCalls.add(_NowPlayingCall(sessionKey, entry));
    if (nowPlayingHandler != null) {
      await nowPlayingHandler!(sessionKey, entry);
    }
  }

  @override
  Future<LastFmScrobbleAck> scrobble({
    required String sessionKey,
    required List<LastFmScrobbleEntry> entries,
  }) async {
    scrobbleCalls.add(_ScrobbleCall(sessionKey, List.of(entries)));
    if (scrobbleHandler != null) {
      return scrobbleHandler!(sessionKey, entries);
    }
    return LastFmScrobbleAck(accepted: entries.length, ignored: 0);
  }
}

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _clearScrobbleQueue(MetadataDatabase db) async {
  while (true) {
    final rows = await db.takePendingScrobbles(limit: 500);
    if (rows.isEmpty) break;
    await db.deleteScrobbles(rows.map((r) => r.id));
  }
}

void _driveContinuousPlayback(
  LastFmScrobbleService service,
  MusicFile song, {
  Duration totalDuration = const Duration(seconds: 60),
  Duration reach = const Duration(seconds: 34),
}) {
  for (var sec = 0; sec <= reach.inSeconds; sec += 2) {
    service.onPositionUpdate(
      song: song,
      position: Duration(seconds: sec),
      isPlaying: true,
      duration: totalDuration,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late MetadataDatabase db;
  late _FakeLastFmApiClient fakeClient;
  late SettingsService settings;
  late AppSecureStorage secureStorage;
  late LastFmAuthService auth;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('lastfm_svc_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(supportDir.path);
    db = MetadataDatabase();
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      if (await supportDir.exists()) {
        await supportDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    settings.lastFmScrobblingEnabled = true;
    settings.lastFmScrobbleRemote = false;

    secureStorage = AppSecureStorage(prefs);
    fakeClient = _FakeLastFmApiClient();
    auth = LastFmAuthService(client: fakeClient, storage: secureStorage);
    await _clearScrobbleQueue(db);
  });

  tearDown(() async {
    await _clearScrobbleQueue(db);
  });

  group('LastFmAuthService', () {
    test('beginAuthorization fetches token and builds authorization Uri', () async {
      fakeClient.tokenToReturn = 'abc-token';

      final req = await auth.beginAuthorization();

      expect(req.token, 'abc-token');
      expect(
        req.authorizationUri.toString(),
        'https://www.last.fm/api/auth/?api_key=test&token=abc-token',
      );
    });

    test('completeAuthorization persists session to secure storage and caches it', () async {
      fakeClient.sessionToReturn = const LastFmSession(
        key: 'sk-123',
        username: 'alice',
      );

      final session = await auth.completeAuthorization('tok-1');

      expect(session.key, 'sk-123');
      expect(session.username, 'alice');
      expect(auth.cachedSession?.key, 'sk-123');
      expect(
        await secureStorage.read(key: LastFmAuthService.sessionKeyStorageKey),
        'sk-123',
      );
      expect(
        await secureStorage.read(key: LastFmAuthService.usernameStorageKey),
        'alice',
      );
    });

    test('loadSession respects cache and forceReload', () async {
      expect(await auth.loadSession(), isNull);

      await secureStorage.write(
        key: LastFmAuthService.sessionKeyStorageKey,
        value: 'sk-stored',
      );
      await secureStorage.write(
        key: LastFmAuthService.usernameStorageKey,
        value: 'bob',
      );

      // Without forceReload, initial auth instance returns cached null;
      // a fresh instance reads from secure storage and caches it.
      expect(await auth.loadSession(), isNull);
      final freshAuth = LastFmAuthService(
        client: fakeClient,
        storage: secureStorage,
      );
      final loaded = await freshAuth.loadSession();
      expect(loaded?.key, 'sk-stored');
      expect(loaded?.username, 'bob');

      // Overwrite storage directly; without forceReload it returns cached copy.
      await secureStorage.write(
        key: LastFmAuthService.usernameStorageKey,
        value: 'bob-updated',
      );
      expect((await freshAuth.loadSession())?.username, 'bob');

      final reloaded = await freshAuth.loadSession(forceReload: true);
      expect(reloaded?.username, 'bob-updated');
    });

    test('signOut and invalidateSession clear cached and stored credentials', () async {
      await auth.completeAuthorization('tok');
      expect(auth.cachedSession, isNotNull);

      await auth.signOut();
      expect(auth.cachedSession, isNull);
      expect(
        await secureStorage.read(key: LastFmAuthService.sessionKeyStorageKey),
        isNull,
      );
      expect(
        await secureStorage.read(key: LastFmAuthService.usernameStorageKey),
        isNull,
      );

      await auth.completeAuthorization('tok-2');
      await auth.invalidateSession();
      expect(auth.cachedSession, isNull);
      expect(
        await secureStorage.read(key: LastFmAuthService.sessionKeyStorageKey),
        isNull,
      );
    });
  });

  group('LastFmScrobbleService', () {
    const localSong = MusicFile(
      path: '/music/test_track.flac',
      name: 'test_track.flac',
      title: 'Test Track',
      artist: 'Test Artist',
      album: 'Test Album',
      durationMillis: 60000,
    );

    const secondLocalSong = MusicFile(
      path: '/music/second_track.flac',
      name: 'second_track.flac',
      title: 'Second Track',
      artist: 'Second Artist',
      durationMillis: 60000,
    );

    const remoteSong = MusicFile(
      path: 'webdav://srv1/Music/remote_track.mp3',
      name: 'remote_track.mp3',
      title: 'Remote Track',
      artist: 'Remote Artist',
      durationMillis: 60000,
    );

    test('skips updates when scrobbling disabled or client unconfigured', () async {
      await auth.completeAuthorization('tok');

      settings.lastFmScrobblingEnabled = false;
      final service = LastFmScrobbleService(
        client: fakeClient,
        auth: auth,
        settings: settings,
        database: db,
      );

      _driveContinuousPlayback(service, localSong);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fakeClient.nowPlayingCalls, isEmpty);
      expect(fakeClient.scrobbleCalls, isEmpty);
      expect(await db.countPendingScrobbles(), 0);

      settings.lastFmScrobblingEnabled = true;
      fakeClient.configured = false;
      expect(service.isAvailable, isFalse);

      _driveContinuousPlayback(service, localSong);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fakeClient.nowPlayingCalls, isEmpty);
      expect(fakeClient.scrobbleCalls, isEmpty);
    });

    test('respects lastFmScrobbleRemote setting for remote songs', () async {
      await auth.completeAuthorization('tok');
      final service = LastFmScrobbleService(
        client: fakeClient,
        auth: auth,
        settings: settings,
        database: db,
      );

      settings.lastFmScrobbleRemote = false;
      _driveContinuousPlayback(service, remoteSong);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(fakeClient.nowPlayingCalls, isEmpty);
      expect(fakeClient.scrobbleCalls, isEmpty);

      settings.lastFmScrobbleRemote = true;
      _driveContinuousPlayback(service, remoteSong);
      await _waitUntil(() => fakeClient.scrobbleCalls.length == 1);

      expect(fakeClient.nowPlayingCalls, hasLength(1));
      expect(fakeClient.scrobbleCalls.single.entries.single.track, 'Remote Track');
    });

    test('throttles duplicate updateNowPlaying within 10s but fires for new song', () async {
      await auth.completeAuthorization('tok');
      final service = LastFmScrobbleService(
        client: fakeClient,
        auth: auth,
        settings: settings,
        database: db,
      );

      service.onPositionUpdate(
        song: localSong,
        position: const Duration(seconds: 1),
        isPlaying: true,
        duration: const Duration(seconds: 60),
      );
      service.onPositionUpdate(
        song: localSong,
        position: const Duration(seconds: 3),
        isPlaying: true,
        duration: const Duration(seconds: 60),
      );
      await _waitUntil(() => fakeClient.nowPlayingCalls.length == 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(fakeClient.nowPlayingCalls, hasLength(1));

      service.onPositionUpdate(
        song: secondLocalSong,
        position: const Duration(seconds: 1),
        isPlaying: true,
        duration: const Duration(seconds: 60),
      );
      await _waitUntil(() => fakeClient.nowPlayingCalls.length == 2);
      expect(fakeClient.nowPlayingCalls.last.entry.track, 'Second Track');
    });

    test('enqueues reached scrobble, flushes successfully, and deletes queue entry', () async {
      await auth.completeAuthorization('tok');
      final service = LastFmScrobbleService(
        client: fakeClient,
        auth: auth,
        settings: settings,
        database: db,
      );

      _driveContinuousPlayback(service, localSong);

      await _waitUntil(() => fakeClient.scrobbleCalls.length == 1);
      await _waitUntil(() => service.pendingCount.value == 0);

      expect(fakeClient.scrobbleCalls.single.sessionKey, 'sk-valid-1');
      expect(fakeClient.scrobbleCalls.single.entries.single.artist, 'Test Artist');
      expect(fakeClient.scrobbleCalls.single.entries.single.track, 'Test Track');
      expect(service.lastScrobbleAt.value, isNotNull);
      expect(service.lastError.value, isNull);
      expect(await db.countPendingScrobbles(), 0);
    });

    test('Error 9 (invalid session) invalidates session and clears queued batch', () async {
      await auth.completeAuthorization('tok');
      final firstFlushTried = Completer<void>();
      fakeClient.scrobbleHandler = (_, _) async {
        if (!firstFlushTried.isCompleted) firstFlushTried.complete();
        throw const LastFmApiException(
          code: 9,
          message: 'Invalid session key - Please re-authenticate',
        );
      };

      final service = LastFmScrobbleService(
        client: fakeClient,
        auth: auth,
        settings: settings,
        database: db,
      );

      _driveContinuousPlayback(service, localSong);
      await firstFlushTried.future;
      await _waitUntil(() => auth.cachedSession == null);
      await _waitUntil(() => service.pendingCount.value == 0);

      expect(
        await secureStorage.read(key: LastFmAuthService.sessionKeyStorageKey),
        isNull,
      );
      expect(await db.countPendingScrobbles(), 0);
      expect(service.lastError.value, isNotNull);
    });

    test('retryable error increments attempts and flushes cleanly once recovered', () async {
      await auth.completeAuthorization('tok');
      var shouldFail = true;
      final firstAttempt = Completer<void>();
      fakeClient.scrobbleHandler = (_, entries) async {
        if (shouldFail) {
          if (!firstAttempt.isCompleted) firstAttempt.complete();
          throw const LastFmApiException(
            code: 16,
            message: 'The service is temporarily unavailable',
          );
        }
        return LastFmScrobbleAck(accepted: entries.length, ignored: 0);
      };

      final service = LastFmScrobbleService(
        client: fakeClient,
        auth: auth,
        settings: settings,
        database: db,
      );

      _driveContinuousPlayback(service, localSong);
      await firstAttempt.future;
      await _waitUntil(() => service.lastError.value != null);

      final pendingAfterFail = await db.takePendingScrobbles();
      expect(pendingAfterFail, hasLength(1));
      expect(pendingAfterFail.single.attempts, 1);
      expect(
        pendingAfterFail.single.lastError,
        'The service is temporarily unavailable',
      );

      shouldFail = false;
      await service.flush();

      expect(await db.countPendingScrobbles(), 0);
      expect(service.pendingCount.value, 0);
      expect(service.lastError.value, isNull);
      expect(service.lastScrobbleAt.value, isNotNull);
    });
  });
}
