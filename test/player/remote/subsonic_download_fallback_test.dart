import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/clients/subsonic_client.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';
import 'package:vynody/player/remote/services/remote_download_service.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/sharing/sharing_riverpod.dart';
import 'package:vynody/player/sharing/sharing_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory tempDir;
  _FakePathProviderPlatform(this.tempDir);

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}

/// ScannerService double that never touches platform channels or file scans.
class _StubScannerService extends ScannerService {
  _StubScannerService() : super(autoInitialize: false);

  @override
  Future<RootPathAddResult> addRootPath(String path,
      {String? persistentDocumentId}) async {
    return const RootPathAddResult(RootPathAddStatus.added);
  }
}

/// SharingService double: fixed download folder, always writable.
class _StubSharingService extends SharingService {
  _StubSharingService(super.ref);

  String forcedPath = '';

  @override
  Future<String> getDefaultSharingFolderPath() async => forcedPath;

  @override
  Future<bool> checkSharingFolderWritable([String? pathToCheck]) async => true;
}

/// Minimal Navidrome stand-in:
/// - `/rest/download.view` answers with audio, or with the given error JSON
///   (HTTP 200, mirroring real Subsonic binary endpoints).
/// - `/rest/stream` always serves [audioBytes].
class _FakeNavidrome {
  final HttpServer server;
  final Map<String, dynamic>? downloadError;
  final List<int> audioBytes;
  int downloadHits = 0;
  int streamHits = 0;
  Map<String, String> lastStreamQuery = const {};

  _FakeNavidrome._(this.server, this.downloadError, this.audioBytes);

  static Future<_FakeNavidrome> start({
    Map<String, dynamic>? downloadError,
    required List<int> audioBytes,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeNavidrome._(server, downloadError, audioBytes);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path.endsWith('/download.view')) {
      downloadHits++;
      final body = downloadError == null
          ? audioBytes
          : _errorBody(downloadError!);
      request.response.headers.contentType = downloadError == null
          ? ContentType.binary
          : ContentType.json;
      request.response.add(body);
      unawaited(request.response.close());
      return;
    }
    if (path.endsWith('/stream')) {
      streamHits++;
      lastStreamQuery = Map<String, String>.from(request.uri.queryParameters);
      request.response.headers.contentType = ContentType.binary;
      request.response.add(audioBytes);
      unawaited(request.response.close());
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    unawaited(request.response.close());
  }

  static List<int> _errorBody(Map<String, dynamic> error) {
    final encoder = JsonUtf8Encoder();
    return encoder.convert({
      'subsonic-response': {
        'status': 'failed',
        'version': '1.16.1',
        'type': 'navidrome',
        'serverVersion': '0.63.2 (be10f89c)',
        'openSubsonic': true,
        'error': error,
      },
    });
  }

  Future<void> stop() => server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Valid MP3 frame header bytes so the payload is a plausible audio file.
  final audioBytes = [
    0xFF, 0xFB, 0x90, 0x00, ...List<int>.filled(2048, 0x11),
  ];

  late Directory tempDir;
  late Directory downloadDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('subsonic_dl_fallback_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    downloadDir = Directory('${tempDir.path}/downloads');
    await downloadDir.create(recursive: true);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Builds a container with stubbed settings/sharing/scanner providers and a
  /// fake Navidrome bound to a loopback port.
  Future<(ProviderContainer, _FakeNavidrome, RemoteServer)> bootstrap({
    Map<String, dynamic>? downloadError,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    settings.lanSharingFolderPath = downloadDir.path;

    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWith((ref) => settings),
      sharingServiceProvider.overrideWith((ref) {
        final sharing = _StubSharingService(ref);
        sharing.forcedPath = downloadDir.path;
        return sharing;
      }),
      scannerServiceProvider.overrideWith((ref) => _StubScannerService()),
    ]);

    final fake = await _FakeNavidrome.start(
      downloadError: downloadError,
      audioBytes: audioBytes,
    );
    final server = RemoteServer(
      id: 'srv',
      name: 'Navidrome',
      type: RemoteServerType.subsonic,
      url: 'http://127.0.0.1:${fake.server.port}',
      username: 'alice',
      createdAt: DateTime.now(),
    );
    return (container, fake, server);
  }

  test('parseErrorBody detects code 50 downloads-disabled error', () {
    const body =
        '{"subsonic-response":{"status":"failed","version":"1.16.1","type":"navidrome","serverVersion":"0.63.2 (be10f89c)","openSubsonic":true,"error":{"code":50,"message":"downloads are disabled"}}}';
    final error = SubsonicClient.parseErrorBody(body);
    expect(error, isNotNull);
    expect(error!.code, 50);
    expect(error.isDownloadsDisabled, isTrue);
    expect(error.message, 'downloads are disabled');
  });

  test('parseErrorBody returns null for non-error payloads', () {
    // Binary audio data must never be parsed as an error.
    final binary = String.fromCharCodes(audioBytes.sublist(0, 64));
    expect(SubsonicClient.parseErrorBody(binary), isNull);
    expect(SubsonicClient.parseErrorBody(''), isNull);
    expect(
        SubsonicClient.parseErrorBody('{"subsonic-response":{"status":"ok"}}'),
        isNull);
    expect(SubsonicClient.parseErrorBody('{"unrelated": true}'), isNull);
  });

  test('enqueueSubsonicTrack stores stream fallback URL with maxBitRate=0',
      () async {
    final (container, fake, server) = await bootstrap();
    addTearDown(() async {
      await fake.stop();
      container.dispose();
    });

    final notifier = container.read(remoteDownloadTasksProvider.notifier);
    final song = MusicFile(
      path: 'subsonic://srv/tr_url',
      name: 'Song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );
    final task = await notifier.enqueueSubsonicTrack(
      server: server,
      password: 'pw',
      song: song,
      trackId: 'tr_url',
    );
    expect(task, isNotNull);
    expect(task!.fallbackUrl, isNotNull);
    final uri = Uri.parse(task.fallbackUrl!);
    expect(uri.path, endsWith('/rest/stream'));
    expect(uri.queryParameters['id'], 'tr_url');
    // Absent maxBitRate means the original file is served (no transcode).
    expect(uri.queryParameters.containsKey('maxBitRate'), isFalse);
    // Fallback URL is generated from the enqueue password: auth params exist.
    expect(uri.queryParameters['u'], 'alice');
    expect(uri.queryParameters.containsKey('t'), isTrue);

    // Let the (enabled) download settle before teardown.
    await _waitForStatus(container, task.id, RemoteDownloadStatus.completed);
  });

  test('falls back to stream when download.view returns code 50', () async {
    final (container, fake, server) = await bootstrap(
      downloadError: {'code': 50, 'message': 'downloads are disabled'},
    );
    addTearDown(() async {
      await fake.stop();
      container.dispose();
    });

    final notifier = container.read(remoteDownloadTasksProvider.notifier);
    final song = MusicFile(
      path: 'subsonic://srv/tr_50',
      name: 'Song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );
    final task = await notifier.enqueueSubsonicTrack(
      server: server,
      password: 'pw',
      song: song,
      trackId: 'tr_50',
    );
    expect(task, isNotNull);

    await _waitForStatus(container, task!.id, RemoteDownloadStatus.completed);

    expect(fake.downloadHits, 1);
    expect(fake.streamHits, 1);
    expect(fake.lastStreamQuery['id'], 'tr_50');
    // Absent maxBitRate means the original file is served (no transcode).
    expect(fake.lastStreamQuery.containsKey('maxBitRate'), isFalse);

    // Saved file must be the stream payload, not the JSON error body.
    final saved = File(task.targetPath);
    expect(saved.existsSync(), isTrue);
    final bytes = saved.readAsBytesSync();
    expect(bytes.length, audioBytes.length);
    expect(bytes[0], 0xFF);
    expect(bytes[1], 0xFB);

    final finalTask = _findTask(container, task.id);
    expect(finalTask.status, RemoteDownloadStatus.completed);
    expect(finalTask.error, isNull);
  });

  test('code 40 error fails the task without stream fallback', () async {
    final (container, fake, server) = await bootstrap(
      downloadError: {'code': 40, 'message': 'Wrong username or password'},
    );
    addTearDown(() async {
      await fake.stop();
      container.dispose();
    });

    final notifier = container.read(remoteDownloadTasksProvider.notifier);
    final song = MusicFile(
      path: 'subsonic://srv/tr_40',
      name: 'Song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );
    final task = await notifier.enqueueSubsonicTrack(
      server: server,
      password: 'pw',
      song: song,
      trackId: 'tr_40',
    );
    expect(task, isNotNull);

    await _waitForStatus(container, task!.id, RemoteDownloadStatus.failed);

    expect(fake.downloadHits, 1);
    expect(fake.streamHits, 0);

    final finalTask = _findTask(container, task.id);
    expect(finalTask.error, contains('Wrong username or password'));

    // Error payload must not be saved as an audio file.
    expect(File(task.targetPath).existsSync(), isFalse);
  });

  test('completes via download.view when downloads are enabled', () async {
    final (container, fake, server) = await bootstrap();
    addTearDown(() async {
      await fake.stop();
      container.dispose();
    });

    final notifier = container.read(remoteDownloadTasksProvider.notifier);
    final song = MusicFile(
      path: 'subsonic://srv/tr_ok',
      name: 'Song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );
    final task = await notifier.enqueueSubsonicTrack(
      server: server,
      password: 'pw',
      song: song,
      trackId: 'tr_ok',
    );
    expect(task, isNotNull);

    await _waitForStatus(container, task!.id, RemoteDownloadStatus.completed);

    expect(fake.downloadHits, 1);
    expect(fake.streamHits, 0);
    final saved = File(task.targetPath);
    expect(saved.existsSync(), isTrue);
    expect(saved.readAsBytesSync().length, audioBytes.length);
  });

  test('temporary remote download falls back to binary stream', () async {
    final (container, fake, server) = await bootstrap(
      downloadError: {'code': 50, 'message': 'downloads are disabled'},
    );
    addTearDown(() async {
      await fake.stop();
      container.dispose();
    });

    final prefs = await SharedPreferences.getInstance();
    final storage = RemoteServerStorage(prefs: prefs);
    await storage.saveServers([server]);
    await storage.savePassword(server.id, 'pw');
    final resolver = RemoteMediaResolver(storage: storage);
    final song = MusicFile(
      path: 'subsonic://srv/tr_temp',
      name: 'Song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );

    final file = await resolver.downloadRemoteTrackToTempFile(song);
    expect(file.readAsBytesSync(), audioBytes);
    expect(fake.downloadHits, 1);
    expect(fake.streamHits, 1);
  });

  test('temporary remote download cleans failed resolver work', () async {
    final (container, fake, server) = await bootstrap(
      downloadError: {'code': 40, 'message': 'Wrong username or password'},
    );
    addTearDown(() async {
      await fake.stop();
      container.dispose();
    });

    final prefs = await SharedPreferences.getInstance();
    final storage = RemoteServerStorage(prefs: prefs);
    await storage.saveServers([server]);
    await storage.savePassword(server.id, 'pw');
    final resolver = RemoteMediaResolver(storage: storage);
    final song = MusicFile(
      path: 'subsonic://srv/tr_temp_error',
      name: 'Song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
    );

    await expectLater(
      resolver.downloadRemoteTrackToTempFile(song),
      throwsA(isA<SubsonicException>()),
    );
    final transcodeTempDir = Directory('${tempDir.path}/transcode_temp');
    expect(transcodeTempDir.existsSync(), isFalse);
  });

}

RemoteDownloadTask _findTask(ProviderContainer container, String id) {
  final tasks = container.read(remoteDownloadTasksProvider);
  for (final t in tasks) {
    if (t.id == id) return t;
  }
  fail('Task $id not found in state');
}

Future<void> _waitForStatus(
  ProviderContainer container,
  String taskId,
  RemoteDownloadStatus status,
) async {
  for (var i = 0; i < 600; i++) {
    final tasks = container.read(remoteDownloadTasksProvider);
    if (tasks.any((t) => t.id == taskId && t.status == status)) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final t = _findTask(container, taskId);
  fail('Expected status $status for $taskId, got ${t.status} (error: ${t.error})');
}
