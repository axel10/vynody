import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/pages/folder_root_view.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/layout_constants.dart';

AudioSnapshot _createTestSnapshot() {
  return AudioSnapshot(
    isPlaying: false,
    isTransitioning: false,
    isLastActionNext: null,
    currentMusic: null,
    position: Duration.zero,
    duration: Duration.zero,
    volume: 1.0,
    isMuted: false,
    currentIndex: 0,
    isRandomMode: false,
    isShuffleRandomMode: false,
    playbackMode: AppPlaybackMode.queue,
    equalizerConfig: EqualizerConfig(
      enabled: false,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: Float32List(10),
    ),
    currentVisualizerOptions: const VisualizerOptimizationOptions(
      frequencyGroups: 100,
    ),
    historyCursor: null,
    deckCursor: null,
    isVisualizerEnabled: false,
    dynamicStartColor: null,
    dynamicEndColor: null,
    isLyricsActive: false,
    sleepTimerRemaining: null,
    sleepTimerDuration: null,
    playbackSpeed: 1.0,
  );
}

class _FakeAudioService extends AudioService {
  @override
  AudioSnapshot build() => _createTestSnapshot();

  @override
  Uint8List? getCachedArtwork(String? path) => null;
}

class _StubScannerService extends ScannerService {
  _StubScannerService() : super(autoInitialize: false);

  @override
  List<MusicFolder> get rootFolders => const [];

  @override
  int get structureRevision => 1;
}

class _TestRemoteServersNotifier extends RemoteServersNotifier {
  final List<RemoteServer> _initial;
  _TestRemoteServersNotifier(this._initial);

  @override
  Future<List<RemoteServer>> build() async => _initial;

  @override
  Future<String?> getPassword(String id) async => 'secret';
}

void main() {
  late SettingsService settingsService;

  final subsonicServer = RemoteServer(
    id: 'server_subsonic',
    name: 'Navidrome Library',
    type: RemoteServerType.subsonic,
    url: 'https://example.com/subsonic',
    username: 'user',
    createdAt: DateTime(2025, 1, 1),
  );

  final webdavServer = RemoteServer(
    id: 'server_webdav',
    name: 'WebDAV Storage',
    type: RemoteServerType.webdav,
    url: 'https://example.com/webdav',
    username: 'user',
    createdAt: DateTime(2025, 1, 2),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildTestWidget({
    required List<RemoteServer> servers,
    ActiveRemoteSession? initialSession,
  }) {
    return ProviderScope(
      overrides: [
        isProUnlockedProvider.overrideWithValue(true),
        settingsServiceProvider.overrideWith((ref) => settingsService),
        scannerServiceProvider.overrideWith((ref) => _StubScannerService()),
        audioServiceProvider.overrideWith((ref) => _FakeAudioService()),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        audioIsPlayingProvider.overrideWith((ref) => false),
        remoteServersProvider.overrideWith(
          () => _TestRemoteServersNotifier(servers),
        ),
        if (initialSession != null)
          activeRemoteSessionProvider.overrideWith(
            () => _PrefilledSessionNotifier(initialSession),
          ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FolderRootView(
            onOpenPlayback: () async {},
            isSelectionMode: false,
            selectedRootPaths: const {},
            isCloudServerSelectionMode: false,
            selectedServerIds: const {},
            onToggleServerSelection: (_) {},
            onExitCloudServerSelection: () {},
            onSelectAllCloudServers: (_) {},
            onPickFolder: () {},
            onToggleRootSelection: (_) {},
            onToggleRootSelectionMode: () {},
            onDeleteSelectedRootFolders: () async {},
            onNavigateTo: (_) {},
            onShowFolderBottomSheet: (_, {required isRoot}) {},
            onShowFolderContextMenu: (_, _, {required isRoot}) {},
          ),
        ),
      ),
    );
  }

  testWidgets('点击未连接的远程媒体库能建立会话并跳转至媒体库标签页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestWidget(servers: [subsonicServer]),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(FolderRootView));
    final container = ProviderScope.containerOf(element);

    expect(container.read(activeRemoteSessionProvider), isNull);
    expect(container.read(mainTabIndexProvider), equals(kMainTabFolders));

    final serverItem = find.text('Navidrome Library');
    expect(serverItem, findsOneWidget);

    await tester.tap(serverItem);
    await tester.pumpAndSettle();

    final session = container.read(activeRemoteSessionProvider);
    expect(session, isNotNull);
    expect(session!.server.id, equals('server_subsonic'));
    expect(container.read(mainTabIndexProvider), equals(kMainTabRemoteLibrary));
  });

  testWidgets('点击已连接的同名远程媒体库保留缓存并跳转至媒体库标签页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final existingSession = ActiveRemoteSession(
      server: subsonicServer,
      password: 'secret',
      navidromeAlbums: [
        {'id': 'album_1', 'name': 'Cached Album'},
      ],
    );

    await tester.pumpWidget(
      buildTestWidget(
        servers: [subsonicServer],
        initialSession: existingSession,
      ),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(FolderRootView));
    final container = ProviderScope.containerOf(element);

    // 初始状态处于目录页，且已有带缓存的活跃会话
    container.read(mainTabIndexProvider.notifier).setIndex(kMainTabFolders);
    await tester.pumpAndSettle();

    final serverItem = find.text('Navidrome Library');
    expect(serverItem, findsOneWidget);

    await tester.tap(serverItem);
    await tester.pumpAndSettle();

    final session = container.read(activeRemoteSessionProvider);
    expect(session, isNotNull);
    // 验证会话依然是原有的，且缓存未被冲掉
    expect(session!.navidromeAlbums, isNotNull);
    expect(session.navidromeAlbums!.length, equals(1));
    expect(container.read(mainTabIndexProvider), equals(kMainTabRemoteLibrary));
  });

  testWidgets('点击 WebDAV 服务器不跳转媒体库标签页', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestWidget(servers: [webdavServer]),
    );
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(FolderRootView));
    final container = ProviderScope.containerOf(element);

    final serverItem = find.text('WebDAV Storage');
    expect(serverItem, findsOneWidget);

    await tester.tap(serverItem);
    await tester.pumpAndSettle();

    final session = container.read(activeRemoteSessionProvider);
    expect(session, isNotNull);
    expect(session!.server.id, equals('server_webdav'));
    // WebDAV 留在目录页（由目录页 Navigator 展示子页）
    expect(container.read(mainTabIndexProvider), equals(kMainTabFolders));
  });
}

class _PrefilledSessionNotifier extends ActiveRemoteSessionNotifier {
  final ActiveRemoteSession _session;
  _PrefilledSessionNotifier(this._session);

  @override
  ActiveRemoteSession? build() => _session;
}
