import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/app_tooltip.dart';

void main() {
  testWidgets('Playback collapse button renders 44x44 circular button with tooltip and handles tap', (tester) async {
    bool collapsed = false;

    Widget buildTestButton() {
      return AppTooltip(
        message: '收起播放页',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 0.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => collapsed = true,
                child: const Center(
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: buildTestButton(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(ClipRRect));
    expect(size.width, 44.0);
    expect(size.height, 44.0);

    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    expect(collapsed, isTrue);
  });
}
