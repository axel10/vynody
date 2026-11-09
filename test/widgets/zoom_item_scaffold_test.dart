import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';

void main() {
  testWidgets('ZoomItemScaffold aligns text to topLeft in grid mode by default',
      (tester) async {
    const cardWidth = 150.0;
    const gridTextHeight = 60.0;
    const cardHeight = cardWidth + gridTextHeight;

    final gridMetrics = FolderZoomLayoutMetrics(
      targetZoomScale: 1.0,
      animatedZoomScale: 1.0,
      gridMorph: 1.0,
      compactMorph: 0.0,
      animatedGridCols: 4.0,
      animatedGridTextHeight: gridTextHeight,
      animatedListExtent: 56.0,
      targetCardWidth: cardWidth,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: ZoomItemScaffold(
              metrics: gridMetrics,
              cover: Container(color: Colors.blue),
              titleText: 'Sample Album Title',
              subtitleText: 'Sample Artist',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 检查 title 文本的实际渲染位置
    final titleFinder = find.text('Sample Album Title');
    expect(titleFinder, findsOneWidget);

    final titleTop = tester.getTopLeft(titleFinder).dy;
    // 封面高度为 cardWidth = 150.0。
    // 在网格视图顶部对齐下，gridTextTop 为 coverSize + 8.0 = 158.0，
    // titleTop 应该在 158.0 附近。
    expect(titleTop, lessThan(162.0));
    expect(titleTop, greaterThanOrEqualTo(156.0));
  });

  testWidgets(
      'ZoomItemScaffold triggers onContextMenu only once on long press with correct position',
      (tester) async {
    final positions = <Offset>[];

    final gridMetrics = FolderZoomLayoutMetrics(
      targetZoomScale: 1.0,
      animatedZoomScale: 1.0,
      gridMorph: 1.0,
      compactMorph: 0.0,
      animatedGridCols: 4.0,
      animatedGridTextHeight: 60.0,
      animatedListExtent: 56.0,
      targetCardWidth: 150.0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150.0,
              height: 210.0,
              child: ZoomItemScaffold(
                metrics: gridMetrics,
                titleText: 'Server Item',
                onContextMenu: (position) {
                  positions.add(position);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final itemFinder = find.text('Server Item');
    expect(itemFinder, findsOneWidget);

    final itemCenter = tester.getCenter(itemFinder);

    await tester.longPress(itemFinder);
    await tester.pumpAndSettle();

    expect(positions.length, equals(1));
    expect(positions.first, isNot(equals(Offset.zero)));
    expect(positions.first, equals(itemCenter));
  });
}
