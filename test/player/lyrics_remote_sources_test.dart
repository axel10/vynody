import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/embedded_tag_provider.dart';
import 'package:vynody/player/lyrics/sources/media_server_capability_cache.dart';
import 'package:vynody/player/lyrics/sources/media_server_lyrics_provider.dart';
import 'package:vynody/player/lyrics/sources/media_server_lyrics_result.dart';
import 'package:vynody/player/lyrics/sources/sidecar_lrc_provider.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/clients/jellyfin_client.dart';
import 'package:vynody/player/remote/clients/subsonic_client.dart';
import 'package:vynody/player/remote/remote_server_models.dart';

LyricsQuery _query(String path) {
  return LyricsQuery(
    filePath: path,
    fileName: 'song.flac',
    title: 'Song',
    artist: 'Artist',
    album: 'Album',
    duration: const Duration(seconds: 180),
  );
}

Dio _subsonicDio({
  Map<String, dynamic>? data,
  int statusCode = 200,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (statusCode >= 400) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: statusCode,
              ),
            ),
          );
          return;
        }
        handler.resolve(
          Response(requestOptions: options, statusCode: 200, data: data),
        );
      },
    ),
  );
  return dio;
}

Dio _jellyfinDio({dynamic lyricsBody, int lyricsStatus = 200}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.contains('AuthenticateByName')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'AccessToken': 'token',
                'User': {'Id': 'user'},
                'ServerId': 'server',
              },
            ),
          );
          return;
        }
        if (lyricsStatus >= 400) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(
                requestOptions: options,
                statusCode: lyricsStatus,
              ),
            ),
          );
          return;
        }
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: lyricsBody,
          ),
        );
      },
    ),
  );
  return dio;
}

RemoteServer _server(String id, RemoteServerType type) {
  return RemoteServer(
    id: id,
    name: id,
    type: type,
    url: 'http://localhost:4533',
    username: 'user',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDir = Directory.systemTemp.createTempSync('lyrics_remote_test');
  PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  final repository = LyricsCacheRepository(db: MetadataDatabase());

  setUp(() {
    MediaServerCapabilityCache.instance.clearAll();
  });

  group('旁挂 lrc（远程）', () {
    test('注入 reader 时对 smb:// 生效，命中返回 remote_lrc', () async {
      final provider = SidecarLrcProvider(
        cacheRepository: repository,
        remoteSidecarReader: (path) async => '[00:01.00]hello\n[00:02.00]world',
      );

      final query = _query('smb://server/share/song.flac');
      expect(provider.handles(query), isTrue);

      final result = await provider.load(query, saveToDb: false);
      expect(result, isNotNull);
      expect(result!.source, 'remote_lrc');
      expect(result.lyricsText, contains('hello'));
      expect(result.syncedLines.first.text, 'hello');
    });

    test('reader 返回空时视为未命中', () async {
      final provider = SidecarLrcProvider(
        cacheRepository: repository,
        remoteSidecarReader: (path) async => '   ',
      );

      final result = await provider.load(
        _query('webdav://server/music/song.flac'),
        saveToDb: false,
      );
      expect(result, isNull);
    });

    test('未注入 reader 时远程路径不参与匹配', () {
      final provider = SidecarLrcProvider(cacheRepository: repository);
      expect(provider.handles(_query('smb://server/share/song.flac')), isFalse);
      expect(provider.handles(_query('/music/song.flac')), isTrue);
    });
  });

  group('内嵌歌词（远程）', () {
    test('reader 命中时返回 embedded 来源', () async {
      final provider = EmbeddedTagProvider(
        cacheRepository: repository,
        remoteLyricsReader: (path) async => '[00:01.00]embedded line',
      );

      final query = _query('smb://server/share/song.flac');
      expect(provider.handles(query), isTrue);

      final result = await provider.load(query, saveToDb: false);
      expect(result, isNotNull);
      expect(result!.source, 'embedded');
      expect(result.lyricsText, contains('embedded line'));
    });

    test('reader 返回 null 时继续下一层', () async {
      final provider = EmbeddedTagProvider(
        cacheRepository: repository,
        remoteLyricsReader: (path) async => null,
      );

      final result = await provider.load(
        _query('webdav://server/music/song.flac'),
        saveToDb: false,
      );
      expect(result, isNull);
    });

    test('媒体库曲目（subsonic / jellyfin）同样参与内嵌探测', () async {
      final seen = <String>[];
      final provider = EmbeddedTagProvider(
        cacheRepository: repository,
        remoteLyricsReader: (path) async {
          seen.add(path);
          return '[00:01.00]tag line';
        },
      );

      for (final path in ['subsonic://server/123', 'jellyfin://server/abc']) {
        final query = _query(path);
        expect(provider.handles(query), isTrue, reason: path);
        final result = await provider.load(query, saveToDb: false);
        expect(result?.source, 'embedded', reason: path);
      }
      expect(seen, ['subsonic://server/123', 'jellyfin://server/abc']);
    });
  });

  group('媒体库内嵌歌词的取字节地址', () {
    test('Subsonic 用 stream + format=raw，且不带 maxBitRate', () {
      final client = SubsonicClient(
        server: RemoteServer(
          id: 'server',
          name: 'server',
          type: RemoteServerType.subsonic,
          url: 'http://localhost:4533',
          username: 'user',
          maxBitRate: 128,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        password: 'p',
      );

      final url = client.buildRawStreamUrl('42');
      expect(url, contains('rest/stream'));
      expect(url, contains('id=42'));
      expect(url, contains('format=raw'));
      // 带了码率上限就会被服务端转码，转码流不支持 Range。
      expect(url, isNot(contains('maxBitRate')));
    });

    test('Jellyfin 用 static=true 并带会话 token', () async {
      final client = JellyfinClient(
        server: RemoteServer(
          id: 'jf-raw',
          name: 'jf',
          type: RemoteServerType.jellyfin,
          url: 'http://localhost:8096',
          username: 'user',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        password: 'p',
        customDio: _jellyfinDio(
          lyricsBody: null,
          lyricsStatus: 200,
        ),
      );
      await client.authenticate();

      final url = client.buildRawStreamUrl('abc');
      expect(url, contains('/Audio/abc/stream'));
      expect(url, contains('static=true'));
      expect(url, isNot(contains('static=false')));
      expect(url, contains('api_key=token'));
      expect(client.authHeaders['X-Emby-Token'], 'token');
    });
  });

  group('媒体库四态消费', () {
    test('hit 时返回 remote_server 结果', () async {
      final provider = MediaServerLyricsProvider(
        cacheRepository: repository,
        remoteLyricsFetcher: (query, {CancelToken? cancelToken}) async =>
            const MediaServerLyricsResult.hit(
              '[00:01.00]server line',
              variant: 'test',
            ),
      );

      final result = await provider.load(
        _query('subsonic://server/123'),
        saveToDb: false,
      );
      expect(result, isNotNull);
      expect(result!.source, 'remote_server');
    });

    for (final status in [
      MediaServerLyricsStatus.absent,
      MediaServerLyricsStatus.unsupported,
      MediaServerLyricsStatus.failed,
    ]) {
      test('${status.name} 时不产出结果，交给下一层', () async {
        final provider = MediaServerLyricsProvider(
          cacheRepository: repository,
          remoteLyricsFetcher: (query, {CancelToken? cancelToken}) async =>
              MediaServerLyricsResult.miss(status),
        );

        final result = await provider.load(
          _query('jellyfin://server/abc'),
          saveToDb: false,
        );
        expect(result, isNull);
      });
    }
  });

  group('Subsonic 四态', () {
    test('结构化歌词命中，优先带时间轴的条目', () async {
      final client = SubsonicClient(
        server: _server('sub-hit', RemoteServerType.subsonic),
        password: 'p',
        customDio: _subsonicDio(
          data: {
            'subsonic-response': {
              'status': 'ok',
              'lyricsList': {
                'structuredLyrics': [
                  {
                    'synced': false,
                    'line': [
                      {'value': 'plain'},
                    ],
                  },
                  {
                    'synced': true,
                    'line': [
                      {'start': 1500, 'value': 'synced'},
                    ],
                  },
                ],
              },
            },
          },
        ),
      );

      final result = await client.fetchLyricsResult(id: '123');
      expect(result.status, MediaServerLyricsStatus.hit);
      expect(result.variant, 'structured-synced');
      expect(result.text, contains('synced'));
    });

    test('扩展端点 404 判为 unsupported 并写入能力缓存', () async {
      final server = _server('sub-404', RemoteServerType.subsonic);
      final dio = _subsonicDio(statusCode: 404);
      final client = SubsonicClient(
        server: server,
        password: 'p',
        customDio: dio,
      );

      final result = await client.fetchLyricsResult(id: '123');
      expect(result.status, MediaServerLyricsStatus.unsupported);
      expect(
        MediaServerCapabilityCache.instance.isUnsupported(
          server.id,
          MediaServerCapabilityCache.subsonicLyricsBySongId,
        ),
        isTrue,
      );
    });

    test('能力缓存命中后不再发请求', () async {
      final server = _server('sub-cached', RemoteServerType.subsonic);
      var calls = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ),
            );
          },
        ),
      );
      final client = SubsonicClient(
        server: server,
        password: 'p',
        customDio: dio,
      );

      await client.fetchLyricsResult(id: '1');
      final callsAfterFirst = calls;
      await client.fetchLyricsResult(id: '2');

      expect(callsAfterFirst, greaterThan(0));
      // 第二次只可能发 legacy 请求（artist/title 为空，实际不会发），不应再打扩展端点。
      expect(calls, callsAfterFirst);
    });

    test('code 70 判为 absent', () async {
      final client = SubsonicClient(
        server: _server('sub-70', RemoteServerType.subsonic),
        password: 'p',
        customDio: _subsonicDio(
          data: {
            'subsonic-response': {
              'status': 'failed',
              'error': {'code': 70, 'message': 'not found'},
            },
          },
        ),
      );

      final result = await client.fetchLyricsResult(id: '123');
      expect(result.status, MediaServerLyricsStatus.absent);
    });

    test('连接失败判为 failed，且不写能力缓存', () async {
      final server = _server('sub-net', RemoteServerType.subsonic);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
              ),
            );
          },
        ),
      );
      final client = SubsonicClient(
        server: server,
        password: 'p',
        customDio: dio,
      );

      final result = await client.fetchLyricsResult(id: '123');
      expect(result.status, MediaServerLyricsStatus.failed);
      expect(
        MediaServerCapabilityCache.instance.isUnsupported(
          server.id,
          MediaServerCapabilityCache.subsonicLyricsBySongId,
        ),
        isFalse,
      );
    });
  });

  group('Jellyfin 四态', () {
    test('Start 全为 0 时输出纯文本，不伪造逐行时间轴', () async {
      final client = JellyfinClient(
        server: _server('jf-plain', RemoteServerType.jellyfin),
        password: 'p',
        customDio: _jellyfinDio(
          lyricsBody: {
            'Lyrics': {
              'Lines': [
                {'Start': 0, 'Text': 'first'},
                {'Start': 0, 'Text': 'second'},
              ],
            },
          },
        ),
      );

      final result = await client.fetchLyricsResult('abc');
      expect(result.status, MediaServerLyricsStatus.hit);
      expect(result.variant, 'jellyfin-lines');
      expect(result.synced, isFalse);
      expect(result.text, 'first\nsecond');
      expect(result.text, isNot(contains('[00:00')));
    });

    test('有有效 Start 时输出带时间戳的 LRC', () async {
      final client = JellyfinClient(
        server: _server('jf-synced', RemoteServerType.jellyfin),
        password: 'p',
        customDio: _jellyfinDio(
          lyricsBody: {
            'Lyrics': {
              'Lines': [
                {'Start': 10000000, 'Text': 'first'},
              ],
            },
          },
        ),
      );

      final result = await client.fetchLyricsResult('abc');
      expect(result.status, MediaServerLyricsStatus.hit);
      expect(result.synced, isTrue);
      expect(result.text, contains('[00:01.00]first'));
    });

    test('404 判为 unsupported 并写入能力缓存', () async {
      final server = _server('jf-404', RemoteServerType.jellyfin);
      final client = JellyfinClient(
        server: server,
        password: 'p',
        customDio: _jellyfinDio(lyricsStatus: 404),
      );

      final result = await client.fetchLyricsResult('abc');
      expect(result.status, MediaServerLyricsStatus.unsupported);
      expect(
        MediaServerCapabilityCache.instance.isUnsupported(
          server.id,
          MediaServerCapabilityCache.jellyfinLyricsEndpoint,
        ),
        isTrue,
      );

      // 第二次直接走缓存，不再发请求（返回 unsupported 且 diagnostic 为 cached）
      final cached = await client.fetchLyricsResult('def');
      expect(cached.status, MediaServerLyricsStatus.unsupported);
      expect(cached.diagnostic, 'cached');
    });
  });
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
