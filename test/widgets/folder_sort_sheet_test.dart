import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/folder_sort_sheet.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: Scaffold(body: child),
  );
}

void main() {
  const folder = '/music/rock';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('默认跟随全局：改排序方式写全局设置', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);

    await tester.pumpWidget(
      _wrap(FolderSortSheet(scanner: scanner, folderPath: folder)),
    );
    await tester.pumpAndSettle();

    expect(find.text('仅此目录'), findsOneWidget);
    expect(find.text('此目录跟随全局排序设置'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();

    expect(scanner.getGlobalSortSettings().criteria, SortCriteria.title);
    expect(scanner.hasSortOverrideForFolder(folder), isFalse);
  });

  testWidgets('开启仅此目录后改排序只写此目录', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);
    // 显式给全局一个非默认值，避免和「默认音轨号」撞车
    scanner.setGlobalSort(criteria: SortCriteria.filename);

    await tester.pumpWidget(
      _wrap(FolderSortSheet(scanner: scanner, folderPath: folder)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(scanner.hasSortOverrideForFolder(folder), isTrue);
    expect(find.text('此目录单独使用上面的排序设置'), findsOneWidget);

    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();

    expect(scanner.getSortSettingsForFolder(folder).criteria,
        SortCriteria.title);
    // 全局仍是文件名，未被牵连
    expect(scanner.getGlobalSortSettings().criteria, SortCriteria.filename);
  });

  testWidgets('关闭仅此目录后选项回到全局值', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);
    scanner.setGlobalSort(criteria: SortCriteria.filename);
    scanner.setFolderSortLocalized(folder, true);
    scanner.setFolderSort(folder, criteria: SortCriteria.title);

    await tester.pumpWidget(
      _wrap(FolderSortSheet(scanner: scanner, folderPath: folder)),
    );
    await tester.pumpAndSettle();

    // 打开时展示此目录生效的「标题」，而非全局的「文件名」
    final titleTile = tester.widget<RadioListTile<SortCriteria>>(
      find.ancestor(
        of: find.text('标题'),
        matching: find.byType(RadioListTile<SortCriteria>),
      ),
    );
    expect(titleTile.selected, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(scanner.hasSortOverrideForFolder(folder), isFalse);
    final filenameTile = tester.widget<RadioListTile<SortCriteria>>(
      find.ancestor(
        of: find.text('文件名'),
        matching: find.byType(RadioListTile<SortCriteria>),
      ),
    );
    expect(filenameTile.selected, isTrue);
    expect(find.text('此目录跟随全局排序设置'), findsOneWidget);
  });
}
