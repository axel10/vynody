import 'dart:convert';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';

/// 转码 / AI 歌词走的 `downloadRemoteTrackToTempFile` 有两条分支：
///  1. 命中 `AudioStreamCacheManager`（播放时的预取缓存）→ 直接拷贝本地文件；
///  2. 未命中 → 按协议现建下载 URL。
///
/// 曾经第 2 条分支只认 Subsonic，其余全落到 `WebDavClient`：Jellyfin 的曲目 id
/// 被当成 WebDAV 相对路径，拼出 `http://host/<trackId>`，必然 404。实机看起来
/// 「正常」是因为第 1 条分支先接住了（默认 `remotePrefetchCount = 2`，播过的
/// 曲目都有缓存）。这组用例把两条分支都钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 合法 MP3 帧头，避免被 RemotePayloadGuard 当成非媒体载荷。
  final audioBytes = <int>[
    0xFF, 0xFB, 0x90, 0x00,
    ...List<int>.filled(2048, 0x11),
  ];

  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vynody_jf_tmp_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<({RemoteServer server, RemoteServerStorage storage})> bootstrap(
    int port,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final server = RemoteServer(
      id: 'srvjf',
      name: 'Jellyfin',
      type: RemoteServerType.jellyfin,
      url: 'http://127.0.0.1:$port',
      username: 'alice',
      createdAt: DateTime.now(),
    );
    final storage = RemoteServerStorage(prefs: prefs);
    await storage.saveServers([server]);
    await storage.savePassword(server.id, 'pw');
    return (server: server, storage: storage);
  }

  MusicFile jellyfinSong(String trackId) => MusicFile(
        path: 'jellyfin://srvjf/$trackId',
        name: 'Song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
      );

  test('缓存未命中时，Jellyfin 临时下载走 /Audio/{id}/stream 拿到音频', () async {
    final fake = await _FakeJellyfin.start(audioBytes);
    addTearDown(fake.stop);
    final (:server, :storage) = await bootstrap(fake.server.port);

    final resolver = RemoteMediaResolver(storage: storage);

    final tempFile = await resolver.downloadRemoteTrackToTempFile(
      jellyfinSong('tr_jf_uncached'),
    );
    addTearDown(() async {
      try {
        await tempFile.parent.delete(recursive: true);
      } catch (_) {}
    });

    expect(await tempFile.readAsBytes(), audioBytes);
    // 必须先鉴权拿 token，再拼 stream 地址；而不是把 trackId 拼到 baseUrl 后面。
    expect(fake.authHits, 1);
    expect(fake.streamHits, 1);
    expect(fake.lastBadPath, isNull);
  });

  test('播放缓存命中时直接拷贝本地文件，完全不走网络——实机「正常」的原因', () async {
    final fake = await _FakeJellyfin.start(audioBytes);
    addTearDown(fake.stop);
    final (:server, :storage) = await bootstrap(fake.server.port);

    // 复刻播放预取写入的缓存文件：文件名 = md5('<serverId>:<trackId>')。
    final cacheDir = Directory(p.join(tempDir.path, 'audio_stream_cache'));
    await cacheDir.create(recursive: true);
    const cacheKey = 'srvjf:tr_jf_cached';
    final cacheFile = File(
      p.join(cacheDir.path, '${md5.convert(utf8.encode(cacheKey))}.cache'),
    );
    await cacheFile.writeAsBytes(audioBytes);

    final resolver = RemoteMediaResolver(
      storage: storage,
      cacheManager: AudioStreamCacheManager(customCacheDirectory: cacheDir),
    );

    final tempFile = await resolver.downloadRemoteTrackToTempFile(
      jellyfinSong('tr_jf_cached'),
    );
    addTearDown(() async {
      try {
        await tempFile.parent.delete(recursive: true);
      } catch (_) {}
    });

    expect(await tempFile.readAsBytes(), audioBytes);
    expect(fake.streamHits, 0);
    expect(fake.authHits, 0);
  });
}

/// 极简 Jellyfin：只认 `/Users/AuthenticateByName` 与 `/Audio/{id}/stream`，
/// 其余路径一律 404 —— 这正是 WebDAV 拼出来的 URL 会撞上的结果。
class _FakeJellyfin {
  _FakeJellyfin._(this.server, this.audioBytes);

  final HttpServer server;
  final List<int> audioBytes;
  int streamHits = 0;
  int authHits = 0;
  String? lastBadPath;

  static Future<_FakeJellyfin> start(List<int> audioBytes) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeJellyfin._(server, audioBytes);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'POST' && path.endsWith('/Users/AuthenticateByName')) {
      authHits++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'AccessToken': 'tok123',
        'User': {'Id': 'u1', 'Name': 'alice'},
      }));
      await request.response.close();
      return;
    }
    if (path.startsWith('/Audio/') && path.endsWith('/stream')) {
      streamHits++;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add(audioBytes);
      await request.response.close();
      return;
    }
    lastBadPath = path;
    request.response.statusCode = HttpStatus.notFound;
    request.response.headers.contentType = ContentType.text;
    request.response.write('Not Found');
    await request.response.close();
  }

  Future<void> stop() => server.close(force: true);
}

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}
