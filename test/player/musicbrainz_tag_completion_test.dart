import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/song_tag_completion_riverpod.dart';
import 'package:vynody/player/metadata/acoustid_service.dart';
import 'package:vynody/player/metadata/musicbrainz_tag_completion_service.dart';
import 'package:vynody/utils/network_client.dart';

class _MockNetworkClient implements NetworkClient {
  _MockNetworkClient(this._handler);

  final FutureOr<Response<dynamic>> Function(
    String path,
    Map<String, dynamic>? queryParameters,
  )
  _handler;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    final res = await _handler(path, queryParameters);
    return Response<T>(
      requestOptions: res.requestOptions,
      data: res.data as T?,
      statusCode: res.statusCode,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Dio get dio => throw UnimplementedError();
}

class _FakeAcoustIDService extends Fake implements AcoustIDService {}

void main() {
  setUp(() {
    MusicBrainzTagCompletionService.resetCacheForTest();
  });

  group('MusicBrainzTagCompletionService', () {
    test('skips network call and returns empty list when all terms are disabled or unknown', () async {
      var called = false;
      final service = MusicBrainzTagCompletionService(
        client: _MockNetworkClient((path, query) {
          called = true;
          return Response(requestOptions: RequestOptions(path: path), data: {});
        }),
      );

      final res1 = await service.searchMatches(
        songPath: '/music/test.mp3',
        title: 'Unknown',
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        durationMillis: 0,
      );
      expect(res1, isEmpty);

      final res2 = await service.searchMatches(
        songPath: '/music/test.mp3',
        title: 'Real Title',
        artist: 'Real Artist',
        album: 'Real Album',
        durationMillis: 180000,
        enableTitleQuery: false,
        enableArtistQuery: false,
        enableAlbumQuery: false,
        enableDurationQuery: false,
      );
      expect(res2, isEmpty);
      expect(called, isFalse);
    });

    test('escapes Lucene special characters and constructs clamped duration range', () async {
      String? capturedQuery;
      final service = MusicBrainzTagCompletionService(
        client: _MockNetworkClient((path, query) {
          capturedQuery = query?['query'] as String?;
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'count': 0, 'recordings': []},
          );
        }),
      );

      await service.searchMatches(
        songPath: '/music/test.mp3',
        title: 'A+B (Live) [2024]: Remix?',
        artist: 'AC/DC & Friends!',
        album: 'Unknown Album',
        durationMillis: 2000,
      );

      expect(capturedQuery, isNotNull);
      expect(
        capturedQuery,
        contains(r'recording:"A\+B \(Live\) \[2024\]\: Remix\?"'),
      );
      expect(capturedQuery, contains(r'artistname:"AC\/DC \& Friends\!"'));
      expect(capturedQuery, isNot(contains('release:')));
      // 2000 - 5000 clamps at 0; 2000 + 5000 = 7000
      expect(capturedQuery, contains('dur:[0 TO 7000]'));
    });

    test('sorts searchMatches by releases count -> score -> duration diff -> title', () async {
      final service = MusicBrainzTagCompletionService(
        client: _MockNetworkClient((path, query) {
          return Response(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'count': 5,
              'recordings': [
                {
                  'id': 'rec-1-rel-low-score',
                  'title': 'Song Beta',
                  'score': 90,
                  'length': 200000,
                  'artist-credit': [
                    {'artist': {'name': 'Artist'}}
                  ],
                  'releases': [
                    {'id': 'r1', 'title': 'Single Release'}
                  ],
                },
                {
                  'id': 'rec-2-rel',
                  'title': 'Song Multi Release',
                  'score': 70,
                  'length': 250000,
                  'artist-credit': [
                    {'artist': {'name': 'Artist'}}
                  ],
                  'releases': [
                    {'id': 'r2a', 'title': 'Rel A'},
                    {'id': 'r2b', 'title': 'Rel B'},
                  ],
                },
                {
                  'id': 'rec-1-rel-far-dur',
                  'title': 'Song Far Dur',
                  'score': 95,
                  'length': 220000,
                  'artist-credit': [
                    {'artist': {'name': 'Artist'}}
                  ],
                  'releases': [
                    {'id': 'r3', 'title': 'Rel C'}
                  ],
                },
                {
                  'id': 'rec-1-rel-close-dur',
                  'title': 'Song Close Dur',
                  'score': 95,
                  'length': 201000,
                  'artist-credit': [
                    {'artist': {'name': 'Artist'}}
                  ],
                  'releases': [
                    {'id': 'r4', 'title': 'Rel D'}
                  ],
                },
              ],
            },
          );
        }),
      );

      final matches = await service.searchMatches(
        songPath: '/music/test.mp3',
        title: 'Song',
        artist: 'Artist',
        album: null,
        durationMillis: 200000,
      );

      expect(
        matches.map((m) => m.recordingId).toList(),
        [
          'rec-2-rel', // most releases (2)
          'rec-1-rel-close-dur', // 1 release, score 95, closest duration (1s diff)
          'rec-1-rel-far-dur', // 1 release, score 95, 20s diff
          'rec-1-rel-low-score', // 1 release, score 90
        ],
      );
    });

    test('MusicBrainzTrackMatch.releaseGroups merges same-title releases case-insensitively', () {
      final match = MusicBrainzTrackMatch.fromJson({
        'id': 'rec-1',
        'title': 'Track',
        'score': 100,
        'artist-credit': [
          {'artist': {'name': 'A'}, 'joinphrase': ' & '},
          {'artist': {'name': 'B'}, 'joinphrase': ''},
        ],
        'releases': [
          {'id': 'r1', 'title': 'Greatest Hits', 'country': 'US'},
          {'id': 'r2', 'title': 'Single EP', 'country': 'JP'},
          {'id': 'r3', 'title': '  greatest hits ', 'country': 'UK'},
        ],
      });

      expect(match.artist, 'A & B');
      final groups = match.releaseGroups;
      expect(groups, hasLength(2));
      expect(groups[0].title, 'Greatest Hits');
      expect(groups[0].releases.map((r) => r.id), ['r1', 'r3']);
      expect(groups[1].title, 'Single EP');
      expect(groups[1].releases.map((r) => r.id), ['r2']);
    });
  });

  group('SongTagCompletionController', () {
    test('discards stale MusicBrainz query responses when a newer request starts', () async {
      final firstCompleter = Completer<Response<dynamic>>();
      final secondCompleter = Completer<Response<dynamic>>();
      var callCount = 0;

      final service = MusicBrainzTagCompletionService(
        client: _MockNetworkClient((path, query) {
          callCount++;
          return callCount == 1 ? firstCompleter.future : secondCompleter.future;
        }),
      );

      final controller = SongTagCompletionController(
        songPath: '/music/test.mp3',
        acoustidService: _FakeAcoustIDService(),
        service: service,
      );

      final firstFuture = controller.loadMusicBrainzMatches(
        title: 'Old Query',
        artist: null,
        album: null,
        durationMillis: null,
        enableTitleQuery: true,
        enableArtistQuery: false,
        enableAlbumQuery: false,
        enableDurationQuery: false,
      );

      final secondFuture = controller.loadMusicBrainzMatches(
        title: 'New Query',
        artist: null,
        album: null,
        durationMillis: null,
        enableTitleQuery: true,
        enableArtistQuery: false,
        enableAlbumQuery: false,
        enableDurationQuery: false,
      );

      // Complete newer query first with "New Result".
      secondCompleter.complete(
        Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'recordings': [
              {'id': 'new-id', 'title': 'New Result', 'score': 100},
            ],
          },
        ),
      );
      await secondFuture;

      expect(controller.isMusicBrainzLoading, isFalse);
      expect(controller.musicBrainzMatches.single.recordingId, 'new-id');

      // Now complete stale first query with "Old Result" — must be ignored.
      firstCompleter.complete(
        Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 200,
          data: {
            'recordings': [
              {'id': 'old-id', 'title': 'Old Result', 'score': 100},
            ],
          },
        ),
      );
      await firstFuture;

      expect(controller.musicBrainzMatches.single.recordingId, 'new-id');
      controller.dispose();
    });

    test('sets musicBrainzErrorMessage and clears loading on search error', () async {
      final service = MusicBrainzTagCompletionService(
        client: _MockNetworkClient((path, query) {
          throw DioException(requestOptions: RequestOptions(path: path));
        }),
      );

      final controller = SongTagCompletionController(
        songPath: '/music/test.mp3',
        acoustidService: _FakeAcoustIDService(),
        service: service,
      );

      await controller.loadMusicBrainzMatches(
        title: 'Failing Query',
        artist: null,
        album: null,
        durationMillis: null,
        enableTitleQuery: true,
        enableArtistQuery: false,
        enableAlbumQuery: false,
        enableDurationQuery: false,
      );

      expect(controller.isMusicBrainzLoading, isFalse);
      expect(controller.musicBrainzErrorMessage, isNotNull);
      expect(controller.musicBrainzErrorMessage, isNotEmpty);
      controller.dispose();
    });
  });
}
