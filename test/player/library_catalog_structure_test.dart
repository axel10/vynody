import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/library/library_catalog.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

const _base = SongMetadata(
  id: 1,
  path: '/music/album/01.mp3',
  title: 'Track',
  album: 'Album',
  artist: 'Artist',
  albumArtist: 'Album Artist',
  trackNumber: 1,
  duration: 180000,
  year: 1999,
  genres: ['Rock'],
  artworkPath: '/cache/art.jpg',
  thumbnailPath: '/cache/thumb.jpg',
  artworkWidth: 600,
  artworkHeight: 600,
  lastModifiedTime: 1700000000000,
  sourceFlags: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('libraryStructureEquals', () {
    test('同一首歌的两份快照结构等价', () {
      expect(libraryStructureEquals([_base], [_base]), isTrue);
      // 不同实例但字段全等
      expect(
        libraryStructureEquals([_base], [_base.copyWith(id: 1)]),
        isTrue,
      );
    });

    test('只有 thumbnailPath 变化时视为结构等价', () {
      final before = [_base.copyWith(thumbnailPath: null)];
      final after = [_base.copyWith(thumbnailPath: '/cache/new-thumb.jpg')];

      expect(libraryStructureEquals(before, after), isTrue);
      expect(libraryStructureEquals(after, before), isTrue);
    });

    test('themeColorsBlob / waveformBlob 变化不影响结构判断', () {
      final before = [
        _base.copyWith(
          themeColorsBlob: Uint8List.fromList([1, 2, 3]),
          waveformBlob: Uint8List.fromList([4, 5, 6]),
        ),
      ];
      final after = [
        _base.copyWith(
          themeColorsBlob: Uint8List.fromList([9, 9, 9]),
          waveformBlob: Uint8List.fromList([8, 8, 8]),
        ),
      ];

      // 每次查库都会生成新的 Uint8List 实例，若参与比较会恒为 false
      expect(libraryStructureEquals(before, after), isTrue);
    });

    test('影响专辑聚合的字段变化会被识别', () {
      final cases = <String, SongMetadata>{
        'title': _base.copyWith(title: 'Renamed'),
        'album': _base.copyWith(album: 'Another Album'),
        'artist': _base.copyWith(artist: 'Other Artist'),
        'albumArtist': _base.copyWith(albumArtist: 'Other Album Artist'),
        'trackNumber': _base.copyWith(trackNumber: 2),
        'duration': _base.copyWith(duration: 1),
        'year': _base.copyWith(year: 2001),
        'genres': _base.copyWith(genres: ['Jazz']),
        'artworkPath': _base.copyWith(artworkPath: '/cache/art2.jpg'),
        'artworkWidth': _base.copyWith(artworkWidth: 300),
        'artworkHeight': _base.copyWith(artworkHeight: 300),
        'lastModifiedTime': _base.copyWith(lastModifiedTime: 1800000000000),
        'deletedAt': _base.copyWith(deletedAt: 1),
        'sourceFlags': _base.copyWith(sourceFlags: 2),
        'isAppModified': _base.copyWith(isAppModified: true),
        'fileRating': _base.copyWith(fileRating: 5),
      };

      cases.forEach((field, changed) {
        expect(
          libraryStructureEquals([_base], [changed]),
          isFalse,
          reason: '$field 变化应被视为结构变化',
        );
      });
    });

    test('流派列表按内容比较，不依赖 List identity', () {
      expect(
        libraryStructureEquals(
          [_base.copyWith(genres: ['Rock', 'Pop'])],
          [_base.copyWith(genres: ['Rock', 'Pop'])],
        ),
        isTrue,
      );
      expect(
        libraryStructureEquals(
          [_base.copyWith(genres: ['Rock', 'Pop'])],
          [_base.copyWith(genres: ['Pop', 'Rock'])],
        ),
        isFalse,
      );
      expect(
        libraryStructureEquals(
          [_base.copyWith(genres: null)],
          [_base.copyWith(genres: const <String>[])],
        ),
        isFalse,
      );
    });

    test('曲目数量或顺序变化会被识别', () {
      final second = _base.copyWith(id: 2, path: '/music/album/02.mp3');

      expect(libraryStructureEquals([_base], [_base, second]), isFalse);
      expect(libraryStructureEquals([_base, second], [second, _base]), isFalse);
    });
  });
}
