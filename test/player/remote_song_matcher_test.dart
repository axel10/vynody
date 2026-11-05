import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/remote_song_matcher.dart';

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
      'remote_song_matcher_test_',
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

  var seq = 0;
  Future<void> insertSong({
    required String title,
    required String artist,
    String album = 'Album',
    int? duration,
    String? path,
  }) async {
    seq++;
    await db.insertOrUpdateSong(
      SongMetadata(
        path: path ?? '/matcher/$seq.flac',
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      ),
    );
  }

  Future<RemoteSongMatcher> matcher() => RemoteSongMatcher.build(db: db);

  group('文本归一化', () {
    test('大小写、标点、空白都不影响', () {
      expect(
        normalizeSongMatchText('  Hello, World!  '),
        normalizeSongMatchText('helloworld'),
      );
      expect(normalizeSongMatchText('晴天'), '晴天');
      expect(normalizeSongMatchText(null), '');
    });

    test('feat. / ft. / & / 逗号 拆出共同的参与者', () {
      final feat = artistMatchKeys('Alice feat. Carol');
      final comma = artistMatchKeys('Alice, Carol');
      expect(feat, contains('alice'));
      expect(comma, contains('alice'));
      expect(feat, contains('carol'));
      expect(comma, contains('carol'));
    });

    test('不拆斜杠，避免短名字误命中 AC/DC', () {
      expect(artistMatchKeys('AC/DC'), ['acdc']);
    });
  });

  group('索引匹配', () {
    test('标题 + 艺术家归一化后命中', () async {
      await insertSong(title: 'Case Test', artist: 'Alice', path: '/m/case.flac');

      final match = (await matcher()).matchByMetadata(
        title: '  case test ',
        artist: 'alice',
      );

      expect(match.matches.single.path, '/m/case.flac');
      expect(match.ambiguous, isFalse);
    });

    test('艺术家写法差异（feat. 与并列）互相命中', () async {
      await insertSong(
        title: 'Feat Song',
        artist: 'Alice feat. Carol',
        path: '/m/feat.flac',
      );

      final match = (await matcher()).matchByMetadata(
        title: 'Feat Song',
        artist: 'Alice, Carol',
      );

      expect(match.matches.single.path, '/m/feat.flac');
    });

    test('远端没写艺术家时放宽到只按标题', () async {
      await insertSong(title: 'No Artist', artist: 'Alice', path: '/m/na.flac');

      final match = (await matcher()).matchByMetadata(title: 'No Artist');

      expect(match.matches.single.path, '/m/na.flac');
    });

    test('本地艺术家为空时不因远端艺术家不同而漏掉', () async {
      await insertSong(title: 'Empty Local', artist: '', path: '/m/el.flac');

      final match = (await matcher()).matchByMetadata(
        title: 'Empty Local',
        artist: 'Someone',
      );

      expect(match.matches.single.path, '/m/el.flac');
    });

    test('艺术家不同不会仅凭标题错配', () async {
      // 远端是 Carol 的 Home，本机只有 Bob 的 Home：应当匹配不到，而不是
      // 把 Bob 那首的歌词写过去。
      await insertSong(title: 'Home', artist: 'Bob', path: '/m/bob.flac');

      final match = (await matcher()).matchByMetadata(
        title: 'Home',
        artist: 'Carol',
        durationMs: 200000,
      );

      expect(match.isEmpty, isTrue);
    });

    test('空标题不参与匹配', () async {
      await insertSong(title: '', artist: 'Alice', path: '/m/blank.flac');

      final match = (await matcher()).matchByMetadata(title: '  ', artist: '');

      expect(match.isEmpty, isTrue);
    });

    test('文件名索引大小写与分隔符不敏感', () async {
      await insertSong(
        title: 'By File',
        artist: 'Alice',
        path: '/Volumes/Music/By File.flac',
      );

      final m = await matcher();
      expect(m.matchByFileName('by file.flac').single.title, 'By File');
      expect(m.matchByFileName(r'By File.flac').single.title, 'By File');
    });
  });

  group('多候选收敛', () {
    test('时长差 3 秒内视为同一首，超出则收敛到更接近的版本', () async {
      await insertSong(
        title: 'Two Versions',
        artist: 'Alice',
        duration: 200000,
        path: '/m/studio.flac',
      );
      await insertSong(
        title: 'Two Versions',
        artist: 'Alice',
        duration: 260000,
        path: '/m/live.flac',
      );

      final match = (await matcher()).matchByMetadata(
        title: 'Two Versions',
        artist: 'Alice',
        durationMs: 261000,
      );

      expect(match.matches.single.path, '/m/live.flac');
      expect(match.ambiguous, isFalse);
    });

    test('时长也相同时用专辑收敛', () async {
      await insertSong(
        title: 'Album Pick',
        artist: 'Alice',
        album: 'Studio',
        duration: 200000,
        path: '/m/ap-studio.flac',
      );
      await insertSong(
        title: 'Album Pick',
        artist: 'Alice',
        album: 'Live',
        duration: 200000,
        path: '/m/ap-live.flac',
      );

      final match = (await matcher()).matchByMetadata(
        title: 'Album Pick',
        artist: 'Alice',
        album: 'Live',
        durationMs: 200000,
      );

      expect(match.matches.single.path, '/m/ap-live.flac');
      expect(match.ambiguous, isFalse);
    });

    test('专辑也分不开时标记 ambiguous，并按时长差值排序', () async {
      await insertSong(
        title: 'Dup',
        artist: 'Alice',
        album: 'Same',
        duration: 200000,
        path: '/m/dup-a.flac',
      );
      await insertSong(
        title: 'Dup',
        artist: 'Alice',
        album: 'Same',
        duration: 202000,
        path: '/m/dup-b.flac',
      );

      final match = (await matcher()).matchByMetadata(
        title: 'Dup',
        artist: 'Alice',
        album: 'Same',
        durationMs: 201900,
      );

      expect(match.ambiguous, isTrue);
      expect(match.matches.length, 2);
      expect(match.matches.first.path, '/m/dup-b.flac');
    });
  });
}
