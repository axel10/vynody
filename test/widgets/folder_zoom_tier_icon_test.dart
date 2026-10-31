import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';

void main() {
  group('ZoomTierIcon tests', () {
    testWidgets('renders all 7 discrete zoom tiers without error', (tester) async {
      for (final tier in FolderZoomTier.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ZoomTierIcon(
                  tier: tier,
                  size: 24,
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        );
        expect(find.byType(ZoomTierIcon), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);
      }
    });

    testWidgets('supports continuous zoomScale snapping', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ZoomTierIcon(
                zoomScale: 0.16, // snaps to compactList
                size: 20,
              ),
            ),
          ),
        ),
      );
      final widget = tester.widget<ZoomTierIcon>(find.byType(ZoomTierIcon));
      expect(widget.effectiveTier, equals(FolderZoomTier.compactList));
    });

    testWidgets('supports shadows parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ZoomTierIcon(
                tier: FolderZoomTier.standardList,
                size: 20,
                shadows: [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ZoomTierIcon), findsOneWidget);
    });
  });
}
