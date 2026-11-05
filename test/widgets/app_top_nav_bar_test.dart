import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';

void main() {
  group('AppTopNavBar', () {
    /// 默认测试窗口是 800×600（横屏），而横屏下 [AppTopNavBar] 走浮动胶囊分支：
    /// 只渲染胶囊的父级标题，`title` 完全不参与布局。标题相关的用例必须先声明竖屏。
    void usePortraitSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('triggers onTitleTap when title is tapped', (tester) async {
      usePortraitSurface(tester);
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTopNavBar(
              title: 'Albums',
              onTitleTap: () {
                tapped = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Albums'), findsOneWidget);
      await tester.tap(find.text('Albums'));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('renders normally without onTitleTap', (tester) async {
      usePortraitSurface(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppTopNavBar(
              title: 'Artists',
            ),
          ),
        ),
      );

      expect(find.text('Artists'), findsOneWidget);
    });
  });
}
