import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TestPathProviderPlatform({required this.supportPath});
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'find_songs_by_title_and_artist_test_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(
      supportPath: supportDirectory.path,
    );
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      await db.close();
    } catch (_) {}
    try {
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> insertSong({
    required String path,
    required String title,
    required String artist,
    String album = 'Album',
  }) async {
    await db.insertOrUpdateSong(
      SongMetadata(path: path, title: title, artist: artist, album: album),
    );
  }

  test('同名不同艺术家时只返回艺术家匹配的那首', () async {
    await insertSong(path: '/m/same1.flac', title: 'Same Name', artist: 'Alice');
    await insertSong(path: '/m/same2.flac', title: 'Same Name', artist: 'Bob');

    final result = await db.findSongsByTitleAndArtist(
      title: 'Same Name',
      artist: 'Bob',
    );

    expect(result.map((s) => s.path).toList(), ['/m/same2.flac']);
  });

  test('不传 artist 时退化为只按标题查', () async {
    await insertSong(path: '/m/any1.flac', title: 'Any Title', artist: 'Alice');
    await insertSong(path: '/m/any2.flac', title: 'Any Title', artist: 'Bob');

    final result = await db.findSongsByTitleAndArtist(title: 'Any Title');

    expect(result.length, 2);
  });

  test('本地 artist 为空的记录不因艺术家条件被排除', () async {
    await insertSong(path: '/m/empty.flac', title: 'Empty Artist', artist: '');

    final result = await db.findSongsByTitleAndArtist(
      title: 'Empty Artist',
      artist: 'Someone',
    );

    expect(result.map((s) => s.path).toList(), ['/m/empty.flac']);
  });

  test('艺术家写法差异（feat. / 并列）仍能匹配', () async {
    await insertSong(
      path: '/m/feat.flac',
      title: 'Feat Song',
      artist: 'Alice feat. Carol',
    );

    final result = await db.findSongsByTitleAndArtist(
      title: 'Feat Song',
      artist: 'Alice',
    );

    expect(result.map((s) => s.path).toList(), ['/m/feat.flac']);
  });

  test('标题大小写不敏感', () async {
    await insertSong(path: '/m/case.flac', title: 'Case Test', artist: 'Alice');

    final result = await db.findSongsByTitleAndArtist(
      title: '  case test  ',
      artist: 'alice',
    );

    expect(result.length, 1);
  });
}
