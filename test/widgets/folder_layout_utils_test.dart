import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';

void main() {
  group('FolderZoomTier & Snap tests', () {
    test('snapFolderZoomScale snaps continuous values to 6 discrete tiers', () {
      expect(snapFolderZoomScale(-0.1), equals(kFolderZoomTierCompactList));
      expect(snapFolderZoomScale(0.0), equals(kFolderZoomTierCompactList));
      expect(snapFolderZoomScale(0.08), equals(kFolderZoomTierCompactList));
      expect(snapFolderZoomScale(0.12), equals(kFolderZoomTierStandardList));
      expect(snapFolderZoomScale(0.24), equals(kFolderZoomTierStandardList));
      expect(snapFolderZoomScale(0.35), equals(kFolderZoomTierLargeList));
      expect(snapFolderZoomScale(0.49), equals(kFolderZoomTierLargeList));
      expect(snapFolderZoomScale(0.55), equals(kFolderZoomTierSmallGrid));
      expect(snapFolderZoomScale(0.65), equals(kFolderZoomTierSmallGrid));
      expect(snapFolderZoomScale(0.75), equals(kFolderZoomTierMediumGrid));
      expect(snapFolderZoomScale(0.85), equals(kFolderZoomTierMediumGrid));
      expect(snapFolderZoomScale(0.92), equals(kFolderZoomTierLargeGrid));
      expect(snapFolderZoomScale(1.0), equals(kFolderZoomTierLargeGrid));
      expect(snapFolderZoomScale(1.5), equals(kFolderZoomTierLargeGrid));
    });

    test('stepFolderZoomScale increments and decrements by discrete tiers', () {
      expect(
        stepFolderZoomScale(kFolderZoomTierCompactList, 1),
        equals(kFolderZoomTierStandardList),
      );
      expect(
        stepFolderZoomScale(kFolderZoomTierStandardList, 1),
        equals(kFolderZoomTierLargeList),
      );
      expect(
        stepFolderZoomScale(kFolderZoomTierLargeList, 1),
        equals(kFolderZoomTierSmallGrid),
      );
      expect(
        stepFolderZoomScale(kFolderZoomTierSmallGrid, 1),
        equals(kFolderZoomTierMediumGrid),
      );
      expect(
        stepFolderZoomScale(kFolderZoomTierMediumGrid, 1),
        equals(kFolderZoomTierLargeGrid),
      );
      expect(
        stepFolderZoomScale(kFolderZoomTierLargeGrid, 1),
        equals(kFolderZoomTierLargeGrid),
      );

      expect(
        stepFolderZoomScale(kFolderZoomTierLargeGrid, -1),
        equals(kFolderZoomTierMediumGrid),
      );
      expect(
        stepFolderZoomScale(kFolderZoomTierCompactList, -1),
        equals(kFolderZoomTierCompactList),
      );
    });

    test('getFolderZoomTier correctly classifies all 6 tiers', () {
      expect(getFolderZoomTier(0.0), equals(FolderZoomTier.compactList));
      expect(getFolderZoomTier(0.2), equals(FolderZoomTier.standardList));
      expect(getFolderZoomTier(0.4), equals(FolderZoomTier.largeList));
      expect(getFolderZoomTier(0.6), equals(FolderZoomTier.smallGrid));
      expect(getFolderZoomTier(0.8), equals(FolderZoomTier.mediumGrid));
      expect(getFolderZoomTier(1.0), equals(FolderZoomTier.largeGrid));
    });

    test('isFolderZoomGrid separates list and grid views at 0.5', () {
      expect(isFolderZoomGrid(kFolderZoomTierCompactList), isFalse);
      expect(isFolderZoomGrid(kFolderZoomTierStandardList), isFalse);
      expect(isFolderZoomGrid(kFolderZoomTierLargeList), isFalse);
      expect(isFolderZoomGrid(kFolderZoomTierSmallGrid), isTrue);
      expect(isFolderZoomGrid(kFolderZoomTierMediumGrid), isTrue);
      expect(isFolderZoomGrid(kFolderZoomTierLargeGrid), isTrue);
    });

    test('getFolderListCoverSize returns discrete sizes for list tiers', () {
      expect(getFolderListCoverSize(kFolderZoomTierCompactList), equals(40.0));
      expect(getFolderListCoverSize(kFolderZoomTierStandardList), equals(64.0));
      expect(getFolderListCoverSize(kFolderZoomTierLargeList), equals(88.0));
    });

    test('FolderZoomPolicy.calculateCrossAxisCount adapts across 3 grid tiers', () {
      const desktopWidth = 1280.0;
      // In landscape: largeGrid is fixed at 6, medium is 7, small is 8 (+1 per smaller tier).
      int cols(double width, FolderZoomTier tier, {required bool isPortrait}) =>
          FolderZoomPolicy.calculateCrossAxisCount(
            width: width,
            tier: tier,
            isPortrait: isPortrait,
          );

      expect(
        cols(desktopWidth, FolderZoomTier.largeGrid, isPortrait: false),
        equals(6),
      );
      expect(
        cols(desktopWidth, FolderZoomTier.mediumGrid, isPortrait: false),
        equals(7),
      );
      expect(
        cols(desktopWidth, FolderZoomTier.smallGrid, isPortrait: false),
        equals(8),
      );

      // In phone portrait: largeGrid is 2, medium is 3, small is 4 (+1 per smaller tier).
      const phoneWidth = 390.0;
      expect(
        cols(phoneWidth, FolderZoomTier.largeGrid, isPortrait: true),
        equals(2),
      );
      expect(
        cols(phoneWidth, FolderZoomTier.mediumGrid, isPortrait: true),
        equals(3),
      );
      expect(
        cols(phoneWidth, FolderZoomTier.smallGrid, isPortrait: true),
        equals(4),
      );

      // In tablet portrait: largeGrid is 3, medium is 4, small is 5 (+1 per smaller tier).
      const tabletWidth = 768.0;
      expect(
        cols(tabletWidth, FolderZoomTier.largeGrid, isPortrait: true),
        equals(3),
      );
      expect(
        cols(tabletWidth, FolderZoomTier.mediumGrid, isPortrait: true),
        equals(4),
      );
      expect(
        cols(tabletWidth, FolderZoomTier.smallGrid, isPortrait: true),
        equals(5),
      );
    });

    testWidgets(
      'FolderZoomPolicy.resolve 用外层宽度扣内边距，卡片几何与网格排布一致',
      (tester) async {
        late FolderZoomPolicy policy;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                policy = FolderZoomPolicy.resolve(
                  context: context,
                  outerWidth: 1280.0,
                  zoomScale: kFolderZoomTierLargeGrid,
                  isPortrait: false,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(policy.isGrid, isTrue);
        expect(policy.crossAxisCount, 6);

        // 外层 1280 扣掉两侧 16 的网格内边距，再按 6 列均分、列距 16。
        const expectedCardWidth = (1280.0 - 32.0 - 5 * 16.0) / 6.0;
        expect(policy.cardWidth, closeTo(expectedCardWidth, 1e-9));

        // 大网格横屏文字区 74。卡片高度必须等于卡片宽 + 文字区，
        // 否则「定位当前播放」会按与真实行高不同的值估算偏移。
        expect(policy.cardHeight, closeTo(expectedCardWidth + 74.0, 1e-9));
        expect(
          policy.childAspectRatio,
          closeTo(expectedCardWidth / (expectedCardWidth + 74.0), 1e-9),
        );

        // 6 个子文件夹占满 1 行；歌曲第 6 首落在第 2 行。
        final stride = policy.cardHeight + kGridMainAxisSpacing;
        expect(
          policy.calculateScrollOffset(folderCount: 6, songIndex: 6),
          closeTo(stride * 2, 1e-9),
        );

        // 居中：减去半屏、加上半行，并夹在 [0, maxScrollExtent]。
        final centered = policy.centerInViewport(
          itemOffset: 1000.0,
          viewportDimension: 600.0,
          maxScrollExtent: 2000.0,
        );
        expect(centered, closeTo(1000.0 - 300.0 + policy.cardHeight / 2, 1e-9));
        expect(
          policy.centerInViewport(
            itemOffset: 100.0,
            viewportDimension: 600.0,
            maxScrollExtent: 2000.0,
          ),
          0.0,
        );
      },
    );

    test('folderGridFontSizes 按卡片宽度分档，与屏幕宽度无关', () {
      // 横屏 8 列的卡片约 142pt，1920 窗口 6 列约 265pt：屏幕更宽不等于字号更大。
      expect(folderGridFontSizes(142.0).title, 12.5);
      expect(folderGridFontSizes(265.0).title, 15.0);

      // 手机竖屏 4 列的卡片约 84pt，必须落到最小档，否则标题被省略号吃掉。
      expect(folderGridFontSizes(84.0).title, 11.5);
      expect(folderGridFontSizes(84.0).subtitle, 9.5);

      // 档位边界闭区间：正好等于阈值时归入更大的那一档。
      expect(folderGridFontSizes(109.9).title, 11.5);
      expect(folderGridFontSizes(110.0).title, 12.5);
      expect(folderGridFontSizes(149.9).title, 12.5);
      expect(folderGridFontSizes(150.0).title, 13.5);
      expect(folderGridFontSizes(199.9).title, 13.5);
      expect(folderGridFontSizes(200.0).title, 14.5);
      expect(folderGridFontSizes(239.9).title, 14.5);
      expect(folderGridFontSizes(240.0).title, 15.0);
    });

    testWidgets(
      'FolderZoomSliverBuilder 的 targetCardWidth 与 Policy 同源',
      (tester) async {
        late FolderZoomLayoutMetrics metrics;
        late FolderZoomPolicy policy;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  FolderZoomSliverBuilder(
                    zoomScale: kFolderZoomTierLargeGrid,
                    width: 1280.0,
                    builder: (context, m) {
                      metrics = m;
                      policy = FolderZoomPolicy.resolve(
                        context: context,
                        outerWidth: 1280.0,
                        zoomScale: kFolderZoomTierLargeGrid,
                      );
                      return const SliverToBoxAdapter(
                        child: SizedBox.shrink(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );

        // 字号档位读的是 metrics.targetCardWidth，偏移/宽高比读的是 policy：
        // 两者算不出同一个宽度，字号就会和真实卡片宽度脱节。
        expect(metrics.targetCardWidth, closeTo(policy.cardWidth, 1e-9));
        expect(
          metrics.targetChildAspectRatio,
          closeTo(policy.childAspectRatio, 1e-9),
        );
      },
    );
  });
}
