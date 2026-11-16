import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/audio_riverpod.dart'
    show isBlurEffectEnabledProvider;
import 'package:vynody/utils/blur_constants.dart';
import 'package:vynody/widgets/frosted_header_bar.dart';

void main() {
  testWidgets('FrostedHeaderBar uses AppBackdropFilter when frosted is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FrostedHeaderBar(
            child: SizedBox(height: 50, child: Text('Header')),
          ),
        ),
      ),
    );

    expect(find.byType(AppBackdropFilter), findsOneWidget);
    expect(find.text('Header'), findsOneWidget);
  });

  testWidgets('FrostedHeaderBar skips AppBackdropFilter when backgroundColor is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FrostedHeaderBar(
            backgroundColor: Colors.transparent,
            hasBorder: false,
            child: SizedBox(height: 50, child: Text('Transparent Header')),
          ),
        ),
      ),
    );

    expect(find.byType(AppBackdropFilter), findsNothing);
    expect(find.text('Transparent Header'), findsOneWidget);
  });

  testWidgets('FrostedOverlayHeaderStack measures header height and passes topPadding', (
    tester,
  ) async {
    double? reportedBodyHeight;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FrostedOverlayHeaderStack(
            topPadding: 24.0,
            header: const FrostedHeaderBar(
              child: SizedBox(height: 64.0, child: Text('Top')),
            ),
            bodyBuilder: (context, headerHeight) {
              reportedBodyHeight = headerHeight;
              return Padding(
                padding: EdgeInsets.only(top: headerHeight),
                child: const Text('Body'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 24.0 (topPadding) + 64.0 (child) + 0.8 (border) = 88.8
    expect(reportedBodyHeight, greaterThanOrEqualTo(88.0));
    final bodyTop = tester.getTopLeft(find.text('Body')).dy;
    final headerBottom =
        tester.getBottomLeft(find.byType(FrostedHeaderBar)).dy;
    expect(bodyTop, closeTo(headerBottom, 0.5));
  });

  testWidgets('FrostedHeaderBar uses non-blur alpha when blur is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBlurEffectEnabledProvider.overrideWith((ref) => false),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FrostedHeaderBar(
              child: SizedBox(height: 50, child: Text('No Blur Header')),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(FrostedHeaderBar),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color?.a, closeTo(AppBlur.heavyAlpha(false, isBlurEnabled: false), 0.01));
  });
}
