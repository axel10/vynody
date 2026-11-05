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

const String _songPath = '/music/lyrics/selected-language.flac';

/// 与生产代码一致：保存歌词内容的调用方**不会**填 selectedTranslationLanguage。
LyricsCacheRecord _lyricsRecord({String lyrics = '[00:01.00]hello'}) {
  return LyricsCacheRecord(
    cacheKey: _songPath,
    source: LyricsCacheSource.lrclib,
    isSynced: true,
    syncedLyrics: lyrics,
    syncedLines: const [],
    timelineOffsetMillis: 0,
    updatedAtMillis: 1,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();
  final repo = LyricsCacheRepository(db: db);
  final cacheKey = ScannerPathUtils.normalizeLyricCacheKey(_songPath);

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_selected_translation_language_test_',
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

  setUp(() async {
    await repo.clearAllLyricsCachesByKey(cacheKey);
  });

  test('保存歌词内容不会洗掉已选的译文语言', () async {
    await repo.saveLyricsCache(_lyricsRecord());
    await repo.setSelectedTranslationLanguage(cacheKey, 'ja');

    // 模拟「保存时间轴偏移 / 切来源 / 生成歌词」：整行重写，记录里不带选择。
    await repo.saveLyricsCache(_lyricsRecord(lyrics: '[00:02.00]hello again'));

    expect(await repo.getSelectedTranslationLanguage(cacheKey), 'ja');
    final record = await repo.getLyricsCache(cacheKey);
    expect(record?.selectedTranslationLanguage, 'ja');
    expect(record?.syncedLyrics, '[00:02.00]hello again');
  });

  test('记录里显式带了选择时以记录为准（导入 / 分享接收路径）', () async {
    await repo.saveLyricsCache(_lyricsRecord());
    await repo.setSelectedTranslationLanguage(cacheKey, 'ja');

    await repo.saveLyricsCache(
      _lyricsRecord().copyWith(selectedTranslationLanguage: 'ko'),
    );

    expect(await repo.getSelectedTranslationLanguage(cacheKey), 'ko');
  });

  test('没有歌词记录时写选择是 no-op，不会凭空造行', () async {
    await repo.setSelectedTranslationLanguage(cacheKey, 'ja');

    expect(await repo.getSelectedTranslationLanguage(cacheKey), '');
    expect(await repo.getLyricsCache(cacheKey), isNull);
  });

  test('传空串可以清掉选择，回落全局设置', () async {
    await repo.saveLyricsCache(_lyricsRecord());
    await repo.setSelectedTranslationLanguage(cacheKey, 'ja');
    await repo.setSelectedTranslationLanguage(cacheKey, '');

    expect(await repo.getSelectedTranslationLanguage(cacheKey), '');
  });

  test('map 往返保留选择，老备份缺字段按空处理', () async {
    final map = _lyricsRecord()
        .copyWith(selectedTranslationLanguage: 'zh-tw')
        .toMap();
    expect(map['selectedTranslationLanguage'], 'zh-tw');
    expect(
      LyricsCacheRecord.fromMap(map).selectedTranslationLanguage,
      'zh-tw',
    );

    final legacyMap = _lyricsRecord().toMap()
      ..remove('selectedTranslationLanguage');
    expect(
      LyricsCacheRecord.fromMap(legacyMap).selectedTranslationLanguage,
      '',
    );
  });
}
