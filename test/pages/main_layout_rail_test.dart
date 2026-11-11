import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/main_layout.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';

class _MockSessionNotifier extends ActiveRemoteSessionNotifier {
  final ActiveRemoteSession? _initial;
  _MockSessionNotifier(this._initial);
  @override
  ActiveRemoteSession? build() => _initial;
}

void main() {
  late SettingsService settingsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildRail({
    int selectedIndex = 2,
    int? librarySubIndex,
    bool isLibraryExpanded = true,
    bool extended = true,
    ActiveRemoteSession? activeRemoteSession,
    bool isPro = false,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        if (activeRemoteSession != null)
          activeRemoteSessionProvider.overrideWith(() => _MockSessionNotifier(activeRemoteSession)),
        if (isPro)
          isProUnlockedProvider.overrideWith((ref) => true),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SlidingNavigationRail(
            width: 240,
            extended: extended,
            selectedIndex: selectedIndex,
            onDestinationSelected: (_) {},
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.red,
            isPlayback: false,
            isSettingsActive: false,
            isLibraryExpanded: isLibraryExpanded,
            librarySubIndex: librarySubIndex,
            onLibrarySubDestinationSelected: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('When librarySubIndex is null, playlist is not selected', (tester) async {
    await tester.pumpWidget(buildRail());
    await tester.pumpAndSettle();

    // Verify 媒体库 and sub-items are rendered
    expect(find.text('媒体库'), findsNWidgets(2));
    expect(find.text('播放列表'), findsOneWidget);

    // Edit button should not be visible when not hovered
    expect(find.text('编辑'), findsNothing);
    expect(find.text('完成'), findsNothing);
  });

  testWidgets('Hovering 媒体库 shows 编辑 button, clicking it enters edit mode with checkboxes',
      (tester) async {
    await tester.pumpWidget(buildRail());
    await tester.pumpAndSettle();

    // Simulate mouse hover over 媒体库 section header row
    final libraryTileFinder = find.text('媒体库').last;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(libraryTileFinder));
    await tester.pumpAndSettle();

    // Now 编辑 should be visible
    expect(find.text('编辑'), findsOneWidget);

    // Click 编辑
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // Now 完成 should be visible
    expect(find.text('完成'), findsOneWidget);

    // Checkboxes should be displayed for each sub item (8 check icons since all visible by default)
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(8));

    // Toggle (uncheck) "最近播放"
    await tester.tap(find.text('最近播放'));
    await tester.pumpAndSettle();

    // Now 最近播放 is unchecked (7 check icons remaining)
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(7));
    expect(settingsService.isLibraryTabVisible('recentlyPlayed'), isFalse);

    // Click 完成 to exit edit mode
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    // Edit mode exited
    expect(find.text('完成'), findsNothing);

    // 最近播放 should no longer be displayed in media library sub-tabs!
    expect(find.text('最近播放'), findsNothing);

    // Other checked items (e.g. 专辑, 艺术家) are still displayed
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('艺术家'), findsOneWidget);
  });

  testWidgets('Library sub-items remain expanded when non-library tab is selected', (tester) async {
    // When selectedIndex is 0 (文件) or 1 (播放)
    await tester.pumpWidget(buildRail(selectedIndex: 0));
    await tester.pumpAndSettle();

    // Verify 媒体库 standalone entry, 媒体库 section header, and sub-items are still displayed
    expect(find.text('媒体库'), findsNWidgets(2));
    expect(find.text('播放列表'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('艺术家'), findsOneWidget);
  });

  testWidgets('SlidingNavigationRail does not contain redundant Play destination', (tester) async {
    await tester.pumpWidget(buildRail(selectedIndex: 0));
    await tester.pumpAndSettle();

    // Verify play icons are not present in rail destinations
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
    expect(find.byIcon(Icons.play_circle), findsNothing);

    // Verify other primary navigation icons are present
    expect(find.byIcon(Icons.folder), findsOneWidget); // active
    expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('When remote library session is active, remote library section is inserted before local library and playlist', (tester) async {
    final testServer = RemoteServer(
      id: 'test-remote-server',
      name: 'Test Server',
      type: RemoteServerType.subsonic,
      url: 'https://music.example.com',
      username: 'user',
      createdAt: DateTime.now(),
    );
    final session = ActiveRemoteSession(
      server: testServer,
      password: 'password',
    );

    await tester.pumpWidget(buildRail(
      selectedIndex: 0,
      activeRemoteSession: session,
      isPro: true,
    ));
    await tester.pumpAndSettle();

    // Verify 远程媒体库 entries are present
    // One for the primary navigation icon and one for section header
    expect(find.text('远程媒体库'), findsNWidgets(2));
    // Sub-items of remote library should be visible (e.g. 搜索 is remote-only)
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('播放列表'), findsOneWidget);

    final folderDy = tester.getTopLeft(find.text('媒体源')).dy;
    final remoteHeaderDy = tester.getTopLeft(find.text('远程媒体库').last).dy;
    final remoteSearchDy = tester.getTopLeft(find.text('搜索')).dy;
    final localLibraryHeaderDy = tester.getTopLeft(find.text('媒体库').last).dy;
    final playlistDy = tester.getTopLeft(find.text('播放列表')).dy;

    // Remote library section and sub items must appear after 媒体源 and before local library / playlist
    expect(folderDy < remoteHeaderDy, isTrue, reason: 'Remote section header should be below 媒体源');
    expect(remoteHeaderDy < remoteSearchDy, isTrue, reason: 'Remote sub-items should be below remote section header');
    expect(remoteSearchDy < localLibraryHeaderDy, isTrue, reason: 'Remote section should be above local library header');
    expect(localLibraryHeaderDy < playlistDy, isTrue, reason: 'Local library header should be above playlist header');
  });
}

