import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

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

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_migration_test_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(
      supportPath: supportDirectory.path,
    );
  });

  tearDown(() async {
    try {
      await MetadataDatabase().close();
    } catch (_) {}
    try {
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('Migrates v38 lyrics cache to v40 pathKey without collision, restoring real paths', () async {
    final dbFile = File(p.join(supportDirectory.path, 'metadata.db'));
    final rawDb = sqlite.sqlite3.open(dbFile.path);

    // 1. 创建 v38 结构表
    //
    // songs 表按 v38 的真实结构保留迁移会读写的列：
    // genres（from < 11 引入）、metadataTextScanned（from < 18 引入）、
    // isAppModified（from < 28 引入）。from < 43 / from < 44 的 UPDATE 依赖这三列，
    // 缺任意一列都会让迁移在真实 v38 库上同样失败，因此这里必须保留。
    rawDb.execute('''
      CREATE TABLE songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE,
        title TEXT,
        album TEXT,
        artist TEXT,
        genres TEXT,
        metadataTextScanned INTEGER,
        isAppModified INTEGER
      );

      -- v38 已存在 remote_songs（from < 32 引入），迁移会为其补 year 列
      CREATE TABLE remote_songs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serverId TEXT NOT NULL,
        remoteId TEXT NOT NULL,
        virtualUri TEXT NOT NULL,
        UNIQUE(virtualUri)
      );

      CREATE TABLE lyrics_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cacheKey TEXT NOT NULL,
        source TEXT NOT NULL,
        languageCode TEXT NOT NULL DEFAULT '',
        isSynced INTEGER NOT NULL,
        syncedLyrics TEXT,
        syncedLinesJson TEXT NOT NULL,
        timelineOffsetMillis INTEGER NOT NULL,
        updatedAtMillis INTEGER NOT NULL,
        UNIQUE(cacheKey, source, languageCode)
      );

      CREATE TABLE lyrics_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cacheKey TEXT NOT NULL,
        actionType TEXT NOT NULL,
        description TEXT NOT NULL,
        lyrics TEXT NOT NULL,
        translation TEXT,
        timelineOffsetMillis INTEGER NOT NULL DEFAULT 0,
        createdAtMillis INTEGER NOT NULL
      );

      CREATE TABLE lyrics_translation_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cacheKey TEXT NOT NULL,
        languageCode TEXT NOT NULL DEFAULT 'zh',
        translatedText TEXT NOT NULL,
        translatedLinesJson TEXT NOT NULL,
        provider TEXT,
        updatedAtMillis INTEGER NOT NULL,
        UNIQUE(cacheKey, languageCode)
      );

      PRAGMA user_version = 38;
    ''');

    const testSongPath = r'C:\Users\Administrator\Downloads\OneRepublic - Someday.flac';
    rawDb.execute(
      '''
      INSERT INTO songs (
        path, title, album, artist, metadataTextScanned, isAppModified
      ) VALUES (?, ?, ?, ?, 1, 0)
      ''',
      [testSongPath, 'Someday', 'Human', 'OneRepublic'],
    );

    // 插入会导致旧迁移崩溃的冲突数据：
    // id 1229: 带时长的 5 段 key
    // id 1230: 不带时长的 4 段 key（相同 source 和 languageCode）
    // id 1231: manual_adjust 记录（更高优先级）
    rawDb.execute(
      '''
      INSERT INTO lyrics_cache (
        id, cacheKey, source, languageCode, isSynced, syncedLyrics,
        syncedLinesJson, timelineOffsetMillis, updatedAtMillis
      ) VALUES
      (1230, 'c_users_administrator_downloads_onerepublic_someday_flac|someday|onerepublic|human', 'lrclib', '', 1, '[00:01.00]Lrclib 4-part', '[]', 0, 1000),
      (1229, 'c_users_administrator_downloads_onerepublic_someday_flac|someday|onerepublic|human|187', 'lrclib', '', 1, '[00:01.00]Lrclib 5-part', '[]', 0, 2000),
      (1231, 'c_users_administrator_downloads_onerepublic_someday_flac|someday|onerepublic|human', 'manual_adjust', '', 1, '[00:01.00]Manual Adjusted', '[]', 150, 3000);
      ''',
    );

    rawDb.execute(
      '''
      INSERT INTO lyrics_history (
        id, cacheKey, actionType, description, lyrics, translation, timelineOffsetMillis, createdAtMillis
      ) VALUES
      (1, 'c_users_administrator_downloads_onerepublic_someday_flac|someday|onerepublic|human|187', 'manual_edit', 'Test edit', '[00:01.00]Edited', NULL, 150, 3000);
      ''',
    );

    rawDb.execute(
      '''
      INSERT INTO lyrics_translation_cache (
        id, cacheKey, languageCode, translatedText, translatedLinesJson, provider, updatedAtMillis
      ) VALUES
      (1, 'c_users_administrator_downloads_onerepublic_someday_flac|someday|onerepublic|human|187', 'zh', '某一天', '[]', 'bing', 3000);
      ''',
    );

    rawDb.close();

    // 2. 使用 MetadataDatabase 打开触发 Drift onUpgrade 迁移
    final db = MetadataDatabase();
    await db.ensureOpen();

    // 3. 验证迁移成功，路径被正确还原并规范化
    final normalizedPath = ScannerPathUtils.normalizePath(testSongPath);
    final cache = await db.getLyricsCache(normalizedPath);

    expect(cache, isNotNull);
    expect(cache!.cacheKey, normalizedPath);
    // 应选出优先级最高的 manual_adjust
    expect(cache.source, LyricsCacheSource.manualAdjust);
    expect(cache.syncedLyrics, '[00:01.00]Manual Adjusted');
    expect(cache.timelineOffsetMillis, 150);

    // 验证历史记录的 key 也被还原
    final histories = await db.getLyricsHistories(normalizedPath);
    expect(histories.length, 1);
    expect(histories.first.cacheKey, normalizedPath);
    expect(histories.first.description, 'Test edit');

    // 验证翻译缓存的 key 也被还原
    final translations = await db.getLyricsTranslationCaches(normalizedPath);
    expect(translations.length, 1);
    expect(translations.first.cacheKey, normalizedPath);
    expect(translations.first.translatedText, '某一天');
  });
}
