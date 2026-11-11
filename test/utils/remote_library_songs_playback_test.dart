import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/utils/remote_library_playback.dart';

class _MockAudioService extends Fake implements AudioService {
  List<MusicFile>? playedPlaylist;
  PlaybackSource? playedSource;

  @override
  Future<void> playPlaylist(
    List<MusicFile> songs, {
    int initialIndex = 0,
    PlaybackSource? source,
  }) async {
    playedPlaylist = songs;
    playedSource = source;
  }
}

void main() {
  group('playAllRemoteSongs tests', () {
    testWidgets('when hasMore is false, directly plays loadedSongs without progress',
        (tester) async {
      final mockAudioService = _MockAudioService();

      final server = RemoteServer(
        id: 'test-server',
        name: 'Test Server',
        type: RemoteServerType.subsonic,
        url: 'https://test.example.com',
        username: 'user',
        createdAt: DateTime.now(),
      );

      final songs = [
        const MusicFile(
          path: 'subsonic://test-server/1',
          name: 'Track 1.mp3',
          title: 'Track 1',
        ),
        const MusicFile(
          path: 'subsonic://test-server/2',
          name: 'Track 2.mp3',
          title: 'Track 2',
        ),
      ];

      late BuildContext testContext;
      late WidgetRef testRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWith((ref) => mockAudioService),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                testContext = context;
                testRef = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await playAllRemoteSongs(
        context: testContext,
        ref: testRef,
        server: server,
        password: 'pass',
        loadedSongs: songs,
        hasMore: false,
        sourceId: 'remote-test-songs',
        sourceName: 'Songs',
      );

      expect(mockAudioService.playedPlaylist?.length, 2);
      expect(mockAudioService.playedSource?.id, 'remote-test-songs');
    });
  });
}
