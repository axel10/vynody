import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/remote_server_slivers.dart';

void main() {
  final server = RemoteServer(
    id: 'server_1',
    name: 'My WebDAV Server',
    type: RemoteServerType.webdav,
    url: 'https://example.com/webdav',
    username: 'user',
    createdAt: DateTime(2025, 1, 1),
  );

  Widget buildTestWidget({
    required void Function(String) onToggleServerSelection,
    bool isSelectionMode = false,
  }) {
    return ProviderScope(
      overrides: [
        isProUnlockedProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              RemoteServersSliver(
                servers: [server],
                zoomScale: 0.0,
                isSelectionMode: isSelectionMode,
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
    expect(find.text(l10n.browseServer), findsOneWidget);
    expect(find.text(l10n.editRemoteServer), findsOneWidget);
  });
}
