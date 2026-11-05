import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/sharing/lyrics_import_conflict.dart';
import 'package:vynody/player/sharing/lyrics_package_importer.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TestPathProviderPlatform({required this.supportPath});
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

const String _songPath = 'C:/Music/Pop/OneRepublic - Someday.flac';

/// 构造一个「发送端打包出来」的歌词包，字段与 `sendFiles` / `syncLyricsToDevice`
/// 里生成的一致：`cacheRecord.toMap()` + `translations.map(toMap)`。
Map<String, dynamic> _buildRemotePackage({
  required LyricsCacheSource source,
  required int updatedAtMillis,
  int timelineOffsetMillis = 0,
  List<Map<String, dynamic>> translations = const [],
  int? id,
}) {
  final record = LyricsCacheRecord(
    id: id,
    cacheKey: 'remote-cache-key-${source.dbValue}',
    source: source,
    selectedTranslationLanguage: 'ko',
    isSynced: true,
    syncedLyrics: '[00:01.00]hello\n[00:03.00]world',
    syncedLines: const [
      LyricLine(timestamp: Duration(milliseconds: 1000), text: 'hello'),
      LyricLine(timestamp: Duration(milliseconds: 3000), text: 'world'),
    ],
    timelineOffsetMillis: timelineOffsetMillis,
    updatedAtMillis: updatedAtMillis,
  );
  return {
    'title': 'Someday',
    'artist': 'OneRepublic',
    'album': 'Human',
    'duration_ms': 187000,
    'lyrics_cache': record.toMap(),
    'translations': translations,
  };
}

Map<String, dynamic> _translationMap(
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
  ).toMap();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();
  final importer = LyricsPackageImporter(db);
  late String cacheKey;

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_package_importer_test_',
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

  test('新歌：歌词正文、逐字行、偏移、多语言译文全部落地', () async {
    // 用一个不存在的 key 保证「本地无记录」。
    final localKey = ScannerPathUtils.normalizeLyricCacheKey(
      'C:/Music/Pop/Brand New - Song.flac',
    );

    final outcome = await importer.import(
      localCacheKey: localKey,
      incomingPackage: _buildRemotePackage(
        source: LyricsCacheSource.aiKaraoke,
        updatedAtMillis: 5000,
        timelineOffsetMillis: 300,
        translations: [
          _translationMap('zh-cn', '你好世界', at: 5000),
          _translationMap('ja', 'こんにちは世界', at: 5000),
          _translationMap('ko', '안녕하세요', at: 5000),
        ],
      ),
    );

    expect(outcome, LyricsImportOutcome.added);

    final lyrics = await db.getLyricsCache(localKey);
    expect(lyrics, isNotNull);
    // 关键：这是「重新扫描拿不到」的三类数据。
    expect(lyrics!.timelineOffsetMillis, 300);
    expect(lyrics.source, LyricsCacheSource.aiKaraoke);
    expect(lyrics.syncedLines.length, 2);
    expect(lyrics.syncedLines.first.text, 'hello');
    // 远端自增主键不能带进来。
    expect(lyrics.id, isNot(5000));

    final translations = await db.getLyricsTranslationCaches(localKey);
    expect(
      translations.map((t) => t.languageCode).toSet(),
      {'zh-cn', 'ja', 'ko'},
    );
  });

  test('远端 selectedTranslationLanguage 不覆盖本机选择', () async {
    final localKey = ScannerPathUtils.normalizeLyricCacheKey(
      'C:/Music/Pop/Keep - Choice.flac',
    );
    await db.insertOrUpdateLyricsCache(
      LyricsCacheRecord(
        cacheKey: localKey,
        source: LyricsCacheSource.lrclib,
        selectedTranslationLanguage: 'ja',
        isSynced: true,
        syncedLyrics: '[00:01.00]old',
        syncedLines: const [
          LyricLine(timestamp: Duration(milliseconds: 1000), text: 'old'),
        ],
        timelineOffsetMillis: 0,
        updatedAtMillis: 1000,
      ),
    );

    await importer.import(
      localCacheKey: localKey,
      incomingPackage: _buildRemotePackage(
        source: LyricsCacheSource.aiKaraoke,
        updatedAtMillis: 5000,
      ),
    );

    final lyrics = await db.getLyricsCache(localKey);
    expect(lyrics!.selectedTranslationLanguage, 'ja');
  });

  test('本地来源更优时整条终止，译文一条也不导入', () async {
    final localKey = ScannerPathUtils.normalizeLyricCacheKey(
      'C:/Music/Pop/Prefer - Local.flac',
    );
    await db.insertOrUpdateLyricsCache(
      LyricsCacheRecord(
        cacheKey: localKey,
        source: LyricsCacheSource.embedded,
        isSynced: true,
        syncedLyrics: '[00:01.00]embedded',
        syncedLines: const [
          LyricLine(timestamp: Duration(milliseconds: 1000), text: 'embedded'),
        ],
        timelineOffsetMillis: 0,
        updatedAtMillis: 1000,
      ),
    );

    final outcome = await importer.import(
      localCacheKey: localKey,
      incomingPackage: _buildRemotePackage(
        source: LyricsCacheSource.aiKaraoke,
        updatedAtMillis: 9999999,
        translations: [_translationMap('ja', '日本語')],
      ),
    );

    expect(outcome, LyricsImportOutcome.skipped);
    expect((await db.getLyricsCache(localKey))!.syncedLyrics, '[00:01.00]embedded');
    expect(await db.getLyricsTranslationCaches(localKey), isEmpty);
  });

  test('包缺少 lyrics_cache 时安全跳过', () async {
    final outcome = await importer.import(
      localCacheKey: cacheKey,
      incomingPackage: const {'translations': []},
    );
    expect(outcome, LyricsImportOutcome.skipped);
  });

  test('translations 缺失时仍能导入歌词本体', () async {
    final localKey = ScannerPathUtils.normalizeLyricCacheKey(
      'C:/Music/Pop/No - Translation.flac',
    );
    final package = _buildRemotePackage(
      source: LyricsCacheSource.lrclib,
      updatedAtMillis: 5000,
    )..remove('translations');

    final outcome = await importer.import(
      localCacheKey: localKey,
      incomingPackage: package,
    );

    expect(outcome, LyricsImportOutcome.added);
    expect((await db.getLyricsCache(localKey))!.syncedLines.length, 2);
  });

  test('本地标记「无词」时不被传过来的歌词推翻', () async {
    final localKey = ScannerPathUtils.normalizeLyricCacheKey(
      'C:/Music/Pop/No - Lyrics.flac',
    );
    await db.insertOrUpdateLyricsCache(
      LyricsCacheRecord(
        cacheKey: localKey,
        source: LyricsCacheSource.none,
        isSynced: false,
        syncedLyrics: null,
        syncedLines: const [],
        timelineOffsetMillis: 0,
        updatedAtMillis: 1,
      ),
    );

    final outcome = await importer.import(
      localCacheKey: localKey,
      incomingPackage: _buildRemotePackage(
        source: LyricsCacheSource.aiKaraoke,
        updatedAtMillis: 9999999,
      ),
    );

    expect(outcome, LyricsImportOutcome.skipped);
  });
}
