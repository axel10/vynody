import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

FolderZoomLayoutMetrics _metrics({
  required double zoomScale,
  required double cardWidth,
}) {
  return FolderZoomLayoutMetrics(
    targetZoomScale: zoomScale,
    animatedZoomScale: zoomScale,
    gridMorph: isFolderZoomGrid(zoomScale) ? 1.0 : 0.0,
    compactMorph: 0.0,
    animatedGridCols: 6.0,
    animatedGridTextHeight: 74.0,
    animatedListExtent: 80.0,
    targetCardWidth: cardWidth,
  );
}

void main() {
  // 回归：桌面端目录页缩略图发糊。
  //
  // 网格态的封面边长等于网格卡片宽度（横屏固定 6/7/8 列），macOS 常见窗口下
  // 达 180~270dp；此前一律按 kZoomItemThumbnailSize（120）解码，2x 屏上只有
  // 240px 纹理铺满 460px，放大近两倍。这里锁住「按卡片宽度取桶」这一行为。
  group('zoomItemThumbnailSizeFor', () {
    test('网格态按卡片宽度解码，桌面卡片落到 250 桶', () {
      final size = zoomItemThumbnailSizeFor(
        _metrics(zoomScale: FolderZoomTier.largeGrid.zoomScale, cardWidth: 233.0),
      );
      expect(size, 233.0);
      expect(thumbnailBucketSizeFor(size), 250.0);
    });

    test('列表态仍走小桶，不因网格卡片宽度白解码', () {
      final size = zoomItemThumbnailSizeFor(
        _metrics(zoomScale: FolderZoomTier.standardList.zoomScale, cardWidth: 233.0),
      );
      expect(size, 64.0);
      expect(thumbnailBucketSizeFor(size), 120.0);
    });

    test('手机竖屏窄卡片仍落在 120 桶，内存不涨', () {
      final size = zoomItemThumbnailSizeFor(
        _metrics(zoomScale: FolderZoomTier.smallGrid.zoomScale, cardWidth: 112.0),
      );
      expect(thumbnailBucketSizeFor(size), 120.0);
    });

    test('隐藏封面（minimal list）时不为 0，分桶兜底到最小档', () {
      final size = zoomItemThumbnailSizeFor(
        _metrics(zoomScale: FolderZoomTier.minimalList.zoomScale, cardWidth: 233.0),
      );
      expect(size, 0.0);
      expect(thumbnailBucketSizeFor(size), 60.0);
    });
  });
}
