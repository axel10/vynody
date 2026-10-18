import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';

/// 目录排序「作用域」语义的回归测试。
///
/// 约定：
/// - 未开启「仅此目录」= 该目录跟随全局，改动写全局；
/// - 开启 = 目录持有一份覆盖，改动只影响此目录；
/// - 关闭 = 删除覆盖，回到全局。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const folder = '/music/rock';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ScannerService buildService() => ScannerService(autoInitialize: false);

  test('未开启「仅此目录」时解析为全局设置', () {
    final scanner = buildService();
    addTearDown(scanner.dispose);

    expect(scanner.hasSortOverrideForFolder(folder), isFalse);
    final resolved = scanner.getSortSettingsForFolder(folder);
    expect(resolved.criteria, SortCriteria.filename);
    expect(resolved.order, SortOrder.ascending);
  });

  test('开启「仅此目录」物化覆盖，但值仍等于当前生效设置', () {
    final scanner = buildService();
    addTearDown(scanner.dispose);

    scanner.setGlobalSort(criteria: SortCriteria.title);
    scanner.setFolderSortLocalized(folder, true);

    expect(scanner.hasSortOverrideForFolder(folder), isTrue);
    final resolved = scanner.getSortSettingsForFolder(folder);
    expect(resolved.criteria, SortCriteria.title);
    expect(resolved.order, SortOrder.ascending);
  });

  test('有覆盖时改排序只影响此目录，全局不变', () {
    final scanner = buildService();
    addTearDown(scanner.dispose);

    scanner.setFolderSortLocalized(folder, true);
    scanner.setFolderSort(folder, criteria: SortCriteria.trackNumber);
    scanner.setFolderSort(folder, order: SortOrder.descending);

    expect(scanner.getSortSettingsForFolder(folder).criteria,
        SortCriteria.trackNumber);
    expect(scanner.getSortSettingsForFolder(folder).order,
        SortOrder.descending);
    // 其它目录与全局不受影响
    expect(scanner.getGlobalSortSettings().criteria, SortCriteria.filename);
    expect(scanner.getGlobalSortSettings().order, SortOrder.ascending);
    expect(scanner.hasSortOverrideForFolder('/music/jazz'), isFalse);
  });

  test('关闭「仅此目录」删除覆盖，回到全局设置', () {
    final scanner = buildService();
    addTearDown(scanner.dispose);

    scanner.setFolderSortLocalized(folder, true);
    scanner.setFolderSort(folder, criteria: SortCriteria.title);
    expect(scanner.hasSortOverrideForFolder(folder), isTrue);

    scanner.setFolderSortLocalized(folder, false);

    expect(scanner.hasSortOverrideForFolder(folder), isFalse);
    expect(scanner.getSortSettingsForFolder(folder).criteria,
        SortCriteria.filename);
  });

  test('全局改动不会穿透已开启「仅此目录」的目录', () {
    final scanner = buildService();
    addTearDown(scanner.dispose);

    scanner.setFolderSortLocalized(folder, true);
    scanner.setGlobalSort(criteria: SortCriteria.trackNumber);

    expect(scanner.getSortSettingsForFolder(folder).criteria,
        SortCriteria.filename);
    expect(scanner.getSortSettingsForFolder('/music/jazz').criteria,
        SortCriteria.trackNumber);
  });

  test('重复开启 / 重复关闭都不会产生多余状态', () {
    final scanner = buildService();
    addTearDown(scanner.dispose);

    scanner.setFolderSortLocalized(folder, true);
    scanner.setFolderSortLocalized(folder, true);
    expect(scanner.hasSortOverrideForFolder(folder), isTrue);

    scanner.setFolderSortLocalized(folder, false);
    scanner.setFolderSortLocalized(folder, false);
    expect(scanner.hasSortOverrideForFolder(folder), isFalse);
  });
}
