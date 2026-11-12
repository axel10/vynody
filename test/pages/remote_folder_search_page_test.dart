import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/remote_folder_search_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/folder_zoom_gesture_layer.dart';
import 'package:vynody/widgets/library_large_title.dart';
import 'package:vynody/widgets/library_search_field.dart';
import 'package:vynody/widgets/song_zoom_item.dart';

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

class _MockActiveRemoteSessionNotifier extends ActiveRemoteSessionNotifier {
  _MockActiveRemoteSessionNotifier(this._initialSession);
  final ActiveRemoteSession? _initialSession;

  @override
  ActiveRemoteSession? build() => _initialSession;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsService settingsService;

  final server = RemoteServer(
    id: 'test_server',
    name: 'Test Server',
    type: RemoteServerType.webdav,
    url: 'http://127.0.0.1:8080',
    username: 'user',
    createdAt: DateTime.now(),
  );

  setUp(() async {
    tempDir =
        Directory.systemTemp.createTempSync('remote_folder_search_test_');
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
    required ActiveRemoteSession sessionState,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        audioIsPlayingProvider.overrideWith((ref) => false),
        activeRemoteSessionProvider.overrideWith(
          () => _MockActiveRemoteSessionNotifier(sessionState),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RemoteFolderSearchPage(
          server: server,
          password: 'secret',
          currentPath: '/music',
        ),
      ),
    );
  }

  testWidgets('RemoteFolderSearchPage renders header and zooms properly',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final session = ActiveRemoteSession(
      server: server,
      password: 'secret',
      initialPath: '/music',
      webDavDirectoryCache: {
        '/music': [
          WebDavFile(
            path: '/music/pop',
            name: 'pop',
            isDirectory: true,
            contentLength: 0,
            lastModified: DateTime.now(),
          ),
          WebDavFile(
            path: '/music/love.mp3',
            name: 'love.mp3',
            isDirectory: false,
            contentLength: 2048,
            lastModified: DateTime.now(),
          ),
        ],
      },
    );

    await tester.pumpWidget(createSubject(sessionState: session));
    await tester.pumpAndSettle();

    // 页头应具备统一的大标题和搜索框
    expect(find.byType(LibraryLargeTitle), findsOneWidget);
    expect(find.byType(LibrarySearchField), findsOneWidget);
    expect(find.text('输入内容以开始搜索'), findsOneWidget);

    // 输入搜索文本
    await tester.enterText(find.byType(TextField), 'love');
    // 等待 250ms debounce
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    // 搜索结果应当包含分类标题与缩放层
    expect(find.byType(FolderZoomGestureLayer), findsOneWidget);
    expect(find.byType(SearchSectionHeader), findsOneWidget);
    expect(find.widgetWithText(SongZoomItem, 'love'), findsOneWidget);
  });

  testWidgets(
      'RemoteFolderSearchPage avoids top system status bar when padding is not provided',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 48.0);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);

    final session = ActiveRemoteSession(
      server: server,
      password: 'secret',
      initialPath: '/music',
    );

    await tester.pumpWidget(createSubject(sessionState: session));
    await tester.pumpAndSettle();

    final titlePos = tester.getTopLeft(find.byType(LibraryLargeTitle));
    // safeTop is 48.0, topPadding is 48.0, with +16 offset the title starts at dy >= 64.0
    expect(titlePos.dy, greaterThanOrEqualTo(64.0));
  });
}
