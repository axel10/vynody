import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_import_export_service.dart';

void main() {
  group('LyricsImportExportService - parseCacheKey', () {
    test('parses correctly formatted cacheKey', () {
      final meta = LyricsImportExportService.parseCacheKey(
        'path/to/song.mp3|Yesterday|The_Beatles|Help!|180',
      );
      expect(meta['title'], 'Yesterday');
      expect(meta['artist'], 'The Beatles');
      expect(meta['album'], 'Help!');
      expect(meta['duration'], '180');
    });

    test('gracefully handles invalid cacheKey format', () {
      final meta = LyricsImportExportService.parseCacheKey('yesterday');
      expect(meta['title'], 'yesterday');
      expect(meta['artist'], '');
      expect(meta['album'], '');
      expect(meta['duration'], '');
    });
  });

  group('LyricsImportExportService - Export & Import', () {
    late _FakeLyricsCacheRepository repository;
    late LyricsImportExportService service;

    setUp(() {
      repository = _FakeLyricsCacheRepository();
      service = const LyricsImportExportService();
    });

    test('exports lyrics and translation cache records to valid JSON', () async {
      final cacheRecord = LyricsCacheRecord(
        cacheKey: 'path/to/song.mp3|Yesterday|The_Beatles|Help!|180',
        source: LyricsCacheSource.manualAdjust,
        isSynced: true,
        syncedLyrics: '[00:10.00]Yesterday...',
        syncedLines: const [
          LyricLine(
            timestamp: Duration(seconds: 10),
            text: 'Yesterday...',
          ),
        ],
        timelineOffsetMillis: 0,
        updatedAtMillis: 1000,
      );

      final transRecord = LyricsTranslationCacheRecord(
        cacheKey: 'path/to/song.mp3|Yesterday|The_Beatles|Help!|180',
        languageCode: 'zh',
        translatedText: '昨日...',
        translatedLines: const ['昨日...'],
        provider: 'gemini',
        updatedAtMillis: 1000,
      );

      await repository.saveLyricsCache(cacheRecord);
      await repository.saveLyricsTranslationCache(transRecord);

      final jsonStr = await service.exportLyrics(repository);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['version'], 1);
      expect(decoded['lyricsCaches'], hasLength(1));
      expect(decoded['lyricsTranslationCaches'], hasLength(1));

      final firstCache = decoded['lyricsCaches'][0];
      expect(firstCache['cacheKey'], cacheRecord.cacheKey);
      expect(firstCache['syncedLyrics'], cacheRecord.syncedLyrics);
    });

    test('scans backup and auto-imports non-conflicting records', () async {
      final backup = {
        'version': 1,
        'lyricsCaches': [
          {
            'cacheKey': 'key1',
            'source': 'manual_adjust',
            'languageCode': 'en',
            'isSynced': 1,
            'syncedLyrics': 'Test lyrics',
            'syncedLinesJson': '[]',
            'timelineOffsetMillis': 0,
            'updatedAtMillis': 1000,
          }
        ],
        'lyricsTranslationCaches': [
          {
            'cacheKey': 'key1',
            'languageCode': 'zh',
            'translatedText': '测试歌词',
            'translatedLinesJson': '["测试歌词"]',
            'provider': 'gemini',
            'updatedAtMillis': 1000,
          }
        ]
      };

      final result = await service.scanBackup(jsonEncode(backup), repository);

      expect(result.totalImported, 1);
      expect(result.autoImportedCount, 1);
      expect(result.conflicts, isEmpty);

      // Verify records are saved in repository
      final savedRecord = await repository.getLyricsCache('key1');
      expect(savedRecord, isNotNull);
      expect(savedRecord!.syncedLyrics, 'Test lyrics');

      final savedTrans = await repository.getLyricsTranslationCaches('key1');
      expect(savedTrans, hasLength(1));
      expect(savedTrans.first.translatedText, '测试歌词');
    });

    test('scans backup and identifies conflicts', () async {
      final existingRecord = LyricsCacheRecord(
        cacheKey: 'key1',
        source: LyricsCacheSource.manualAdjust,
        isSynced: true,
        syncedLyrics: 'Original lyrics',
        syncedLines: const [],
        timelineOffsetMillis: 0,
        updatedAtMillis: 500,
      );
      await repository.saveLyricsCache(existingRecord);

      final backup = {
        'version': 1,
        'lyricsCaches': [
          {
            'cacheKey': 'key1',
            'source': 'lrclib', // Different source
            'languageCode': 'en',
            'isSynced': 1,
            'syncedLyrics': 'Imported lyrics', // Different content
            'syncedLinesJson': '[]',
            'timelineOffsetMillis': 0,
            'updatedAtMillis': 1000,
          }
        ],
        'lyricsTranslationCaches': []
      };

      final result = await service.scanBackup(jsonEncode(backup), repository);

      expect(result.totalImported, 1);
      expect(result.autoImportedCount, 0);
      expect(result.conflicts, hasLength(1));

      final conflict = result.conflicts.first;
      expect(conflict.existing.syncedLyrics, 'Original lyrics');
      expect(conflict.imported.syncedLyrics, 'Imported lyrics');
    });
  });
}

class _FakeLyricsCacheRepository implements LyricsCacheRepository {
  final Map<String, LyricsCacheRecord> _caches = {};
  final Map<String, List<LyricsTranslationCacheRecord>> _translations = {};

  @override
  Future<List<LyricsCacheRecord>> getAllLyricsCaches() async {
    return _caches.values.toList();
  }

  @override
  Future<List<LyricsTranslationCacheRecord>> getAllLyricsTranslationCaches() async {
    return _translations.values.expand((element) => element).toList();
  }

  @override
  Future<LyricsCacheRecord?> getLyricsCache(String cacheKey) async {
    return _caches[cacheKey];
  }

  @override
  Future<List<LyricsTranslationCacheRecord>> getLyricsTranslationCaches(
    String cacheKey,
  ) async {
    return _translations[cacheKey] ?? [];
  }

  @override
  Future<void> saveLyricsCache(LyricsCacheRecord record) async {
    _caches[record.cacheKey] = record;
  }

  @override
  Future<void> saveLyricsTranslationCache(
    LyricsTranslationCacheRecord record,
  ) async {
    _translations.putIfAbsent(record.cacheKey, () => []).add(record);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
