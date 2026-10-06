import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';

class LyricsCacheRepository {
  LyricsCacheRepository({MetadataDatabase? db})
    : _db = db ?? MetadataDatabase();

  final MetadataDatabase _db;

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) {
    return _db.getLyricsCache(cacheKey);
  }

  /// 基于 [LyricsQuery] 的候选 cacheKeys 以及本地文件路径前缀进行容差查询单条记录
  Future<LyricsCacheRecord?> getLyricsCacheTolerant(
    LyricsQuery query, {
    bool ignoreNone = true,
  }) async {
    // 1. 尝试 candidateCacheKeys（精确键及 ±1s/±2s 容差）
    for (final key in query.candidateCacheKeys) {
      final list = await getLyricsCaches(key);
      for (final record in list) {
        if (ignoreNone && record.source == LyricsCacheSource.none) {
          continue;
        }
        return record;
      }
    }

    // 2. 若未命中且为本地文件（含有 filePath 且非远程媒体流协议），
    // 则以物理文件路径前缀查询该文件已有的任意歌词缓存（防止元数据时长与真实解码时长不一致导致假未命中）
    final prefix = query.fileBasedCacheKeyPrefix;
    if (prefix.isNotEmpty && !RemoteMediaResolver.isRemoteUri(query.filePath)) {
      final list = await getLyricsCachesByPrefix(prefix);
      for (final record in list) {
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

  Future<List<LyricsCacheRecord>> getLyricsCachesByPrefix(String prefix) {
    return _db.getLyricsCachesByPrefix(prefix);
  }

  /// 基于 [LyricsQuery] 的候选 cacheKeys 及文件路径前缀查询所有可用缓存记录并去重
  Future<List<LyricsCacheRecord>> getLyricsCachesTolerant(
    LyricsQuery query, {
    bool ignoreNone = true,
  }) async {
    final records = <LyricsCacheRecord>[];
    final seen = <String>{};

    void addRecords(List<LyricsCacheRecord> list) {
      for (final r in list) {
        if (ignoreNone && r.source == LyricsCacheSource.none) continue;
        final identity = '${r.source.dbValue}|${r.languageCode}';
        if (seen.add(identity)) {
          records.add(r);
        }
      }
    }

    // 1. 尝试 candidateCacheKeys
    for (final key in query.candidateCacheKeys) {
      final list = await getLyricsCaches(key);
      addRecords(list);
    }

    // 2. 本地文件基于物理路径前缀兜底补充
    final prefix = query.fileBasedCacheKeyPrefix;
    if (prefix.isNotEmpty && !RemoteMediaResolver.isRemoteUri(query.filePath)) {
      final list = await getLyricsCachesByPrefix(prefix);
      addRecords(list);
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
