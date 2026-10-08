import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/auto_hide_header.dart';

void main() {
  group('AutoHideHeaderScope and AutoHideHeader tests', () {
    testWidgets('Header hides on scroll down and shows on scroll up on mobile', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AutoHideHeaderScope(
                enabled: true,
                builder: (context, isVisible) {
                  return Stack(
                    children: [
                      ListView.builder(
                        controller: scrollController,
                        itemCount: 100,
                        itemBuilder: (context, index) => SizedBox(
                          height: 50,
                          child: Text('Item $index'),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 50,
                        child: AutoHideHeader(
                          isVisible: isVisible,
                          child: const ColoredBox(
                            color: Colors.blue,
                            child: Text('Top Header'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        expect(find.text('Top Header'), findsOneWidget);

        final animatedSlideFinder = find.byType(AnimatedSlide);
        expect(animatedSlideFinder, findsOneWidget);
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, Offset.zero);

        // Scroll down (drag upwards by 200px)
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        // Header should slide out of view
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, const Offset(0, -1.0));

        // Scroll back up (drag downwards by 100px)
        await tester.drag(find.byType(ListView), const Offset(0, 100));
        await tester.pumpAndSettle();

        // Header should slide back in
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, Offset.zero);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Desktop platforms keep header permanently visible regardless of scroll', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AutoHideHeaderScope(
                enabled: true,
                builder: (context, isVisible) {
                  return Stack(
                    children: [
                      ListView.builder(
                        itemCount: 100,
                        itemBuilder: (context, index) => SizedBox(
                          height: 50,
                          child: Text('Item $index'),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 50,
                        child: AutoHideHeader(
                          isVisible: isVisible,
                          child: const Text('Top Header'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        final animatedSlideFinder = find.byType(AnimatedSlide);
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, Offset.zero);

        // Scroll down
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();

        // On desktop, header must stay visible at Offset.zero
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, Offset.zero);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Header stays visible when forceVisible is true on mobile', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AutoHideHeaderScope(
                enabled: true,
                forceVisible: true,
                builder: (context, isVisible) {
                  return Stack(
                    children: [
                      ListView.builder(
                        itemCount: 100,
                        itemBuilder: (context, index) => SizedBox(
                          height: 50,
                          child: Text('Item $index'),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 50,
                        child: AutoHideHeader(
                          isVisible: isVisible,
                          child: const Text('Top Header'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // Scroll down
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        final animatedSlide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
        expect(animatedSlide.offset, Offset.zero);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Horizontal scrolling does not hide header on mobile', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AutoHideHeaderScope(
                enabled: true,
                builder: (context, isVisible) {
                  return Stack(
                    children: [
                      ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: 100,
                        itemBuilder: (context, index) => SizedBox(
                          width: 100,
                          child: Text('Horizontal $index'),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 50,
                        child: AutoHideHeader(
                          isVisible: isVisible,
                          child: const Text('Top Header'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // Drag horizontally
        await tester.drag(find.byType(ListView), const Offset(-200, 0));
        await tester.pumpAndSettle();

        final animatedSlide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
        expect(animatedSlide.offset, Offset.zero);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
