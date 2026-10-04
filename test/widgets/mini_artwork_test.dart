import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/mini_player_widgets.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

void main() {
  testWidgets('MiniArtwork renders fallback icon when currentMusic is null',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioCurrentMusicProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MiniArtwork(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note), findsOneWidget);
    expect(find.byType(SongThumbnail), findsNothing);
  });

  testWidgets('MiniArtwork renders SongThumbnail when currentMusic is present',
      (tester) async {
    const testMusic = MusicFile(
      path: '/test/music.mp3',
      name: 'music.mp3',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioCurrentMusicProvider.overrideWithValue(testMusic),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: MiniArtwork(),
          ),
        ),
      ),
    );

    expect(find.byType(SongThumbnail), findsOneWidget);
    final thumbnailFinder = find.byType(SongThumbnail);
    final songThumbnail = tester.widget<SongThumbnail>(thumbnailFinder);
    expect(songThumbnail.path, '/test/music.mp3');
    expect(songThumbnail.width, 36.0);
    expect(songThumbnail.height, 36.0);
  });
}
