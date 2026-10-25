import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/widgets/drag/drag_payload.dart';
import 'package:vynody/widgets/draggable_playlist_item.dart';

void main() {
  testWidgets('DraggablePlaylistItem renders child and extracts songs correctly',
      (tester) async {
    final song1 = MusicFile(
      path: '/path/song1.mp3',
      name: 'song1.mp3',
      title: 'Song 1',
    );
    final song2 = MusicFile(
      path: '/path/song2.mp3',
      name: 'song2.mp3',
      title: 'Song 2',
    );
    final playlist = Playlist(
      id: 'test_pl_1',
      name: 'My Playlist',
      songs: [song1, song2],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DraggablePlaylistItem(
            playlist: playlist,
            child: const Text('Playlist Content'),
          ),
        ),
      ),
    );

    expect(find.text('Playlist Content'), findsOneWidget);

    final item = tester.widget<DraggablePlaylistItem>(
      find.byType(DraggablePlaylistItem),
    );
    expect(item.playlist.songs.length, 2);
    expect(item.playlist.songs.map((s) => s.path).toList(), [
      '/path/song1.mp3',
      '/path/song2.mp3',
    ]);
  });

  test('DraggablePlaylistItem payload extracts song paths', () {
    final song1 = MusicFile(
      path: '/path/song1.mp3',
      name: 'song1.mp3',
    );
    final song2 = MusicFile(
      path: '/path/song2.mp3',
      name: 'song2.mp3',
    );
    final song3 = MusicFile(
      path: '/path/song3.mp3',
      name: 'song3.mp3',
    );

    final pl1 = Playlist(
      id: 'pl1',
      name: 'Playlist 1',
      songs: [song1, song2],
    );
    final pl2 = Playlist(
      id: 'pl2',
      name: 'Playlist 2',
      songs: [song2, song3],
    );

    // Single playlist payload
    final singlePayload = SongPathsPayload(
      paths: [for (final s in pl1.songs) s.path],
    );
    expect(singlePayload.paths, ['/path/song1.mp3', '/path/song2.mp3']);

    // Batch playlists payload deduplicates overlapping songs
    final batchPayload = SongPathsPayload.flattened([pl1.songs, pl2.songs]);
    expect(batchPayload.paths, [
      '/path/song1.mp3',
      '/path/song2.mp3',
      '/path/song3.mp3',
    ]);
  });
}
