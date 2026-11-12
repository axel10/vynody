import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/pages/folder_search_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/widgets/folder_zoom_item.dart';
import 'package:vynody/widgets/library_large_title.dart';
import 'package:vynody/widgets/library_search_field.dart';

import 'package:vynody/player/settings/settings_service.dart';

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

class _StubScannerService extends ScannerService {
  _StubScannerService({
    required this.mockSongs,
    required this.mockFolders,
    this.mockSongCounts = const {},
  }) : super(autoInitialize: false);

  final List<MusicFile> mockSongs;
  final List<MusicFolder> mockFolders;
  final Map<String, int> mockSongCounts;

  @override
  Future<List<MusicFile>> searchSongs(
    String query, {
    String? folderPath,
  }) async {
    if (folderPath != null && folderPath.isNotEmpty) {
      return mockSongs.where((s) => s.path.startsWith(folderPath)).toList();
    }
    return mockSongs;
  }

  @override
  Future<List<MusicFolder>> searchFolders(String query) async {
    return mockFolders;
  }

  @override
  int getSongCountForFolder(MusicFolder folder) {
    if (mockSongCounts.containsKey(folder.path)) {
      return mockSongCounts[folder.path]!;
    }
    return super.getSongCountForFolder(folder);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsService settingsService;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('folder_search_page_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget createSubject({
    required ScannerService scanner,
    MusicFolder? currentFolder,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        scannerServiceProvider.overrideWith((ref) => scanner),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        audioIsPlayingProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: FolderSearchPage(
          currentFolder: currentFolder,
        ),
      ),
    );
  }

  testWidgets('FolderSearchPage initial empty state displays hint', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final stubScanner = _StubScannerService(
      mockSongs: [],
      mockFolders: [],
    );

    await tester.pumpWidget(createSubject(scanner: stubScanner));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('输入内容以开始搜索'), findsOneWidget);
  });

  testWidgets('FolderSearchPage performs search and displays results', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final songA = MusicFile(
      path: '/root/pop/songA.mp3',
      name: 'songA.mp3',
      title: 'Song A',
      artist: 'Singer 1',
    );
    final songB = MusicFile(
      path: '/root/rock/songB.mp3',
      name: 'songB.mp3',
      title: 'Song B',
      artist: 'Singer 2',
    );
    final folderPop = MusicFolder(
      path: '/root/pop',
      name: 'pop',
      files: [songA],
    );

    final stubScanner = _StubScannerService(
      mockSongs: [songA, songB],
      mockFolders: [folderPop],
    );

    await tester.pumpWidget(createSubject(
      scanner: stubScanner,
      currentFolder: folderPop,
    ));
    await tester.pumpAndSettle();

    // 输入搜索文本
    await tester.enterText(find.byType(TextField), 'Song');
    // 等待 300ms debounce
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // 应该展示结果分组
    expect(find.textContaining('当前目录及子目录结果'), findsOneWidget);
    expect(find.text('Song A'), findsOneWidget);
    expect(find.textContaining('全局其他目录结果'), findsOneWidget);
    expect(find.text('Song B'), findsOneWidget);
  });

  testWidgets(
      'FolderSearchPage displays section header between folders and songs, and displays non-zero song count for folders',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final currentFolder = MusicFolder(
      path: '/root/music',
      name: 'music',
    );
    final subFolder = MusicFolder(
      path: '/root/music/RockFolder',
      name: 'RockFolder',
      // files is intentionally empty to simulate search result model
    );
    final song = MusicFile(
      path: '/root/music/rock_song.mp3',
      name: 'rock_song.mp3',
      title: 'Rock Song',
      artist: 'Rock Band',
    );

    final stubScanner = _StubScannerService(
      mockSongs: [song],
      mockFolders: [subFolder],
      mockSongCounts: {
        '/root/music/RockFolder': 18,
      },
    );

    await tester.pumpWidget(createSubject(
      scanner: stubScanner,
      currentFolder: currentFolder,
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'rock');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // 验证当前目录标题
    expect(find.textContaining('当前目录及子目录结果'), findsOneWidget);
    // 验证文件夹渲染
    expect(find.text('RockFolder'), findsOneWidget);
    // 验证文件夹歌曲数量不是 0，而是从 scanner.getSongCountForFolder 获得的 18
    expect(find.text('18 首歌曲'), findsOneWidget);
    // 验证在文件夹和歌曲之间展示了分节标题
    expect(find.text('匹配的歌曲 (1)'), findsOneWidget);
    // 验证歌曲渲染
    expect(find.text('Rock Song'), findsOneWidget);

    // 验证分节标题、搜索框与内容均左对齐
    final searchFieldLeft =
        tester.getTopLeft(find.byType(LibrarySearchField)).dx;
    final sectionHeaderLeft = tester.getTopLeft(find.text('匹配的歌曲 (1)')).dx;
    final folderItemLeft = tester.getTopLeft(find.byType(FolderZoomItem)).dx;
    expect(searchFieldLeft, equals(sectionHeaderLeft));
    expect(sectionHeaderLeft, equals(folderItemLeft));
  });

  testWidgets(
      'FolderSearchPage avoids top system status bar when padding is not provided',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 48.0);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    final stubScanner = _StubScannerService(
      mockSongs: [],
      mockFolders: [],
    );

    await tester.pumpWidget(createSubject(scanner: stubScanner));
    await tester.pumpAndSettle();

    final titlePos = tester.getTopLeft(find.byType(LibraryLargeTitle));
    // safeTop is 48.0, topPadding is 48.0, with +16 offset the title starts at dy >= 64.0
    expect(titlePos.dy, greaterThanOrEqualTo(64.0));
  });
}
