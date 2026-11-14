import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/library_action_bar.dart';
import 'package:vynody/widgets/library_search_field.dart';

/// 本地 / 远程媒体库共用顶部动作行的布局契约：
/// 横屏搜索框最左、所有按钮平铺；竖屏播放组 + 搜索左对齐，其余全进「更多」，
/// 只有 `keepInNarrow` 的动作留在「更多」左边；点搜索整行变搜索框。
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  late int starTaps;
  late int sortTaps;
  late int zoomTaps;
  late int clearTaps;
  late TextEditingController controller;

  List<LibraryToolbarAction> actions() => [
        LibraryToolbarAction(
          icon: Icons.favorite_border_rounded,
          label: '收藏',
          onPressed: () => starTaps++,
          keepInNarrow: true,
        ),
        LibraryToolbarAction(
          icon: Icons.sort_rounded,
          label: '排序',
          onPressed: () => sortTaps++,
        ),
        LibraryToolbarAction(
          icon: Icons.grid_view_rounded,
          label: '视图',
          onPressed: () => zoomTaps++,
          hideInWide: true,
        ),
      ];

  LibraryActionBar bar({required bool isWide, bool showSearch = true}) {
    return LibraryActionBar(
      isWide: isWide,
      searchController: controller,
      searchQuery: '',
      onSearchChanged: (_) {},
      onSearchCleared: () => clearTaps++,
      showSearch: showSearch,
      onPlayAll: () {},
      onShufflePlay: () {},
      actions: actions(),
      countLabel: '共 12 首',
    );
  }

  setUp(() {
    starTaps = 0;
    sortTaps = 0;
    zoomTaps = 0;
    clearTaps = 0;
    controller = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
  });

  test('横竖屏判据只有一处：横屏恒为宽，竖屏超过 780 也算宽', () {
    expect(libraryToolbarIsWide(isLandscape: true, maxWidth: 360), isTrue);
    expect(libraryToolbarIsWide(isLandscape: false, maxWidth: 360), isFalse);
    expect(libraryToolbarIsWide(isLandscape: false, maxWidth: 800), isTrue);
  });

  testWidgets('横屏：搜索框最左，播放组与其余按钮全部平铺，无「更多」',
      (tester) async {
    await tester.pumpWidget(wrap(bar(isWide: true)));

    expect(find.byType(LibrarySearchField), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.text('共 12 首'), findsOneWidget);
    // hideInWide 的动作（分栏页让给左栏的排序）横屏不渲染。
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

    final searchLeft = tester.getTopLeft(find.byType(TextField)).dx;
    final playLeft = tester.getTopLeft(find.byIcon(Icons.play_arrow_rounded)).dx;
    expect(searchLeft, lessThan(playLeft));
  });

  testWidgets('横屏：动作组贴左，统计信息贴右边界', (tester) async {
    await tester.pumpWidget(wrap(bar(isWide: true)));

    final barRect = tester.getRect(find.byType(LibraryActionBar));
    final searchRect = tester.getRect(find.byType(LibrarySearchField));
    final sortRect = tester.getRect(find.byIcon(Icons.sort_rounded));
    final countRect = tester.getRect(find.text('共 12 首'));

    // 搜索框贴左，按钮紧跟其后，中间的留白不被平分成两半。
    expect(searchRect.left - barRect.left, lessThan(1));
    expect(barRect.right - countRect.right, lessThan(1));
    expect(sortRect.right, lessThan(countRect.left));
  });

  testWidgets('竖屏：播放组 + 搜索左对齐，红心在「更多」左边，其余收进菜单',
      (tester) async {
    await tester.pumpWidget(wrap(bar(isWide: false)));

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shuffle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsNothing);
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    expect(find.text('共 12 首'), findsNothing);

    final starLeft =
        tester.getTopLeft(find.byIcon(Icons.favorite_border_rounded)).dx;
    final moreLeft =
        tester.getTopLeft(find.byIcon(Icons.more_vert_rounded)).dx;
    expect(starLeft, lessThan(moreLeft));
  });

  testWidgets('竖屏点搜索后整行变搜索框，关闭可回常态', (tester) async {
    await tester.pumpWidget(wrap(bar(isWide: false)));

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(
      tester.getSize(find.byType(LibraryActionBar)).height,
      kLibraryActionBarHeight,
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(clearTaps, 1);
  });

  testWidgets('竖屏「更多」包含其余全部动作（含分栏隐藏项），点击能触发',
      (tester) async {
    await tester.pumpWidget(wrap(bar(isWide: false)));

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('排序'), findsOneWidget);
    expect(find.text('视图'), findsOneWidget);
    // 红心 keepInNarrow，不进菜单。
    expect(find.text('收藏'), findsNothing);

    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();
    expect(sortTaps, 1);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('视图'));
    await tester.pumpAndSettle();
    expect(zoomTaps, 1);
  });

  testWidgets('分栏豁免：showSearch=false 时横竖屏都不渲染搜索入口',
      (tester) async {
    await tester.pumpWidget(wrap(bar(isWide: true, showSearch: false)));
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsNothing);

    await tester.pumpWidget(wrap(bar(isWide: false, showSearch: false)));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
  });

  testWidgets('横屏传 leading：标题独占左侧，搜索框与按钮组整体贴右',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        LibraryActionBar(
          isWide: true,
          leading: const Text('专辑'),
          searchController: controller,
          searchQuery: '',
          onSearchChanged: (_) {},
          onSearchCleared: () {},
          onPlayAll: () {},
          onShufflePlay: () {},
          actions: actions(),
        ),
      ),
    );

    final titleLeft = tester.getTopLeft(find.text('专辑')).dx;
    final searchLeft = tester.getTopLeft(find.byType(TextField)).dx;
    final playLeft = tester.getTopLeft(find.byIcon(Icons.play_arrow_rounded)).dx;
    final sortLeft = tester.getTopLeft(find.byIcon(Icons.sort_rounded)).dx;
    final sortRight = tester.getTopRight(find.byIcon(Icons.sort_rounded)).dx;
    final screenWidth = tester.getSize(find.byType(LibraryActionBar)).width;

    // 标题在最左；搜索框仍在播放组左边；中间是留白，不是紧贴标题。
    expect(titleLeft, lessThan(searchLeft));
    expect(searchLeft, lessThan(playLeft));
    expect(playLeft, lessThan(sortLeft));
    expect(searchLeft, greaterThan(titleLeft + 100));
    // 动作组右对齐：最后一个按钮贴着行尾（按钮自身还带 8 的图标内缩）。
    expect(sortRight, greaterThan(screenWidth - 24));
  });

  testWidgets('横屏 collapseInWide 动作固定收进「更多」菜单', (tester) async {
    var downloadAllTaps = 0;
    await tester.pumpWidget(
      wrap(
        LibraryActionBar(
          isWide: true,
          searchController: controller,
          searchQuery: '',
          onSearchChanged: (_) {},
          onSearchCleared: () {},
          onPlayAll: () {},
          onShufflePlay: () {},
          actions: [
            ...actions(),
            LibraryToolbarAction(
              icon: Icons.download_for_offline_rounded,
              label: '全部下载',
              collapseInWide: true,
              onPressed: () => downloadAllTaps++,
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.byIcon(Icons.sort_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_for_offline_rounded), findsNothing);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('全部下载'), findsOneWidget);
    await tester.tap(find.text('全部下载'));
    await tester.pumpAndSettle();
    expect(downloadAllTaps, 1);
  });

  testWidgets('横屏宽度缩窄时自适应将尾部按钮折叠进「更多」，不发生溢出', (tester) async {
    var extraTaps = 0;
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 480,
          child: LibraryActionBar(
            isWide: true,
            leading: const Text('歌曲'),
            searchController: controller,
            searchQuery: '',
            onSearchChanged: (_) {},
            onSearchCleared: () {},
            onPlayAll: () {},
            onShufflePlay: () {},
            actions: [
              LibraryToolbarAction(
                icon: Icons.favorite_border_rounded,
                label: '收藏',
                onPressed: () => starTaps++,
                keepInNarrow: true,
              ),
              LibraryToolbarAction(
                icon: Icons.sort_rounded,
                label: '排序',
                onPressed: () => sortTaps++,
              ),
              LibraryToolbarAction(
                icon: Icons.my_location_rounded,
                label: '定位',
                onPressed: () => extraTaps++,
              ),
              LibraryToolbarAction(
                icon: Icons.download_rounded,
                label: '下载管理',
                onPressed: () => extraTaps++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    // 尾部「下载管理」应已折进「更多」
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    expect(find.text('下载管理'), findsOneWidget);
    await tester.tap(find.text('下载管理'));
    await tester.pumpAndSettle();
    expect(extraTaps, 1);
  });
}
