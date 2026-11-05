import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';

/// 条目几何回归：档位切换时，**两个档位都可见**的条目必须在两个确定布局之间
/// 直线平移；只在单侧可见的条目则由 `FolderZoomItemPinning` 锁死在屏上，靠
/// 透明度 / 缩放原地淡入淡出（见各自用例）。
///
/// 曾经的实现是拿插值出来的小数 `animatedGridCols` 直接推格子的，列数每跨过
/// 一个整数（列表 6 列 → 小网格 8 列）条目的格子归属就换一格，位置目标在动画
/// 中途跳走，轨迹先往一边滑 250px 再折返——观感就是「绕了个圈」。

const double _kWidth = 1200.0;
const double _kHeight = 800.0;

SliverConstraints _constraints() => SliverConstraints(
      axisDirection: AxisDirection.down,
      growthDirection: GrowthDirection.forward,
      userScrollDirection: ScrollDirection.idle,
      scrollOffset: 0.0,
      precedingScrollExtent: 0.0,
      overlap: 0.0,
      remainingPaintExtent: _kHeight,
      crossAxisExtent: _kWidth,
      crossAxisDirection: AxisDirection.right,
      viewportMainAxisExtent: _kHeight,
      remainingCacheExtent: _kHeight,
      cacheOrigin: 0.0,
    );

/// 采样某个条目在当前布局下的中心坐标。
///
/// 网格委托在布局时会读 `SchedulerBinding.currentFrameTimeStamp` 给段打帧号，
/// 而这个 getter 只在帧内有效（帧结束后会被置空，见 scheduler/binding.dart 的
/// `handleDrawFrame`）。所以采样必须挂到一次真实帧的回调里执行 —— 直接在测试体里
/// 调 `getLayout` 会命中 `'_currentFrameTimeStamp != null'` 断言。
///
/// 补的这一帧时长为 0：动画进度不变，采样点仍是上一帧 pump 出来的那份布局。
Future<Offset> _centerOf(
  WidgetTester tester,
  FolderZoomLayoutMetrics metrics,
  int index,
) async {
  Offset? center;
  tester.binding.scheduleFrameCallback((_) {
    final layout = SliverAnimatedZoomGridDelegate(metrics: metrics)
        .getLayout(_constraints());
    final geometry = layout.getGeometryForChildIndex(index);
    center = Offset(
      geometry.crossAxisOffset + geometry.crossAxisExtent / 2,
      geometry.scrollOffset + geometry.mainAxisExtent / 2,
    );
  });
  await tester.pump();
  return center!;
}

/// 带真实条目数的网格宿主。
///
/// 单侧可见条目的判定（`FolderZoomViewportTracker.buildPinning`）需要知道条目总数，
/// 而 [SliverToBoxAdapter] 的 `childCount` 为 0，冻结表会直接返回 `null`，
/// 于是所有条目都走加权位移 —— 用 [_host] 根本测不到 pin 分支。
Widget _gridHost({
  required double zoomScale,
  required void Function(FolderZoomLayoutMetrics) onMetrics,
  int itemCount = 40,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          FolderZoomSliverBuilder(
            zoomScale: zoomScale,
            width: _kWidth,
            builder: (context, metrics) {
              onMetrics(metrics);
              return SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) =>
                      SizedBox.expand(key: ValueKey('grid_item_$index')),
                  childCount: itemCount,
                ),
                gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
              );
            },
          ),
        ],
      ),
    ),
  );
}

Widget _host({
  required double zoomScale,
  required void Function(FolderZoomLayoutMetrics) onMetrics,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          FolderZoomSliverBuilder(
            zoomScale: zoomScale,
            width: _kWidth,
            builder: (context, metrics) {
              onMetrics(metrics);
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            },
          ),
        ],
      ),
    ),
  );
}

void main() {
  setUp(() {});

  Future<void> useLandscapeSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(_kWidth, _kHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 直线轨迹的核心断言：偏离起点—终点连线的最大距离、以及横向是否折返。
  void expectStraightPath(
    int index,
    Offset start,
    List<Offset> path,
  ) {
    expect(
      (path.first - start).distance,
      lessThan(0.5),
      reason: 'item $index 起跳位置必须接住上一帧',
    );

    final chord = path.last - path.first;
    if (chord.distance > 0.5) {
      for (final point in path) {
        final delta = point - path.first;
        final deviation =
            (delta.dx * chord.dy - delta.dy * chord.dx).abs() / chord.distance;
        expect(
          deviation,
          lessThan(1.0),
          reason: 'item $index 偏离直线 ${deviation.toStringAsFixed(1)}px',
        );
      }
    }

    final direction = (path.last.dx - path.first.dx).sign;
    for (var i = 1; i < path.length; i++) {
      final step = (path[i].dx - path[i - 1].dx) * direction;
      expect(
        step,
        greaterThan(-0.5),
        reason: 'item $index 在第 $i 帧横向折返，位移 ${step.toStringAsFixed(1)}px',
      );
    }
  }

  /// 从 [from] 切到 [to]，逐帧采样若干条目的中心位置。
  Future<
      ({
        Map<int, Offset> starts,
        Map<int, List<Offset>> paths,
        FolderZoomLayoutMetrics metrics,
      })> sampleTransition(
    WidgetTester tester, {
    required double from,
    required double to,
    List<int> indices = const [0, 3, 7],
  }) async {
    FolderZoomLayoutMetrics? latest;
    void capture(FolderZoomLayoutMetrics value) => latest = value;

    await tester.pumpWidget(_host(zoomScale: from, onMetrics: capture));
    await tester.pumpAndSettle();

    final starts = <int, Offset>{
      for (final index in indices)
        index: await _centerOf(tester, latest!, index),
    };

    await tester.pumpWidget(_host(zoomScale: to, onMetrics: capture));

    final paths = <int, List<Offset>>{
      for (final index in indices) index: <Offset>[],
    };
    // pumpWidget 这一帧就是动画的第 0 帧（进度 0），必须和起跳位置完全重合。
    for (final index in indices) {
      paths[index]!.add(await _centerOf(tester, latest!, index));
    }
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 14));
      for (final index in indices) {
        paths[index]!.add(await _centerOf(tester, latest!, index));
      }
    }
    await tester.pumpAndSettle();
    for (final index in indices) {
      paths[index]!.add(await _centerOf(tester, latest!, index));
    }
    return (starts: starts, paths: paths, metrics: latest!);
  }

  testWidgets('横屏 列表 → 小网格：每个条目沿直线平移，不中途折返', (tester) async {
    await useLandscapeSurface(tester);

    final sample = await sampleTransition(
      tester,
      from: kFolderZoomTierLargeList,
      to: kFolderZoomTierSmallGrid,
    );
    for (final index in sample.paths.keys) {
      expectStraightPath(index, sample.starts[index]!, sample.paths[index]!);
    }

    // 收尾必须精确落在小网格的稳态布局上。
    expect(sample.metrics.resolvedGeometryLayers.length, 1);
    final settled = sample.metrics.resolvedGeometryLayers.single;
    expect(settled.isGrid, isTrue);
    expect(settled.crossAxisCount, 8);
  });

  testWidgets('横屏 大网格 → 小网格：列数变化时条目同样直线换位', (tester) async {
    await useLandscapeSurface(tester);

    final sample = await sampleTransition(
      tester,
      from: kFolderZoomTierLargeGrid,
      to: kFolderZoomTierSmallGrid,
    );
    for (final index in sample.paths.keys) {
      expectStraightPath(index, sample.starts[index]!, sample.paths[index]!);
    }
    expect(sample.metrics.resolvedGeometryLayers.single.crossAxisCount, 8);
  });

  testWidgets('动画中途再次切档：条目从当前位置接着走，不跳回整数档位', (tester) async {
    await useLandscapeSurface(tester);

    FolderZoomLayoutMetrics? metrics;
    void capture(FolderZoomLayoutMetrics value) => metrics = value;

    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierLargeList, onMetrics: capture),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierSmallGrid, onMetrics: capture),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final beforeInterrupt = await _centerOf(tester, metrics!, 7);
    expect(metrics!.resolvedGeometryLayers.length, greaterThan(1));

    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierLargeGrid, onMetrics: capture),
    );
    final afterInterrupt = await _centerOf(tester, metrics!, 7);

    expect(
      (afterInterrupt - beforeInterrupt).distance,
      lessThan(1.0),
      reason: '中途改档让条目跳了 '
          '${(afterInterrupt - beforeInterrupt).distance.toStringAsFixed(1)}px',
    );

    final weightSum = metrics!.resolvedGeometryLayers
        .fold<double>(0.0, (total, layer) => total + layer.weight);
    expect(weightSum, closeTo(1.0, 1e-6));

    await tester.pumpAndSettle();
    expect(metrics!.resolvedGeometryLayers.length, 1);
    expect(metrics!.resolvedGeometryLayers.single.crossAxisCount, 6);
  });

  // 语义（与 zoomable_sliver_grid 的 FolderZoomItemPinning 一致）：
  // 只有**两个档位都可见**的条目才做位移动画；只在单侧可见的条目位置锁死在屏上，
  // 靠透明度 / 缩放做原地淡入淡出。
  testWidgets('单侧可见条目锁在屏上淡入淡出，只有两侧都可见的条目才位移', (tester) async {
    await useLandscapeSurface(tester);

    FolderZoomLayoutMetrics? latest;
    void capture(FolderZoomLayoutMetrics value) => latest = value;

    await tester.pumpWidget(
      _gridHost(zoomScale: kFolderZoomTierLargeList, onMetrics: capture),
    );
    await tester.pumpAndSettle();

    // 列表 -> 小网格：列表一屏 7 条左右，索引 8 以后只在小网格可见。
    await tester.pumpWidget(
      _gridHost(zoomScale: kFolderZoomTierSmallGrid, onMetrics: capture),
    );
    await tester.pump();

    final pinning = latest!.itemPinning;
    expect(pinning, isNotNull, reason: '过渡开始必须冻结出单侧条目处置表');

    final fadeIn = <int>[
      for (var i = 0; i < 40; i++)
        if (pinning!.pinOf(i) == FolderZoomItemPin.fadeIn) i,
    ];
    expect(fadeIn, isNotEmpty, reason: '列表 → 小网格必然有只在目标档位可见的条目');

    // 双端都可见的条目：挑一条确实被构建出来、且两档位置差得远的。
    // index 0 在两档都在顶端，位置本来就一样，测不出位移。
    final shared = <int>[
      for (var i = 1; i < 40; i++)
        if (pinning!.pinOf(i) == FolderZoomItemPin.shared &&
            find.byKey(ValueKey('grid_item_$i')).evaluate().isNotEmpty)
          i,
    ];
    expect(shared, isNotEmpty, reason: '必须存在两侧都可见的条目');
    final sharedIndex = shared.last;

    final pinnedIndex = fadeIn.first;
    final pinnedFinder = find.byKey(ValueKey('grid_item_$pinnedIndex'));
    final pinnedTopAtStart = tester.getRect(pinnedFinder).top;
    final pinnedTransition = latest!.resolveItemTransition(pinnedIndex);
    expect(pinnedTransition.isShared, isFalse, reason: '单侧可见条目不能走加权位移');
    expect(pinnedTransition.scale, lessThan(1.0), reason: '淡入起点要略微缩小');
    final opacityAtStart = pinnedTransition.opacity;

    final sharedFinder = find.byKey(ValueKey('grid_item_$sharedIndex'));
    final sharedTopAtStart = tester.getRect(sharedFinder).top;
    final sharedTransition = latest!.resolveItemTransition(sharedIndex);
    expect(sharedTransition.isShared, isTrue);
    expect(sharedTransition.opacity, 1.0);
    expect(sharedTransition.scale, 1.0);

    await tester.pump(const Duration(milliseconds: 100));

    expect(
      (tester.getRect(pinnedFinder).top - pinnedTopAtStart).abs(),
      lessThan(1.5),
      reason: '淡入条目必须钉在目标格位上，整段过渡不移动',
    );
    expect(
      latest!.resolveItemTransition(pinnedIndex).opacity,
      greaterThan(opacityAtStart),
      reason: '淡入条目的不透明度要往上走',
    );
    if (sharedFinder.evaluate().isNotEmpty) {
      expect(
        (tester.getRect(sharedFinder).top - sharedTopAtStart).abs(),
        greaterThan(0.5),
        reason: '两侧都可见的条目必须继续做位移动画，不能一起钉死',
      );
    }

    await tester.pumpAndSettle();
    expect(
      (tester.getRect(pinnedFinder).top - pinnedTopAtStart).abs(),
      lessThan(1.5),
      reason: '落定位置应与过渡期锁定位置一致，不能收尾时跳一下',
    );
    expect(latest!.itemPinning, isNull, reason: '动画结束后不再有冻结表');
    expect(latest!.resolveItemTransition(pinnedIndex).isShared, isTrue);

    // 反向（小网格 -> 列表）：只在起点可见的条目原地淡出。
    await tester.pumpWidget(
      _gridHost(zoomScale: kFolderZoomTierLargeList, onMetrics: capture),
    );
    await tester.pump();

    final exitPinning = latest!.itemPinning;
    expect(exitPinning, isNotNull);
    final fadeOut = <int>[
      for (var i = 0; i < 40; i++)
        if (exitPinning!.pinOf(i) == FolderZoomItemPin.fadeOut) i,
    ];
    expect(fadeOut, isNotEmpty, reason: '小网格 → 列表必然有只在起始档位可见的条目');

    final fadingOut = fadeOut.first;
    final fadingOutFinder = find.byKey(ValueKey('grid_item_$fadingOut'));
    final fadingOutTop = tester.getRect(fadingOutFinder).top;
    final opacityBefore = latest!.resolveItemTransition(fadingOut).opacity;

    await tester.pump(const Duration(milliseconds: 120));

    expect(
      (tester.getRect(fadingOutFinder).top - fadingOutTop).abs(),
      lessThan(1.5),
      reason: '淡出条目锁在起始屏幕位置，不能位移',
    );
    expect(
      latest!.resolveItemTransition(fadingOut).opacity,
      lessThan(opacityBefore),
      reason: '淡出条目的不透明度要往下走',
    );
  });

  testWidgets(
    '带 SliverPadding 的多档连点：单侧条目原地淡入、位移条目平滑且收敛到稳态位置',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      FolderZoomLayoutMetrics? latest;
      Widget buildWithPadding(double zoomScale) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: CustomScrollView(
                slivers: [
                  FolderZoomSliverBuilder(
                    zoomScale: zoomScale,
                    width: 1200,
                    builder: (context, metrics) {
                      latest = metrics;
                      final hPad = folderContentHorizontalPadding(
                        isPortrait: false,
                        gridMorph: metrics.gridMorph,
                      );
                      return SliverPadding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        sliver: SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => SizedBox.expand(
                              key: ValueKey('item_$index'),
                            ),
                            childCount: 40,
                          ),
                          gridDelegate: SliverAnimatedZoomGridDelegate(
                            metrics: metrics,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // 起始：标准列表（index 13 不可见）
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierStandardList));
      await tester.pumpAndSettle();

      // 连续跨越 列表 -> 大列表 -> 小网格 -> 中网格（模拟滑块或滚轮跨档）
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierLargeList));
      await tester.pump(const Duration(milliseconds: 24));
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierSmallGrid));
      await tester.pump(const Duration(milliseconds: 24));
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierMediumGrid));
      await tester.pump();

      // index 10 在列表不可见、在网格可见：必须被划成单侧条目（原地淡入 / 淡出），
      // 位置锁在屏上，而不是从列表几何里的真实位置一路滑过来。
      // 注意连点跨档时处置沿用上一段冻结结果（这里从「标准列表可见 → 大列表不可见」
      // 那一段继承下来，所以是 fadeOut），关键是不等于 shared。
      final startTransition = latest!.resolveItemTransition(10);
      expect(startTransition.isShared, isFalse, reason: '单侧可见条目不能走加权位移');
      expect(latest!.itemPinning, isNotNull, reason: '过渡开始必须冻结出处置表');
      expect(
        latest!.itemPinning!.pinOf(10),
        isNot(FolderZoomItemPin.shared),
        reason: '单侧可见条目必须被 pin 住',
      );

      await tester.pumpAndSettle();
      final targetRect = tester.getRect(find.byKey(const ValueKey('item_10')));
      final targetCenter = targetRect.center;

      // 重新从标准列表连续切到中网格，逐帧验证：
      // - 单侧条目（10）锁定期间屏幕位置不动、不跳变；
      // - 双端可见的条目（0）位移连续、单帧不跳；
      // - 收尾时 index 10 精确落在稳态位置。
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierStandardList));
      await tester.pumpAndSettle();

      await tester.pumpWidget(buildWithPadding(kFolderZoomTierLargeList));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierSmallGrid));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierMediumGrid));

      Offset? previousSharedCenter;
      double? lockedTop;
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));

        // 单侧条目：锁定期间位置必须钉住，不能随几何漂移。
        final pin =
            latest!.itemPinning?.pinOf(10) ?? FolderZoomItemPin.shared;
        final pinnedFinder = find.byKey(const ValueKey('item_10'));
        if (pin != FolderZoomItemPin.shared &&
            pinnedFinder.evaluate().isNotEmpty) {
          final rect = tester.getRect(pinnedFinder);
          lockedTop ??= rect.top;
          expect(
            (rect.top - lockedTop).abs(),
            lessThan(1.5),
            reason: 'item_10 是单侧可见条目，第 $i 帧漂移了 '
                '${(rect.top - lockedTop).abs().toStringAsFixed(1)}px',
          );
        }

        // 双端可见条目：位移连续，单帧不允许跳变。
        final sharedFinder = find.byKey(const ValueKey('item_0'));
        if (sharedFinder.evaluate().isEmpty) continue;
        final sharedRect = tester.getRect(sharedFinder);
        if (previousSharedCenter != null) {
          expect(
            (sharedRect.center - previousSharedCenter).distance,
            lessThan(300.0),
            reason: 'item_0 在第 $i 帧发生跳变',
          );
        }
        previousSharedCenter = sharedRect.center;
      }

      await tester.pumpAndSettle();
      final settledRect =
          tester.getRect(find.byKey(const ValueKey('item_10')));
      expect(
        (settledRect.center - targetCenter).distance,
        lessThan(1.0),
        reason: '过渡结束后应精确收敛到目标档位的稳态位置',
      );
    },
  );

  testWidgets(
    '页面有一定滚动时，切档缩放仍能正确判定共同可见条目，并实现平滑位移与滚动锚定',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      FolderZoomLayoutMetrics? latest;
      Widget buildPage(double zoomScale) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 900,
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  FolderZoomSliverBuilder(
                    zoomScale: zoomScale,
                    width: 1200,
                    builder: (context, metrics) {
                      latest = metrics;
                      return SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => SizedBox.expand(
                            key: ValueKey('scrolled_item_$index'),
                          ),
                          childCount: 100,
                        ),
                        gridDelegate: SliverAnimatedZoomGridDelegate(
                          metrics: metrics,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // 起始：标准列表（行高 80px，间距 1px，stride 81px）
      await tester.pumpWidget(buildPage(kFolderZoomTierStandardList));
      await tester.pumpAndSettle();

      // 滚动到第 25 个条目附近（25 * 81 = 2025px）
      scrollController.jumpTo(2025.0);
      await tester.pumpAndSettle();

      // 在当前视口中，index 25, 26, 27 处于可见区域
      expect(scrollController.offset, 2025.0);

      // 切换到小网格（横屏 1200px 下 8 列网格）
      await tester.pumpWidget(buildPage(kFolderZoomTierSmallGrid));
      await tester.pump();

      // 验证共同可见条目判定：index 25 在两端均可见，必须为 isShared = true！
      final transition25 = latest!.resolveItemTransition(25);
      expect(
        transition25.isShared,
        isTrue,
        reason: '有滚动时 index 25 应该被识别为共同可见条目',
      );

      final transition26 = latest!.resolveItemTransition(26);
      expect(transition26.isShared, isTrue);

      // 随动画推进，验证滚动位置已平滑向目标档位的锚定位置同步
      await tester.pump(const Duration(milliseconds: 130));
      expect(scrollController.offset, lessThan(2025.0));

      await tester.pumpAndSettle();
      // 动画完成，index 25 与 index 26 依然停留在屏幕上（处于视口可见范围内）
      expect(find.byKey(const ValueKey('scrolled_item_25')), findsOneWidget);
      expect(find.byKey(const ValueKey('scrolled_item_26')), findsOneWidget);
      final finalRect25 =
          tester.getRect(find.byKey(const ValueKey('scrolled_item_25')));
      final finalRect26 =
          tester.getRect(find.byKey(const ValueKey('scrolled_item_26')));
      expect(finalRect25.bottom, greaterThan(0.0));
      expect(finalRect25.top, lessThan(900.0));
      expect(finalRect26.top, closeTo(finalRect25.top, 0.01));
    },
  );
}
