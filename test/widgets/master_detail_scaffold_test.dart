import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/master_detail_scaffold.dart';

class _TestContainer extends StatefulWidget {
  final Size screenSize;

  const _TestContainer({
    super.key,
    required this.screenSize,
  });

  @override
  State<_TestContainer> createState() => _TestContainerState();
}

class _TestContainerState extends State<_TestContainer> {
  String? _selectedKey;

  final items = const ['Item1', 'Item2', 'Item3'];

  @override
  Widget build(BuildContext context) {
    // MasterDetailScaffold 是 ConsumerStatefulWidget，需要 ProviderScope 祖先。
    return ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(
          size: widget.screenSize,
        ),
        child: MaterialApp(
          home: Scaffold(
            body: MasterDetailScaffold<String>(
              items: items,
              itemKey: (item) => item,
              selectedKey: _selectedKey,
              onSelectedKeyChanged: (key) {
                setState(() {
                  _selectedKey = key;
                });
              },
              routeName: 'test_detail',
              masterPaneHeaderBuilder: (context) =>
                  const Text('pane-header'),
              masterItemBuilder:
                  (context, item, index, isSelected, isWide, onTap) {
                return ListTile(
                  title: Text(item),
                  selected: isSelected,
                  onTap: onTap,
                );
              },
              detailBuilder: (context, item) =>
                  Text('Detail Content: $item'),
              detailPageBuilder: (context, item) => Scaffold(
                appBar: AppBar(title: Text('Detail Page: $item')),
                body: Text('Page Body: $item'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'Landscape without explicit click stays on master list when resized to portrait',
    (tester) async {
      // 1. Start in landscape (800 x 400)
      await tester.binding.setSurfaceSize(const Size(800, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testWidgetKey = GlobalKey();
      await tester.pumpWidget(
        _TestContainer(
          key: testWidgetKey,
          screenSize: const Size(800, 400),
        ),
      );
      await tester.pumpAndSettle();

      // Right detail should show preview of first item
      expect(find.text('Detail Content: Item1'), findsOneWidget);
      expect(find.text('Detail Page: Item1'), findsNothing);

      // 2. Rotate/resize to portrait (400 x 800) without clicking anything
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        _TestContainer(
          key: testWidgetKey,
          screenSize: const Size(400, 800),
        ),
      );
      await tester.pumpAndSettle();

      // Should remain on the master list in portrait, NOT push the detail page
      expect(find.text('Detail Page: Item1'), findsNothing);
      expect(find.text('Item1'), findsOneWidget);
      expect(find.text('Item2'), findsOneWidget);
    },
  );

  testWidgets(
    'Landscape explicit click does not push detail page when resized to portrait',
    (tester) async {
      // 1. Start in landscape (800 x 400)
      await tester.binding.setSurfaceSize(const Size(800, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final testWidgetKey = GlobalKey();
      await tester.pumpWidget(
        _TestContainer(
          key: testWidgetKey,
          screenSize: const Size(800, 400),
        ),
      );
      await tester.pumpAndSettle();

      // 2. Explicitly tap Item2 in the landscape master list
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();

      expect(find.text('Detail Content: Item2'), findsOneWidget);

      // 3. Rotate/resize to portrait (400 x 800)
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        _TestContainer(
          key: testWidgetKey,
          screenSize: const Size(400, 800),
        ),
      );
      await tester.pumpAndSettle();

      // 旋转为竖屏后不再自动跳转详情页，停留在主列表
      expect(find.text('Detail Page: Item2'), findsNothing);
      expect(find.text('Page Body: Item2'), findsNothing);
      expect(find.text('Item1'), findsOneWidget);
      expect(find.text('Item2'), findsOneWidget);

      // 4. 用户主动点击才进入二级详情页
      await tester.tap(find.text('Item2'));
      await tester.pumpAndSettle();

      expect(find.text('Detail Page: Item2'), findsOneWidget);

      // 5. 返回后停留在主列表
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      expect(find.text('Detail Page: Item2'), findsNothing);
      expect(find.text('Item1'), findsOneWidget);
    },
  );

  testWidgets(
    '左栏栏头只在横屏分栏时出现，竖屏退回页头搜索',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _TestContainer(screenSize: const Size(900, 500)),
      );
      await tester.pumpAndSettle();

      expect(find.text('pane-header'), findsOneWidget);

      // 竖屏没有分栏：左栏栏头随分栏一起消失。
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        _TestContainer(screenSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      expect(find.text('pane-header'), findsNothing);
      expect(find.text('Item1'), findsOneWidget);
    },
  );
}
