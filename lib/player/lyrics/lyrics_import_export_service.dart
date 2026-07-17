import 'dart:convert';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';

class LyricsConflict {
  final LyricsCacheRecord imported;
  final LyricsCacheRecord existing;
  final List<LyricsTranslationCacheRecord> importedTranslations;

  const LyricsConflict({
    required this.imported,
    required this.existing,
    required this.importedTranslations,
  });
}

class LyricsScanResult {
  final int totalImported;
  final int autoImportedCount;
  final List<LyricsConflict> conflicts;

  const LyricsScanResult({
    required this.totalImported,
    required this.autoImportedCount,
    required this.conflicts,
  });
}

class LyricsImportExportService {
  const LyricsImportExportService();

  /// Parse cache key into human readable metadata
  static Map<String, String> parseCacheKey(String cacheKey) {
    final parts = cacheKey.split('|');
    if (parts.length >= 5) {
      final durationSec = parts[parts.length - 1];
      final album = parts[parts.length - 2];
      final artist = parts[parts.length - 3];
      final title = parts[parts.length - 4];
      return {
        'title': title.replaceAll('_', ' ').trim(),
        'artist': artist.replaceAll('_', ' ').trim(),
        'album': album.replaceAll('_', ' ').trim(),
        'duration': durationSec,
      };
    }
    return {
      'title': cacheKey,
      'artist': '',
      'album': '',
      'duration': '',
    };
  }

  /// Exports all lyrics cache and translation records to a JSON string.
  Future<String> exportLyrics(LyricsCacheRepository repository) async {
    final caches = await repository.getAllLyricsCaches();
    final translations = await repository.getAllLyricsTranslationCaches();

    final backup = {
      'version': 1,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'lyricsCaches': caches.map((c) => c.toMap()).toList(),
      'lyricsTranslationCaches': translations.map((t) => t.toMap()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Scans a JSON backup string and processes imports.
  /// Records without conflicts are imported immediately.
  /// Conflicting records are returned for user resolution.
  Future<LyricsScanResult> scanBackup(
    String jsonStr,
    LyricsCacheRepository repository,
  ) async {
    final Map<String, dynamic> backup = jsonDecode(jsonStr) as Map<String, dynamic>;

    final List<dynamic> rawCaches = backup['lyricsCaches'] as List? ?? [];
    final List<dynamic> rawTranslations = backup['lyricsTranslationCaches'] as List? ?? [];

    final importedRecords = rawCaches
        .map((e) => LyricsCacheRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    final importedTranslations = rawTranslations
        .map((e) => LyricsTranslationCacheRecord.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    // Group translations by cacheKey for easy retrieval
    final Map<String, List<LyricsTranslationCacheRecord>> translationMap = {};
    for (final trans in importedTranslations) {
      translationMap.putIfAbsent(trans.cacheKey, () => []).add(trans);
    }

    int autoImportedCount = 0;
    final List<LyricsConflict> conflicts = [];

    for (final imported in importedRecords) {
      final existing = await repository.getLyricsCache(imported.cacheKey);
      final recordTranslations = translationMap[imported.cacheKey] ?? [];

      if (existing == null) {
        // No conflict: import immediately
        await repository.saveLyricsCache(imported);
        for (final trans in recordTranslations) {
          await repository.saveLyricsTranslationCache(trans);
        }
        autoImportedCount++;
      } else if (_isRecordDifferent(imported, existing)) {
        // Conflict detected: save for manual/batch resolution
        conflicts.add(
          LyricsConflict(
            imported: imported,
            existing: existing,
            importedTranslations: recordTranslations,
          ),
        );
      } else {
        // Identical records: we can save/overwrite silently without conflict or just skip
        await repository.saveLyricsCache(imported);
        for (final trans in recordTranslations) {
          await repository.saveLyricsTranslationCache(trans);
        }
        autoImportedCount++;
      }
    }

    return LyricsScanResult(
      totalImported: importedRecords.length,
      autoImportedCount: autoImportedCount,
      conflicts: conflicts,
    );
  }

  /// Imports a specific record and its associated translations into the database.
  Future<void> importRecord(
    LyricsCacheRecord record,
    List<LyricsTranslationCacheRecord> translations,
    LyricsCacheRepository repository,
  ) async {
    await repository.saveLyricsCache(record);
    for (final trans in translations) {
      await repository.saveLyricsTranslationCache(trans);
    }
  }

  bool _isRecordDifferent(LyricsCacheRecord imported, LyricsCacheRecord existing) {
    if (imported.isSynced != existing.isSynced) return true;
    if (imported.syncedLyrics != existing.syncedLyrics) return true;
    if (imported.timelineOffsetMillis != existing.timelineOffsetMillis) return true;
    if (imported.source != existing.source) return true;
    if (imported.languageCode != existing.languageCode) return true;

    if (imported.syncedLines.length != existing.syncedLines.length) return true;
    for (int i = 0; i < imported.syncedLines.length; i++) {
      if (imported.syncedLines[i].text != existing.syncedLines[i].text ||
          imported.syncedLines[i].timestamp != existing.syncedLines[i].timestamp) {
        return true;
      }
    }
    return false;
  }
}
