import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/library_search_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_service.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

/// 只提供歌曲检索结果的 ScannerService 替身：本页其余能力都不参与测试。
class _StubScannerService extends ScannerService {
  _StubScannerService(this._songs) : super(autoInitialize: false);

  final List<MusicFile> _songs;
  int calls = 0;

  @override
  Future<List<MusicFile>> searchSongs(
    String query, {
    String? folderPath,
  }) async {
    calls += 1;
    return _songs;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final representative = MusicFile(path: '/music/a.mp3', name: 'a.mp3');
  final blueAlbum = AlbumSummary(
    id: 'album-1',
    title: 'Blue Album',
    artist: 'Weezer',
    songs: const [],
    representativeSong: representative,
    totalDurationMillis: 0,
  );
  final weezer = ArtistSummary(
    queryKey: 'weezer',
    name: 'Weezer',
    songs: const [],
    representativeSong: representative,
    songCount: 12,
  );
  final dbSongs = [
    MusicFile(
      path: '/music/blue.mp3',
      name: 'blue.mp3',
      title: 'Blue Track',
      artist: 'Weezer',
      album: 'Blue Album',
    ),
  ];

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('library_search_page_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await MetadataDatabase().clearAll();
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required _StubScannerService scanner,
    Stream<List<AlbumSummary>>? albums,
    Stream<List<ArtistSummary>>? artists,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        scannerServiceProvider.overrideWith((ref) => scanner),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        albumLibraryProvider.overrideWith(
          (ref) => albums ?? Stream.value([blueAlbum]),
        ),
        artistLibraryProvider.overrideWith(
          (ref) => artists ?? Stream.value([weezer]),
        ),
        playlistServiceProvider.overrideWith((ref) => PlaylistService()),
      ],
    );
    // 不释放的话曲库那条订阅会一直挂着，测试收尾等待流关闭时会把整个用例卡死。
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: OKToast(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LibrarySearchPage(),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('输入关键词后按 艺术家 / 专辑 / 歌曲 分组呈现结果', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    await pumpPage(tester, scanner: scanner);

    expect(find.text('输入内容以开始搜索'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(scanner.calls, 1, reason: '防抖之后只发一次数据库检索');
    expect(find.text('艺术家 (1)'), findsOneWidget);
    expect(find.text('专辑 (1)'), findsOneWidget);
    expect(find.text('歌曲 (1)'), findsOneWidget);
    expect(find.text('Blue Track'), findsOneWidget);
  });

  testWidgets('清空搜索词后结果立即撤掉，不再发新查询', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    await pumpPage(tester, scanner: scanner);

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('歌曲 (1)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('歌曲 (1)'), findsNothing);
    expect(find.text('输入内容以开始搜索'), findsOneWidget);
    expect(scanner.calls, 1, reason: '空词不该触发数据库检索');
  });

  testWidgets('曲库数据晚于搜索词到达时，分组要跟着补齐', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    final albumStream = StreamController<List<AlbumSummary>>();
    final artistStream = StreamController<List<ArtistSummary>>();
    addTearDown(albumStream.close);
    addTearDown(artistStream.close);

    await pumpPage(
      tester,
      scanner: scanner,
      albums: albumStream.stream,
      artists: artistStream.stream,
    );

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // 此时只有数据库那一路有结果。
    expect(find.text('歌曲 (1)'), findsOneWidget);
    expect(find.text('专辑 (1)'), findsNothing);

    albumStream.add([blueAlbum]);
    artistStream.add([weezer]);
    await tester.pump();
    await tester.pump();

    expect(find.text('专辑 (1)'), findsOneWidget);
    expect(find.text('艺术家 (1)'), findsOneWidget);
  });

  testWidgets('长按歌曲进多选，底部出现选择面板', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    await pumpPage(tester, scanner: scanner);

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text('Blue Track'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget);
  });

  testWidgets('专辑与歌曲可以混选，选择集不按分节拆', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    await pumpPage(tester, scanner: scanner);

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // 先长按专辑进多选，再长按歌曲追加。两者类型不同，仍应落在同一个选择集里。
    await tester.longPress(find.text('Blue Album'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.longPress(find.text('Blue Track'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已选 2 项'), findsOneWidget);
  });

  testWidgets('全选跨段：艺术家 / 专辑 / 歌曲一起选中', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    await pumpPage(tester, scanner: scanner);

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text('Blue Track'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pump(const Duration(milliseconds: 300));

    // 艺术家 1 + 专辑 1 + 歌曲 1
    expect(find.text('已选 3 项'), findsOneWidget);
  });

  testWidgets('改搜索词时退出多选，避免选择集与页面条目脱节', (tester) async {
    final scanner = _StubScannerService(dbSongs);
    await pumpPage(tester, scanner: scanner);

    await tester.enterText(find.byType(TextField), 'weezer');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text('Blue Track'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'blue');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已选 1 项'), findsNothing);
  });
}
