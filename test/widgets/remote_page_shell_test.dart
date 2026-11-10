import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/remote_page_shell.dart';

/// 页面壳的行为约束。
///
/// 这套壳被远程专辑 / 艺术家 / 歌单 / 流派详情共用，任何一处行为变化都会同时
/// 影响四个页面，所以把「顶栏常显、多选面板条件渲染、返回拦截、滚动阈值」
/// 四条固定下来。
void main() {
  Widget wrap(Widget child) => ProviderScope(child: MaterialApp(home: child));

  Widget buildShell({
    Widget? selectionPanel,
    bool? popScopeCanPop,
    VoidCallback? onPopBlocked,
    bool enableFloatingCapsule = true,
  }) {
    return RemotePageShell(
      wrapWithMiniPlayer: false,
      selectionPanel: selectionPanel,
      popScopeCanPop: popScopeCanPop,
      onPopBlocked: onPopBlocked,
      enableFloatingCapsule: enableFloatingCapsule,
      contentBuilder: (context) => const Center(child: Text('content-body')),
      navBarBuilder: (context, isHeaderVisible, isPastTop) => SizedBox(
        height: 56,
        child: Row(
          children: [
            const Text('nav-bar'),
            Text('past=$isPastTop'),
            Text('visible=$isHeaderVisible'),
          ],
        ),
      ),
    );
  }

  testWidgets('内容与顶栏同时渲染，顶栏默认常显', (tester) async {
    await tester.pumpWidget(wrap(buildShell()));

    expect(find.text('content-body'), findsOneWidget);
    expect(find.text('nav-bar'), findsOneWidget);
    // `AutoHideHeaderScope(enabled: false)` + 未强制隐藏 → 恒可见。
    expect(find.text('visible=true'), findsOneWidget);
  });

  testWidgets('selectionPanel 为 null 时不渲染，给出时渲染', (tester) async {
    await tester.pumpWidget(wrap(buildShell()));
    expect(find.text('selection-panel'), findsNothing);

    await tester.pumpWidget(
      wrap(
        buildShell(
          selectionPanel: const Align(
            alignment: Alignment.bottomCenter,
            child: Text('selection-panel'),
          ),
        ),
      ),
    );
    expect(find.text('selection-panel'), findsOneWidget);
  });

  testWidgets('popScopeCanPop 为 null 时不插手返回；给出 false 时挂 PopScope', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(buildShell()));
    expect(find.byType(PopScope), findsNothing);

    await tester.pumpWidget(wrap(buildShell(popScopeCanPop: false)));
    await tester.pumpAndSettle();
    final blocking = find.byWidgetPredicate(
      (widget) => widget is PopScope && widget.canPop == false,
    );
    expect(blocking, findsOneWidget);
  });

  testWidgets('纵向滚动超过阈值后 isPastTop 翻真，回落顶部后复位', (tester) async {
    await tester.pumpWidget(
      wrap(
        RemotePageShell(
          wrapWithMiniPlayer: false,
          contentBuilder: (context) => ListView.builder(
            itemCount: 60,
            itemBuilder: (context, index) => SizedBox(
              height: 60,
              child: Text('row-$index'),
            ),
          ),
          navBarBuilder: (context, isHeaderVisible, isPastTop) =>
              Text('past=$isPastTop'),
        ),
      ),
    );
    expect(find.text('past=false'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('past=true'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 800));
    await tester.pumpAndSettle();
    expect(find.text('past=false'), findsOneWidget);
  });

  testWidgets('enableFloatingCapsule=false 时不监听滚动，isPastTop 恒假', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        RemotePageShell(
          wrapWithMiniPlayer: false,
          enableFloatingCapsule: false,
          contentBuilder: (context) => ListView.builder(
            itemCount: 60,
            itemBuilder: (context, index) => SizedBox(
              height: 60,
              child: Text('row-$index'),
            ),
          ),
          navBarBuilder: (context, isHeaderVisible, isPastTop) =>
              Text('past=$isPastTop'),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('past=false'), findsOneWidget);
  });
}
