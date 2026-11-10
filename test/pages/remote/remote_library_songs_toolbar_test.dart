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

  testWidgets('横屏：所有按钮平铺，不出现「更多」按钮', (tester) async {
    await pumpToolbar(tester, size: const Size(844, 390));

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byType(LibraryZoomButton), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
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
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byType(LibraryZoomButton), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    // 竖屏此前不显示视图档位，现在从「更多」里加回来。
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
  });

  testWidgets('顶部区域宽度与下方曲目网格同源', (tester) async {
    final settings = await pumpSongsView(tester);

    final header = tester.widget<SliverRemoteContentConstraint>(
      find.byType(SliverRemoteContentConstraint),
    );
    expect(header.maxWidth, kFolderPageMaxWidth);

    final expectedHPad = folderContentHorizontalPadding(
      isPortrait: true,
      gridMorph: isFolderZoomGrid(snapFolderZoomScale(settings.songZoomScale))
          ? 1.0
          : 0.0,
    );
    expect(
      header.padding,
      EdgeInsets.fromLTRB(expectedHPad, 6, expectedHPad, 8),
    );
  });

  /// 列表视图与网格视图必须同宽：水平内边距由缩放包的
  /// `folderContentHorizontalPadding` 决定（曾按档位在 8/4 与 16 之间插值，
  /// 切到列表后顶部与曲目行一起变宽，页头反而比内容窄），页面自己传的
  /// padding 也会被包内 `_resolveLayerHorizontal` 按档位重新校正。
  for (final entry in const {'列表视图': 0.0, '网格视图': 1.0}.entries) {
    testWidgets('${entry.key}：顶部动作行与曲目行同宽且贴 16', (tester) async {
      await pumpSongsViewWithRows(tester, zoomScale: entry.value);

      final toolbarLeft =
          tester.getRect(find.byType(RemoteLibrarySongsToolbar)).left;
      final rowLeft = tester.getRect(find.byType(SongZoomItem).first).left;
      final rowRight = tester.getRect(find.byType(SongZoomItem).first).right;

      expect(toolbarLeft, kGridHorizontalPadding);
      expect(rowLeft, toolbarLeft, reason: '顶部与内容左边缘必须一致');
      // 网格视图一行多张卡片，只有列表视图能按整行宽度核对右边缘。
      if (entry.value == 0.0) {
        final toolbarRight =
            tester.getRect(find.byType(RemoteLibrarySongsToolbar)).right;
        expect(rowRight, toolbarRight, reason: '顶部与内容右边缘必须一致');
      }
    });
  }
}
