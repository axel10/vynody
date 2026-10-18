import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_metadata_store.dart';
import 'package:vynody/player/scanner/scanner_tree_builder.dart';

/// 目录树的硬性规定：`themeColorsBlob` / `waveformBlob` / `artworkBytes`
/// 这三列二进制数据一律不许进树。它们由 SQLite 持有，UI 按需读取或重新生成；
/// 播放态（currentMusic / 队列）自己持有一份并在销毁时释放。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ScannerMetadataStore buildStore(MusicFolder root) {
    return ScannerMetadataStore(
      rootFolders: () => [root],
      systemMediaFolder: () => null,
      notifyListeners: () {},
      scheduleMetadataNotify: () {},
      onMetadataMutated: () {},
      onAlbumMetadataMutated: () {},
      notifySongMissingState: (_, _) {},
      normalizePath: (path) => path,
      pathsEqual: (left, right) => left == right,
    );
  }

  test('updateMetadataForPath 不把二进制列写进目录树', () {
    const songPath = '/music/album/song.mp3';
    final root = MusicFolder(
      path: '/music',
      name: 'music',
      files: const [MusicFile(path: songPath, name: 'song.mp3')],
    );
    final store = buildStore(root);

    store.updateMetadataForPath(
      SongMetadata(
        path: songPath,
        title: 'Song',
        album: 'Album',
        artist: 'Artist',
        thumbnailPath: '/cache/thumb.jpg',
        artworkPath: '/cache/art.jpg',
        artworkWidth: 800,
        artworkHeight: 800,
        themeColorsBlob: Uint8List.fromList([1, 2, 3]),
        waveformBlob: Uint8List.fromList([4, 5, 6, 7]),
      ),
      artworkBytes: Uint8List.fromList(List<int>.filled(4096, 9)),
    );

    final updated = root.files.single;
    expect(updated.artworkBytes, isNull, reason: '封面原图不许进树');
    expect(updated.themeColorsBlob, isNull, reason: '主题色 blob 不许进树');
    expect(updated.waveformBlob, isNull, reason: '波形 blob 不许进树');

    // 引用类字段照旧同步，列表/详情靠它们显示封面。
    expect(updated.thumbnailPath, '/cache/thumb.jpg');
    expect(updated.artworkPath, '/cache/art.jpg');
    expect(updated.artworkWidth, 800);
    expect(updated.title, 'Song');
  });

  test('空字节数组仍然只承担「清空封面」哨兵的作用', () {
    const songPath = '/music/album/song2.mp3';
    final root = MusicFolder(
      path: '/music',
      name: 'music',
      files: const [
        MusicFile(
          path: songPath,
          name: 'song2.mp3',
          thumbnailPath: '/cache/old_thumb.jpg',
          artworkPath: '/cache/old_art.jpg',
        ),
      ],
    );
    final store = buildStore(root);

    store.updateMetadataForPath(
      const SongMetadata(
        path: songPath,
        title: 'Song 2',
        album: 'Album',
        artist: 'Artist',
      ),
      artworkBytes: Uint8List(0),
    );

    final updated = root.files.single;
    expect(updated.thumbnailPath, isNull);
    expect(updated.artworkPath, isNull);
    expect(updated.artworkBytes, isNull);
    expect(updated.themeColorsBlob, isNull);
    expect(updated.waveformBlob, isNull);
  });

  test('ScannerTreeBuilder 建树时丢弃三类二进制列', () {
    final builder = ScannerTreeBuilder(
      normalizePath: (path) => path,
      pathsEqual: (left, right) => left == right,
    );

    final file = builder.musicFileFromSongMetadata(
      SongMetadata(
        path: '/music/a.mp3',
        title: 'A',
        album: 'Album',
        artist: 'Artist',
        thumbnailPath: '/cache/a_thumb.jpg',
        themeColorsBlob: Uint8List.fromList([1, 2, 3]),
        waveformBlob: Uint8List.fromList([4, 5, 6, 7]),
      ),
    );

    expect(file.artworkBytes, isNull);
    expect(file.themeColorsBlob, isNull);
    expect(file.waveformBlob, isNull);
    expect(file.thumbnailPath, '/cache/a_thumb.jpg');
    expect(file.title, 'A');
  });
}
