import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_flow/player/lyrics/lyrics_service.dart';
import 'package:vibe_flow/utils/network_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LyricsService.searchTracksByTitle', () {
    test('sends only title-related query parameters', () async {
      final response = Response<dynamic>(
        requestOptions: RequestOptions(path: 'https://lrclib.net/api/search'),
        data: [
          {
            'trackName': 'Song Title',
            'artistName': 'Artist',
            'albumName': 'Album',
            'duration': 185,
            'plainLyrics': 'Line 1\nLine 2',
            'syncedLyrics': null,
          },
        ],
      );
      final client = _RecordingNetworkClient(response);
      final service = LyricsService(client: client);

      final tracks = await service.searchTracksByTitle(title: 'Song Title');

      expect(client.callCount, 1);
      expect(client.lastPath, 'https://lrclib.net/api/search');
      expect(client.lastQueryParameters, {
        'track_name': 'Song Title',
        'q': 'Song Title',
      });
      expect(tracks, hasLength(1));
      expect(tracks.single.displayTitle, 'Song Title');
      expect(tracks.single.hasSyncedLyrics, isFalse);
    });

    test(
      'returns empty list without issuing a request for blank title',
      () async {
        final client = _RecordingNetworkClient(
          Response<dynamic>(
            requestOptions: RequestOptions(
              path: 'https://lrclib.net/api/search',
            ),
            data: const [],
          ),
        );
        final service = LyricsService(client: client);

        final tracks = await service.searchTracksByTitle(title: '   ');

        expect(tracks, isEmpty);
        expect(client.callCount, 0);
      },
    );
  });
}

class _RecordingNetworkClient implements NetworkClient {
  _RecordingNetworkClient(this.response);

  final Response<dynamic> response;
  int callCount = 0;
  String? lastPath;
  Map<String, dynamic>? lastQueryParameters;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    callCount++;
    lastPath = path;
    lastQueryParameters = queryParameters == null
        ? null
        : Map<String, dynamic>.from(queryParameters);
    return response as Response<T>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Dio get dio => throw UnimplementedError();
}
