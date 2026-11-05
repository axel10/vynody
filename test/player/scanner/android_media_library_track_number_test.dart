import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/folder_cover_resolver.dart';
import 'package:vynody/player/scanner/scanner_tree_builder.dart';

void main() {
  AndroidMediaLibraryEntry androidEntry({
    String path = '/music/01.mp3',
    String title = 'Zebra',
    Object? trackNumber,
  }) {
    return AndroidMediaLibraryEntry.fromMap(<Object?, Object?>{
      'id': '1',
      'uri': 'content://media/external/audio/media/1',
      'filePath': path,
      'title': title,
      'displayName': '01.mp3',
      'relativePath': 'Music/Album/',
      'durationMs': 180000,
      'trackNumber': trackNumber,
    });
  }

  final builder = ScannerTreeBuilder(
    normalizePath: (path) => path,
    pathsEqual: (a, b) => a == b,
  );

  group('AndroidMediaLibraryEntry.fromMap 音轨号', () {
    test('正整数 / 整数字符串 / "轨号/总数" 都能解析', () {
      expect(androidEntry(trackNumber: 3).trackNumber, 3);
      expect(androidEntry(trackNumber: '3').trackNumber, 3);
      expect(androidEntry(trackNumber: '7/12').trackNumber, 7);
      expect(androidEntry(trackNumber: 5.0).trackNumber, 5);
    });

    test('0 / 负数 / 空 / 非法值 / 缺省一律为 null', () {
      expect(androidEntry(trackNumber: 0).trackNumber, isNull);
      expect(androidEntry(trackNumber: '0/10').trackNumber, isNull);
      expect(androidEntry(trackNumber: -2).trackNumber, isNull);
      expect(androidEntry(trackNumber: '').trackNumber, isNull);
      expect(androidEntry(trackNumber: 'unknown').trackNumber, isNull);
      expect(androidEntry().trackNumber, isNull);
    });
  });

  group('musicFileFromAndroidEntry', () {
    test('后台元数据还没解析完时用 MediaStore 音轨号兜底', () {
      final file = builder.musicFileFromAndroidEntry(
        androidEntry(trackNumber: 1),
        path: '/music/01.mp3',
      );
      expect(file.trackNumber, 1);
    });

    test('DB 标签更权威；DB 缺音轨号时仍回退到 entry', () {
      final withDb = builder.musicFileFromAndroidEntry(
        androidEntry(trackNumber: 1),
        path: '/music/01.mp3',
        metadata: const SongMetadata(
          path: '/music/01.mp3',
          title: 'Zebra',
          album: 'Album',
          artist: 'Artist',
          trackNumber: 9,
        ),
      );
      expect(withDb.trackNumber, 9);

      final dbMissingTrack = builder.musicFileFromAndroidEntry(
        androidEntry(trackNumber: 1),
        path: '/music/01.mp3',
        metadata: const SongMetadata(
          path: '/music/01.mp3',
          title: 'Zebra',
          album: 'Album',
          artist: 'Artist',
        ),
      );
      expect(dbMissingTrack.trackNumber, 1);
    });

    test('两边都没有音轨号时为 null', () {
      final file = builder.musicFileFromAndroidEntry(
        androidEntry(),
        path: '/music/01.mp3',
      );
      expect(file.trackNumber, isNull);
    });
  });

  test('系统媒体库目录的代表封面按音轨号选，而不是按标题', () {
    // 标题顺序与音轨号相反：一旦退化成纯标题排序，就会错选 Apple。
    // 封面路径由 DB 元数据提供（首次扫描 DB 可能只有封面列），音轨号仍来自 entry。
    MusicFile fileFromEntry({
      required String path,
      required String title,
      required int trackNumber,
      required String artworkPath,
    }) {
      return builder.musicFileFromAndroidEntry(
        androidEntry(path: path, title: title, trackNumber: trackNumber),
        path: path,
        metadata: SongMetadata(
          path: path,
          title: title,
          album: 'Album',
          artist: 'Artist',
          artworkPath: artworkPath,
        ),
      );
    }

    final track2 = fileFromEntry(
      path: '/music/02.mp3',
      title: 'Apple',
      trackNumber: 2,
      artworkPath: '/art/02.jpg',
    );
    final track1 = fileFromEntry(
      path: '/music/01.mp3',
      title: 'Zebra',
      trackNumber: 1,
      artworkPath: '/art/01.jpg',
    );

    expect(track1.trackNumber, 1);
    expect(track1.artworkPath, '/art/01.jpg');

    final folder = MusicFolder(
      path: '/music',
      name: 'music',
      files: [track2, track1],
    );
    final rep = FolderCoverResolver.evaluateRepresentativeSongForFolderSync(folder);

    expect(rep?.trackNumber, 1);
    expect(rep?.path, '/music/01.mp3');
  });
}
