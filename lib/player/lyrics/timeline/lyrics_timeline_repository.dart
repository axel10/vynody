import 'package:drift/drift.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'lyrics_timeline_entry.dart';

class LyricsTimelineRepository {
  LyricsTimelineRepository({MetadataDatabase? db})
      : _db = db ?? MetadataDatabase();

  final MetadataDatabase _db;
  static const int maxHistoryCount = 10;

  Future<List<LyricsTimelineEntry>> getHistory(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) return const [];

    final rows = await _db.getLyricsHistories(normalized, limit: maxHistoryCount);
    return rows.map((r) => LyricsTimelineEntry(
      id: r.id,
      cacheKey: r.cacheKey,
      actionType: r.actionType,
      description: r.description,
      lyrics: r.lyrics,
      translation: r.translation,
      timelineOffsetMillis: r.timelineOffsetMillis,
      createdAtMillis: r.createdAtMillis,
    )).toList();
  }

  Future<void> saveEntry(LyricsTimelineEntry entry) async {
    final normalized = entry.cacheKey.trim();
    if (normalized.isEmpty) return;

    final companion = LyricsHistoriesCompanion(
      cacheKey: Value(normalized),
      actionType: Value(entry.actionType),
      description: Value(entry.description),
      lyrics: Value(entry.lyrics),
      translation: Value(entry.translation),
      timelineOffsetMillis: Value(entry.timelineOffsetMillis),
      createdAtMillis: Value(entry.createdAtMillis),
    );

    await _db.insertLyricsHistory(companion);
    await _db.trimLyricsHistories(normalized, maxCount: maxHistoryCount);
  }

  Future<void> clearHistory(String cacheKey) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) return;
    await _db.clearLyricsHistoriesByKey(normalized);
  }
}
