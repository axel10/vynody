import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/sharing/lyrics_translation_importer.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TestPathProviderPlatform({required this.supportPath});
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

const String _songPath = 'C:/Music/Pop/OneRepublic - Someday.flac';

LyricsTranslationCacheRecord _translation(
  String languageCode,
  String text, {
  int at = 1000,
}) {
  return LyricsTranslationCacheRecord(
    cacheKey: _songPath,
    languageCode: languageCode,
    translatedText: text,
    translatedLines: [text],
    provider: 'deepseek',
    updatedAtMillis: at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();
  final importer = LyricsTranslationImporter(db);
  late String cacheKey;

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_translation_importer_test_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(
      supportPath: supportDirectory.path,
    );
    await db.ensureOpen();
    cacheKey = ScannerPathUtils.normalizeLyricCacheKey(_songPath);
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

  setUp(() async {
    await db.clearLyricsTranslationCacheByKey(cacheKey);
  });

  Future<Map<String, LyricsTranslationCacheRecord>> readLocal() async {
    final rows = await db.getLyricsTranslationCaches(cacheKey);
    return {for (final row in rows) row.languageCode: row};
  }

  test('本机多语言与人远端语言取并集，不删除本机独有语言', () async {
    await db.insertOrUpdateLyricsTranslationCache(
      _translation('zh-cn', '本机中文', at: 1000),
    );
    await db.insertOrUpdateLyricsTranslationCache(
      _translation('ja', '本機の日本語', at: 1000),
    );
    await db.insertOrUpdateLyricsTranslationCache(
      _translation('ko', '기기 한국어', at: 1000),
    );

    final written = await importer.merge(
      cacheKey: cacheKey,
      incoming: [_translation('zh-cn', '远端中文', at: 2000)],
    );

    expect(written, 1);
    final local = await readLocal();
    // 关键断言：本机独有的语言没有被「整表清空」带走。
    expect(local.keys.toSet(), {'zh-cn', 'ja', 'ko'});
    expect(local['zh-cn']!.translatedText, '远端中文');
    expect(local['ja']!.translatedText, '本機の日本語');
    expect(local['ko']!.translatedText, '기기 한국어');
  });

  test('远端译文不比本地新时跳过，保留本地内容', () async {
    await db.insertOrUpdateLyricsTranslationCache(
      _translation('zh-cn', '本机较新', at: 5000),
    );

    final written = await importer.merge(
      cacheKey: cacheKey,
      incoming: [_translation('zh-cn', '远端较旧', at: 1000)],
    );

    expect(written, 0);
    expect((await readLocal())['zh-cn']!.translatedText, '本机较新');
  });

  test('语言码变体归一到同一行，不会写出重复语言', () async {
    await db.insertOrUpdateLyricsTranslationCache(
      _translation('zh-cn', '本机中文', at: 1000),
    );

    await importer.merge(
      cacheKey: cacheKey,
      incoming: [_translation('zh_CN', '远端中文', at: 2000)],
    );

    final local = await readLocal();
    expect(local.keys.toList(), ['zh-cn']);
    expect(local['zh-cn']!.translatedText, '远端中文');
  });

  test('空语言码被丢弃，不产生脏行', () async {
    final written = await importer.merge(
      cacheKey: cacheKey,
      incoming: [_translation('', '没有语言码', at: 2000)],
    );

    expect(written, 0);
    expect(await readLocal(), isEmpty);
  });

  test('空载荷不改动数据库', () async {
    await db.insertOrUpdateLyricsTranslationCache(
      _translation('ja', '日本語', at: 1000),
    );

    expect(await importer.merge(cacheKey: cacheKey, incoming: const []), 0);
    expect((await readLocal()).keys.toSet(), {'ja'});
  });

  group('LyricsCacheRecord.toImported', () {
    LyricsCacheRecord remote() {
      return LyricsCacheRecord(
        id: 4242,
        cacheKey: 'remote-cache-key',
        source: LyricsCacheSource.aiKaraoke,
        selectedTranslationLanguage: 'ko',
        isSynced: true,
        syncedLyrics: '[00:01.00]hello',
        syncedLines: const [],
        timelineOffsetMillis: 300,
        updatedAtMillis: 1700,
      );
    }

    test('丢弃远端自增主键，否则会按 id 命中本地另一首歌的行', () {
      expect(remote().toImported(cacheKey: 'local').id, isNull);
    });

    test('换成本地派生的 cacheKey', () {
      expect(remote().toImported(cacheKey: 'local').cacheKey, 'local');
    });

    test('不搬运 selectedTranslationLanguage（设备级偏好）', () {
      expect(
        remote().toImported(cacheKey: 'local').selectedTranslationLanguage,
        isEmpty,
      );
    });

    test('内容字段逐项保留，含偏移', () {
      final imported = remote().toImported(cacheKey: 'local');
      expect(imported.source, LyricsCacheSource.aiKaraoke);
      expect(imported.isSynced, isTrue);
      expect(imported.syncedLyrics, '[00:01.00]hello');
      expect(imported.timelineOffsetMillis, 300);
      expect(imported.updatedAtMillis, 1700);
    });
  });
}
