import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/lyrics/timeline/lyrics_timeline.dart';

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
  final repository = LyricsTimelineRepository(db: db);
  final service = LyricsTimelineService(repository: repository);

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_timeline_test_',
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

  group('LyricsTimelineService', () {
    test('records snapshot and creates initial baseline if previous lyrics exists', () async {
      const cacheKey = 'song-1';

      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'First Edit',
        lyrics: '[00:01.00]Edited lyrics',
        previousLyrics: '[00:01.00]Original baseline lyrics',
        previousDescription: 'Baseline',
      );

      final history = await service.getHistory(cacheKey);
      expect(history.length, 2);

      // Newest first
      expect(history[0].actionType, LyricsTimelineActionType.manualEdit);
      expect(history[0].lyrics, '[00:01.00]Edited lyrics');

      // Baseline initial version
      expect(history[1].actionType, LyricsTimelineActionType.initial);
      expect(history[1].lyrics, '[00:01.00]Original baseline lyrics');
    });

    test('deduplicates consecutive identical snapshots', () async {
      const cacheKey = 'song-2';

      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Edit 1',
        lyrics: '[00:01.00]Line 1',
      );

      // Same content again
      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Edit 2',
        lyrics: '[00:01.00]Line 1',
      );

      final history = await service.getHistory(cacheKey);
      expect(history.length, 1);
      expect(history.first.description, 'Edit 1');
    });

    test('strictly limits history to default 30 entries (FIFO)', () async {
      const cacheKey = 'song-3';

      for (int i = 1; i <= 35; i++) {
        // Sleep slightly to guarantee different timestamps
        await Future.delayed(const Duration(milliseconds: 2));
        await service.recordSnapshot(
          cacheKey: cacheKey,
          actionType: LyricsTimelineActionType.manualEdit,
          description: 'Version $i',
          lyrics: '[00:0$i.00]Line $i',
        );
      }

      final history = await service.getHistory(cacheKey);
      expect(history.length, 30);

      // Latest should be Version 35
      expect(history.first.description, 'Version 35');
      // Oldest retained should be Version 6 (35 - 30 + 1)
      expect(history.last.description, 'Version 6');
    });

    test('respects custom max count from maxCountProvider', () async {
      final customRepo = LyricsTimelineRepository(
        db: db,
        maxCountProvider: () => 10,
      );
      final customService = LyricsTimelineService(repository: customRepo);
      const cacheKey = 'song-custom-limit';

      for (int i = 1; i <= 15; i++) {
        await Future.delayed(const Duration(milliseconds: 2));
        await customService.recordSnapshot(
          cacheKey: cacheKey,
          actionType: LyricsTimelineActionType.manualEdit,
          description: 'Version $i',
          lyrics: '[00:0$i.00]Line $i',
        );
      }

      final history = await customService.getHistory(cacheKey);
      expect(history.length, 10);
      expect(history.first.description, 'Version 15');
      expect(history.last.description, 'Version 6');
    });

    test('clears history for given cacheKey', () async {
      const cacheKey = 'song-4';

      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Edit 1',
        lyrics: 'Line 1',
      );

      var history = await service.getHistory(cacheKey);
      expect(history.length, 1);

      await service.clearHistory(cacheKey);
      history = await service.getHistory(cacheKey);
      expect(history.isEmpty, true);
    });

    test('rollback and subsequent edit appends new snapshot without truncating existing history', () async {
      const cacheKey = 'song-append-only';

      // 1. Create Version 1, Version 2, Version 3
      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Version 1',
        lyrics: 'Line 1',
      );
      await Future.delayed(const Duration(milliseconds: 5));
      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Version 2',
        lyrics: 'Line 2',
      );
      await Future.delayed(const Duration(milliseconds: 5));
      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Version 3',
        lyrics: 'Line 3',
      );

      var history = await service.getHistory(cacheKey);
      expect(history.map((e) => e.description).toList(), ['Version 3', 'Version 2', 'Version 1']);

      // 2. Rollback to Version 1 (no new snapshot is added during restore)
      // When user subsequently edits based on Version 1:
      await Future.delayed(const Duration(milliseconds: 5));
      await service.recordSnapshot(
        cacheKey: cacheKey,
        actionType: LyricsTimelineActionType.manualEdit,
        description: 'Version 4 (derived from Version 1)',
        lyrics: 'Line 1 modified',
      );

      history = await service.getHistory(cacheKey);
      // Verify Version 4 is prepended as newest, and Version 3, 2, 1 are all preserved
      expect(history.length, 4);
      expect(
        history.map((e) => e.description).toList(),
        ['Version 4 (derived from Version 1)', 'Version 3', 'Version 2', 'Version 1'],
      );
    });
  });
}
