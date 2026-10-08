import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/scroll_to_top_wrapper.dart';

void main() {
  group('ScrollToTopWrapper', () {
    testWidgets('uses neutral colors on Android', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final scrollController = ScrollController();
        final themeData = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: themeData,
            home: Scaffold(
              body: ScrollToTopWrapper(
                scrollController: scrollController,
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 50,
                  itemBuilder: (context, index) => SizedBox(
                    height: 50,
                    child: Text('Item $index'),
                  ),
                ),
              ),
            ),
          ),
        );

        final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton),
        );

        expect(
          fab.backgroundColor,
          equals(themeData.colorScheme.surfaceContainerHighest),
        );
        expect(
          fab.foregroundColor,
          equals(themeData.colorScheme.onSurface),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('uses neutral colors on iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final scrollController = ScrollController();
        final themeData = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: themeData,
            home: Scaffold(
              body: ScrollToTopWrapper(
                scrollController: scrollController,
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 50,
                  itemBuilder: (context, index) => SizedBox(
                    height: 50,
                    child: Text('Item $index'),
                  ),
                ),
              ),
            ),
          ),
        );

        final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton),
        );

        expect(
          fab.backgroundColor,
          equals(themeData.colorScheme.surfaceContainerHighest),
        );
        expect(
          fab.foregroundColor,
          equals(themeData.colorScheme.onSurface),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('uses default FAB colors on macOS/desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final scrollController = ScrollController();
        final themeData = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: themeData,
            home: Scaffold(
              body: ScrollToTopWrapper(
                scrollController: scrollController,
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 50,
                  itemBuilder: (context, index) => SizedBox(
                    height: 50,
                    child: Text('Item $index'),
                  ),
                ),
              ),
            ),
          ),
        );

        final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton),
        );

        expect(fab.backgroundColor, isNull);
        expect(fab.foregroundColor, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
