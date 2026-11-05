import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/sharing/lyrics_import_conflict.dart';

void main() {
  const tolerance = kLanSyncTimestampToleranceMillis;

  LyricsImportOutcome decide({
    required LyricsCacheSource? local,
    required LyricsCacheSource incoming,
    int localAt = 1000,
    int incomingAt = 2000,
  }) {
    return decideLyricsImport(
      localSource: local,
      localUpdatedAtMillis: localAt,
      incomingSource: incoming,
      incomingUpdatedAtMillis: incomingAt,
    );
  }

  test('本地没有记录 → added', () {
    expect(decide(local: null, incoming: LyricsCacheSource.lrclib),
        LyricsImportOutcome.added);
  });

  test('远端优先级更高 → updated', () {
    // aiKaraoke(4) 优于 lrclib(7)
    expect(
      decide(local: LyricsCacheSource.lrclib, incoming: LyricsCacheSource.aiKaraoke),
      LyricsImportOutcome.updated,
    );
  });

  test('本机内嵌 LRC 不被远端 AI 歌词覆盖', () {
    // 这是旧实现最大的错：它自己那张表把 embedded 判成 2、AI 判成 3，
    // 于是远端 AI 会盖掉本机内嵌 LRC，而 displayPriority 认为内嵌（2）更优。
    for (final aiSource in [
      LyricsCacheSource.aiKaraoke,
      LyricsCacheSource.aiTimeline,
      LyricsCacheSource.aiGenerate,
      LyricsCacheSource.ai,
    ]) {
      expect(
        decide(
          local: LyricsCacheSource.embedded,
          incoming: aiSource,
          incomingAt: 9 * tolerance,
        ),
        LyricsImportOutcome.skipped,
        reason: '${aiSource.dbValue} 不应覆盖 embedded',
      );
    }
  });

  test('本机标记「无词」时，任何远端歌词都不覆盖', () {
    for (final source in LyricsCacheSource.values) {
      if (source == LyricsCacheSource.none) continue;
      expect(
        decide(
          local: LyricsCacheSource.none,
          incoming: source,
          incomingAt: 9 * tolerance,
        ),
        LyricsImportOutcome.skipped,
        reason: '${source.dbValue} 不应推翻「无词」',
      );
    }
  });

  test('同档、远端更新 → updated', () {
    expect(
      decide(
        local: LyricsCacheSource.lrclib,
        incoming: LyricsCacheSource.lrclib,
        localAt: 1000,
        incomingAt: 1000 + 60 * 1000,
      ),
      LyricsImportOutcome.updated,
    );
  });

  test('同档、时钟偏差超出容差 → 保留本地', () {
    // 远端时钟快一年，不能因此恒定单向覆盖。
    const oneYear = 365 * 24 * 60 * 60 * 1000;
    expect(
      decide(
        local: LyricsCacheSource.lrclib,
        incoming: LyricsCacheSource.lrclib,
        localAt: 1000,
        incomingAt: 1000 + oneYear,
      ),
      LyricsImportOutcome.skipped,
    );
  });

  test('同档、远端更旧 → 保留本地', () {
    expect(
      decide(
        local: LyricsCacheSource.lrclib,
        incoming: LyricsCacheSource.lrclib,
        localAt: 5000,
        incomingAt: 1000,
      ),
      LyricsImportOutcome.skipped,
    );
  });

  test('容差边界：等于容差仍可比，超过才算时钟不可信', () {
    expect(
      decide(
        local: LyricsCacheSource.lrclib,
        incoming: LyricsCacheSource.lrclib,
        localAt: 0,
        incomingAt: tolerance,
      ),
      LyricsImportOutcome.updated,
    );
    expect(
      decide(
        local: LyricsCacheSource.lrclib,
        incoming: LyricsCacheSource.lrclib,
        localAt: 0,
        incomingAt: tolerance + 1,
      ),
      LyricsImportOutcome.skipped,
    );
  });
}
