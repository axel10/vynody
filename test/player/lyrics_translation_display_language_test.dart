import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/lyrics_controller.dart';
import 'package:vynody/player/lyrics/lyrics_controller_dependencies.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _TestPathProviderPlatform({required this.supportPath});
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

const String _songPath = '/music/lyrics/display-language.flac';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDirectory;
  final db = MetadataDatabase();
  final repo = LyricsCacheRepository(db: db);
  final cacheKey = ScannerPathUtils.normalizeLyricCacheKey(_songPath);

  setUpAll(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'lyrics_translation_display_language_test_',
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

  /// 造一份「人工选过译文语言」的歌词缓存 + 两条可用译文。
  Future<void> seedCache({
    required String selectedTranslationLanguage,
    List<String> languages = const ['zh-cn', 'ja'],
  }) async {
    await repo.clearAllLyricsCachesByKey(cacheKey);
    await repo.saveLyricsCache(
      LyricsCacheRecord(
        cacheKey: _songPath,
        source: LyricsCacheSource.lrclib,
        isSynced: true,
        syncedLyrics: '[00:01.00]hello',
        syncedLines: const [],
        selectedTranslationLanguage: selectedTranslationLanguage,
        timelineOffsetMillis: 0,
        updatedAtMillis: 1,
      ),
    );
    for (final language in languages) {
      await repo.saveLyricsTranslationCache(
        LyricsTranslationCacheRecord(
          cacheKey: _songPath,
          languageCode: language,
          translatedText: '$language 译文',
          translatedLines: ['$language 译文'],
          provider: 'openrouter',
          updatedAtMillis: language == 'ja' ? 2 : 1,
        ),
      );
    }
  }

  /// 一步到位：起容器、跑一次缓存同步、返回控制器。
  Future<(ProviderContainer, LyricsController)> boot({
    required String globalLanguage,
    required MusicFile song,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService(await SharedPreferences.getInstance());
    settings.lyricsTranslationTargetLanguageCode = globalLanguage;

    var currentSong = song;
    final container = ProviderContainer(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settings),
        isProUnlockedProvider.overrideWithValue(true),
        lyricsControllerDependenciesProvider.overrideWithValue(
          LyricsControllerDependencies(
            db: db,
            currentMusic: () => currentSong,
            queue: () => [currentSong],
            currentIndex: () => 0,
            playerDuration: () => const Duration(seconds: 200),
            isLyricsActive: () => true,
            cacheSongDuration: (path, durationMillis) {},
            updateSongInPlaylist: (updated) => currentSong = updated,
          ),
        ),
      ],
    );
    final controller = container.read(lyricsControllerProvider.notifier);
    await controller.watchLyricsCacheForSong(currentSong);
    return (container, controller);
  }

  Future<void> waitFor(bool Function() predicate) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!predicate() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  MusicFile newSong() => const MusicFile(
    path: _songPath,
    name: 'display-language.flac',
    durationMillis: 200000,
  );

  test('这首歌选定的译文语言会被带进 state 并优先展示', () async {
    await seedCache(selectedTranslationLanguage: 'ja');

    final (container, controller) = await boot(
      globalLanguage: 'zh-cn',
      song: newSong(),
    );
    addTearDown(container.dispose);

    await waitFor(
      () => container.read(lyricsControllerProvider).hasLyrics,
    );

    final lyrics = controller.currentLyricsForCurrentSong();
    expect(lyrics?.translations.keys.toSet(), {'zh-cn', 'ja'});
    // 全局是 zh-cn，但这首歌选的是 ja —— 必须展示 ja。
    expect(controller.effectiveTranslationLanguageFor(lyrics), 'ja');
  });

  test('选定的语言没有译文内容时回落到全局默认', () async {
    await seedCache(selectedTranslationLanguage: 'ko');

    final (container, controller) = await boot(
      globalLanguage: 'zh-cn',
      song: newSong(),
    );
    addTearDown(container.dispose);

    await waitFor(
      () => container.read(lyricsControllerProvider).hasLyrics,
    );

    final lyrics = controller.currentLyricsForCurrentSong();
    expect(controller.effectiveTranslationLanguageFor(lyrics), 'zh-cn');
  });

  test('没有选定语言时用全局默认', () async {
    await seedCache(selectedTranslationLanguage: '');

    final (container, controller) = await boot(
      globalLanguage: 'ja',
      song: newSong(),
    );
    addTearDown(container.dispose);

    await waitFor(
      () => container.read(lyricsControllerProvider).hasLyrics,
    );

    final lyrics = controller.currentLyricsForCurrentSong();
    expect(controller.effectiveTranslationLanguageFor(lyrics), 'ja');
    expect(
      container.read(lyricsControllerProvider).translationDisplayLanguageCode,
      '',
    );
  });

  test('没有任何译文时按全局默认返回语言码，不抛异常', () async {
    await seedCache(
      selectedTranslationLanguage: 'ja',
      languages: const [],
    );

    final (container, controller) = await boot(
      globalLanguage: 'zh-cn',
      song: newSong(),
    );
    addTearDown(container.dispose);

    await waitFor(
      () => container.read(lyricsControllerProvider).hasLyrics,
    );

    // 没有歌词对象时无从判断内容，按「选定的语言」返回（这首歌的意图）。
    expect(controller.effectiveTranslationLanguageFor(null), 'ja');
    // 有歌词但一条译文都没有：两级都没内容，落到「最新有内容」兜底，
    // 该兜底在完全没有译文时原样返回入参（全局默认）。
    expect(
      controller.effectiveTranslationLanguageFor(
        controller.currentLyricsForCurrentSong(),
      ),
      'zh-cn',
    );
  });

  test('切换译文语言会落库并立即生效', () async {
    await seedCache(selectedTranslationLanguage: '');

    final (container, controller) = await boot(
      globalLanguage: 'zh-cn',
      song: newSong(),
    );
    addTearDown(container.dispose);
    await waitFor(() => container.read(lyricsControllerProvider).hasLyrics);

    await controller.selectTranslationLanguageForCurrentSong('ja');

    expect(
      container.read(lyricsControllerProvider).translationDisplayLanguageCode,
      'ja',
    );
    expect(await repo.getSelectedTranslationLanguage(cacheKey), 'ja');
    expect(
      controller.effectiveTranslationLanguageFor(
        controller.currentLyricsForCurrentSong(),
      ),
      'ja',
    );
  });

  test('切回空串会清掉选择并回落全局默认', () async {
    await seedCache(selectedTranslationLanguage: 'ja');

    final (container, controller) = await boot(
      globalLanguage: 'zh-cn',
      song: newSong(),
    );
    addTearDown(container.dispose);
    await waitFor(() => container.read(lyricsControllerProvider).hasLyrics);

    await controller.selectTranslationLanguageForCurrentSong('');

    expect(await repo.getSelectedTranslationLanguage(cacheKey), '');
    expect(
      container.read(lyricsControllerProvider).translationDisplayLanguageCode,
      '',
    );
    expect(
      controller.effectiveTranslationLanguageFor(
        controller.currentLyricsForCurrentSong(),
      ),
      'zh-cn',
    );
  });

  test('已有译文时：不带 force 直接跳过，带 force 才真的重翻且不清空旧译文', () async {
    await seedCache(selectedTranslationLanguage: 'zh-cn');

    final (container, controller) = await boot(
      globalLanguage: 'zh-cn',
      song: newSong(),
    );
    addTearDown(container.dispose);
    await waitFor(() => container.read(lyricsControllerProvider).hasLyrics);

    final before = await repo.getLyricsTranslationCaches(cacheKey);
    expect(before.length, 2);

    // 命中「内存已有该语言译文」短路：不发请求。
    expect(await controller.translateLyricsForCurrentSong(), isNull);
    expect(
      (await repo.getLyricsTranslationCaches(cacheKey)).length,
      before.length,
    );

    // force 绕过短路，真的发起请求；测试环境没有 API key，按失败返回错误文案。
    // 关键是这里**没有**走「先清空译文」的老路。
    final forcedError = await controller.translateLyricsForCurrentSong(
      force: true,
    );
    expect(forcedError, isNotNull);

    final after = await repo.getLyricsTranslationCaches(cacheKey);
    expect(after.length, before.length);
    // 用「语言码 → 译文全文」的快照比较：List 没有值相等语义，直接比 Set 会误判。
    Map<String, String> snapshot(
      List<LyricsTranslationCacheRecord> rows,
    ) => {
      for (final row in rows) row.languageCode: row.translatedLines.join('\n'),
    };
    expect(snapshot(after), snapshot(before));
    // 本次翻译的目标语言已被记住。
    expect(await repo.getSelectedTranslationLanguage(cacheKey), 'zh-cn');
  });
}
