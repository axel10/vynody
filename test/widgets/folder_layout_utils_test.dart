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
      expect(
        getFolderZoomGridCrossAxisCount(desktopWidth, kFolderZoomTierSmallGrid),
        equals(7),
      );
      expect(
        getFolderZoomGridCrossAxisCount(desktopWidth, kFolderZoomTierMediumGrid),
        equals(5),
      );
      expect(
        getFolderZoomGridCrossAxisCount(desktopWidth, kFolderZoomTierLargeGrid),
        equals(4),
      );

      const phoneWidth = 390.0;
      expect(
        getFolderZoomGridCrossAxisCount(phoneWidth, kFolderZoomTierSmallGrid),
        equals(3),
      );
      expect(
        getFolderZoomGridCrossAxisCount(phoneWidth, kFolderZoomTierMediumGrid),
        equals(2),
      );
      expect(
        getFolderZoomGridCrossAxisCount(phoneWidth, kFolderZoomTierLargeGrid),
        equals(2),
      );
    });
  });
}
