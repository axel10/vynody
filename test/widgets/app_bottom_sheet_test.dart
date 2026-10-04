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

  group('AppAdaptiveSheet', () {
    testWidgets('adapts to Bottom Sheet on portrait screens', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAdaptiveSheet(
              sheetMaxWidth: 380,
              dialogMaxWidth: 600,
              child: const Text('Adaptive Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Adaptive Content'), findsOneWidget);
      // In portrait/sheet mode, drag handle is displayed
      expect(find.byType(AppDragHandle), findsOneWidget);

      final alignFinder = find.descendant(
        of: find.byType(AppAdaptiveSheet),
        matching: find.byType(Align),
      );
      final alignWidget = tester.widget<Align>(alignFinder.first);
      expect(alignWidget.alignment, equals(Alignment.bottomCenter));
    });

    testWidgets('adapts to Dialog on wide / desktop screens', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAdaptiveSheet(
              sheetMaxWidth: 380,
              dialogMaxWidth: 680,
              child: const Text('Adaptive Content'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Adaptive Content'), findsOneWidget);
      // In wide screen Dialog mode, drag handle is hidden
      expect(find.byType(AppDragHandle), findsNothing);

      final alignFinder = find.descendant(
        of: find.byType(AppAdaptiveSheet),
        matching: find.byType(Align),
      );
      final alignWidget = tester.widget<Align>(alignFinder.first);
      expect(alignWidget.alignment, equals(Alignment.center));

      // Container width should be constrained by dialogMaxWidth
      final boxFinder = find.descendant(
        of: find.byType(AppAdaptiveSheet),
        matching: find.byType(ConstrainedBox),
      );
      final box = tester.widget<ConstrainedBox>(boxFinder.first);
      expect(box.constraints.maxWidth, equals(680));
    });

    testWidgets('respects explicit asDialog override', (tester) async {
      // 1. Force Dialog on portrait screen
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAdaptiveSheet(
              asDialog: true,
              child: const Text('Forced Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDragHandle), findsNothing);

      // 2. Force Bottom Sheet on wide screen
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppAdaptiveSheet(
              asDialog: false,
              child: const Text('Forced Sheet'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppDragHandle), findsOneWidget);
    });
  });

  group('showAppAdaptiveModal', () {
    testWidgets('presents showDialog on wide screens', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppAdaptiveModal(
                    context: context,
                    builder: (modalCtx) => const AppAdaptiveSheet(
                      child: Text('Modal Dialog Content'),
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Modal Dialog Content'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing); // Dialog route uses RawDialogRoute
      expect(find.byType(AppDragHandle), findsNothing);
      expect(find.byType(ModalBarrier), findsWidgets);
    });

    testWidgets('presents showModalBottomSheet on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppAdaptiveModal(
                    context: context,
                    builder: (modalCtx) => const AppAdaptiveSheet(
                      child: Text('Modal Sheet Content'),
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Modal Sheet Content'), findsOneWidget);
      expect(find.byType(AppDragHandle), findsOneWidget);
    });

    testWidgets('dynamically morphs between BottomSheet and Dialog upon window resize / orientation change without reopening', (tester) async {
      // 1. Start in portrait (400 x 800)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppAdaptiveModal(
                    context: context,
                    builder: (modalCtx) => const AppAdaptiveSheet(
                      child: Text('Live Morph Content'),
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Portrait: drag handle is displayed
      expect(find.text('Live Morph Content'), findsOneWidget);
      expect(find.byType(AppDragHandle), findsOneWidget);

      // 2. Rotate to landscape / widen window (1200 x 800) WITHOUT closing the modal
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();

      // Dynamically morphed to Dialog: drag handle disappeared
      expect(find.text('Live Morph Content'), findsOneWidget);
      expect(find.byType(AppDragHandle), findsNothing);

      // 3. Rotate back to portrait (400 x 800)
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpAndSettle();

      // Dynamically morphed back to BottomSheet: drag handle reappeared!
      expect(find.text('Live Morph Content'), findsOneWidget);
      expect(find.byType(AppDragHandle), findsOneWidget);
    });

    testWidgets('dragging handle downwards translates sheet and dismissing pops route', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAppAdaptiveModal(
                    context: context,
                    builder: (modalCtx) => const AppAdaptiveSheet(
                      child: Text('Draggable Modal Sheet'),
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      expect(find.text('Draggable Modal Sheet'), findsOneWidget);
      final handleFinder = find.byType(AppDragHandle);
      expect(handleFinder, findsOneWidget);

      // 1. Drag down slightly (30px) - should not dismiss the sheet
      await tester.drag(handleFinder, const Offset(0, 30));
      await tester.pumpAndSettle();
      expect(find.text('Draggable Modal Sheet'), findsOneWidget);

      // 2. Drag down significantly (> 80px) - should dismiss the sheet
      await tester.drag(handleFinder, const Offset(0, 120));
      await tester.pumpAndSettle();

      expect(find.text('Draggable Modal Sheet'), findsNothing);
    });
  });
}
