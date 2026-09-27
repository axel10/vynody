import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/folder_helpers.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String supportPath;
  _TestPathProviderPlatform({required this.supportPath});

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeFolderCoversBottomUp', () {
    test('propagates leaf representative cover up to root when parent has no direct songs', () {
      const leafSong = MusicFile(
        path: '/music/rock/classic/01.mp3',
        name: '01.mp3',
        artworkPath: '/art/01.jpg',
      );
      final classicFolder = MusicFolder(
        path: '/music/rock/classic',
        name: 'classic',
        files: [leafSong],
      );
      final rockFolder = MusicFolder(
        path: '/music/rock',
        name: 'rock',
        subFolders: [classicFolder],
      );
      final rootFolder = MusicFolder(
        path: '/music',
        name: 'music',
        subFolders: [rockFolder],
      );

      final covers = computeFolderCoversBottomUp(rootFolder);

      expect(covers['/music/rock/classic'], equals('/music/rock/classic/01.mp3'));
      expect(covers['/music/rock'], equals('/music/rock/classic/01.mp3'));
      expect(covers['/music'], equals('/music/rock/classic/01.mp3'));

      expect(classicFolder.representativeSongCache, equals(leafSong));
      expect(rockFolder.representativeSongCache, equals(leafSong));
      expect(rootFolder.representativeSongCache, equals(leafSong));
    });

    test('prefers parent direct artwork song over child subfolder song', () {
      const parentSong = MusicFile(
        path: '/music/album/parent.mp3',
        name: 'parent.mp3',
        artworkPath: '/art/parent.jpg',
      );
      const childSong = MusicFile(
        path: '/music/album/bonus/child.mp3',
        name: 'child.mp3',
        artworkPath: '/art/child.jpg',
      );
      final bonusFolder = MusicFolder(
        path: '/music/album/bonus',
        name: 'bonus',
        files: [childSong],
      );
      final albumFolder = MusicFolder(
        path: '/music/album',
        name: 'album',
        files: [parentSong],
        subFolders: [bonusFolder],
      );

      final covers = computeFolderCoversBottomUp(albumFolder);

      expect(covers['/music/album'], equals('/music/album/parent.mp3'));
      expect(covers['/music/album/bonus'], equals('/music/album/bonus/child.mp3'));
    });

    test('handles android system media virtual path hierarchy', () {
      const popSong = MusicFile(
        path: 'system/Download/Pop/pop.mp3',
        name: 'pop.mp3',
        thumbnailPath: '/thumb/pop.png',
      );
      final popFolder = MusicFolder(
        path: 'system/Download/Pop',
        name: 'Pop',
        files: [popSong],
      );
      final downloadFolder = MusicFolder(
        path: 'system/Download',
        name: 'Download',
        subFolders: [popFolder],
      );
      final systemFolder = MusicFolder(
        path: 'system',
        name: 'System Media',
        subFolders: [downloadFolder],
      );

      final covers = computeFolderCoversBottomUp(systemFolder);

      expect(covers['system/Download/Pop'], equals('system/Download/Pop/pop.mp3'));
      expect(covers['system/Download'], equals('system/Download/Pop/pop.mp3'));
      expect(covers['system'], equals('system/Download/Pop/pop.mp3'));
    });

    test('evaluateRepresentativeSongForFolder selects artwork song and falls back correctly', () {
      const artSong = MusicFile(
        path: '/folder/art.mp3',
        name: 'art.mp3',
        artworkPath: '/art.jpg',
      );
      const noArtSong = MusicFile(
        path: '/folder/plain.mp3',
        name: 'plain.mp3',
      );

      final folder1 = MusicFolder(
        path: '/folder',
        name: 'folder',
        files: [noArtSong, artSong],
      );
      expect(evaluateRepresentativeSongForFolder(folder1), equals(artSong));

      final folder2 = MusicFolder(
        path: '/folder2',
        name: 'folder2',
        files: [noArtSong],
      );
      expect(evaluateRepresentativeSongForFolder(folder2), equals(noArtSong));

      final emptyFolder = MusicFolder(path: '/empty', name: 'empty');
      expect(evaluateRepresentativeSongForFolder(emptyFolder), isNull);
    });
  });

  group('MetadataDatabase Folder Covers Cache Persistence', () {
    late Directory tempDir;
    final db = MetadataDatabase();

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('folder_covers_test_');
      PathProviderPlatform.instance = _TestPathProviderPlatform(
        supportPath: tempDir.path,
      );
      await db.ensureOpen();
    });

    tearDownAll(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('batch upserts and retrieves folder representative metadata', () async {
      const song1 = SongMetadata(
        path: '/music/rock/song1.mp3',
        title: 'Song 1',
        artist: 'Rock Band',
        album: 'Rock Album',
        artworkPath: '/art/song1.jpg',
      );
      const song2 = SongMetadata(
        path: '/music/jazz/song2.mp3',
        title: 'Song 2',
        artist: 'Jazz Master',
        album: 'Jazz Album',
        thumbnailPath: '/thumb/song2.png',
      );

      await db.insertOrUpdateSong(song1);
      await db.insertOrUpdateSong(song2);

      await db.batchUpsertFolderCovers({
        '/music/rock': song1.path,
        '/music/jazz': song2.path,
      });

      final allMetadata = await db.getAllFolderRepresentativeMetadata();
      expect(allMetadata['/music/rock']?.title, equals('Song 1'));
      expect(allMetadata['/music/jazz']?.title, equals('Song 2'));

      final rockRep = await db.getFolderRepresentativeMetadata('/music/rock');
      expect(rockRep?.title, equals('Song 1'));

      await db.removeFolderCoversForPaths(['/music/rock']);
      final remaining = await db.getAllFolderRepresentativeMetadata();
      expect(remaining.containsKey('/music/rock'), isFalse);
      expect(remaining.containsKey('/music/jazz'), isTrue);
    });

    test('removeFolderCoversUnderRoots cleans up root and all nested subfolders', () async {
      const songRoot = SongMetadata(path: '/root/01.mp3', title: 'Root Song', album: 'Album', artist: 'Artist', artworkPath: '/art/root.jpg');
      const songSub1 = SongMetadata(path: '/root/sub1/02.mp3', title: 'Sub1 Song', album: 'Album', artist: 'Artist', artworkPath: '/art/sub1.jpg');
      const songSub2 = SongMetadata(path: '/root/sub1/nested/03.mp3', title: 'Sub2 Song', album: 'Album', artist: 'Artist', artworkPath: '/art/sub2.jpg');
      const otherSong = SongMetadata(path: '/other/04.mp3', title: 'Other Song', album: 'Album', artist: 'Artist', artworkPath: '/art/other.jpg');

      await db.insertOrUpdateSong(songRoot);
      await db.insertOrUpdateSong(songSub1);
      await db.insertOrUpdateSong(songSub2);
      await db.insertOrUpdateSong(otherSong);

      await db.batchUpsertFolderCovers({
        '/root': songRoot.path,
        '/root/sub1': songSub1.path,
        '/root/sub1/nested': songSub2.path,
        '/other': otherSong.path,
      });

      await db.removeFolderCoversUnderRoots(['/root']);

      final remaining = await db.getAllFolderRepresentativeMetadata();
      expect(remaining.containsKey('/root'), isFalse);
      expect(remaining.containsKey('/root/sub1'), isFalse);
      expect(remaining.containsKey('/root/sub1/nested'), isFalse);
      expect(remaining.containsKey('/other'), isTrue);
    });
  });
}
