import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/app_tooltip.dart';

void main() {
  testWidgets('AppTooltip wraps child in Semantics by default', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppTooltip(
            message: 'Hello Tooltip',
            child: Text('Target'),
          ),
        ),
      ),
    );

    // Verify target text is rendered
    expect(find.text('Target'), findsOneWidget);

    // Verify semantics contain the tooltip message
    final SemanticsNode node = tester.getSemantics(find.text('Target'));
    final SemanticsData semantics = node.getSemanticsData();
    expect(semantics.tooltip, 'Hello Tooltip');
  });

  testWidgets('AppTooltip does not add semantics if excludeFromSemantics is true', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppTooltip(
            message: 'Hello Tooltip',
            excludeFromSemantics: true,
            child: Text('Target'),
          ),
        ),
      ),
    );

    expect(find.text('Target'), findsOneWidget);

    final SemanticsNode node = tester.getSemantics(find.text('Target'));
    final SemanticsData semantics = node.getSemanticsData();
    expect(semantics.tooltip, isEmpty);
  });

  testWidgets('AppTooltip shows overlay on long press', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppTooltip(
            message: 'Show Me',
            child: Text('Target'),
          ),
        ),
      ),
    );

    // Tooltip overlay should not be visible yet
    expect(find.text('Show Me'), findsNothing);

    // Long press target
    await tester.longPress(find.text('Target'));
    await tester.pump(); // Start animation
    await tester.pump(const Duration(milliseconds: 150)); // Complete fade-in animation

    // Verify tooltip is shown in overlay
    expect(find.text('Show Me'), findsOneWidget);
  });
}
