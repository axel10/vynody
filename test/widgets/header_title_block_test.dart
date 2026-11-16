import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/header_title_block.dart';
import 'package:vynody/widgets/library_large_title.dart';

void main() {
  testWidgets('HeaderTitleBlock places subtitle below title with queue style', (
    tester,
  ) async {
    final theme = ThemeData.light();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: HeaderTitleBlock(
            title: '播放队列',
            subtitle: '12 首歌曲 · 45 分钟',
          ),
        ),
      ),
    );

    final titleFinder = find.text('播放队列');
    final subtitleFinder = find.text('12 首歌曲 · 45 分钟');
    expect(titleFinder, findsOneWidget);
    expect(subtitleFinder, findsOneWidget);

    final titleRect = tester.getRect(titleFinder);
    final subtitleRect = tester.getRect(subtitleFinder);

    expect(subtitleRect.top, greaterThanOrEqualTo(titleRect.bottom));
    expect(subtitleRect.left, closeTo(titleRect.left, 0.1));

    final resolvedTheme = Theme.of(tester.element(subtitleFinder));
    final subtitleText = tester.widget<Text>(subtitleFinder);
    expect(
      subtitleText.style?.color,
      resolvedTheme.colorScheme.onSurfaceVariant,
    );
    expect(
      subtitleText.style?.fontSize,
      resolvedTheme.textTheme.bodyMedium?.fontSize,
    );
  });

  testWidgets('HeaderTitleBlock prefers subtitleWidget when provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HeaderTitleBlock(
            title: '播放队列',
            subtitle: 'ignored',
            subtitleWidget: Text('custom-subtitle'),
          ),
        ),
      ),
    );

    expect(find.text('custom-subtitle'), findsOneWidget);
    expect(find.text('ignored'), findsNothing);
  });

  testWidgets('LibraryLargeTitle places countLabel below title', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LibraryLargeTitle(
            title: '专辑',
            countLabel: '128 张专辑',
            showBackButton: false,
          ),
        ),
      ),
    );

    final titleRect = tester.getRect(find.text('专辑'));
    final countRect = tester.getRect(find.text('128 张专辑'));

    expect(countRect.top, greaterThanOrEqualTo(titleRect.bottom));
    expect(countRect.left, closeTo(titleRect.left, 0.1));
  });
}
