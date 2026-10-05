import 'package:drift/drift.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'lyrics_timeline_entry.dart';

class LyricsTimelineRepository {
  LyricsTimelineRepository({
    MetadataDatabase? db,
    int Function()? maxCountProvider,
  })  : _db = db ?? MetadataDatabase(),
        _maxCountProvider = maxCountProvider;

  final MetadataDatabase _db;
  final int Function()? _maxCountProvider;

  static int Function()? globalMaxCountProvider;
  static const int defaultMaxHistoryCount = 30;
  static const int maxAllowedHistoryCount = 50;
  static const int minAllowedHistoryCount = 10;

  int get maxHistoryCount =>
      _maxCountProvider?.call() ??
      globalMaxCountProvider?.call() ??
      defaultMaxHistoryCount;

  Future<List<LyricsTimelineEntry>> getHistory(
    String cacheKey, {
    int? limit,
  }) async {
    final normalized = cacheKey.trim();
    if (normalized.isEmpty) return const [];

    final effectiveLimit = limit ?? maxHistoryCount;
    final rows = await _db.getLyricsHistories(normalized, limit: effectiveLimit);
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
