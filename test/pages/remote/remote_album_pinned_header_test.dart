import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/remote_library_albums_tab.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/widgets/adaptive_pinned_header_scroll_view.dart';

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

  final sampleAlbums = List.generate(
    30,
    (i) => <String, dynamic>{
      'id': 'album-$i',
      'title': 'Album $i',
      'artist': 'Artist $i',
      'songCount': 10,
      'year': 2020 + (i % 5),
    },
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildTestWidget({
    required Size size,
    Widget? toolbar,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
      ],
      child: OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(size: size),
              child: RemoteLibraryAlbumsView(
                server: testServer,
                password: 'password',
                albums: sampleAlbums,
                isLoading: false,
                error: null,
                searchQuery: '',
                isSelectionMode: false,
                selectedAlbumIds: const {},
                lastAlbumAnchorIndex: null,
                bottomOffset: 0.0,
                onRefresh: () async {},
                onSetSelection: (_) {},
                onToggleSelection: (_) {},
                onUpdateAnchor: (_) {},
                onPlayAlbumDirectly: (_, __) {},
                toolbar: toolbar,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('RemoteLibraryAlbumsView pins toolbar in landscape when scrolling', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final searchController = TextEditingController();
    addTearDown(() => searchController.dispose());

    final toolbar = RemoteLibraryAlbumsToolbar(
      key: const ValueKey('remote_albums_toolbar'),
      searchController: searchController,
      searchQuery: '',
      onSearchChanged: (_) {},
      onClearSearch: () {},
      sortType: 'name',
      onSortTypeChanged: (_) {},
      starredOnly: false,
      onToggleStarredOnly: (_) {},
      onPlayAll: () {},
      onShufflePlay: () {},
    );

    await tester.pumpWidget(buildTestWidget(
      size: const Size(1280, 800),
      toolbar: toolbar,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AdaptivePinnedHeaderScrollView), findsOneWidget);
    expect(find.byKey(const ValueKey('remote_albums_toolbar')), findsOneWidget);

    final initialToolbarPos = tester.getTopLeft(find.byKey(const ValueKey('remote_albums_toolbar')));

    // Drag the scrollable album grid upwards by 300px
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    final scrolledToolbarPos = tester.getTopLeft(find.byKey(const ValueKey('remote_albums_toolbar')));

    // In landscape mode, toolbar position should remain pinned at the top
    expect(scrolledToolbarPos.dy, equals(initialToolbarPos.dy));
  });

  testWidgets('RemoteLibraryAlbumsView scrolls toolbar away in portrait', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final searchController = TextEditingController();
    addTearDown(() => searchController.dispose());

    final toolbar = RemoteLibraryAlbumsToolbar(
      key: const ValueKey('remote_albums_toolbar'),
      searchController: searchController,
      searchQuery: '',
      onSearchChanged: (_) {},
      onClearSearch: () {},
      sortType: 'name',
      onSortTypeChanged: (_) {},
      starredOnly: false,
      onToggleStarredOnly: (_) {},
      onPlayAll: () {},
      onShufflePlay: () {},
    );

    await tester.pumpWidget(buildTestWidget(
      size: const Size(400, 800),
      toolbar: toolbar,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('remote_albums_toolbar')), findsOneWidget);

    final initialToolbarPos = tester.getTopLeft(find.byKey(const ValueKey('remote_albums_toolbar')));

    // Drag the scrollable album grid upwards by 80px
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -80));
    await tester.pumpAndSettle();

    final scrolledToolbarPos = tester.getTopLeft(find.byKey(const ValueKey('remote_albums_toolbar')));

    // In portrait mode, toolbar should scroll away with the content
    expect(scrolledToolbarPos.dy, lessThan(initialToolbarPos.dy));
  });
}
