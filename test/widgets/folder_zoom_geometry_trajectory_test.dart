import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';

/// 条目几何回归：档位切换时每个条目必须在两个**确定**布局之间直线平移。
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

Offset _centerOf(FolderZoomLayoutMetrics metrics, int index) {
  final layout = SliverAnimatedZoomGridDelegate(metrics: metrics)
      .getLayout(_constraints());
  final geometry = layout.getGeometryForChildIndex(index);
  return Offset(
    geometry.crossAxisOffset + geometry.crossAxisExtent / 2,
    geometry.scrollOffset + geometry.mainAxisExtent / 2,
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
      for (final index in indices) index: _centerOf(latest!, index),
    };

    await tester.pumpWidget(_host(zoomScale: to, onMetrics: capture));

    final paths = <int, List<Offset>>{
      for (final index in indices) index: <Offset>[],
    };
    // pumpWidget 这一帧就是动画的第 0 帧（进度 0），必须和起跳位置完全重合。
    for (final index in indices) {
      paths[index]!.add(_centerOf(latest!, index));
    }
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 14));
      for (final index in indices) {
        paths[index]!.add(_centerOf(latest!, index));
      }
    }
    await tester.pumpAndSettle();
    for (final index in indices) {
      paths[index]!.add(_centerOf(latest!, index));
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

    final beforeInterrupt = _centerOf(metrics!, 7);
    expect(metrics!.resolvedGeometryLayers.length, greaterThan(1));

    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierLargeGrid, onMetrics: capture),
    );
    final afterInterrupt = _centerOf(metrics!, 7);

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

  testWidgets('单侧可见条目不发生位移，仅做原地淡入淡出与方向一致的缩放', (tester) async {
    await useLandscapeSurface(tester);

    FolderZoomLayoutMetrics? latest;
    void capture(FolderZoomLayoutMetrics value) => latest = value;

    // 1. 列表 -> 小网格（档位变大）：index 13 仅在小网格可见（淡入 + 由小变大 0.85 -> 1.0）
    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierLargeList, onMetrics: capture),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierSmallGrid, onMetrics: capture),
    );
    final enterStartCenter = _centerOf(latest!, 13);
    final enterStartTransition = latest!.resolveItemTransition(13);
    expect(enterStartTransition.isShared, isFalse);
    expect(enterStartTransition.opacity, closeTo(0.0, 1e-4));
    expect(
      enterStartTransition.scale,
      closeTo(1.0 - kFolderZoomFadeScaleDelta, 1e-4),
    );

    await tester.pump(const Duration(milliseconds: 100));
    final enterMidCenter = _centerOf(latest!, 13);
    final enterMidTransition = latest!.resolveItemTransition(13);
    expect((enterMidCenter - enterStartCenter).distance, lessThan(0.01));
    expect(enterMidTransition.opacity, greaterThan(0.1));
    expect(enterMidTransition.opacity, lessThan(0.95));
    expect(enterMidTransition.scale, greaterThan(enterStartTransition.scale));
    expect(enterMidTransition.scale, lessThan(1.0));

    // 双端均可见的 index 3 保持位移动画（opacity=1, scale=1）
    final sharedMidTransition = latest!.resolveItemTransition(3);
    expect(sharedMidTransition.isShared, isTrue);
    expect(sharedMidTransition.opacity, 1.0);
    expect(sharedMidTransition.scale, 1.0);

    await tester.pumpAndSettle();
    final enterEndCenter = _centerOf(latest!, 13);
    expect((enterEndCenter - enterStartCenter).distance, lessThan(0.01));

    // 2. 小网格 -> 列表（档位缩小）：index 13 仅在小网格可见（淡出 + 由大变小 1.0 -> 0.85）
    await tester.pumpWidget(
      _host(zoomScale: kFolderZoomTierLargeList, onMetrics: capture),
    );
    final exitStartCenter = _centerOf(latest!, 13);
    final exitStartTransition = latest!.resolveItemTransition(13);
    expect(exitStartTransition.isShared, isFalse);
    expect(exitStartTransition.opacity, closeTo(1.0, 1e-4));
    expect(exitStartTransition.scale, closeTo(1.0, 1e-4));

    await tester.pump(const Duration(milliseconds: 100));
    final exitMidCenter = _centerOf(latest!, 13);
    final exitMidTransition = latest!.resolveItemTransition(13);
    expect((exitMidCenter - exitStartCenter).distance, lessThan(0.01));
    expect(exitMidTransition.opacity, lessThan(0.9));
    expect(exitMidTransition.opacity, greaterThan(0.05));
    expect(exitMidTransition.scale, lessThan(1.0));
    expect(
      exitMidTransition.scale,
      greaterThan(1.0 - kFolderZoomFadeScaleDelta),
    );
  });

  testWidgets(
    'List <-> Grid with SliverPadding and multi-tier steps keeps single-side items stationary on screen',
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

      // index 10 在列表不可见，在网格可见；记录其在屏幕上的真实中心坐标与尺寸
      final startTransition = latest!.resolveItemTransition(10);
      expect(startTransition.isShared, isFalse);

      await tester.pumpAndSettle();
      final targetRect = tester.getRect(find.byKey(const ValueKey('item_10')));
      final targetCenter = targetRect.center;

      // 重新从标准列表连续切到中网格，逐帧验证 index 10 的屏幕中心坐标完全不漂移
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierStandardList));
      await tester.pumpAndSettle();

      await tester.pumpWidget(buildWithPadding(kFolderZoomTierLargeList));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierSmallGrid));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pumpWidget(buildWithPadding(kFolderZoomTierMediumGrid));

      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final transition = latest!.resolveItemTransition(10);
        expect(transition.isShared, isFalse);
        final rect = tester.getRect(find.byKey(const ValueKey('item_10')));
        expect((rect.center - targetCenter).distance, lessThan(0.05));
      }
    },
  );
}
