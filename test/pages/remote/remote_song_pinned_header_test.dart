import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/pages/remote/remote_library_sub_host_page.dart';
import 'package:vynody/pages/remote/widgets/remote_library_songs_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/adaptive_pinned_header_scroll_view.dart';
import 'package:vynody/widgets/floating_capsule_header.dart';
import 'package:vynody/widgets/library_large_title.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settingsService;

  final testServer = RemoteServer(
    id: 'test_server',
    name: 'Navidrome Server',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'testuser',
    createdAt: DateTime.now(),
  );

  final sampleSongs = List.generate(
    30,
    (i) => MusicFile(
      id: i + 1,
      path: 'subsonic://${testServer.id}/song-$i',
      name: 'Song $i.mp3',
      title: 'Song $i',
      artist: 'Artist $i',
      album: 'Album $i',
      durationMillis: 180000,
    ),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildSongsTestWidget({
    required Size size,
    RemoteLibrarySongsToolbar? toolbar,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
        audioCurrentMusicProvider.overrideWith((ref) => null),
        audioIsPlayingProvider.overrideWith((ref) => false),
      ],
      child: OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size),
              child: RemoteLibrarySongsView(
                server: testServer,
                password: 'password',
                songs: sampleSongs,
                totalServerSongsCount: sampleSongs.length,
                starredSongIds: const {},
                isLoading: false,
                isLoadingMore: false,
                hasMore: false,
                error: null,
                onRefresh: () async {},
                onLoadMore: null,
                searchQuery: '',
                bottomOffset: 0.0,
                isSelectionMode: false,
                selectedSongPaths: const {},
                lastSongAnchorIndex: null,
                onSetSelection: (_) {},
                onToggleSelection: (_) {},
                onUpdateAnchor: (_) {},
                onToggleStar: (_) {},
                toolbar: toolbar,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('RemoteLibrarySongsView pins toolbar in landscape when scrolling',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    addTearDown(() {
      searchController.dispose();
      searchFocusNode.dispose();
    });

    final toolbar = RemoteLibrarySongsToolbar(
      key: const ValueKey('remote_songs_toolbar'),
      title: 'Songs',
      searchController: searchController,
      searchFocusNode: searchFocusNode,
      searchQuery: '',
      onSearchChanged: (_) {},
      onClearSearch: () {},
      starredOnly: false,
      onToggleStarredOnly: (_) {},
      onSortPressed: () {},
    );

    await tester.pumpWidget(
      buildSongsTestWidget(
        size: const Size(1280, 800),
        toolbar: toolbar,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdaptivePinnedHeaderScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_songs_toolbar')), findsOneWidget);

    final initialToolbarPos =
        tester.getTopLeft(find.byKey(const ValueKey('remote_songs_toolbar')));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final afterScrollToolbarPos =
        tester.getTopLeft(find.byKey(const ValueKey('remote_songs_toolbar')));
    expect(afterScrollToolbarPos.dy, equals(initialToolbarPos.dy));
  });

  testWidgets('RemoteLibrarySongsView scrolls toolbar away in portrait',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    addTearDown(() {
      searchController.dispose();
      searchFocusNode.dispose();
    });

    final toolbar = RemoteLibrarySongsToolbar(
      key: const ValueKey('remote_songs_toolbar'),
      title: 'Songs',
      searchController: searchController,
      searchFocusNode: searchFocusNode,
      searchQuery: '',
      onSearchChanged: (_) {},
      onClearSearch: () {},
      starredOnly: false,
      onToggleStarredOnly: (_) {},
      onSortPressed: () {},
    );

    await tester.pumpWidget(
      buildSongsTestWidget(
        size: const Size(400, 800),
        toolbar: toolbar,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AdaptivePinnedHeaderScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_songs_toolbar')), findsOneWidget);

    final initialToolbarPos =
        tester.getTopLeft(find.byKey(const ValueKey('remote_songs_toolbar')));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final toolbarFinder = find.byKey(const ValueKey('remote_songs_toolbar'));
    if (toolbarFinder.evaluate().isNotEmpty) {
      final afterScrollToolbarPos = tester.getTopLeft(toolbarFinder);
      expect(afterScrollToolbarPos.dy, lessThan(initialToolbarPos.dy));
    }
  });

  testWidgets(
      'RemoteLibrarySubHostPage disables floating capsule for capsuleDisabledTabs and provides LibrarySubHostScope',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final navKeys = [
      GlobalKey<NavigatorState>(),
      GlobalKey<NavigatorState>(),
    ];
    double? observedTopPadding;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settingsService),
          remoteLibraryActiveTabIndexProvider.overrideWith(() {
            return _FixedRemoteTabIndexNotifier(1);
          }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.only(top: 24),
            ),
            child: RemoteLibrarySubHostPage(
              initialIndex: 1,
              navigatorKeys: navKeys,
              onBack: () {},
              onRefresh: (_) {},
              capsuleDisabledTabs: const {1},
              tabs: [
                (_) => const SizedBox.shrink(),
                (ctx) {
                  observedTopPadding = LibrarySubHostScope.maybeOf(ctx)?.topPadding;
                  return ListView.builder(
                    itemCount: 40,
                    itemBuilder: (_, i) => ListTile(title: Text('Row $i')),
                  );
                },
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(observedTopPadding, greaterThanOrEqualTo(24.0));

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final capsule = tester.widget<FloatingCapsuleHeader>(
      find.byType(FloatingCapsuleHeader),
    );
    expect(capsule.visible, isFalse);
  });
}

class _FixedRemoteTabIndexNotifier extends RemoteLibraryActiveTabIndexNotifier {
  _FixedRemoteTabIndexNotifier(this._initial);
  final int _initial;

  @override
  int? build() => _initial;
}
