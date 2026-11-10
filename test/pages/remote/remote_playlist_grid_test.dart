import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/remote_library_playlists_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/remote_playlist_zoom_item.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 远程歌单页的网格行为回归。
///
/// 这一页原本是固定行式列表，与本地歌单页（档位网格）完全两套观感。
/// 改成档位网格后，下面两条不变量必须一直成立：
/// 1. 走 `SliverGrid` + `SliverAnimatedZoomGridDelegate`，不是行式列表；
/// 2. 顺序完全等于服务端返回顺序 —— 服务端没有「歌单之间排序」的接口，
///    所以这一页既不本地记忆顺序，也不提供拖拽重排。
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

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  Map<String, dynamic> playlist(String id, String name) => <String, dynamic>{
        'id': id,
        'name': name,
        'songCount': 1,
      };

  Future<void> pumpView(
    WidgetTester tester,
    List<Map<String, dynamic>> playlists,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: OKToast(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 1400,
                height: 900,
                child: RemoteLibraryPlaylistsView(
                  server: server,
                  password: 'pwd',
                  playlists: playlists,
                  selectedPlaylistId: null,
                  isLoading: false,
                  error: null,
                  onRefresh: () async {},
                  searchQuery: '',
                  bottomOffset: 0,
                  isSelectionMode: false,
                  selectedPlaylistIds: const <String>{},
                  lastPlaylistAnchorIndex: null,
                  onSelectPlaylistId: (_) {},
                  onSetSelection: (_) {},
                  onToggleSelection: (_) {},
                  onUpdateAnchor: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // 档位度量要等首帧布局完成才有值，之后还有一次 morph 收敛，多推几帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  List<RemotePlaylistZoomItem> renderedItems(WidgetTester tester) {
    return tester
        .widgetList<RemotePlaylistZoomItem>(
          find.byType(RemotePlaylistZoomItem),
        )
        .toList();
  }

  testWidgets('歌单页走档位网格，且不可重排', (tester) async {
    await pumpView(tester, [
      playlist(RemoteLibraryPlaylistsView.starredPlaylistId, '我喜欢的歌曲'),
      playlist('pl_a', 'A'),
      playlist('pl_b', 'B'),
    ]);

    expect(find.byType(RemotePlaylistZoomItem), findsNWidgets(3));
    // 档位网格：SliverGrid 的 delegate 必须是档位那套。
    final zoomGrids = tester
        .widgetList<SliverGrid>(find.byType(SliverGrid))
        .where((grid) => grid.gridDelegate is SliverAnimatedZoomGridDelegate)
        .toList();
    expect(zoomGrids, isNotEmpty);
    // 顺序不可拖拽重排：不允许出现可重排网格。
    expect(find.byType(ZoomReorderableSliverGrid), findsNothing);
  });

  testWidgets('顺序完全跟服务端返回一致，不做本地重排', (tester) async {
    await pumpView(tester, [
      playlist('pl_c', 'C'),
      playlist('pl_a', 'A'),
      playlist('pl_b', 'B'),
    ]);

    expect(
      renderedItems(tester).map((e) => e.title).toList(),
      <String>['C', 'A', 'B'],
    );
  });
}
