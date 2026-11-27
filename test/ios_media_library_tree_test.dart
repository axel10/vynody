import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_tree_builder.dart';

void main() {
  late ScannerTreeBuilder builder;

  setUp(() {
    builder = ScannerTreeBuilder(
      normalizePath: (path) => path.trim(),
      pathsEqual: (left, right) => left.trim() == right.trim(),
    );
  });

  test('buildIosMediaLibrary groups tracks into Artist/Album two-level tree', () {
    final entries = <IosMediaLibraryEntry>[
      const IosMediaLibraryEntry(
        id: '101',
        uri: 'ipod-library://item/item.m4a?id=101',
        title: 'Track One',
        artist: 'Jay Chou',
        album: 'Fantasy',
        durationMs: 240000,
        trackNumber: 1,
      ),
      const IosMediaLibraryEntry(
        id: '102',
        uri: 'ipod-library://item/item.m4a?id=102',
        title: 'Track Two',
        artist: 'AC/DC',
        album: 'Back in Black',
        durationMs: 255000,
        trackNumber: 2,
      ),
      const IosMediaLibraryEntry(
        id: '103',
        uri: 'ipod-library://item/item.m4a?id=103',
        title: 'No Tags',
        durationMs: 180000,
      ),
    ];

    final root = builder.buildIosMediaLibrary(
      entries,
      const <String, SongMetadata>{},
      (a, b) => a.compareTo(b),
      unknownArtist: 'Unknown Artist',
      unknownAlbum: 'Unknown Album',
    );

    expect(root.path, 'system');
    expect(root.files, isEmpty);
    expect(
      root.subFolders.map((f) => f.name).toList(),
      ['AC／DC', 'Jay Chou', 'Unknown Artist'],
    );

    final acdcFolder = root.subFolders[0];
    expect(acdcFolder.path, 'system/AC／DC');
    expect(acdcFolder.subFolders.single.name, 'Back in Black');
    expect(acdcFolder.subFolders.single.path, 'system/AC／DC/Back in Black');
    expect(acdcFolder.subFolders.single.files.single.title, 'Track Two');

    final unknownFolder = root.subFolders[2];
    expect(unknownFolder.subFolders.single.name, 'Unknown Album');
    expect(unknownFolder.subFolders.single.files.single.path, 'ipod-library://item/item.m4a?id=103');
  });

  test('buildIosMediaLibrary prefers DB metadata over raw entry tags', () {
    const uri = 'ipod-library://item/item.m4a?id=201';
    final entries = <IosMediaLibraryEntry>[
      const IosMediaLibraryEntry(
        id: '201',
        uri: uri,
        title: 'Raw Title',
        artist: 'Raw Artist',
        album: 'Raw Album',
        durationMs: 200000,
      ),
    ];

    final metadataByPath = <String, SongMetadata>{
      uri: const SongMetadata(
        path: uri,
        title: 'DB Title',
        artist: 'DB Artist',
        album: 'DB Album',
        albumArtist: 'DB Album Artist',
        thumbnailPath: '/tmp/ios_201.jpg',
      ),
    };

    final root = builder.buildIosMediaLibrary(
      entries,
      metadataByPath,
      (a, b) => a.compareTo(b),
      unknownArtist: 'Unknown Artist',
      unknownAlbum: 'Unknown Album',
    );

    final artistFolder = root.subFolders.single;
    expect(artistFolder.name, 'DB Album Artist');
    final albumFolder = artistFolder.subFolders.single;
    expect(albumFolder.name, 'DB Album');
    expect(albumFolder.files.single.title, 'DB Title');
    expect(albumFolder.files.single.thumbnailPath, '/tmp/ios_201.jpg');
  });
}
