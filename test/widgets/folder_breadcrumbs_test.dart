import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/folder_header_nav_bar.dart';

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
}
