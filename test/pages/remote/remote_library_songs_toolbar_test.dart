import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/remote/widgets/remote_library_common_widgets.dart';
import 'package:vynody/pages/remote/widgets/remote_library_songs_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/library_action_bar.dart';
import 'package:vynody/widgets/library_zoom_popover.dart';
import 'package:vynody/widgets/song_zoom_item.dart';

/// 远程「歌曲」tab 顶部动作行的回归：
/// 1. 横屏所有按钮平铺（搜索框 / 播放组 / 红心 / 下载 / 排序 / 视图档位），无「更多」；
/// 2. 竖屏左侧只剩播放组 + 搜索按钮，红心留在「更多」左边，其余全部进「更多」；
/// 3. 竖屏此前被隐藏的视图档位，现在从「更多」里加回来；
/// 4. 顶部区域宽度与下方曲目网格同源。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final server = RemoteServer(
    id: 'subsonic_test',
    name: 'Navidrome Server',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'testuser',
    createdAt: DateTime(2026, 1, 1),
  );

  Future<SettingsService> pumpToolbar(
    WidgetTester tester, {
    required Size size,
    List<LibraryToolbarAction> trailingActions = const <LibraryToolbarAction>[],
    String? title,
    String? countLabel,
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
          home: Scaffold(
            body: RemoteLibrarySongsToolbar(
              title: title,
              countLabel: countLabel,
              trailingActions: trailingActions,
              searchController: TextEditingController(),
              searchFocusNode: FocusNode(),
              searchQuery: '',
              onSearchChanged: (_) {},
              onClearSearch: () {},
              starredOnly: false,
              onToggleStarredOnly: (_) {},
              onSortPressed: () {},
              onPlayAll: () {},
              onShufflePlay: () {},
              onDownloadAll: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return settings;
  }

  Future<SettingsService> pumpSongsView(WidgetTester tester) async {
    const size = Size(390, 844);
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          // 空列表分支只需要顶部区域；挡掉播放状态 provider，避免测试进程
          // 去初始化 AudioService / Rust 动态库（flutter_tester 里没有该库）。
          audioCurrentMusicProvider.overrideWith((ref) => null),
          audioIsPlayingProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RemoteLibrarySongsView(
              server: server,
              password: 'pwd',
              songs: const <MusicFile>[],
              totalServerSongsCount: 0,
              starredSongIds: const <String>{},
              isLoading: false,
              isLoadingMore: false,
              hasMore: false,
              error: null,
              onRefresh: () async {},
              onLoadMore: () {},
              searchQuery: '',
              bottomOffset: 0,
              isSelectionMode: false,
              selectedSongPaths: const <String>{},
              lastSongAnchorIndex: null,
              onSetSelection: (_) {},
              onToggleSelection: (_) {},
              onUpdateAnchor: (_) {},
              onToggleStar: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return settings;
  }

  /// 带曲目的歌曲视图：需要真实条目才能核对顶部区与曲目行的左右边缘。
  Future<void> pumpSongsViewWithRows(
    WidgetTester tester, {
    required double zoomScale,
  }) async {
    const size = Size(1200, 800);
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    settings.songZoomScale = zoomScale;

    final songs = List<MusicFile>.generate(
      6,
      (i) => MusicFile(
        path: 'remote://song-$i',
        name: 'Song $i',
        artist: 'Artist $i',
        album: 'Album $i',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          audioCurrentMusicProvider.overrideWith((ref) => null),
          audioIsPlayingProvider.overrideWith((ref) => false),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: RemoteLibrarySongsView(
              server: server,
              password: 'pwd',
              songs: songs,
              totalServerSongsCount: songs.length,
              starredSongIds: const <String>{},
              isLoading: false,
              isLoadingMore: false,
              hasMore: false,
              error: null,
              onRefresh: () async {},
              onLoadMore: () {},
              searchQuery: '',
              bottomOffset: 0,
              isSelectionMode: false,
              selectedSongPaths: const <String>{},
              lastSongAnchorIndex: null,
              onSetSelection: (_) {},
              onToggleSelection: (_) {},
              onUpdateAnchor: (_) {},
              onToggleStar: (_) {},
              toolbar: RemoteLibrarySongsToolbar(
                searchController: TextEditingController(),
                searchFocusNode: FocusNode(),
                searchQuery: '',
                onSearchChanged: (_) {},
                onClearSearch: () {},
                starredOnly: false,
                onToggleStarredOnly: (_) {},
                onSortPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('横屏：常用按钮平铺，「全部下载」收进「更多」菜单', (tester) async {
    await pumpToolbar(tester, size: const Size(844, 390));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byType(LibraryZoomButton), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_rounded), findsNothing);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.download_for_offline_rounded), findsOneWidget);
  });

  testWidgets('窄横屏含大标题与库级尾缀按钮时不溢出', (tester) async {
    await pumpToolbar(
      tester,
      size: const Size(560, 390),
      title: '歌曲',
      countLabel: '1234 首 · 82:15:30',
      trailingActions: [
        LibraryToolbarAction(
          icon: Icons.refresh_rounded,
          label: '刷新',
          hideInNarrow: true,
          collapseInWide: true,
          onPressed: () {},
        ),
        LibraryToolbarAction(
          icon: Icons.my_location_rounded,
          label: '定位当前播放',
          onPressed: () {},
        ),
        LibraryToolbarAction(
          icon: Icons.download_rounded,
          label: '下载管理',
          onPressed: () {},
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });

  testWidgets('竖屏：只有播放组 + 搜索 + 红心 + 更多，其余收进菜单',
      (tester) async {
    await pumpToolbar(tester, size: const Size(390, 844));

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsNothing);
    expect(find.byIcon(Icons.download_for_offline_rounded), findsNothing);
    expect(find.byType(LibraryZoomButton), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_rounded), findsOneWidget);
    // 竖屏此前不显示视图档位，现在从「更多」里加回来。
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
  });

  testWidgets('顶部区域与下方内容同宽：内边距只由页头自己给一份', (tester) async {
    await pumpSongsView(tester);

    // 页头插槽不再自带水平内边距 —— 那份 16 由 `LibraryCategoryHeader`
    // 内部统一给，外层再套一份会让标题与搜索框比网格右移 16px，
    // 和本地库的二级页对不齐。
    expect(find.byType(SliverRemotePageHeaderSlot), findsOneWidget);
    expect(find.byType(RemoteContentConstraint), findsNothing);
  });

  /// 列表视图与网格视图的页头必须铺满内容区，正文从 16 开始。
  ///
  /// 页头的 16 是本地库 `LibraryCategoryHeader` 的口径；曲目行仍按缩放包的
  /// `folderContentHorizontalPadding` 按档位取 8/4，两者相差的几像素是列表态
  /// 多塞内容的既有取舍，不在本次对齐范围内。
  for (final entry in const {'列表视图': 0.0, '网格视图': 1.0}.entries) {
    testWidgets('${entry.key}：页头铺满内容区且正文贴 16', (tester) async {
      await pumpSongsViewWithRows(tester, zoomScale: entry.value);

      final headerRect =
          tester.getRect(find.byType(RemoteLibrarySongsToolbar));
      expect(headerRect.left, 0, reason: '页头背景要铺到内容区左边缘');
      expect(headerRect.right, 1200, reason: '页头背景要铺到内容区右边缘');

      final searchLeft = tester.getRect(find.byType(TextField)).left;
      expect(searchLeft, kGridHorizontalPadding, reason: '页头正文贴 16');
    });
  }
}
