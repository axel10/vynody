import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/lrc_utils.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TestPathProviderPlatform({required this.supportPath});
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

/// rich love / OneRepublic & Seeb —— 用来做进歌词面板查询流程的回归夹具。
///
/// 典型在两点：艺术家是 `A & B` 的多艺人串（容易被元数据清洗吞掉后半段），
/// 歌词是标准逐行带时间戳的 LRC（容易被半路重解析成不同的行集合）。
const String _richLovePath =
    'C:/Music/Pop/OneRepublic & Seeb - Rich Love.mp3';
const String _richLoveTitle = 'rich love';
const String _richLoveArtist = 'OneRepublic & Seeb';
const String _richLoveLrc = r'''
[00:00.72]I remember talking and drinking what we could find
[00:04.87]Burnin' all those candles and staying up through the night
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();
  final cacheRepo = LyricsCacheRepository(db: db);

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_entry_flow_test_',
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

  group('来源标签映射', () {
    test('本地 lrc 与媒体库服务端歌词都归到 external', () {
      expect(
        LyricsCacheSource.fromExternalSourceTag('local_lrc'),
        LyricsCacheSource.external,
      );
      expect(
        LyricsCacheSource.fromExternalSourceTag('remote_server'),
        LyricsCacheSource.external,
      );
      expect(
        LyricsCacheSource.fromExternalSourceTag('embedded'),
        LyricsCacheSource.embedded,
      );
      expect(
        LyricsCacheSource.fromExternalSourceTag('lrclib'),
        LyricsCacheSource.lrclib,
      );
    });

    test('优先级表覆盖除 none 外的全部来源且不重复', () {
      final expected = LyricsCacheSource.values
          .where((source) => source != LyricsCacheSource.none)
          .toSet();

      expect(kLyricsSourcePreferenceOrder.toSet(), expected);
      expect(kLyricsSourcePreferenceOrder.length, expected.length);
    });

    test('用户手工调整过的歌词排在最前', () {
      expect(
        kLyricsSourcePreferenceOrder.first,
        LyricsCacheSource.manualAdjust,
      );
    });
  });

  group('缓存键与元数据解耦', () {
    test('缓存键只由文件路径决定，与标题、艺术家、时长无关', () {
      final withFullMetadata = LyricsQuery(
        filePath: _richLovePath,
        fileName: 'OneRepublic & Seeb - Rich Love.mp3',
        title: _richLoveTitle,
        artist: _richLoveArtist,
        album: 'Single',
        duration: const Duration(minutes: 3, seconds: 20),
      );
      // 刚切歌、元数据还没回填时的样子：没有 duration，也没有 title/artist。
      final bare = LyricsQuery(
        filePath: _richLovePath,
        fileName: '',
        title: '',
      );

      expect(withFullMetadata.cacheKey, bare.cacheKey);
      expect(
        bare.cacheKey,
        ScannerPathUtils.normalizeLyricCacheKey(_richLovePath),
      );
    });

    test('写入后仅凭路径即可取回，不需要构造带时长的查询', () async {
      final key = ScannerPathUtils.normalizeLyricCacheKey(_richLovePath);
      await cacheRepo.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: _richLovePath,
          source: LyricsCacheSource.external,
          isSynced: true,
          syncedLyrics: _richLoveLrc,
          syncedLines: LrcUtils.parseLyricsWithTranslation(
            _richLoveLrc,
          ).syncedLines,
          timelineOffsetMillis: 0,
          updatedAtMillis: 1,
        ),
      );

      final record = await cacheRepo.getLyricsCache(key);
      expect(record, isNotNull);
      expect(record!.syncedLyrics, contains('I remember talking'));
      expect(record.syncedLines.length, 2);
    });
  });

  group('rich love 歌词落库与回读', () {
    test('行与时间戳原样保留，展示与库内同源', () async {
      final key = ScannerPathUtils.normalizeLyricCacheKey(_richLovePath);
      final parsed = LrcUtils.parseLyricsWithTranslation(_richLoveLrc);

      await cacheRepo.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: _richLovePath,
          source: LyricsCacheSource.lrclib,
          isSynced: true,
          syncedLyrics: _richLoveLrc,
          syncedLines: parsed.syncedLines,
          timelineOffsetMillis: 0,
          updatedAtMillis: 2,
        ),
      );

      final record = await cacheRepo.getLyricsCache(key);
      expect(record, isNotNull);
      expect(record!.syncedLines.length, parsed.syncedLines.length);
      expect(
        record.syncedLines.first.timestamp,
        const Duration(milliseconds: 720),
      );
      expect(
        record.syncedLines[1].timestamp,
        const Duration(milliseconds: 4870),
      );
      expect(
        record.syncedLines.first.text,
        'I remember talking and drinking what we could find',
      );
    });

    test('换源只覆盖同一条记录，不会留下两份行集合', () async {
      final key = ScannerPathUtils.normalizeLyricCacheKey(_richLovePath);
      final parsed = LrcUtils.parseLyricsWithTranslation(_richLoveLrc);

      await cacheRepo.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: _richLovePath,
          source: LyricsCacheSource.manualAdjust,
          isSynced: true,
          syncedLyrics: _richLoveLrc,
          syncedLines: parsed.syncedLines,
          timelineOffsetMillis: 300,
          updatedAtMillis: 3,
        ),
      );

      final all = await cacheRepo.getLyricsCaches(key);
      expect(all.length, 1);
      expect(all.single.source, LyricsCacheSource.manualAdjust);
      expect(all.single.timelineOffsetMillis, 300);
      expect(all.single.syncedLines.length, 2);
    });
  });
}
