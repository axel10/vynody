import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/music_folders_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/pages/folder_root_view.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/settings/settings_service.dart';

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildDialogHost({
    required List<RemoteServer> servers,
    void Function(bool?)? onDialogClosed,
  }) {
    return ProviderScope(
      overrides: [
        isProUnlockedProvider.overrideWithValue(true),
        settingsServiceProvider.overrideWith((ref) => settingsService),
        scannerServiceProvider.overrideWith((ref) => _StubScannerService()),
        remoteServersProvider.overrideWith(
          () => _TestRemoteServersNotifier(servers),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final res = await MusicFoldersDialog.show(context);
                  onDialogClosed?.call(res);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('MusicFoldersDialog renders 2+1 buttons and remote server list',
      (tester) async {
    bool? closedResult;
    await tester.pumpWidget(
      buildDialogHost(
        servers: [subsonicServer],
        onDialogClosed: (v) => closedResult = v,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Header & 2+1 buttons
    expect(find.text('添加媒体源'), findsOneWidget);
    expect(find.text('添加文件夹'), findsOneWidget);
    expect(find.text('远程媒体库'), findsOneWidget);
    expect(find.text('保存并扫描'), findsOneWidget);

    // Remote server is shown in list even when rootFolders is empty
    expect(find.text('Navidrome Library'), findsOneWidget);
    expect(find.text('暂无已选根目录'), findsNothing);

    // Clicking 保存并扫描 closes directly without empty-folder warning
    await tester.tap(find.text('保存并扫描'));
    await tester.pumpAndSettle();

    expect(find.text('暂未添加任何目录'), findsNothing);
    expect(closedResult, isTrue);
  });

  testWidgets('MusicFoldersDialog warns when both folders and servers are empty',
      (tester) async {
    await tester.pumpWidget(buildDialogHost(servers: const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('暂无已选根目录'), findsOneWidget);

    await tester.tap(find.text('保存并扫描'));
    await tester.pumpAndSettle();

    expect(find.text('暂未添加任何目录'), findsOneWidget);
  });

  testWidgets('FolderRootView displays 添加媒体源 button', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isProUnlockedProvider.overrideWithValue(true),
          settingsServiceProvider.overrideWith((ref) => settingsService),
          scannerServiceProvider.overrideWith((ref) => _StubScannerService()),
          audioServiceProvider.overrideWith((ref) => _FakeAudioService()),
          audioCurrentMusicProvider.overrideWith((ref) => null),
          audioIsPlayingProvider.overrideWith((ref) => false),
          remoteServersProvider.overrideWith(
            () => _TestRemoteServersNotifier(const []),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
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
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加媒体源'), findsOneWidget);
    expect(find.text('添加根目录'), findsNothing);
  });
}
