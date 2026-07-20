import 'package:flutter/material.dart';

/// Returns responsive cross axis count based on layout width for folder and song grids.
int getFolderGridCrossAxisCount(double width) {
  return switch (width) {
    >= 1350 => 6,
    >= 1100 => 5,
    >= 850 => 4,
    >= 650 => 3,
    _ => 2,
  };
}

/// Calculates grid item aspect ratio considering system font scaling and orientation.
double calculateFolderGridChildAspectRatio(
  BuildContext context,
  double width,
  int crossAxisCount,
) {
  final isPortrait =
      MediaQuery.of(context).orientation == Orientation.portrait;
  final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
  final clampedScale = textScale.clamp(1.0, 1.3);
  final double textHeight = (isPortrait ? 72.0 : 84.0) * clampedScale;
  final itemWidth = (width - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
  return itemWidth / (itemWidth + textHeight);
}
