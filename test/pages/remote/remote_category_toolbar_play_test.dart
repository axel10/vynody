import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/remote_library_albums_tab.dart';
import 'package:vynody/pages/remote/widgets/remote_library_playlists_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';

/// 远程分类 tab（专辑 / 艺术家 / 流派 / 歌单）顶部必须有「播放全部 / 随机播放」。
///
/// 此前只有歌曲 tab 有这两个入口，其余分类页的播放组在统一动作行改造时丢了。
/// 工具栏只负责回调，条目 → 曲目的展开由 `playRemoteLibraryEntities` 负责。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpToolbar(
    WidgetTester tester,
    Widget child, {
    required Size size,
  }) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('专辑工具栏横屏：播放全部与随机播放都在，点击能触发', (tester) async {
    var playAll = 0;
    var shuffle = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpToolbar(
      tester,
      RemoteLibraryAlbumsToolbar(
        searchController: controller,
        searchQuery: '',
        onSearchChanged: (_) {},
        onClearSearch: () {},
        sortType: 'alphabeticalByName',
        onSortTypeChanged: (_) {},
        starredOnly: false,
        onToggleStarredOnly: (_) {},
        totalCount: 12,
        onPlayAll: () => playAll++,
        onShufflePlay: () => shuffle++,
      ),
      size: const Size(844, 390),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    expect(playAll, 1);
    expect(shuffle, 1);
  });

  testWidgets('歌单工具栏竖屏：播放组留在行首，其余收进「更多」', (tester) async {
    var playAll = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pumpToolbar(
      tester,
      RemoteLibraryPlaylistsToolbar(
        searchController: controller,
        onSearchChanged: (_) {},
        onClearSearch: () {},
        onCreatePlaylist: () {},
        onSortPressed: () {},
        totalCount: 3,
        onPlayAll: () => playAll++,
        onShufflePlay: () {},
      ),
      size: const Size(390, 844),
    );

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    // 新建歌单与排序竖屏收进「更多」，不再平铺。
    expect(find.byIcon(Icons.add_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(playAll, 1);
  });
}
