import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/timeline/lyrics_timeline.dart';
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
  final db = MetadataDatabase();
  final cacheRepo = LyricsCacheRepository(db: db);
  final timelineService = LyricsTimelineService(
    repository: LyricsTimelineRepository(db: db),
  );

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_normalized_cache_test_',
    );
    PathProviderPlatform.instance = _TestPathProviderPlatform(
      supportPath: supportDirectory.path,
    );
    await db.ensureOpen();
  });

  tearDownAll(() async {
    try {
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Normalized Lyrics Cache & Timeline Structure Tests', () {
    test('LyricsQuery.cacheKey uses normalized file path', () {
      const path1 = 'C:/Music/Artist/Song.mp3';
      const query1 = LyricsQuery(
        filePath: path1,
        fileName: 'Song.mp3',
        title: 'Song Title (feat. Artist)',
        artist: 'Artist',
        album: 'Album',
      );

      final expectedKey = ScannerPathUtils.normalizeLyricCacheKey(path1);
      expect(query1.cacheKey, expectedKey);
    });

    test('Each song has at most one lyrics cache record in database', () async {
      const filePath = 'C:/Music/Pop/Hit.mp3';
      final normKey = ScannerPathUtils.normalizeLyricCacheKey(filePath);

      // Save initial cache (e.g. from LRCLIB)
      final record1 = LyricsCacheRecord(
        cacheKey: filePath,
        source: LyricsCacheSource.lrclib,
        isSynced: true,
        syncedLyrics: '[00:01.00]Online Lyrics',
        syncedLines: const [],
        timelineOffsetMillis: 0,
        updatedAtMillis: 1000,
      );
      await cacheRepo.saveLyricsCache(record1);

      var fetched = await cacheRepo.getLyricsCache(normKey);
      expect(fetched, isNotNull);
      expect(fetched!.source, LyricsCacheSource.lrclib);
      expect(fetched.syncedLyrics, '[00:01.00]Online Lyrics');

      // Overwrite cache (e.g. manual edit)
      final record2 = LyricsCacheRecord(
        cacheKey: filePath,
        source: LyricsCacheSource.manualAdjust,
        isSynced: true,
        syncedLyrics: '[00:01.00]Manual Edited Lyrics',
        syncedLines: const [],
        timelineOffsetMillis: 200,
        updatedAtMillis: 2000,
      );
      await cacheRepo.saveLyricsCache(record2);

      // Verify only 1 record exists and it contains latest content
      final allMatching = await cacheRepo.getLyricsCaches(normKey);
      expect(allMatching.length, 1);
      expect(allMatching.first.source, LyricsCacheSource.manualAdjust);
      expect(allMatching.first.syncedLyrics, '[00:01.00]Manual Edited Lyrics');
      expect(allMatching.first.timelineOffsetMillis, 200);
    });

    test('Timeline snapshots are linked to the normalized cacheKey', () async {
      const filePath = 'C:/Music/Rock/Track.flac';
      final normKey = ScannerPathUtils.normalizeLyricCacheKey(filePath);

      await timelineService.recordSnapshot(
        cacheKey: filePath,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Edit line 1',
        lyrics: '[00:02.00]Track Line 1',
        previousLyrics: '[00:01.00]Original Line',
      );

      final history = await timelineService.getHistory(normKey);
      expect(history.length, 2);
      expect(history[0].cacheKey, normKey);
      expect(history[0].lyrics, '[00:02.00]Track Line 1');
      expect(history[1].cacheKey, normKey);
      expect(history[1].lyrics, '[00:01.00]Original Line');
    });

    test('Legacy pipe-delimited keys are automatically normalized to file path', () {
      const legacyKey = 'C:\\Music\\Song.mp3|song_title|artist_name|album_name';
      final normalized = ScannerPathUtils.normalizeLyricCacheKey(legacyKey);
      expect(
        normalized,
        ScannerPathUtils.normalizeLyricCacheKey('C:\\Music\\Song.mp3'),
      );
    });
  });
}
