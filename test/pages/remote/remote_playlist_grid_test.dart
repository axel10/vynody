import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/sort_options_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/remote_library_playlists_tab.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/remote_playlist_zoom_item.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

/// 远程歌单页的网格与排序行为回归。
///
/// 这一页原本是固定行式列表，与本地歌单页（档位网格）完全两套观感。
/// 改成档位网格后，下面几条不变量必须一直成立：
/// 1. 走 `SliverGrid` + `SliverAnimatedZoomGridDelegate`，不是行式列表；
/// 2. 默认顺序完全等于服务端返回顺序 —— 服务端没有「歌单之间排序」的接口，
///    所以这一页既不本地记忆顺序，也不提供拖拽重排；
/// 3. 排序按钮只做展示层排序：默认服务端原序，切换字段才排，星标虚拟歌单恒首位。
///    存进本地设置的是「按哪个字段 + 升降序」这个视图偏好，不是歌单顺序。
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

  Map<String, dynamic> playlist(
    String id,
    String name, {
    int songCount = 1,
    int duration = 0,
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'songCount': songCount,
        'duration': duration,
      };

  Future<void> pumpView(
    WidgetTester tester,
    List<Map<String, dynamic>> playlists, {
    RemotePlaylistSortField sortField = RemotePlaylistSortField.serverOrder,
    bool sortAscending = true,
  }) async {
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
                  sortField: sortField,
                  sortAscending: sortAscending,
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

  testWidgets('按名称排序：升序 / 降序', (tester) async {
    final source = [
      playlist('pl_c', 'C'),
      playlist('pl_a', 'A'),
      playlist('pl_b', 'B'),
    ];

    await pumpView(tester, source, sortField: RemotePlaylistSortField.name);
    expect(
      renderedItems(tester).map((e) => e.title).toList(),
      <String>['A', 'B', 'C'],
    );

    await pumpView(
      tester,
      source,
      sortField: RemotePlaylistSortField.name,
      sortAscending: false,
    );
    expect(
      renderedItems(tester).map((e) => e.title).toList(),
      <String>['C', 'B', 'A'],
    );
  });

  testWidgets('按歌曲数 / 时长排序，星标虚拟歌单恒首位', (tester) async {
    final source = [
      playlist(RemoteLibraryPlaylistsView.starredPlaylistId, '我喜欢的歌曲'),
      playlist('pl_few', 'Few', songCount: 2, duration: 10),
      playlist('pl_many', 'Many', songCount: 9, duration: 90),
      playlist('pl_mid', 'Mid', songCount: 5, duration: 50),
    ];

    await pumpView(
      tester,
      source,
      sortField: RemotePlaylistSortField.songCount,
      sortAscending: false,
    );
    var items = renderedItems(tester);
    expect(items.first.isPinned, isTrue);
    expect(
      items.skip(1).map((e) => e.title).toList(),
      <String>['Many', 'Mid', 'Few'],
    );

    await pumpView(
      tester,
      source,
      sortField: RemotePlaylistSortField.duration,
    );
    items = renderedItems(tester);
    expect(items.first.isPinned, isTrue);
    expect(
      items.skip(1).map((e) => e.title).toList(),
      <String>['Few', 'Mid', 'Many'],
    );
  });

  testWidgets('工具栏用排序按钮替换了刷新按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: OKToast(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: RemoteLibraryPlaylistsToolbar(
                searchController: TextEditingController(),
                onSearchChanged: (_) {},
                onClearSearch: () {},
                onCreatePlaylist: () {},
                onSortPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('排序弹窗在「服务端原序」下禁用降序开关', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<SortResult<RemotePlaylistSortField>>(
                  context: context,
                  builder: (_) => SortOptionsDialog<RemotePlaylistSortField>(
                    title: '排序',
                    currentField: RemotePlaylistSortField.serverOrder,
                    sortAscending: true,
                    ascendingToggleEnabled: (field) =>
                        field != RemotePlaylistSortField.serverOrder,
                    options: const [
                      SortOptionItem(
                        value: RemotePlaylistSortField.serverOrder,
                        label: '服务端原序',
                        icon: Icons.cloud_queue_rounded,
                      ),
                      SortOptionItem(
                        value: RemotePlaylistSortField.name,
                        label: '歌单名称',
                        icon: Icons.sort_by_alpha_rounded,
                      ),
                    ],
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );

    await tester.tap(find.text('歌单名称'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNotNull,
    );
  });

  group('本地设置里的排序字段解析', () {
    test('每个枚举值都能用 .name 往返', () {
      for (final field in RemotePlaylistSortField.values) {
        expect(remotePlaylistSortFieldFromStorage(field.name), field);
      }
    });

    test('null / 空串 / 未知值都退回服务端原序', () {
      expect(
        remotePlaylistSortFieldFromStorage(null),
        RemotePlaylistSortField.serverOrder,
      );
      expect(
        remotePlaylistSortFieldFromStorage(''),
        RemotePlaylistSortField.serverOrder,
      );
      expect(
        remotePlaylistSortFieldFromStorage('starred'),
        RemotePlaylistSortField.serverOrder,
      );
    });
  });
}
