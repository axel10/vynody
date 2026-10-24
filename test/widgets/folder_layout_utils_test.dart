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
      expect(getFolderListCoverSize(kFolderZoomTierStandardList), equals(52.0));
      expect(getFolderListCoverSize(kFolderZoomTierLargeList), equals(64.0));
    });

    test('getFolderZoomGridCrossAxisCount adapts across 3 grid tiers', () {
      const desktopWidth = 1280.0;
      // In landscape: largeGrid is fixed at 6, medium is 7, small is 8 (+1 per smaller tier).
      expect(
        getFolderZoomGridCrossAxisCount(desktopWidth, kFolderZoomTierLargeGrid),
        equals(6),
      );
      expect(
        getFolderZoomGridCrossAxisCount(desktopWidth, kFolderZoomTierMediumGrid),
        equals(7),
      );
      expect(
        getFolderZoomGridCrossAxisCount(desktopWidth, kFolderZoomTierSmallGrid),
        equals(8),
      );

      // In phone portrait: largeGrid is 2, medium is 3, small is 4 (+1 per smaller tier).
      const phoneWidth = 390.0;
      expect(
        getFolderZoomGridCrossAxisCount(phoneWidth, kFolderZoomTierLargeGrid),
        equals(2),
      );
      expect(
        getFolderZoomGridCrossAxisCount(phoneWidth, kFolderZoomTierMediumGrid),
        equals(3),
      );
      expect(
        getFolderZoomGridCrossAxisCount(phoneWidth, kFolderZoomTierSmallGrid),
        equals(4),
      );

      // In tablet portrait: largeGrid is 3, medium is 4, small is 5 (+1 per smaller tier).
      const tabletWidth = 768.0;
      expect(
        getFolderZoomGridCrossAxisCount(
          tabletWidth,
          kFolderZoomTierLargeGrid,
          isPortrait: true,
        ),
        equals(3),
      );
      expect(
        getFolderZoomGridCrossAxisCount(
          tabletWidth,
          kFolderZoomTierMediumGrid,
          isPortrait: true,
        ),
        equals(4),
      );
      expect(
        getFolderZoomGridCrossAxisCount(
          tabletWidth,
          kFolderZoomTierSmallGrid,
          isPortrait: true,
        ),
        equals(5),
      );
    });

    test('FolderZoomPolicy correctly encapsulates offset calculation and viewport centering', () {
      const policy = FolderZoomPolicy(
        width: 1280.0,
        zoomScale: 1.0,
        isPortrait: false,
        tier: FolderZoomTier.largeGrid,
        crossAxisCount: 6,
        textHeight: 74.0,
        cardWidth: 200.0,
        cardHeight: 274.0,
        childAspectRatio: 200.0 / 274.0,
        listTileExtent: 80.0,
        listRowStride: 88.0,
        isGrid: true,
      );

      // 6 subfolders = 1 row in 6-col grid: 1 * (274 + 24) = 298.0
      // songIndex 6 = row 1 (the 2nd row of songs): 1 * (274 + 24) = 298.0
      // total = 596.0
      final offset = policy.calculateScrollOffset(folderCount: 6, songIndex: 6);
      expect(offset, equals(596.0));

      final centered = policy.centerInViewport(
        itemOffset: 1000.0,
        viewportDimension: 600.0,
        maxScrollExtent: 2000.0,
      );
      // itemExtent is cardHeight (274.0):
      // target = 1000 - 300 + 137 = 837.0
      expect(centered, equals(837.0));
    });
  });
}
