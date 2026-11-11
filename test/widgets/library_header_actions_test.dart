import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/library_action_bar.dart';
import 'package:vynody/widgets/library_category_header.dart';
import 'package:vynody/widgets/library_header_actions.dart';
import 'package:vynody/widgets/nav_capsule_island.dart';

/// 媒体库滚动后浮出的顶栏胶囊与页头动作行的同源契约：
/// 胶囊「更多」里必须就是页头动作行解析出的那一份动作（同一批闭包），
/// 且菜单在展开那一刻才求值 —— 否则「播放全部」会拿着旧列表去播。
void main() {
  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  late TextEditingController searchController;

  setUp(() {
    searchController = TextEditingController();
  });

  tearDown(() {
    searchController.dispose();
  });

  LibraryToolbarAction sortAction(VoidCallback onPressed) {
    return LibraryToolbarAction(
      icon: Icons.sort_rounded,
      label: '排序',
      onPressed: onPressed,
    );
  }

  test('按 tab 分账：切到哪个分类就只读那个分类的动作', () {
    final controller = LibraryHeaderActionsController();
    controller.register(0, [sortAction(() {})]);
    controller.register(4, [
      sortAction(() {}),
      LibraryToolbarAction(
        icon: Icons.grid_view_rounded,
        label: '视图',
        onPressed: () {},
      ),
    ]);

    expect(controller.activeActions, hasLength(1));

    controller.setActiveTab(4);
    expect(controller.activeActions.map((a) => a.label), ['排序', '视图']);

    // 未注册过的分类返回空清单，不能把上一个分类的动作顶上来。
    controller.setActiveTab(7);
    expect(controller.activeActions, isEmpty);
  });

  testWidgets('页头把播放组、搜索与附加动作一起登记给胶囊', (tester) async {
    final controller = LibraryHeaderActionsController();
    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    var sortTaps = 0;

    await tester.pumpWidget(
      wrap(
        LibraryHeaderActionsScope(
          tabIndex: 0,
          controller: controller,
          child: LibraryCategoryHeader(
            title: '专辑',
            isWide: false,
            searchController: searchController,
            searchQuery: '',
            onSearchChanged: (_) {},
            onSearchCleared: () {},
            onPlayAll: () {},
            onShufflePlay: () {},
            extraActions: [sortAction(() => sortTaps++)],
          ),
        ),
      ),
    );

    // 竖屏动作行里「排序」已经收进「更多」，页头上不该平铺出来。
    expect(find.byIcon(Icons.sort_rounded), findsNothing);

    final labels = controller.activeActions.map((a) => a.label).toList();
    // 前四项是「播放组 + 搜索 + 分类附加动作」，其后是页头自带的来源筛选。
    expect(labels.take(4).toList(), [
      l10n.playAll,
      l10n.shufflePlay,
      l10n.search,
      '排序',
    ]);
  });

  testWidgets('胶囊「更多」渲染页头登记的全部动作，点击能触发', (tester) async {
    final controller = LibraryHeaderActionsController();
    var sortTaps = 0;
    controller.register(0, [sortAction(() => sortTaps++)]);

    await tester.pumpWidget(
      wrap(LibraryTopNavCapsule(controller: controller, onBack: () {})),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();

    expect(find.text('排序'), findsOneWidget);
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();
    expect(sortTaps, 1);
  });

  testWidgets('胶囊右侧的「更多」是正圆：44×44，不能撑成横向胶囊', (tester) async {
    final controller = LibraryHeaderActionsController();
    controller.register(0, [sortAction(() {})]);

    await tester.pumpWidget(
      wrap(LibraryTopNavCapsule(controller: controller, onBack: () {})),
    );

    // 右侧那枚玻璃胶囊的盒子：单动作时必须收成正圆。
    final capsule = tester.getRect(find.byType(NavActionsCapsule));
    final backCapsule = tester.getRect(find.byType(NavCapsuleIsland));

    expect(capsule.width, kNavCapsuleHeight, reason: '宽度必须等于胶囊高，否则圆角落在椭圆上');
    expect(capsule.height, kNavCapsuleHeight);
    expect(capsule.size.aspectRatio, 1.0);
    // 左右两枚必须同径，否则并排看就是「一大一小」。
    expect(backCapsule.size, capsule.size);
  });

  testWidgets('菜单在展开那一刻才求值：重注册后点到的是新闭包', (tester) async {
    final controller = LibraryHeaderActionsController();
    var taps = 0;
    controller.register(0, [sortAction(() => taps += 100)]);
    expect(controller.activeActions.single, isNotNull);

    await tester.pumpWidget(
      wrap(LibraryTopNavCapsule(controller: controller, onBack: () {})),
    );

    // 模拟页头随后重建：同一位置被替换成新闭包（「播放全部」捕获新列表的场景）。
    controller.register(0, [sortAction(() => taps += 1)]);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    expect(taps, 1, reason: '胶囊读的是展开菜单时的清单，不是首次挂载时的那份');
  });
}
