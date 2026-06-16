import 'package:vynody/player/metadata/metadata_database.dart';

class LyricsCacheRepository {
  LyricsCacheRepository({MetadataDatabase? db})
    : _db = db ?? MetadataDatabase();

  final MetadataDatabase _db;

  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) {
    return _db.getLyricsCache(cacheKey);
  }

  Stream<LyricsCacheRecord?> watchLyricsCache(String cacheKey) {
    return _db.watchLyricsCache(cacheKey);
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
}
