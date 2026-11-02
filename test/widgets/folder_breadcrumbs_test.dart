import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/folder_header_nav_bar.dart';
import 'package:vynody/widgets/nav_capsule_island.dart';

import 'helpers/mobile_screenshot_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestSettingsService settingsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = TestSettingsService(prefs);
  });

  Widget buildTestNavBar({
    required MusicFolder currentFolder,
    required List<MusicFolder> navigationHistory,
    VoidCallback? onRefresh,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: FolderHeaderNavBar(
            isOverlay: false,
            scrollProgress: ValueNotifier(0.0),
            currentFolder: currentFolder,
            navigationHistory: navigationHistory,
            onSortPressed: () {},
            onRefresh: onRefresh,
          ),
        ),
      ),
    );
  }

  testWidgets('FolderHeaderNavBar does not duplicate current folder if present in history', (tester) async {
    final folder1 = MusicFolder(name: '系统媒体库', path: 'system', files: [], subFolders: []);
    final folder2 = MusicFolder(name: 'download', path: 'system/download', files: [], subFolders: []);
    final folder3 = MusicFolder(name: 'test', path: 'system/download/test', files: [], subFolders: []);

    // Even if navigationHistory defensively contains folder3, it should not be duplicated with currentFolder
    final history = [folder1, folder2, folder3];

    await tester.pumpWidget(
      buildTestNavBar(
        currentFolder: folder3,
        navigationHistory: history,
      ),
    );

    await tester.pumpAndSettle();

    // 'test' should only appear once in breadcrumbs
    expect(find.text('test'), findsOneWidget);
    expect(find.text('download'), findsOneWidget);
    expect(find.text('系统媒体库'), findsOneWidget);
  });

  testWidgets('FolderHeaderNavBar renders sliced history correctly', (tester) async {
    final folder1 = MusicFolder(name: '系统媒体库', path: 'system', files: [], subFolders: []);
    final folder2 = MusicFolder(name: 'download', path: 'system/download', files: [], subFolders: []);
    final folder3 = MusicFolder(name: 'test', path: 'system/download/test', files: [], subFolders: []);

    // Slice for folder3's page: [folder1, folder2]
    final history = [folder1, folder2];

    await tester.pumpWidget(
      buildTestNavBar(
        currentFolder: folder3,
        navigationHistory: history,
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('系统媒体库'), findsOneWidget);
    expect(find.text('download'), findsOneWidget);
    expect(find.text('test'), findsOneWidget);
  });

  testWidgets('FolderHeaderNavBar renders refresh button and triggers onRefresh', (tester) async {
    final folder = MusicFolder(name: 'music', path: '/home/music', files: [], subFolders: []);
    var refreshed = false;

    // Without onRefresh: no refresh icon
    await tester.pumpWidget(
      buildTestNavBar(
        currentFolder: folder,
        navigationHistory: [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);

    // With onRefresh: refresh icon appears and can be tapped
    await tester.pumpWidget(
      buildTestNavBar(
        currentFolder: folder,
        navigationHistory: [],
        onRefresh: () => refreshed = true,
      ),
    );
    await tester.pumpAndSettle();
    final refreshBtn = find.byIcon(Icons.refresh_rounded);
    expect(refreshBtn, findsOneWidget);

    await tester.tap(refreshBtn);
    await tester.pump();
    expect(refreshed, isTrue);
  });

  Widget buildRootNavBar({
    required double scrollProgress,
    bool hideBreadcrumbs = false,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: FolderHeaderNavBar(
            isOverlay: false,
            scrollProgress: ValueNotifier(scrollProgress),
            onSortPressed: () {},
            hideBreadcrumbs: hideBreadcrumbs,
          ),
        ),
      ),
    );
  }

  testWidgets('根目录视图（面包屑在 Banner 里）滚动后只剩右侧浮动操作胶囊', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 默认（详情页等）：滚动后整条栏切成胶囊岛，左侧带回顶/返回按钮
    await tester.pumpWidget(buildRootNavBar(scrollProgress: 1.0));
    await tester.pumpAndSettle();
    expect(find.byType(NavCapsuleIsland), findsOneWidget);

    // 根目录视图：面包屑交给 Banner，顶栏只留右侧操作胶囊
    await tester.pumpWidget(
      buildRootNavBar(scrollProgress: 1.0, hideBreadcrumbs: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavCapsuleIsland), findsNothing);
    expect(find.byType(NavActionsCapsule), findsOneWidget);
    expect(find.text('媒体源'), findsNothing);
  });

  testWidgets('FolderHeaderNavBar in portrait mode does not show standalone zoom button', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final folder = MusicFolder(name: 'music', path: '/home/music', files: [], subFolders: []);

    await tester.pumpWidget(
      buildTestNavBar(
        currentFolder: folder,
        navigationHistory: [],
      ),
    );
    await tester.pumpAndSettle();

    // Standalone zoom button should not be present in portrait mode
    expect(find.byType(FolderZoomNavButton), findsNothing);
    // Instead, more menu (FolderNavActionMenu) is present
    expect(find.byType(FolderNavActionMenu<String>), findsOneWidget);
  });
}
