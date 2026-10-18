import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/dialogs/folder_sort_sheet.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';

const String _folder = '/music/rock';

/// 以真实路由打开浮层，这样「确定 / 取消」的 pop 才有意义。
Future<void> _openSheet(WidgetTester tester, ScannerService scanner) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showFolderSortSheet(
                context: context,
                scanner: scanner,
                folderPath: _folder,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tapInSheet(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// 浮层可能比屏幕高，确定按钮要先滚进可视区。
Future<void> _tapConfirm(WidgetTester tester) => _tapInSheet(tester, '确定');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('选项只在点确定后写入，此前不动任何设置', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);

    await _openSheet(tester, scanner);

    expect(find.text('仅此目录'), findsOneWidget);
    expect(find.text('此目录跟随全局排序设置'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await _tapInSheet(tester, '标题');

    // 只是选中，还没有写
    expect(scanner.getGlobalSortSettings().criteria,
        SortCriteria.trackNumber);
    expect(scanner.hasSortOverrideForFolder(_folder), isFalse);

    await _tapConfirm(tester);

    expect(scanner.getGlobalSortSettings().criteria, SortCriteria.title);
    expect(scanner.hasSortOverrideForFolder(_folder), isFalse);
    // 浮层已关闭
    expect(find.text('仅此目录'), findsNothing);
  });

  testWidgets('取消不改任何设置', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);

    await _openSheet(tester, scanner);
    await _tapInSheet(tester, '标题');
    await _tapInSheet(tester, '取消');

    expect(scanner.getGlobalSortSettings().criteria,
        SortCriteria.trackNumber);
    expect(scanner.hasSortOverrideForFolder(_folder), isFalse);
    expect(find.text('仅此目录'), findsNothing);
  });

  testWidgets('开启仅此目录后改排序只写此目录', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);
    // 显式给全局一个非默认值，避免和「默认音轨号」撞车
    scanner.setGlobalSort(criteria: SortCriteria.filename);

    await _openSheet(tester, scanner);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // 开关也只改待生效状态
    expect(scanner.hasSortOverrideForFolder(_folder), isFalse);
    expect(find.text('此目录单独使用上面的排序设置'), findsOneWidget);

    await _tapInSheet(tester, '标题');
    expect(scanner.hasSortOverrideForFolder(_folder), isFalse);

    await _tapConfirm(tester);

    expect(scanner.getSortSettingsForFolder(_folder).criteria,
        SortCriteria.title);
    expect(scanner.hasSortOverrideForFolder(_folder), isTrue);
    // 全局仍是文件名，未被牵连
    expect(scanner.getGlobalSortSettings().criteria, SortCriteria.filename);
  });

  testWidgets('关闭仅此目录后选项回到全局值，确定后才删除覆盖', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final scanner = ScannerService(autoInitialize: false);
    addTearDown(scanner.dispose);
    scanner.setGlobalSort(criteria: SortCriteria.filename);
    scanner.setFolderSortLocalized(_folder, true);
    scanner.setFolderSort(_folder, criteria: SortCriteria.title);

    await _openSheet(tester, scanner);

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

    // 关闭开关本身不写库
    expect(scanner.hasSortOverrideForFolder(_folder), isTrue);
    final filenameTile = tester.widget<RadioListTile<SortCriteria>>(
      find.ancestor(
        of: find.text('文件名'),
        matching: find.byType(RadioListTile<SortCriteria>),
      ),
    );
    expect(filenameTile.selected, isTrue);
    expect(find.text('此目录跟随全局排序设置'), findsOneWidget);

    await _tapConfirm(tester);

    expect(scanner.hasSortOverrideForFolder(_folder), isFalse);
    expect(scanner.getSortSettingsForFolder(_folder).criteria,
        SortCriteria.filename);
  });
}
