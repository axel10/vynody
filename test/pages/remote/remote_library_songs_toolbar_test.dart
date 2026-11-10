import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/remote/widgets/remote_library_common_widgets.dart';
import 'package:vynody/pages/remote/widgets/remote_library_songs_tab.dart';
import 'package:vynody/pages/remote/widgets/remote_library_toolbar_widgets.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/library_zoom_popover.dart';

/// 远程媒体库「歌曲」tab 顶部两行（搜索/收藏/排序 + 播放全部/随机/下载）的回归：
/// 1. 排序入口与歌单 tab 一致 —— 单个图标按钮，不再是带文字标签的下拉胶囊；
/// 2. 竖屏隐藏视图按钮（档位仍可捏合），横屏保留；
/// 3. 顶部区域不再锁 1080 单列宽，左右内边距与下方曲目网格同源。
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
    required VoidCallback onSortPressed,
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
              isSearchExpanded: false,
              onToggleSearchExpanded: (_) {},
              starredOnly: false,
              onToggleStarredOnly: (_) {},
              onSortPressed: onSortPressed,
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

  testWidgets('竖屏：排序只有一个图标按钮，视图按钮隐藏', (tester) async {
    var sortTaps = 0;
    await pumpToolbar(
      tester,
      size: const Size(390, 844),
      onSortPressed: () => sortTaps++,
    );

    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byType(RemoteDropdownButton<String>), findsNothing);
    expect(find.byType(LibraryZoomButton), findsNothing);

    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pump();
    expect(sortTaps, 1);
  });

  testWidgets('横屏：排序按钮仍在，视图按钮保留', (tester) async {
    await pumpToolbar(
      tester,
      size: const Size(844, 390),
      onSortPressed: () {},
    );

    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byType(LibraryZoomButton), findsOneWidget);
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
}
