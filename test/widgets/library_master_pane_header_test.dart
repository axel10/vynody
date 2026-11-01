// 横屏左栏顶部工具条（搜索 + 排序）的布局回归测试。
//
// 锁定的行为：
// 1. 左栏在 260 宽窗口下（内容宽约 224）一行排得下搜索框与排序按钮，不溢出；
// 2. 排序按钮仍能正常回调，且和搜索框同处一行左侧栏；
// 3. 不传 onSortPressed 时只剩搜索框。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/library_master_pane_header.dart';

Widget _wrap(Widget child, {double width = 224}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('窄左栏下搜索框与排序按钮同排且不溢出', (tester) async {
    final controller = TextEditingController();
    var sortTaps = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        LibraryMasterPaneHeader(
          searchController: controller,
          searchQuery: '',
          searchHintText: '搜索',
          onSearchChanged: (_) {},
          onSearchCleared: () {},
          onSortPressed: () => sortTaps++,
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    final fieldRect = tester.getRect(find.byType(TextField));
    final sortRect = tester.getRect(find.byIcon(Icons.sort_rounded));
    // 同排：排序图标垂直落在搜索框范围内。
    expect(sortRect.center.dy, closeTo(fieldRect.center.dy, 4.0));
    expect(sortRect.left, greaterThan(fieldRect.right));

    await tester.tap(find.byIcon(Icons.sort_rounded));
    expect(sortTaps, 1);
  });

  testWidgets('不传排序回调时只渲染搜索框', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _wrap(
        LibraryMasterPaneHeader(
          searchController: controller,
          searchQuery: '',
          onSearchChanged: (_) {},
          onSearchCleared: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsNothing);
  });
}
