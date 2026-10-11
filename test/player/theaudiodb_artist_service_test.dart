import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/theaudiodb_artist_service.dart';
import 'package:vynody/utils/network_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TheAudioDbArtistService', () {
    late Directory supportDirectory;

    setUpAll(() async {
      supportDirectory = await Directory.systemTemp.createTemp(
        'theaudiodb_artist_service_test_',
      );
      PathProviderPlatform.instance = _TestPathProviderPlatform(
        supportPath: supportDirectory.path,
      );
    });

    setUp(() async {
      await MetadataDatabase().clearAll();
    });

    tearDownAll(() async {
      try {
        if (await supportDirectory.exists()) {
          await supportDirectory.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('returns null for unknown artist or empty name', () async {
      final service = TheAudioDbArtistService.instance;

      const unknownArtist = ArtistSummary(
        queryKey: 'unknown artist',
        name: 'Unknown Artist',
        songs: <MusicFile>[],
        representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
        songCount: 0,
      );

      final result = await service.fetchAndCacheArtistImage(unknownArtist);
      expect(result, isNull);
    });

    test('returns existing cachedImagePath if file exists', () async {
      final dummyFile = File(p.join(supportDirectory.path, 'dummy_artist.jpg'));
      await dummyFile.writeAsString('fake-image-bytes');

      final service = TheAudioDbArtistService.instance;

      final artist = ArtistSummary(
        queryKey: 'coldplay',
        name: 'Coldplay',
        songs: const <MusicFile>[],
        representativeSong: const MusicFile(path: '/dummy.mp3', name: 'dummy'),
        songCount: 1,
        cachedImagePath: dummyFile.path,
      );

      final result = await service.fetchAndCacheArtistImage(artist);
      expect(result, equals(dummyFile.path));
    });

    test(
      'returns existing DB artistImageCache if record exists and file on disk',
      () async {
        final db = MetadataDatabase();
        final dummyFile = File(
          p.join(supportDirectory.path, 'db_cached_artist.jpg'),
        );
        await dummyFile.writeAsString('fake-db-image-bytes');

        await db.insertOrUpdateArtistImageCache(
          ArtistImageCacheRecord(
            artistId: 'coldplay',
            imagePath: dummyFile.path,
            sourceUrl: 'https://example.com/thumb.jpg',
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        final service = TheAudioDbArtistService(database: db);

        const artist = ArtistSummary(
          queryKey: 'coldplay',
          name: 'Coldplay',
          songs: <MusicFile>[],
          representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
          songCount: 1,
        );

        final result = await service.fetchAndCacheArtistImage(artist);
        expect(result, equals(dummyFile.path));
      },
    );

    test(
      'onArtistImageUpdated stream is broadcast and receives queryKey updates',
      () async {
        final service = TheAudioDbArtistService.instance;
        expect(service.onArtistImageUpdated.isBroadcast, isTrue);
      },
    );

    test(
      'resolves MBID via MusicBrainz and downloads artist image via TheAudioDB artist-mb endpoint',
      () async {
        final db = MetadataDatabase();
        final requestedUrls = <String>[];

        final mockClient = _MockNetworkClient((url) {
          requestedUrls.add(url);
          if (url.contains('musicbrainz.org/ws/2/artist')) {
            return {
              'count': 1,
              'artists': [
                {
                  'id': 'a223958d-5c56-4b2c-a30a-87e357bc121b',
                  'score': 100,
                  'name': '周杰倫',
                },
              ],
            };
          } else if (url.contains('artist-mb.php?i=a223958d-5c56-4b2c-a30a-87e357bc121b')) {
            return {
              'artists': [
                {
                  'idArtist': '116278',
                  'strArtist': 'Jay Chou',
                  'strArtistThumb': 'https://example.com/jay_chou_thumb.jpg',
                },
              ],
            };
          } else if (url.contains('jay_chou_thumb.jpg')) {
            return <int>[1, 2, 3, 4, 5];
          }
          return null;
        });

        final service = TheAudioDbArtistService(
          database: db,
          networkClient: mockClient,
          musicBrainzRateLimitDelay: Duration.zero,
        );

        const artist = ArtistSummary(
          queryKey: '周杰伦',
          name: '周杰伦',
          songs: <MusicFile>[],
          representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
          songCount: 1,
        );

        final result = await service.fetchAndCacheArtistImage(artist);
        expect(result, isNotNull);
        expect(File(result!).existsSync(), isTrue);

        // 验证确实调用了 MusicBrainz 和 TheAudioDB artist-mb.php
        expect(
          requestedUrls.any((u) => u.contains('musicbrainz.org/ws/2/artist')),
          isTrue,
        );
        expect(
          requestedUrls.any((u) => u.contains('artist-mb.php?i=a223958d-5c56-4b2c-a30a-87e357bc121b')),
          isTrue,
        );

        // 验证数据库已缓存
        final cachedRecord = await db.getArtistCache('周杰伦');
        expect(cachedRecord, isNotNull);
        expect(cachedRecord!.artistName, equals('Jay Chou'));
        expect(cachedRecord.noData, isFalse);
      },
    );

    test(
      'falls back to search.php when MusicBrainz returns no match',
      () async {
        final db = MetadataDatabase();
        final requestedUrls = <String>[];

        final mockClient = _MockNetworkClient((url) {
          requestedUrls.add(url);
          if (url.contains('musicbrainz.org/ws/2/artist')) {
            return {'count': 0, 'artists': []};
          } else if (url.contains('search.php?s=Oasis')) {
            return {
              'artists': [
                {
                  'idArtist': '111234',
                  'strArtist': 'Oasis',
                  'strArtistThumb': 'https://example.com/oasis_thumb.jpg',
                },
              ],
            };
          } else if (url.contains('oasis_thumb.jpg')) {
            return <int>[10, 20, 30];
          }
          return null;
        });

        final service = TheAudioDbArtistService(
          database: db,
          networkClient: mockClient,
          musicBrainzRateLimitDelay: Duration.zero,
        );

        const artist = ArtistSummary(
          queryKey: 'oasis',
          name: 'Oasis',
          songs: <MusicFile>[],
          representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
          songCount: 1,
        );

        final result = await service.fetchAndCacheArtistImage(artist);
        expect(result, isNotNull);
        expect(File(result!).existsSync(), isTrue);

        // 验证回退到了 search.php
        expect(
          requestedUrls.any((u) => u.contains('search.php?s=Oasis')),
          isTrue,
        );
      },
    );

    test(
      'directly queries artist-mb.php when artistId is already a valid UUID',
      () async {
        final db = MetadataDatabase();
        final requestedUrls = <String>[];

        final mockClient = _MockNetworkClient((url) {
          requestedUrls.add(url);
          if (url.contains('artist-mb.php?i=86119d30-d930-4e65-a97a-e31e22388166')) {
            return {
              'artists': [
                {
                  'idArtist': '124583',
                  'strArtist': 'Eason Chan',
                  'strArtistThumb': 'https://example.com/eason_thumb.jpg',
                },
              ],
            };
          } else if (url.contains('eason_thumb.jpg')) {
            return <int>[11, 22, 33];
          }
          return null;
        });

        final service = TheAudioDbArtistService(
          database: db,
          networkClient: mockClient,
          musicBrainzRateLimitDelay: Duration.zero,
        );

        const artist = ArtistSummary(
          queryKey: 'eason chan',
          name: '陈奕迅',
          artistId: '86119d30-d930-4e65-a97a-e31e22388166',
          songs: <MusicFile>[],
          representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
          songCount: 1,
        );

        final result = await service.fetchAndCacheArtistImage(artist);
        expect(result, isNotNull);

        // 验证直接调用 artist-mb.php 且未调用 MusicBrainz
        expect(
          requestedUrls.any((u) => u.contains('musicbrainz.org/ws/2/artist')),
          isFalse,
        );
        expect(
          requestedUrls.any((u) => u.contains('artist-mb.php?i=86119d30-d930-4e65-a97a-e31e22388166')),
          isTrue,
        );
      },
    );

    test(
      'records noData: true when neither MusicBrainz nor TheAudioDB find artist',
      () async {
        final db = MetadataDatabase();

        final mockClient = _MockNetworkClient((url) {
          if (url.contains('musicbrainz.org/ws/2/artist')) {
            return {'count': 0, 'artists': []};
          } else if (url.contains('search.php')) {
            return {'artists': null};
          }
          return null;
        });

        final service = TheAudioDbArtistService(
          database: db,
          networkClient: mockClient,
          musicBrainzRateLimitDelay: Duration.zero,
        );

        const artist = ArtistSummary(
          queryKey: 'nonexistent_singer',
          name: 'Nonexistent Singer',
          songs: <MusicFile>[],
          representativeSong: MusicFile(path: '/dummy.mp3', name: 'dummy'),
          songCount: 1,
        );

        final result = await service.fetchAndCacheArtistImage(artist);
        expect(result, isNull);

        final cachedRecord = await db.getArtistCache('nonexistent_singer');
        expect(cachedRecord, isNotNull);
        expect(cachedRecord!.noData, isTrue);
      },
    );
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform({required this.supportPath});

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

class _MockNetworkClient implements NetworkClient {
  _MockNetworkClient(this.handler);

  final dynamic Function(String url) handler;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final result = handler(path);
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: result as T?,
      statusCode: result != null ? 200 : 404,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Dio get dio => throw UnimplementedError();
}
