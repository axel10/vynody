import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'lyrics_timeline_entry.dart';
import 'lyrics_timeline_repository.dart';

final lyricsTimelineServiceProvider = Provider<LyricsTimelineService>((ref) {
  return LyricsTimelineService.instance;
});

class LyricsTimelineService {
  LyricsTimelineService({LyricsTimelineRepository? repository})
      : _repository = repository ?? LyricsTimelineRepository();

  static final LyricsTimelineService instance = LyricsTimelineService();

  final LyricsTimelineRepository _repository;

  /// The current maximum number of history entries retained per song.
  int get maxHistoryCount => _repository.maxHistoryCount;

  /// Retrieves the history of modifications for a given song cacheKey (up to [maxHistoryCount] entries, newest first).
  Future<List<LyricsTimelineEntry>> getHistory(String cacheKey) {
    final normalized = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    return _repository.getHistory(normalized);
  }

  /// Ensures an 'initial' baseline snapshot exists in the timeline for [cacheKey].
  ///
  /// If the timeline history for this song is completely empty and [lyrics] is non-empty,
  /// an initial entry will be created and saved.
  /// If history already exists, this is a no-op.
  Future<void> ensureInitialSnapshot({
    required String cacheKey,
    required String lyrics,
    String? translation,
    int timelineOffsetMillis = 0,
    String? description,
  }) async {
    final normalizedKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedKey.isEmpty) return;

    final trimmedLyrics = lyrics.trim();
    if (trimmedLyrics.isEmpty) return;

    final existingHistory = await _repository.getHistory(normalizedKey);
    if (existingHistory.isNotEmpty) return;

    final initialEntry = LyricsTimelineEntry(
      cacheKey: normalizedKey,
      actionType: LyricsTimelineActionType.initial,
      description: description ?? 'Initial',
      lyrics: trimmedLyrics,
      translation: translation?.trim(),
      timelineOffsetMillis: timelineOffsetMillis,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await _repository.saveEntry(initialEntry);
  }

  /// Records a snapshot into the timeline.
  ///
  /// If the history for this [cacheKey] is currently empty and [previousLyrics] is non-empty,
  /// an 'initial' snapshot will automatically be prepended first to preserve the baseline version.
  ///
  /// Duplicate snapshots with identical lyrics, translation and offset are ignored.
  Future<void> recordSnapshot({
    required String cacheKey,
    required String actionType,
    required String description,
    required String lyrics,
    String? translation,
    int timelineOffsetMillis = 0,
    String? previousLyrics,
    String? previousTranslation,
    int previousOffsetMillis = 0,
    String? previousDescription,
  }) async {
    final normalizedKey = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    if (normalizedKey.isEmpty) return;

    final trimmedLyrics = lyrics.trim();
    if (trimmedLyrics.isEmpty) return;

    final existingHistory = await _repository.getHistory(normalizedKey);

    // If there is no history yet, but there was a previous valid lyrics text, record the initial baseline snapshot.
    if (existingHistory.isEmpty &&
        previousLyrics != null &&
        previousLyrics.trim().isNotEmpty &&
        (previousLyrics.trim() != trimmedLyrics ||
            previousOffsetMillis != timelineOffsetMillis)) {
      final initialEntry = LyricsTimelineEntry(
        cacheKey: normalizedKey,
        actionType: LyricsTimelineActionType.initial,
        description: previousDescription ?? 'Initial',
        lyrics: previousLyrics.trim(),
        translation: previousTranslation?.trim(),
        timelineOffsetMillis: previousOffsetMillis,
        createdAtMillis: DateTime.now().millisecondsSinceEpoch - 1000,
      );
      await _repository.saveEntry(initialEntry);
    }

    // Check against latest snapshot to prevent duplicate consecutive entries
    if (existingHistory.isNotEmpty) {
      final latest = existingHistory.first;
      final isSameLyrics = latest.lyrics.trim() == trimmedLyrics;
      final isSameTrans = (latest.translation ?? '').trim() == (translation ?? '').trim();
      final isSameOffset = latest.timelineOffsetMillis == timelineOffsetMillis;
      if (isSameLyrics && isSameTrans && isSameOffset) {
        return;
      }
    }

    final entry = LyricsTimelineEntry(
      cacheKey: normalizedKey,
      actionType: actionType,
      description: description,
      lyrics: trimmedLyrics,
      translation: translation?.trim(),
      timelineOffsetMillis: timelineOffsetMillis,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    await _repository.saveEntry(entry);
  }

  /// Clears timeline history for a specific song.
  Future<void> clearHistory(String cacheKey) {
    final normalized = ScannerPathUtils.normalizeLyricCacheKey(cacheKey);
    return _repository.clearHistory(normalized);
  }
}
