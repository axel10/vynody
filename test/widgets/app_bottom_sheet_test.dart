import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/app_bottom_sheet.dart';

void main() {
  group('AppDragHandle', () {
    testWidgets('renders drag handle bar and responds to tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDragHandle(
              onTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      final handleFinder = find.byType(AppDragHandle);
      expect(handleFinder, findsOneWidget);

      await tester.tap(handleFinder);
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('AppBottomSheet', () {
    testWidgets('adapts width correctly in portrait and landscape orientations', (tester) async {
      // 1. Portrait mode (width = 400, height = 800)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppBottomSheet(
              maxWidth: 360,
              landscapeMaxWidth: 900,
              child: const Text('Sheet Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sheet Content'), findsOneWidget);
      expect(find.byType(AppDragHandle), findsOneWidget);

      // Verify portrait width is constrained by maxWidth
      final portraitBoxFinder = find.descendant(
        of: find.byType(AppBottomSheet),
        matching: find.byType(ConstrainedBox),
      );
      final portraitBox = tester.widget<ConstrainedBox>(portraitBoxFinder.first);
      expect(portraitBox.constraints.maxWidth, equals(360));

      // 2. Landscape mode (width = 1200, height = 700)
      tester.view.physicalSize = const Size(1200, 700);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppBottomSheet(
              maxWidth: 720,
              landscapeMaxWidth: 1040,
              child: const Text('Sheet Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final landscapeBoxFinder = find.descendant(
        of: find.byType(AppBottomSheet),
        matching: find.byType(ConstrainedBox),
      );
      final landscapeBox = tester.widget<ConstrainedBox>(landscapeBoxFinder.first);
      // Landscape maximum width should be enlarged to landscapeMaxWidth
      expect(landscapeBox.constraints.maxWidth, equals(1040));
    });
  });
}
