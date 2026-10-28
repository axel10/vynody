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
    List<int> indices = const [0, 3, 7, 13],
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
}
