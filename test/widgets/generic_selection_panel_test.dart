import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/generic_selection_panel.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('GenericSelectionPanel renders title, cancel and executes action', (tester) async {
    bool cancelCalled = false;
    bool actionCalled = false;

    await tester.pumpWidget(
      _wrap(
        GenericSelectionPanel(
          title: '已选 2 项',
          onCancel: () => cancelCalled = true,
          actions: [
            SelectionActionItem(
              icon: Icons.edit_rounded,
              label: '编辑',
              onPressed: () => actionCalled = true,
            ),
            SelectionActionItem(
              icon: Icons.delete_outline_rounded,
              label: '删除',
              onPressed: null,
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // Cancel callback
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(cancelCalled, isTrue);

    // Enabled action callback
    await tester.tap(find.text('编辑'));
    expect(actionCalled, isTrue);

    // Disabled action
    final deleteButton = tester.widget<TextButton>(
      find.ancestor(of: find.text('删除'), matching: find.byType(TextButton)).first,
    );
    expect(deleteButton.onPressed, isNull);
  });

  testWidgets('GenericSelectionPanel defaults to 4 columns and pads remaining slots when actions < 4', (tester) async {
    final threeActions = [
      SelectionActionItem(icon: Icons.select_all, label: '全选', onPressed: () {}),
      SelectionActionItem(icon: Icons.edit, label: '编辑', onPressed: () {}),
      SelectionActionItem(icon: Icons.delete, label: '删除', onPressed: () {}),
    ];

    await tester.pumpWidget(
      _wrap(
        GenericSelectionPanel(
          title: '已选 1 项',
          onCancel: () {},
          actions: threeActions,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认排布为 4 列，整行应包含 4 个 Expanded（3 个操作按钮 + 1 个占位）
    final expandedWidgets = tester.widgetList<Expanded>(
      find.descendant(
        of: find.byType(Row).last,
        matching: find.byType(Expanded),
      ),
    );
    expect(expandedWidgets.length, 4);
  });

  testWidgets('GenericSelectionPanel shows scrollbar when actions exceed 2 rows', (tester) async {
    final manyActions = List.generate(
      12,
      (i) => SelectionActionItem(
        icon: Icons.star,
        label: 'Action $i',
        onPressed: () {},
      ),
    );

    await tester.pumpWidget(
      _wrap(
        GenericSelectionPanel(
          title: '批量操作',
          onCancel: () {},
          actions: manyActions,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('GenericSelectionPanel keeps 4 columns in phone portrait even when actions >= 5', (tester) async {
    final fiveActions = List.generate(
      5,
      (i) => SelectionActionItem(
        icon: Icons.star,
        label: 'Action $i',
        onPressed: () {},
      ),
    );

    // 模拟典型手机竖屏（宽度 390，高度 844，竖屏，最短边 < 600）
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
          ),
          child: Scaffold(
            body: Center(
              child: GenericSelectionPanel(
                title: '手机竖屏多选',
                onCancel: () {},
                actions: fiveActions,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expandedWidgets = tester.widgetList<Expanded>(
      find.descendant(
        of: find.byType(Row).last,
        matching: find.byType(Expanded),
      ),
    );
    // 手机竖屏下固定一行 4 个
    expect(expandedWidgets.length, 4);
  });

  testWidgets('GenericSelectionPanel displays 5 columns when in wide screen (landscape) and actions >= 5', (tester) async {
    final fiveActions = List.generate(
      5,
      (i) => SelectionActionItem(
        icon: Icons.star,
        label: 'Action $i',
        onPressed: () {},
      ),
    );

    // 模拟横屏环境
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(844, 390),
          ),
          child: Scaffold(
            body: Center(
              child: GenericSelectionPanel(
                title: '横屏多选',
                onCancel: () {},
                actions: fiveActions,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expandedWidgets = tester.widgetList<Expanded>(
      find.descendant(
        of: find.byType(Row).last,
        matching: find.byType(Expanded),
      ),
    );
    expect(expandedWidgets.length, 5);
  });

  testWidgets('GenericSelectionPanel falls back to shortLabel when item width is constrained', (tester) async {
    final actions = [
      SelectionActionItem(
        icon: Icons.playlist_add_rounded,
        label: '添加到播放列表',
        shortLabel: '播放列表',
        onPressed: () {},
      ),
      SelectionActionItem(
        icon: Icons.queue_music_rounded,
        label: '添加到队列',
        shortLabel: '队列',
        onPressed: () {},
      ),
      SelectionActionItem(
        icon: Icons.star,
        label: '收藏',
        onPressed: () {},
      ),
    ];

    // 在较窄宽度（例如 320）下，单项按钮宽度不足以显示长文本「添加到播放列表」
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320,
          child: GenericSelectionPanel(
            title: '已选 1 首',
            onCancel: () {},
            actions: actions,
            columns: 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('播放列表'), findsOneWidget);
    expect(find.text('添加到播放列表'), findsNothing);
    expect(find.text('队列'), findsOneWidget);
    expect(find.text('添加到队列'), findsNothing);
  });

  testWidgets('GenericSelectionPanel keeps full label when item width is sufficiently wide', (tester) async {
    final actions = [
      SelectionActionItem(
        icon: Icons.playlist_add_rounded,
        label: '添加到播放列表',
        shortLabel: '播放列表',
        onPressed: () {},
      ),
      SelectionActionItem(
        icon: Icons.queue_music_rounded,
        label: '添加到队列',
        shortLabel: '队列',
        onPressed: () {},
      ),
    ];

    // 在超宽容器（例如 600）且只有两列时，单项按钮宽度极其充裕
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 600,
          child: GenericSelectionPanel(
            title: '已选 1 首',
            onCancel: () {},
            actions: actions,
            columns: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加到播放列表'), findsOneWidget);
    expect(find.text('播放列表'), findsNothing);
    expect(find.text('添加到队列'), findsOneWidget);
    expect(find.text('队列'), findsNothing);
  });
}
