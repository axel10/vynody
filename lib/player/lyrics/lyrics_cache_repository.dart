import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

class LyricsCacheRepository {
  LyricsCacheRepository({MetadataDatabase? db})
    : _db = db ?? MetadataDatabase();

  final MetadataDatabase _db;

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) {
    return _db.getLyricsCache(cacheKey);
  }

  /// 基于 [LyricsQuery] 的候选 cacheKeys 进行时长容差查询单条记录
  Future<LyricsCacheRecord?> getLyricsCacheTolerant(
    LyricsQuery query, {
    bool ignoreNone = true,
  }) async {
    for (final key in query.candidateCacheKeys) {
      final record = await getLyricsCache(key);
      if (record != null) {
        if (ignoreNone && record.source == LyricsCacheSource.none) {
          continue;
        }
        return record;
      }
    }
    return null;
  }

  Stream<LyricsCacheRecord?> watchLyricsCache(String cacheKey) {
    return _db.watchLyricsCache(cacheKey);
  }

  Future<List<LyricsCacheRecord>> getLyricsCaches(String cacheKey) {
    return _db.getLyricsCaches(cacheKey);
  }

  /// 基于 [LyricsQuery] 的候选 cacheKeys 查询所有可用缓存记录并去重
  Future<List<LyricsCacheRecord>> getLyricsCachesTolerant(
    LyricsQuery query, {
    bool ignoreNone = true,
  }) async {
    final records = <LyricsCacheRecord>[];
    final seen = <String>{};
    for (final key in query.candidateCacheKeys) {
      final list = await getLyricsCaches(key);
      for (final r in list) {
        if (ignoreNone && r.source == LyricsCacheSource.none) continue;
        final identity = '${r.source.dbValue}|${r.languageCode}';
        if (seen.add(identity)) {
          records.add(r);
        }
      }
    }
    return records;
  }

  Stream<List<LyricsCacheRecord>> watchLyricsCaches(String cacheKey) {
    return _db.watchLyricsCaches(cacheKey);
  }

  Future<void> saveLyricsCache(LyricsCacheRecord record) {
    return _db.insertOrUpdateLyricsCache(record);
  }

  Future<List<LyricsTranslationCacheRecord>> getLyricsTranslationCaches(
    String cacheKey,
  ) {
    return _db.getLyricsTranslationCaches(cacheKey);
  }

  Stream<List<LyricsTranslationCacheRecord>> watchLyricsTranslationCaches(
    String cacheKey,
  ) {
    return _db.watchLyricsTranslationCaches(cacheKey);
  }

  Future<void> saveLyricsTranslationCache(LyricsTranslationCacheRecord record) {
    return _db.insertOrUpdateLyricsTranslationCache(record);
  }

  Future<void> clearLyricsCache() {
    return _db.clearLyricsCache();
  }

  Future<void> clearLyricsCacheByKey(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) return;
    await _db.clearLyricsCacheByKey(normalized);
  }

  /// 基于 [LyricsQuery] 的候选 cacheKeys 清除所有对应缓存
  Future<void> clearLyricsCacheTolerant(LyricsQuery query) async {
    for (final key in query.candidateCacheKeys) {
      await clearLyricsCacheByKey(key);
    }
  }

  Future<void> clearLyricsTranslationCache() {
    return _db.clearLyricsTranslationCache();
  }

  Future<void> clearLyricsTranslationCacheByKey(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) return;
    await _db.clearLyricsTranslationCacheByKey(normalized);
  }

  Future<void> clearAllLyricsCaches() async {
    await clearLyricsCache();
    await clearLyricsTranslationCache();
  }

  Future<void> clearAllLyricsCachesByKey(String cacheKey) async {
    await clearLyricsCacheByKey(cacheKey);
    await clearLyricsTranslationCacheByKey(cacheKey);
  }

  Future<List<LyricsCacheRecord>> getAllLyricsCaches() {
    return _db.getAllLyricsCaches();
  }

  Future<List<LyricsTranslationCacheRecord>> getAllLyricsTranslationCaches() {
    return _db.getAllLyricsTranslationCaches();
  }
}
