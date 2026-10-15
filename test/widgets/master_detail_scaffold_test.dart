import 'package:flutter/material.dart';
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
    return MediaQuery(
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
            masterItemBuilder: (context, item, index, isSelected, isWide, onTap) {
              return ListTile(
                title: Text(item),
                selected: isSelected,
                onTap: onTap,
              );
            },
            detailBuilder: (context, item) => Text('Detail Content: $item'),
            detailPageBuilder: (context, item) => Scaffold(
              appBar: AppBar(title: Text('Detail Page: $item')),
              body: Text('Page Body: $item'),
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
    'Landscape with explicit click pushes detail page when resized to portrait',
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

      // Should auto-push the detail page for Item2
      expect(find.text('Detail Page: Item2'), findsOneWidget);
      expect(find.text('Page Body: Item2'), findsOneWidget);

      // 4. If user pops the detail page in portrait
      final NavigatorState navigator = tester.state(find.byType(Navigator).last);
      navigator.pop();
      await tester.pumpAndSettle();

      // Back on master list
      expect(find.text('Detail Page: Item2'), findsNothing);
      expect(find.text('Item1'), findsOneWidget);

      // 5. Rotate to landscape and back to portrait without clicking
      await tester.binding.setSurfaceSize(const Size(800, 400));
      await tester.pumpWidget(
        _TestContainer(
          key: testWidgetKey,
          screenSize: const Size(800, 400),
        ),
      );
      await tester.pumpAndSettle();

      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        _TestContainer(
          key: testWidgetKey,
          screenSize: const Size(400, 800),
        ),
      );
      await tester.pumpAndSettle();

      // Since user popped it in portrait, it should NOT auto-push again!
      expect(find.text('Detail Page: Item2'), findsNothing);
      expect(find.text('Item1'), findsOneWidget);
    },
  );
}
