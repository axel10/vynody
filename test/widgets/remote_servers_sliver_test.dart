import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'package:vynody/widgets/remote_server_slivers.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

void main() {
  final server = RemoteServer(
    id: 'server_1',
    name: 'My WebDAV Server',
    type: RemoteServerType.webdav,
    url: 'https://example.com/webdav',
    username: 'user',
    createdAt: DateTime(2025, 1, 1),
  );

  final server2 = RemoteServer(
    id: 'server_2',
    name: 'My Navidrome Server',
    type: RemoteServerType.subsonic,
    url: 'https://example.com/subsonic',
    username: 'user2',
    createdAt: DateTime(2025, 1, 2),
  );

  Widget buildTestWidget({
    required void Function(String) onToggleServerSelection,
    bool isSelectionMode = false,
    ZoomReorderController? reorderController,
    List<RemoteServer>? serversList,
  }) {
    return ProviderScope(
      overrides: [
        isProUnlockedProvider.overrideWithValue(true),
        remoteServersProvider.overrideWith(
          () => _TestRemoteServersNotifier(serversList ?? [server, server2]),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              RemoteServersSliver(
                servers: serversList ?? [server, server2],
                zoomScale: 0.0,
                isSelectionMode: isSelectionMode,
                reorderController: reorderController,
                onToggleServerSelection: onToggleServerSelection,
                onExitSelectionMode: () {},
                onOpenServer: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('长按云端媒体库条目触发选择，不弹出上下文菜单', (tester) async {
    String? selectedId;

    await tester.pumpWidget(
      buildTestWidget(
        onToggleServerSelection: (id) => selectedId = id,
      ),
    );
    await tester.pumpAndSettle();

    final itemFinder = find.text('My WebDAV Server');
    expect(itemFinder, findsOneWidget);

    // 长按条目
    await tester.longPress(itemFinder);
    await tester.pumpAndSettle();

    // 验证长按触发了选择回调
    expect(selectedId, equals('server_1'));

    // 验证没有弹出上下文菜单（例如浏览服务器或编辑选项）
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.browseServer), findsNothing);
    expect(find.text(l10n.editRemoteServer), findsNothing);
  });

  testWidgets('多选模式下长按条目不会弹出上下文菜单', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        isSelectionMode: true,
        onToggleServerSelection: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final itemFinder = find.text('My WebDAV Server');
    expect(itemFinder, findsOneWidget);

    await tester.longPress(itemFinder);
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.browseServer), findsNothing);
    expect(find.text(l10n.editRemoteServer), findsNothing);
  });

  testWidgets('右键条目能正常唤出上下文菜单', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        onToggleServerSelection: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    final itemFinder = find.text('My WebDAV Server');
    expect(itemFinder, findsOneWidget);

    // 触发鼠标右键点击（secondary click）
    final center = tester.getCenter(itemFinder);
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.browseServer), findsNothing);
    expect(find.text(l10n.editRemoteServer), findsOneWidget);
    expect(find.text(l10n.delete), findsOneWidget);
  });

  testWidgets('非多选态下持有 reorderController 使用 ZoomReorderableSliverGrid 但隐藏手柄', (tester) async {
    final controller = ZoomReorderController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTestWidget(
        onToggleServerSelection: (_) {},
        isSelectionMode: false,
        reorderController: controller,
      ),
    );
    await tester.pumpAndSettle();

    // 挂载了可重排网格
    expect(find.byType(ZoomReorderableSliverGrid), findsOneWidget);
    // 普通态下不显示手柄（保持界面干净）
    expect(find.byType(ZoomReorderHandle), findsNothing);

    final grid = tester.widget<ZoomReorderableSliverGrid>(
      find.byType(ZoomReorderableSliverGrid),
    );
    expect(grid.showHandles, isFalse);
    expect(grid.enableDirectDrag, isTrue);

    // 验证 itemDragItemBuilder 不向外提供 paths/files 载荷（不拖到队列抽屉）
    final dragItem = await grid.itemDragItemBuilder!(0, {0}, <String, dynamic>{});
    expect(dragItem.localData, isA<Map<String, dynamic>>());
    final localData = dragItem.localData as Map<String, dynamic>;
    expect(localData.containsKey('paths'), isFalse);
    expect(localData.containsKey('path'), isFalse);
  });

  testWidgets('多选态下持有 reorderController 显示手柄', (tester) async {
    final controller = ZoomReorderController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTestWidget(
        onToggleServerSelection: (_) {},
        isSelectionMode: true,
        reorderController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ZoomReorderableSliverGrid), findsOneWidget);
    expect(find.byType(ZoomReorderHandle), findsNWidgets(2));

    final grid = tester.widget<ZoomReorderableSliverGrid>(
      find.byType(ZoomReorderableSliverGrid),
    );
    expect(grid.showHandles, isTrue);
  });
}

class _TestRemoteServersNotifier extends RemoteServersNotifier {
  final List<RemoteServer> _initial;
  _TestRemoteServersNotifier(this._initial);

  @override
  Future<List<RemoteServer>> build() async => _initial;

  @override
  Future<void> reorderServers(List<RemoteServer> reordered) async {
    state = AsyncData(reordered);
  }
}
