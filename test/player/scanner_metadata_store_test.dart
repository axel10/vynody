import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/models/music_folder.dart';
import 'package:vibe_flow/player/metadata_database.dart';
import 'package:vibe_flow/player/scanner_metadata_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScannerMetadataStore', () {
    test('removeMetadataForPath removes the song from visible folders', () {
      final rootFolder = MusicFolder(
        path: '/music',
        name: 'music',
        subFolders: [
          MusicFolder(
            path: '/music/album',
            name: 'album',
            files: [
              const MusicFile(
                path: '/music/album/song.mp3',
                name: 'song.mp3',
              ),
            ],
          ),
        ],
      );

      final store = ScannerMetadataStore(
        rootFolders: () => [rootFolder],
        systemMediaFolder: () => null,
        notifyListeners: () {},
        scheduleMetadataNotify: () {},
        onMetadataMutated: () {},
        onAlbumMetadataMutated: () {},
        notifySongMissingState: (_, __) {},
        normalizePath: (path) => path,
        pathsEqual: (left, right) => left == right,
      );

      store.cacheMetadata(
        const SongMetadata(
          path: '/music/album/song.mp3',
          title: 'Song',
          album: 'Album',
          artist: 'Artist',
        ),
      );

      expect(store.metadataMap.containsKey('/music/album/song.mp3'), isTrue);
      expect(rootFolder.subFolders, hasLength(1));
      expect(rootFolder.subFolders.single.files, hasLength(1));

      store.removeMetadataForPath('/music/album/song.mp3');

      expect(store.metadataMap.containsKey('/music/album/song.mp3'), isFalse);
      expect(rootFolder.subFolders, isEmpty);
    });
  });
}
