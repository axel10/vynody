import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/library_zoom_popover.dart';

void main() {
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  tearDown(() {
    // 兜底：正常路径由测试体内的 finally 复位，这里防止断言失败后残留。
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> pumpCard(
    WidgetTester tester,
    TargetPlatform platform, {
    LibraryZoomScope scope = LibraryZoomScope.song,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: LibraryZoomPopoverCard(scope: scope),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('档位提示的修饰键跟随平台：macOS 用 ⌘，其余用 Ctrl', (tester) async {
    // flutter_test 会在测试体结束时就校验 foundation 的调试变量已复位，
    // 必须在体内 finally 清掉，放到 tearDown 已经太晚。
    try {
      // macOS 上 ⌘ 与 Ctrl 在判定里都认，但提示只写更顺手的 ⌘。
      await pumpCard(tester, TargetPlatform.macOS);
      expect(find.textContaining('⌘'), findsOneWidget);
      expect(find.textContaining('Ctrl'), findsNothing);

      await pumpCard(tester, TargetPlatform.windows);
      expect(find.textContaining('Ctrl'), findsOneWidget);
      expect(find.textContaining('⌘'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('仅目录页弹窗展示混合视图复选框', (tester) async {
    try {
      await pumpCard(
        tester,
        TargetPlatform.macOS,
        scope: LibraryZoomScope.song,
      );
      expect(find.text('混合视图'), findsNothing);

      await pumpCard(
        tester,
        TargetPlatform.macOS,
        scope: LibraryZoomScope.folder,
      );
      expect(find.text('混合视图'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('勾选混合视图后文件夹固定大网格、歌曲固定标准列表，且禁用档位调节', (tester) async {
    try {
      settings.folderZoomScale = kFolderZoomTierCompactList;
      await pumpCard(
        tester,
        TargetPlatform.macOS,
        scope: LibraryZoomScope.folder,
      );

      expect(settings.folderHybridView, isFalse);
      expect(find.textContaining('滚轮'), findsOneWidget);

      await tester.tap(find.text('混合视图'));
      await tester.pumpAndSettle();

      expect(settings.folderHybridView, isTrue);
      expect(settings.effectiveFolderItemZoomScale, kFolderZoomTierLargeGrid);
      expect(settings.effectiveFolderSongZoomScale, kFolderZoomTierStandardList);

      // 滑杆与快捷键提示在混合视图下均已禁用/隐藏
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
      expect(find.textContaining('滚轮'), findsNothing);

      // 取消勾选恢复原档位
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(settings.folderHybridView, isFalse);
      expect(
        settings.effectiveFolderItemZoomScale,
        kFolderZoomTierCompactList,
      );
      expect(
        settings.effectiveFolderSongZoomScale,
        kFolderZoomTierCompactList,
      );
      expect(
        tester.widget<Slider>(find.byType(Slider)).onChanged,
        isNotNull,
      );
      expect(find.textContaining('滚轮'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('外层为大网格时，AdaptiveFolderZoomSectionHost 仍按子段档位切到列表', (
    tester,
  ) async {
    double? folderTarget;
    bool? folderIsGrid;
    double? songTarget;
    bool? songIsGrid;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: FolderZoomSliverBuilder(
              zoomScale: kFolderZoomTierLargeGrid,
              width: 800,
              builder: (context, metrics) {
                return CustomScrollView(
                  slivers: [
                    AdaptiveFolderZoomSectionHost(
                      zoomScale: kFolderZoomTierLargeGrid,
                      width: 800,
                      builder: (context, m) {
                        folderTarget = m.targetZoomScale;
                        folderIsGrid = m.isGridTarget;
                        return const SliverToBoxAdapter(
                          child: SizedBox(height: 40),
                        );
                      },
                    ),
                    AdaptiveFolderZoomSectionHost(
                      zoomScale: kFolderZoomTierLargeList,
                      width: 800,
                      builder: (context, m) {
                        songTarget = m.targetZoomScale;
                        songIsGrid = m.isGridTarget;
                        return const SliverToBoxAdapter(
                          child: SizedBox(height: 40),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(folderTarget, kFolderZoomTierLargeGrid);
    expect(folderIsGrid, isTrue);
    expect(songTarget, kFolderZoomTierLargeList);
    expect(songIsGrid, isFalse);
  });

  testWidgets('开启混合视图后展示设置按钮，点击弹出设置弹窗可分别配置目录与歌曲视图', (
    tester,
  ) async {
    try {
      await pumpCard(
        tester,
        TargetPlatform.macOS,
        scope: LibraryZoomScope.folder,
      );

      // 未开启混合视图时不展示设置按钮
      expect(find.byIcon(Icons.settings_outlined), findsNothing);

      // 开启混合视图后展示设置按钮
      await tester.tap(find.text('混合视图'));
      await tester.pumpAndSettle();
      expect(settings.folderHybridView, isTrue);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

      // 点击设置按钮弹出混合视图设置弹窗，且不会误触关闭混合视图
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      expect(settings.folderHybridView, isTrue);
      expect(find.text('混合视图设置'), findsOneWidget);
      expect(find.text('目录条目视图'), findsOneWidget);
      expect(find.text('歌曲条目视图'), findsOneWidget);

      // 目录条目视图切换为「列表视图 · 紧凑」，歌曲条目视图切换为「网格视图 · 中」
      final folderCompactTooltip = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byTooltip('列表视图 · 紧凑'),
      );
      final songMediumGridTooltip = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byTooltip('网格视图 · 中'),
      );
      await tester.tap(folderCompactTooltip.first);
      await tester.pumpAndSettle();
      await tester.tap(songMediumGridTooltip.last);
      await tester.pumpAndSettle();

      expect(
        settings.folderHybridItemZoomScale,
        kFolderZoomTierCompactList,
      );
      expect(
        settings.effectiveFolderItemZoomScale,
        kFolderZoomTierCompactList,
      );
      expect(
        settings.folderHybridSongZoomScale,
        kFolderZoomTierMediumGrid,
      );
      expect(
        settings.effectiveFolderSongZoomScale,
        kFolderZoomTierMediumGrid,
      );

      // 点击重置恢复默认值
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      expect(settings.folderHybridItemZoomScale, kFolderZoomTierLargeGrid);
      expect(settings.folderHybridSongZoomScale, kFolderZoomTierStandardList);

      // 点击完成关闭弹窗
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('混合视图设置'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('锚点位于视口上方或底部之外时，视图面板仍钳制在可视范围内', (tester) async {
    Future<void> pumpAndTriggerAt(Offset anchorOffset) async {
      late BuildContext anchorCtx;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: anchorOffset.dx,
                    top: anchorOffset.dy,
                    child: Builder(
                      builder: (ctx) {
                        anchorCtx = ctx;
                        return const SizedBox(width: 32, height: 32);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // ignore: unawaited_futures
      showLibraryZoomPopover(anchorCtx, scope: LibraryZoomScope.folder);
      await tester.pumpAndSettle();
    }

    // 1. 锚点已滚出顶部视口上方（dy = -120）
    await pumpAndTriggerAt(const Offset(350, -120));
    var cardRect = tester.getRect(find.byType(LibraryZoomPopoverCard));
    expect(cardRect.top, greaterThanOrEqualTo(8.0));
    expect(cardRect.bottom, lessThanOrEqualTo(600.0));

    // 关闭弹窗
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2. 锚点高度过大或位于视口底部之外（dy = 590）
    await pumpAndTriggerAt(const Offset(350, 590));
    cardRect = tester.getRect(find.byType(LibraryZoomPopoverCard));
    expect(cardRect.top, greaterThanOrEqualTo(8.0));
    expect(cardRect.bottom, lessThanOrEqualTo(600.0));
  });
}
