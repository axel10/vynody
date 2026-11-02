import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
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

const String _songPath = 'C:/Music/Pop/OneRepublic - Distance.flac';

LyricsTranslationCacheRecord _record(List<String> lines, {int at = 1}) {
  return LyricsTranslationCacheRecord(
    cacheKey: _songPath,
    languageCode: 'zh-cn',
    translatedText: lines.where((line) => line.trim().isNotEmpty).join('\n'),
    translatedLines: lines,
    provider: 'deepseek',
    updatedAtMillis: at,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();
  final repo = LyricsCacheRepository(db: db);

  /// drift 的 watch 流要等查询重新跑完，`pumpEventQueue` 不一定够，给一点真实时间。
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 120));

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_translation_cache_watch_test_',
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

  test('写翻译缓存不能先给 watch 流吐一份空结果', () async {
    final cacheKey = ScannerPathUtils.normalizeLyricCacheKey(_songPath);
    await repo.clearLyricsTranslationCacheByKey(cacheKey);

    final emissions = <List<LyricsTranslationCacheRecord>>[];
    final subscription = repo
        .watchLyricsTranslationCaches(cacheKey)
        .listen(emissions.add);
    await settle();

    await repo.saveLyricsTranslationCache(_record(['一', '', ''], at: 1));
    await settle();
    await repo.saveLyricsTranslationCache(_record(['一', '二', '三'], at: 2));
    await settle();

    await subscription.cancel();

    // 订阅方（歌词面板）把空快照当成「译文没了」：只要出现过一行，
    // 之后任何一帧都不允许再回到空，否则整片译文会被整份覆盖掉。
    final firstWithRows = emissions.indexWhere((rows) => rows.isNotEmpty);
    expect(firstWithRows, isNot(-1), reason: '订阅后应当能观测到写入结果');
    for (final rows in emissions.skip(firstWithRows)) {
      expect(rows, isNotEmpty);
      expect(rows.length, 1);
      expect(rows.single.translatedLines, isNotEmpty);
    }
    expect(emissions.last.single.translatedLines, ['一', '二', '三']);
  });

  test('并发写同一条翻译缓存不抛 UNIQUE 冲突，后写者生效', () async {
    final cacheKey = ScannerPathUtils.normalizeLyricCacheKey(_songPath);
    await repo.clearLyricsTranslationCacheByKey(cacheKey);

    await Future.wait([
      repo.saveLyricsTranslationCache(_record(['一'], at: 10)),
      repo.saveLyricsTranslationCache(_record(['一', '二'], at: 11)),
    ]);

    final rows = await repo.getLyricsTranslationCaches(cacheKey);
    expect(rows.length, 1);
    expect(rows.single.translatedLines, ['一', '二']);
  });
}
