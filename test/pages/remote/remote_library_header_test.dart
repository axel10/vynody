import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/remote_library_toolbar_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_icons.dart';
import 'package:vynody/widgets/library_action_bar.dart';
import 'package:vynody/widgets/library_large_title.dart';
import 'package:vynody/widgets/library_zoom_popover.dart';

/// 远程二级页页头的回归：
/// 1. 分类页头必须有返回键 —— 远程库的二级分类压在自己的局部 Navigator 里，
///    没有返回键就出不去（横屏没有 Rail 兜底时尤其致命）；
/// 2. 播放全部 / 随机播放与大标题同源，横竖屏都出现；
/// 3. `forceNarrow` 用于横屏主从分栏的左栏（330 宽），必须走折行布局。
void main() {
  late SettingsService settings;

  Future<Widget> wrap(Widget child) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
    return ProviderScope(
      overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  RemoteLibraryActionBar buildHeader({
    String? title = '专辑',
    VoidCallback? onBack,
    bool forceNarrow = false,
    List<LibraryToolbarAction> trailingActions = const <LibraryToolbarAction>[],
  }) {
    return RemoteLibraryActionBar(
      title: title,
      onBack: onBack ?? () {},
      forceNarrow: forceNarrow,
      trailingActions: trailingActions,
      searchController: TextEditingController(),
      searchQuery: '',
      onSearchChanged: (_) {},
      onSearchCleared: () {},
      searchHintText: '筛选专辑',
      countLabel: '共 12 张专辑',
      onPlayAll: () {},
      onShufflePlay: () {},
      actions: [
        remoteZoomAction(label: '列表视图', scope: LibraryZoomScope.album),
      ],
    );
  }

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size * 2.0;
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(await wrap(child));
    await tester.pump();
  }

  testWidgets('横屏：大标题 + 计数 + 返回键 + 播放组', (tester) async {
    int backCount = 0;
    await pumpAt(
      tester,
      const Size(900, 500),
      buildHeader(onBack: () => backCount++),
    );

    expect(find.byType(LibraryLargeTitle), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('共 12 张专辑'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);

    await tester.tap(find.byIcon(kAppBackIcon));
    expect(backCount, 1);
  });

  testWidgets('竖屏：返回键与标题仍在首行，动作折到下一行', (tester) async {
    await pumpAt(tester, const Size(390, 844), buildHeader());

    expect(find.byType(LibraryLargeTitle), findsOneWidget);
    expect(find.byIcon(kAppBackIcon), findsOneWidget);
    // 竖屏不放常驻搜索框，只留搜索入口；播放组仍在首屏。
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('没有标题的页头不渲染返回键', (tester) async {
    await pumpAt(
      tester,
      const Size(900, 500),
      buildHeader(title: null),
    );

    expect(find.byType(LibraryLargeTitle), findsNothing);
    expect(find.byIcon(kAppBackIcon), findsNothing);
  });

  testWidgets('forceNarrow：横屏左栏也走折行布局（不出横向溢出）', (tester) async {
    await pumpAt(
      tester,
      const Size(900, 500),
      SizedBox(width: 330, child: buildHeader(forceNarrow: true)),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(LibraryLargeTitle), findsOneWidget);
    expect(find.byIcon(kAppBackIcon), findsOneWidget);
    // 折行布局等同竖屏口径：搜索收成图标按钮，点开才展开输入框。
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('hideInNarrow 动作仅在横屏顶部栏显示，竖屏与更多菜单均隐藏', (tester) async {
    var refreshCount = 0;
    final refreshAction = LibraryToolbarAction(
      icon: Icons.refresh_rounded,
      label: '刷新',
      hideInNarrow: true,
      onPressed: () => refreshCount++,
    );

    // 横屏可见且可点击
    await pumpAt(
      tester,
      const Size(900, 500),
      buildHeader(trailingActions: [refreshAction]),
    );
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    expect(refreshCount, 1);

    // 竖屏不可见，点开「更多」菜单也不包含
    await pumpAt(
      tester,
      const Size(390, 844),
      buildHeader(trailingActions: [refreshAction]),
    );
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    expect(find.text('刷新'), findsNothing);
  });
}
