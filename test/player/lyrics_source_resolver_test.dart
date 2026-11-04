import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_service.dart';
import 'package:vynody/player/lyrics/sources/lyrics_resolver.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

/// 只记录调用情况的可控来源，用来验证顺序由列表决定。
class _RecordingProvider implements LyricsSourceProvider {
  _RecordingProvider(
    this.id, {
    this.applicable = true,
    this.result,
    this.onLoad,
  });

  @override
  final String id;

  final bool applicable;
  final LyricSelectionResult? result;
  final Future<LyricSelectionResult?> Function()? onLoad;

  int loadCount = 0;

  @override
  bool handles(LyricsQuery query) => applicable;

  @override
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  }) async {
    loadCount++;
    final custom = onLoad;
    if (custom != null) return custom();
    return result;
  }
}

LyricSelectionResult _resultFor(String tag) {
  return LyricSelectionResult(
    track: LyricTrack(
      name: 'Song',
      trackName: 'Song',
      instrumental: false,
      plainLyrics: tag,
    ),
    fromGetApi: false,
    source: tag,
    score: 100,
    breakdown: const LyricScoreBreakdown(
      title: 0,
      artist: 0,
      album: 0,
      duration: 0,
      lyricsQuality: 3,
      instrumentalPenalty: 0,
    ),
    durationDiffSeconds: 0,
    syncedLines: const <LyricLine>[],
    lyricsText: tag,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // MetadataDatabase 依赖 path_provider 定位数据库目录，测试环境没有平台通道。
  final tempDir = Directory.systemTemp.createTempSync('lyrics_resolver_test');
  PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);

  final repository = LyricsCacheRepository(db: MetadataDatabase());
  var seq = 0;

  LyricsQuery query() {
    seq++;
    return LyricsQuery(
      filePath: '/resolver-test/$seq/song.flac',
      fileName: 'song.flac',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: const Duration(seconds: 180),
    );
  }

  group('LyricsResolver 顺序', () {
    test('按 providers 列表顺序取第一个命中，后续来源不再调用', () async {
      final q = query();
      final first = _RecordingProvider('first', result: _resultFor('first'));
      final second = _RecordingProvider('second', result: _resultFor('second'));
      var onlineCalled = false;

      final resolver = LyricsResolver(
        cacheRepository: repository,
        providers: [first, second],
        onlineFallback: () async {
          onlineCalled = true;
          return null;
        },
      );

      final result = await resolver.resolve(rawQuery: q, normalizedQuery: q);

      expect(result?.source, 'first');
      expect(first.loadCount, 1);
      expect(second.loadCount, 0);
      expect(onlineCalled, isFalse);
    });

    test('前一个来源未命中时继续下一个', () async {
      final q = query();
      final first = _RecordingProvider('first');
      final second = _RecordingProvider('second', result: _resultFor('second'));

      final resolver = LyricsResolver(
        cacheRepository: repository,
        providers: [first, second],
        onlineFallback: () async => _resultFor('online'),
      );

      final result = await resolver.resolve(rawQuery: q, normalizedQuery: q);

      expect(result?.source, 'second');
      expect(first.loadCount, 1);
      expect(second.loadCount, 1);
    });

    test('不适用的来源不发起读取', () async {
      final q = query();
      final skipped = _RecordingProvider(
        'skipped',
        applicable: false,
        result: _resultFor('skipped'),
      );
      final used = _RecordingProvider('used', result: _resultFor('used'));

      final resolver = LyricsResolver(
        cacheRepository: repository,
        providers: [skipped, used],
      );

      final result = await resolver.resolve(rawQuery: q, normalizedQuery: q);

      expect(result?.source, 'used');
      expect(skipped.loadCount, 0);
      expect(used.loadCount, 1);
    });

    test('全部来源未命中时走在线兜底', () async {
      final q = query();
      final provider = _RecordingProvider('only');
      var onlineCalled = false;

      final resolver = LyricsResolver(
        cacheRepository: repository,
        providers: [provider],
        onlineFallback: () async {
          onlineCalled = true;
          return _resultFor('online');
        },
      );

      final result = await resolver.resolve(rawQuery: q, normalizedQuery: q);

      expect(result?.source, 'online');
      expect(onlineCalled, isTrue);
    });

    test('缓存命中时完全不触碰 providers 与在线兜底', () async {
      final q = query();
      await repository.saveLyricsCache(
        LyricsCacheRecord(
          cacheKey: q.cacheKey,
          source: LyricsCacheSource.external,
          isSynced: true,
          syncedLyrics: '[00:01.00]cached line',
          syncedLines: const [
            LyricLine(timestamp: Duration(seconds: 1), text: 'cached line'),
          ],
          timelineOffsetMillis: 0,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      final provider = _RecordingProvider('provider', result: _resultFor('x'));
      var onlineCalled = false;

      final resolver = LyricsResolver(
        cacheRepository: repository,
        providers: [provider],
        onlineFallback: () async {
          onlineCalled = true;
          return null;
        },
      );

      final result = await resolver.resolve(rawQuery: q, normalizedQuery: q);

      expect(result?.lyricsText, '[00:01.00]cached line');
      expect(result?.source, LyricsCacheSource.external.musicLyricSource);
      expect(provider.loadCount, 0);
      expect(onlineCalled, isFalse);
    });
  });
}

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir.path;
}
