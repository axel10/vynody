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

    // 媒体库每个子分类各有一条 Navigator，三级详情页压在这条 Navigator 里，
    // 所以「详情页的 AutoHideHeaderScope」是「宿主 AutoHideHeaderScope」的后代。
    // 若外层不区分通知归属，详情页下滑会让宿主顶栏跟着收起，返回后根页面就是塌的。
    testWidgets('Nested scope consumes its own scroll, outer header unaffected', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final outerController = ScrollController();
      addTearDown(outerController.dispose);
      try {
        Offset headerOffset(String label) => tester
            .widget<AnimatedSlide>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedSlide),
              ).first,
            )
            .offset;

        Widget list(String key) => ListView.builder(
              key: ValueKey(key),
              itemCount: 100,
              itemBuilder: (context, index) => SizedBox(
                height: 50,
                child: Text('$key $index'),
              ),
            );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AutoHideHeaderScope(
                builder: (context, outerVisible) => Stack(
                  children: [
                    ListView.builder(
                      controller: outerController,
                      itemCount: 100,
                      itemBuilder: (context, index) => SizedBox(
                        height: 50,
                        child: Text('outer $index'),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 40,
                      child: AutoHideHeader(
                        isVisible: outerVisible,
                        child: const SizedBox.expand(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text('Outer Header'),
                          ),
                        ),
                      ),
                    ),
                    // 模拟压在 Navigator 里的三级详情页
                    Positioned.fill(
                      child: AutoHideHeaderScope(
                        builder: (context, innerVisible) => Stack(
                          children: [
                            list('inner'),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 40,
                              child: AutoHideHeader(
                                isVisible: innerVisible,
                                child: const SizedBox.expand(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: Text('Inner Header'),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(headerOffset('Outer Header'), Offset.zero);
        expect(headerOffset('Inner Header'), Offset.zero);

        // 滑内层：只有内层顶栏收起，外层必须纹丝不动
        await tester.drag(find.byKey(const ValueKey('inner')), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(headerOffset('Inner Header'), const Offset(0, -1.0));
        expect(
          headerOffset('Outer Header'),
          Offset.zero,
          reason: '内层滚动通知不得穿透到外层 scope',
        );

        // 外层自己的滚动仍然要生效
        outerController.jumpTo(300);
        await tester.pumpAndSettle();
        expect(headerOffset('Outer Header'), const Offset(0, -1.0));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Horizontal scrolling does not hide header on mobile', (tester) async {      debugDefaultTargetPlatformOverride = TargetPlatform.android;
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

    testWidgets('Header does not toggle on minor scroll jitter below threshold', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final scrollController = ScrollController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AutoHideHeaderScope(
                enabled: true,
                hideThreshold: 24.0,
                showThreshold: 36.0,
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

        // Minor scroll down (drag up by 10px, less than hideThreshold 24px)
        await tester.drag(find.byType(ListView), const Offset(0, -10));
        await tester.pumpAndSettle();
        // Should remain visible
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, Offset.zero);

        // Now scroll down enough to hide (drag up by 150px)
        await tester.drag(find.byType(ListView), const Offset(0, -150));
        await tester.pumpAndSettle();
        // Header should hide
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, const Offset(0, -1.0));

        // Minor scroll up (drag down by 10px, less than showThreshold 36px)
        await tester.drag(find.byType(ListView), const Offset(0, 10));
        await tester.pumpAndSettle();
        // Should STILL be hidden!
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, const Offset(0, -1.0));

        // Significant scroll up (drag down by 60px, exceeds showThreshold 36px)
        await tester.drag(find.byType(ListView), const Offset(0, 60));
        await tester.pumpAndSettle();
        // Should reveal
        expect(tester.widget<AnimatedSlide>(animatedSlideFinder).offset, Offset.zero);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
