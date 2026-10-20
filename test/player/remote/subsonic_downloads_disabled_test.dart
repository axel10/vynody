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
import 'package:vynody/player/remote/services/remote_payload_guard.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/sharing/sharing_riverpod.dart';
import 'package:vynody/player/sharing/sharing_service.dart';
import 'package:vynody/utils/localized_text.dart';

/// Navidrome 关闭下载时，`download.view` 仍然回 HTTP 200，只是响应体换成失败
/// JSON（code 50）。这些用例锁住两件事：
///  1. 错误体绝不会被当音频落盘、也不会被标成「已完成」；
///  2. 用户能收到「服务端已关闭下载」的提示（任务错误文案 + Toast）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 合法 MP3 帧头，让「成功」分支拿到一个像音频的载荷。
  final audioBytes = <int>[0xFF, 0xFB, 0x90, 0x00, ...List<int>.filled(2048, 0x11)];

  group('SubsonicClient.parseErrorBody', () {
    test('识别 code 50（服务端关闭下载）', () {
      const body = '{"subsonic-response":{"status":"failed","version":"1.16.1",'
          '"type":"navidrome","error":{"code":50,"message":"downloads are disabled"}}}';
      final error = SubsonicClient.parseErrorBody(body);
      expect(error, isNotNull);
      expect(error!.code, 50);
      expect(error.isDownloadsDisabled, isTrue);
      expect(error.message, 'downloads are disabled');
    });

    test('其它错误码不算「关闭下载」，但同样识别为错误', () {
      const body = '{"subsonic-response":{"status":"failed",'
          '"error":{"code":40,"message":"Wrong username or password"}}}';
      final error = SubsonicClient.parseErrorBody(body);
      expect(error, isNotNull);
      expect(error!.code, 40);
      expect(error.isDownloadsDisabled, isFalse);
    });

    test('正常响应与二进制载荷都不会被误判', () {
      expect(
        SubsonicClient.parseErrorBody('{"subsonic-response":{"status":"ok"}}'),
        isNull,
      );
      expect(SubsonicClient.parseErrorBody('{"unrelated":true}'), isNull);
      expect(SubsonicClient.parseErrorBody(''), isNull);
      expect(SubsonicClient.parseErrorBody('   '), isNull);
      expect(SubsonicClient.parseErrorBody('not json at all'), isNull);
      // 音频字节转成的字符串不应被当成 JSON。
      expect(
        SubsonicClient.parseErrorBody(String.fromCharCodes(audioBytes.sublist(0, 64))),
        isNull,
      );
    });
  });

  group('RemotePayloadGuard 检查已下载的载荷', () {
    test('非法 UTF-8 / 缺失文件当媒体而不是错误页', () async {
      final dir = await Directory.systemTemp.createTemp('vynody_err_file_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/payload.bin');
      await file.writeAsBytes(audioBytes);
      expect(RemotePayloadGuard.inspect(file), isNull);
      expect(RemotePayloadGuard.inspect(null), isNull);
      expect(
        RemotePayloadGuard.inspect(File('${dir.path}/missing')),
        isNull,
      );
    });

    test('读得出错误体并带出 code 50', () async {
      final dir = await Directory.systemTemp.createTemp('vynody_err_file_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/payload.json');
      await file.writeAsString(
        '{"subsonic-response":{"status":"failed","error":{"code":50,"message":"downloads are disabled"}}}',
      );
      expect(RemotePayloadGuard.inspect(file)?.isDownloadsDisabled, isTrue);
    });
  });

  group('RemotePayloadGuard 识别反向代理错误页', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('vynody_payload_');
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<File> writePayload(String name, String body) async {
      final file = File('${dir.path}/$name');
      await file.writeAsString(body);
      return file;
    }

    test('HTML 错误页（响应没带 Content-Type）：按 < 开头判定', () async {
      final file = await writePayload(
        'proxy.html',
        '<!DOCTYPE html>\n<html><body><h1>502 Bad Gateway</h1></body></html>',
      );
      final error = RemotePayloadGuard.inspect(file);
      expect(error, isNotNull);
      expect(error!.code, RemotePayloadGuard.errorNonMediaPayload);
      expect(error.isDownloadsDisabled, isFalse);
    });

    test('几 MB 的 HTML 错误页同样能识别（旧的 64KB 阈值会漏）', () async {
      final file = await writePayload(
        'big.html',
        '<!DOCTYPE html><html><body>${'x' * 300000}</body></html>',
      );
      expect(file.lengthSync(), greaterThan(64 * 1024));
      expect(RemotePayloadGuard.inspect(file), isNotNull);
    });

    test('Content-Type 是 text/html 时，正文不是标记也能识别', () async {
      final file = await writePayload('upstream.txt', 'upstream connect error');
      final error = RemotePayloadGuard.inspect(
        file,
        contentType: 'text/html; charset=utf-8',
      );
      expect(error, isNotNull);
      expect(error!.message, contains('text/html'));
    });

    test('真正的音频即使 Content-Type 是 text/plain 也不误判', () async {
      final file = File('${dir.path}/audio.mp3');
      await file.writeAsBytes(audioBytes);
      expect(
        RemotePayloadGuard.inspect(file, contentType: 'text/plain'),
        isNull,
      );
      // 容器魔数同样放行。
      final flac = File('${dir.path}/audio.flac');
      await flac.writeAsBytes('fLaC'.codeUnits + List<int>.filled(512, 0));
      expect(RemotePayloadGuard.inspect(flac, contentType: 'text/plain'), isNull);
    });

    test('普通二进制不会被误判', () async {
      final file = File('${dir.path}/blob.bin');
      await file.writeAsBytes(List<int>.generate(512, (i) => i % 256));
      expect(RemotePayloadGuard.inspect(file), isNull);
    });

    test('非 Subsonic 协议下 JSON 错误体不被当成 code 50，但仍按非媒体拦下', () async {
      final file = await writePayload(
        'jellyfin.json',
        '{"Message":"Unauthorized"}',
      );
      final error = RemotePayloadGuard.inspect(file, parseSubsonicError: false);
      expect(error, isNotNull);
      expect(error!.code, RemotePayloadGuard.errorNonMediaPayload);
    });
  });

  group('下载队列', () {
    late Directory tempDir;
    late Directory downloadDir;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('vynody_subsonic_dl_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
      downloadDir = Directory('${tempDir.path}/downloads');
      await downloadDir.create(recursive: true);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    Future<({ProviderContainer container, _FakeNavidrome fake, RemoteServer server})>
        bootstrap({
      Map<String, dynamic>? downloadError,
      String? htmlBody,
      int? downloadStatusCode,
      RemoteServerType serverType = RemoteServerType.subsonic,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs)
        ..lanSharingFolderPath = downloadDir.path;

      final container = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          sharingServiceProvider.overrideWith((ref) {
            final sharing = _StubSharingService(ref);
            sharing.forcedPath = downloadDir.path;
            return sharing;
          }),
          scannerServiceProvider.overrideWith((ref) => _StubScannerService()),
        ],
      );

      final fake = await _FakeNavidrome.start(
        downloadError: downloadError,
        audioBytes: audioBytes,
        htmlBody: htmlBody,
        downloadStatusCode: downloadStatusCode,
      );
      final server = RemoteServer(
        id: 'srv',
        name: 'Navidrome',
        type: serverType,
        url: 'http://127.0.0.1:${fake.server.port}',
        username: 'alice',
        createdAt: DateTime.now(),
      );
      return (container: container, fake: fake, server: server);
    }

    MusicFile song(String id, {String scheme = 'subsonic'}) => MusicFile(
          path: '$scheme://srv/$id',
          name: 'Song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          trackNumber: 1,
        );

    test('code 50：任务失败、错误文案为「服务端已关闭下载」、错误体不落盘', () async {
      final (:container, :fake, :server) = await bootstrap(
        downloadError: {'code': 50, 'message': 'downloads are disabled'},
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_50')],
        ),
      );
      expect(tasks, hasLength(1));

      final finished =
          await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.failed);
      expect(finished.error, currentAppL10n.remoteServerDownloadsDisabled);

      // 目标文件绝不能出现——否则音乐库里会多出一首 200 字节的「坏歌」。
      expect(File(finished.targetPath).existsSync(), isFalse);
      expect(fake.downloadHits, 1);
    });

    test('其它错误码：任务失败，错误体同样不落盘', () async {
      final (:container, :fake, :server) = await bootstrap(
        downloadError: {'code': 40, 'message': 'Wrong username or password'},
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_40')],
        ),
      );

      final finished = await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.failed);
      expect(finished.error, contains('Wrong username or password'));
      expect(File(finished.targetPath).existsSync(), isFalse);
    });

    test('反向代理回 HTML 错误页：任务失败、网页不落盘', () async {
      final (:container, :fake, :server) = await bootstrap(
        htmlBody:
            '<!DOCTYPE html><html><body><h1>502 Bad Gateway</h1></body></html>',
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_html')],
        ),
      );

      final finished = await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.failed);
      expect(finished.error, currentAppL10n.remoteDownloadNotAudioResponse);
      expect(File(finished.targetPath).existsSync(), isFalse);
      expect(fake.downloadHits, 1);
    });

    // Jellyfin 的下载走 /Audio/{id}/stream，不受用户策略里的「允许下载」约束，
    // 因此不存在 code 50 那种「200 + 失败 JSON」；它拒绝时用标准状态码。
    test('Jellyfin 正常下载：走 stream 拿到原始音频', () async {
      final (:container, :fake, :server) = await bootstrap(
        serverType: RemoteServerType.jellyfin,
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_jf_ok', scheme: 'jellyfin')],
        ),
      );

      final finished = await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.completed);
      expect(File(finished.targetPath).readAsBytesSync(), audioBytes);
      expect(fake.downloadHits, 1);
    });

    test('Jellyfin 拒绝下载（403）：任务失败、文案指向权限、不落盘', () async {
      final (:container, :fake, :server) = await bootstrap(
        serverType: RemoteServerType.jellyfin,
        downloadStatusCode: HttpStatus.forbidden,
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_jf_403', scheme: 'jellyfin')],
        ),
      );

      final finished = await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.failed);
      expect(finished.error, currentAppL10n.remoteDownloadUnauthorized);
      expect(File(finished.targetPath).existsSync(), isFalse);
    });

    test('Jellyfin 曲目已不存在（404）：任务失败并说明原因', () async {
      final (:container, :fake, :server) = await bootstrap(
        serverType: RemoteServerType.jellyfin,
        downloadStatusCode: HttpStatus.notFound,
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_jf_404', scheme: 'jellyfin')],
        ),
      );

      final finished = await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.failed);
      expect(finished.error, currentAppL10n.remoteDownloadTrackMissing);
      expect(File(finished.targetPath).existsSync(), isFalse);
    });

    test('服务端允许下载时行为不变', () async {
      final (:container, :fake, :server) = await bootstrap();
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_ok')],
        ),
      );

      final finished = await _waitForTerminal(container, tasks.single.id);
      expect(finished.status, RemoteDownloadStatus.completed);
      final saved = File(finished.targetPath);
      expect(saved.existsSync(), isTrue);
      expect(saved.readAsBytesSync(), audioBytes);
      expect(fake.downloadHits, 1);
    });

    test('批量下载：同服务器只提示一次，其余任务照常失败', () async {
      final (:container, :fake, :server) = await bootstrap(
        downloadError: {'code': 50, 'message': 'downloads are disabled'},
      );
      addTearDown(() async {
        await fake.stop();
        container.dispose();
      });

      final notifier = container.read(remoteDownloadTasksProvider.notifier);
      final tasks = await notifier.enqueue(
        RemoteDownloadRequest(
          server: server,
          password: 'pw',
          songs: [song('tr_a'), song('tr_b')],
        ),
      );
      expect(tasks, hasLength(2));
      for (final task in tasks) {
        final finished = await _waitForTerminal(container, task.id);
        expect(finished.status, RemoteDownloadStatus.failed);
      }
      expect(fake.downloadHits, 2);
    });
  });

  group('转码 / AI 分析用的临时下载', () {
    late Directory tempDir;
    late Directory downloadDir;

    setUp(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('vynody_subsonic_tmp_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
      downloadDir = Directory('${tempDir.path}/downloads');
      await downloadDir.create(recursive: true);
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    Future<({RemoteMediaResolver resolver, _FakeNavidrome fake, RemoteServer server})>
        bootstrap({
      Map<String, dynamic>? downloadError,
      String? htmlBody,
      int? downloadStatusCode,
      RemoteServerType serverType = RemoteServerType.subsonic,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final fake = await _FakeNavidrome.start(
        downloadError: downloadError,
        audioBytes: audioBytes,
        htmlBody: htmlBody,
        downloadStatusCode: downloadStatusCode,
      );
      final server = RemoteServer(
        id: 'srv',
        name: 'Navidrome',
        type: serverType,
        url: 'http://127.0.0.1:${fake.server.port}',
        username: 'alice',
        createdAt: DateTime.now(),
      );
      final storage = RemoteServerStorage(prefs: prefs);
      await storage.saveServers([server]);
      await storage.savePassword(server.id, 'pw');
      return (
        resolver: RemoteMediaResolver(storage: storage),
        fake: fake,
        server: server,
      );
    }

    test('code 50 直接抛出 SubsonicException，并清掉临时目录', () async {
      final (:resolver, :fake, :server) = await bootstrap(
        downloadError: {'code': 50, 'message': 'downloads are disabled'},
      );
      addTearDown(fake.stop);

      final musicFile = MusicFile(
        path: 'subsonic://srv/tr_tmp',
        name: 'Song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
      );

      await expectLater(
        resolver.downloadRemoteTrackToTempFile(musicFile),
        throwsA(
          isA<SubsonicException>()
              .having((e) => e.isDownloadsDisabled, 'isDownloadsDisabled', isTrue),
        ),
      );

      // 临时目录必须清干净，否则 JSON 会留在 transcode_temp 里。
      final transcodeRoot = Directory('${tempDir.path}/transcode_temp');
      final leftover = await transcodeRoot.exists()
          ? await transcodeRoot.list().toList()
          : <FileSystemEntity>[];
      expect(leftover, isEmpty);
    });

    test('反向代理回 HTML 错误页：抛 RemotePayloadException 并清掉临时目录', () async {
      final (:resolver, :fake, :server) = await bootstrap(
        htmlBody:
            '<!DOCTYPE html><html><body><h1>502 Bad Gateway</h1></body></html>',
      );
      addTearDown(fake.stop);

      final musicFile = MusicFile(
        path: 'subsonic://srv/tr_tmp_html',
        name: 'Song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
      );

      await expectLater(
        resolver.downloadRemoteTrackToTempFile(musicFile),
        throwsA(
          isA<RemotePayloadException>().having(
            (e) => e.code,
            'code',
            RemotePayloadGuard.errorNonMediaPayload,
          ),
        ),
      );

      final transcodeRoot = Directory('${tempDir.path}/transcode_temp');
      final leftover = await transcodeRoot.exists()
          ? await transcodeRoot.list().toList()
          : <FileSystemEntity>[];
      expect(leftover, isEmpty);
    });

    test('服务端允许下载时返回真实音频', () async {
      final (:resolver, :fake, :server) = await bootstrap();
      addTearDown(fake.stop);

      final file = await resolver.downloadRemoteTrackToTempFile(
        MusicFile(
          path: 'subsonic://srv/tr_tmp_ok',
          name: 'Song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
        ),
      );
      expect(file.readAsBytesSync(), audioBytes);
    });
  });
}

RemoteDownloadTask _findTask(ProviderContainer container, String id) =>
    container.read(remoteDownloadTasksProvider).firstWhere((t) => t.id == id);

/// 等到任务进入终态（完成 / 失败 / 取消）。
Future<RemoteDownloadTask> _waitForTerminal(
  ProviderContainer container,
  String id,
) async {
  for (var i = 0; i < 600; i++) {
    final task = _findTask(container, id);
    if (task.status == RemoteDownloadStatus.completed ||
        task.status == RemoteDownloadStatus.failed ||
        task.status == RemoteDownloadStatus.cancelled) {
      return task;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  final stuck = _findTask(container, id);
  fail('Task $id stuck in ${stuck.status} (error: ${stuck.error})');
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

/// 不碰平台通道 / 真实文件扫描的 ScannerService 替身。
class _StubScannerService extends ScannerService {
  _StubScannerService() : super(autoInitialize: false);

  @override
  Future<RootPathAddResult> addRootPath(
    String path, {
    String? persistentDocumentId,
  }) async {
    return const RootPathAddResult(RootPathAddStatus.added);
  }
}

/// 固定下载目录、永远可写的 SharingService 替身。
class _StubSharingService extends SharingService {
  _StubSharingService(super.ref);

  String forcedPath = '';

  @override
  Future<String> getDefaultSharingFolderPath() async => forcedPath;

  @override
  Future<bool> checkSharingFolderWritable([String? pathToCheck]) async => true;
}

/// 极简 Navidrome：`/rest/download.view` 要么回音频，要么回「HTTP 200 + 失败
/// JSON」——后者正是真实服务端关闭下载时的表现；[htmlBody] 用来模拟反向代理
/// 自己返回的 200 错误页。
class _FakeNavidrome {
  _FakeNavidrome._(
    this.server,
    this.downloadError,
    this.audioBytes,
    this.htmlBody,
    this.downloadStatusCode,
  );

  final HttpServer server;
  final Map<String, dynamic>? downloadError;
  final List<int> audioBytes;
  final String? htmlBody;

  /// 非空时下载端点直接回该状态码（Jellyfin 的拒绝方式）。
  final int? downloadStatusCode;
  int downloadHits = 0;

  static Future<_FakeNavidrome> start({
    Map<String, dynamic>? downloadError,
    required List<int> audioBytes,
    String? htmlBody,
    int? downloadStatusCode,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeNavidrome._(
      server,
      downloadError,
      audioBytes,
      htmlBody,
      downloadStatusCode,
    );
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;

    // Jellyfin 鉴权：下载 URL 里的 api_key 来自这里。
    if (path == '/Users/AuthenticateByName') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'AccessToken': 'tok',
        'ServerId': 'srv-jellyfin',
        'User': {'Id': 'user-1', 'Name': 'alice'},
      }));
      await request.response.close();
      return;
    }

    final isDownload =
        path.endsWith('/download.view') || path.endsWith('/stream');
    if (!isDownload) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    downloadHits++;
    if (downloadStatusCode != null) {
      request.response.statusCode = downloadStatusCode!;
      await request.response.close();
      return;
    }
    if (htmlBody != null) {
      request.response.headers.contentType = ContentType.html;
      request.response.add(utf8.encode(htmlBody!));
      await request.response.close();
      return;
    }
    final hasError = downloadError != null;
    request.response.headers.contentType =
        hasError ? ContentType.json : ContentType.binary;
    request.response.add(
      hasError ? _errorBody(downloadError!) : audioBytes,
    );
    await request.response.close();
  }

  static List<int> _errorBody(Map<String, dynamic> error) {
    return utf8.encode(jsonEncode({
      'subsonic-response': {
        'status': 'failed',
        'version': '1.16.1',
        'type': 'navidrome',
        'openSubsonic': true,
        'error': error,
      },
    }));
  }

  Future<void> stop() => server.close(force: true);
}
