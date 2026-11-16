import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/remote_library_common_widgets.dart';
import 'package:vynody/widgets/app_top_nav_bar.dart';
import 'package:vynody/widgets/nav_capsule_island.dart';

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

    testWidgets(
      'renders back in NavCapsuleIsland on left and single action in NavActionsCapsule on right in landscape',
      (tester) async {
        // 默认测试窗口 800×600 即横屏，走浮动胶囊分支
        var refreshed = false;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AppTopNavBar(
                title: 'Album',
                parentTitle: 'Albums',
                actions: [
                  RemoteTopNavRefreshButton(
                    onRefresh: () {
                      refreshed = true;
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        final backFinder = find.byType(NavCapsuleIsland);
        final actionsFinder = find.byType(NavActionsCapsule);

        expect(backFinder, findsOneWidget);
        expect(actionsFinder, findsOneWidget);

        // 返回胶囊内不再包含 actions
        final backCapsule = tester.widget<NavCapsuleIsland>(backFinder);
        expect(backCapsule.actions, isNull);

        // 左右胶囊均为 44×44 正圆，且右侧动作胶囊位于返回胶囊右侧
        final backRect = tester.getRect(backFinder);
        final actionRect = tester.getRect(actionsFinder);
        expect(backRect.size, const Size(kNavCapsuleHeight, kNavCapsuleHeight));
        expect(
          actionRect.size,
          const Size(kNavCapsuleHeight, kNavCapsuleHeight),
        );
        expect(actionRect.left, greaterThan(backRect.right));

        await tester.tap(find.byType(RemoteTopNavRefreshButton));
        await tester.pump();
        expect(refreshed, isTrue);
      },
    );
  });
}
