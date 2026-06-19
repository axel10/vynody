import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('splitArtistNames', () {
    test('splits on comma and semicolon', () {
      expect(splitArtistNames('aaa,bbb'), ['aaa', 'bbb']);
      expect(splitArtistNames('aaa ; bbb'), ['aaa', 'bbb']);
    });

    test('trims surrounding whitespace and ignores empty segments', () {
      expect(splitArtistNames('  aaa ,   ; ccc  '), [
        'aaa',
        'ccc',
      ]);
    });
  });

  group('ArtistLibraryRepository', () {
    late Directory supportDirectory;

    setUpAll(() async {
      supportDirectory = await Directory.systemTemp.createTemp(
        'artist_library_test_',
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
      } catch (e) {
        // Catch and ignore file lock issues on Windows
        print('Failed to delete support directory: $e');
      }
    });

    test('groups a song under every parsed artist name', () async {
      final database = MetadataDatabase();
      await database.insertOrUpdateSong(
        const SongMetadata(
          path: '/music/song1.mp3',
          title: 'Song 1',
          album: 'Album 1',
          artist: 'aaa, bbb',
        ),
      );
      await database.insertOrUpdateSong(
        const SongMetadata(
          path: '/music/song2.mp3',
          title: 'Song 2',
          album: 'Album 2',
          artist: 'aaa ; ccc',
        ),
      );
      await database.insertOrUpdateSong(
        const SongMetadata(
          path: '/music/song3.mp3',
          title: 'Song 3',
          album: 'Album 3',
          artist: 'bbb ; ddd ; eee',
        ),
      );

      final summaries = await ArtistLibraryRepository()
          .watchArtistSummaries()
          .first;

      expect(
        summaries.map((artist) => artist.name).toList(),
        containsAll(['aaa', 'bbb', 'ccc', 'ddd', 'eee']),
      );

      final aaa = summaries.singleWhere((artist) => artist.queryKey == 'aaa');
      expect(aaa.songCount, 2);
      expect(
        aaa.songs.map((song) => song.path).toList(),
        containsAll([p.normalize('/music/song1.mp3'), p.normalize('/music/song2.mp3')]),
      );

      final bbb = summaries.singleWhere((artist) => artist.queryKey == 'bbb');
      expect(bbb.songCount, 2);
      expect(
        bbb.songs.map((song) => song.path).toList(),
        containsAll([p.normalize('/music/song1.mp3'), p.normalize('/music/song3.mp3')]),
      );

      final eee = summaries.singleWhere((artist) => artist.queryKey == 'eee');
      expect(eee.songCount, 1);
      expect(eee.songs.single.path, p.normalize('/music/song3.mp3'));
    });
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform({required this.supportPath});

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}
