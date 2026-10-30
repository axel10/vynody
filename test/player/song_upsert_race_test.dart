import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

/// 回归：`insertOrUpdateSong` 必须自己吃掉 `UNIQUE(path)` 冲突。
///
/// 线上表现是启动期扫系统媒体时刷出成百条
/// `SqliteException(2067): UNIQUE constraint failed: songs.path`：
/// `scanSystemMedia()` 被多条入口各触发一次，两次后台重读并发，
/// 同一路径在「读库 → 写库」窗口里互相插队，后写的那次整条元数据被丢弃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'song_upsert_test_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(
      supportPath: supportDirectory.path,
    );
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('并发写同一路径不再抛 UNIQUE 冲突，且只留一行', () async {
    const path = '/storage/emulated/0/Download/lib/album/01 song.m4a';

    SongMetadata song(String title) => SongMetadata(
      path: path,
      title: title,
      album: 'Album',
      artist: 'Artist',
      duration: 200000,
      lastModifiedTime: 1700000000000,
      createdAt: 1700000000000,
      sourceFlags: 2,
    );

    // 不 await 地连着发：两次 SELECT 会先于任一 INSERT 执行，
    // 老实现（先查再写）在这里必然撞 UNIQUE。
    await Future.wait([
      db.insertOrUpdateSong(song('first')),
      db.insertOrUpdateSong(song('second')),
      db.insertOrUpdateSong(song('third')),
    ]);

    final rows =
        (await db.getAllSongMetadata()).where((s) => s.path == path).toList();
    expect(rows.length, 1);
    // 冲突时走 UPDATE，最后一次写入的值应该落地。
    expect(rows.single.title, 'third');
    expect(rows.single.lastModifiedTime, 1700000000000);
  });

  test('同一路径顺序重写只更新、不新增', () async {
    const path = '/storage/emulated/0/Download/lib/album2/02 song.mp3';

    await db.insertOrUpdateSong(
      SongMetadata(
        path: path,
        title: 'v1',
        album: 'A',
        artist: 'B',
        sourceFlags: 2,
      ),
    );
    await db.insertOrUpdateSong(
      SongMetadata(
        path: path,
        title: 'v2',
        album: 'A',
        artist: 'B',
        genres: const ['Rock'],
        sourceFlags: 2,
      ),
    );

    final rows =
        (await db.getAllSongMetadata()).where((s) => s.path == path).toList();
    expect(rows.length, 1);
    expect(rows.single.title, 'v2');
    expect(rows.single.genres, const ['Rock']);
  });
}

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform({required this.supportPath});

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}
