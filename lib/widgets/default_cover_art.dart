import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Distinguishes default cover art categories.
enum CoverArtType {
  folder,
  song,
  systemFolder,
  cloudFolder,
}

/// Whether the current platform is desktop (Windows, macOS, Linux).
/// Purely platform-driven, completely independent of window dimensions.
bool get isDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// A unified, platform-aware fallback cover widget for folders, songs, and system items.
///
/// - On Mobile (Android / iOS): Uses a restrained, Poweramp-style neutral aesthetic
///   (theme-adaptive monochrome icon with a subtle neutral surface container) to keep
///   visual noise minimal in front of heavy blurred backdrops and banners.
/// - On Desktop (Windows / macOS / Linux): Uses a theme-aware harmonious palette/gradient
///   derived from the app's [ColorScheme], keeping folders and songs visually cohesive
///   while offering comfortable visual vitality across large displays.
class DefaultCoverArt extends StatelessWidget {
  const DefaultCoverArt({
    super.key,
    required this.type,
    this.iconSize,
    this.borderRadius,
    this.customIcon,
  });

  const DefaultCoverArt.folder({
    super.key,
    bool isSystem = false,
    this.iconSize,
    this.borderRadius,
    this.customIcon,
  }) : type = isSystem ? CoverArtType.systemFolder : CoverArtType.folder;

  const DefaultCoverArt.song({
    super.key,
    this.iconSize,
    this.borderRadius,
    this.customIcon,
  }) : type = CoverArtType.song;

  const DefaultCoverArt.systemFolder({
    super.key,
    this.iconSize,
    this.borderRadius,
    this.customIcon,
  }) : type = CoverArtType.systemFolder;

  const DefaultCoverArt.cloudFolder({
    super.key,
    this.iconSize,
    this.borderRadius,
    this.customIcon,
  }) : type = CoverArtType.cloudFolder;

  final CoverArtType type;
  final double? iconSize;
  final BorderRadius? borderRadius;
  final IconData? customIcon;

  IconData _resolveIcon() {
    if (customIcon != null) return customIcon!;
    switch (type) {
      case CoverArtType.folder:
        return Icons.folder_rounded;
      case CoverArtType.song:
        return Icons.music_note_rounded;
      case CoverArtType.systemFolder:
        return Icons.library_music_rounded;
      case CoverArtType.cloudFolder:
        return Icons.cloud_queue_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconData = _resolveIcon();

    final BoxDecoration decoration;
    final Color iconColor;

    if (isDesktopPlatform) {
      // Desktop: Theme-aware, cohesive vitality
      switch (type) {
        case CoverArtType.folder:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer,
                colorScheme.secondaryContainer.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: borderRadius,
          );
          iconColor = colorScheme.onPrimaryContainer;
          break;
        case CoverArtType.song:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.secondaryContainer,
                colorScheme.primaryContainer.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: borderRadius,
          );
          iconColor = colorScheme.onSecondaryContainer;
          break;
        case CoverArtType.systemFolder:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.tertiaryContainer,
                colorScheme.primaryContainer.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: borderRadius,
          );
          iconColor = colorScheme.onTertiaryContainer;
          break;
        case CoverArtType.cloudFolder:
          decoration = BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.secondaryContainer,
                colorScheme.tertiaryContainer.withValues(alpha: 0.85),
              ],
            ),
            borderRadius: borderRadius,
          );
          iconColor = colorScheme.onSecondaryContainer;
          break;
      }
    } else {
      // Mobile: Poweramp-style restrained neutral aesthetic
      decoration = BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: borderRadius,
      );
      iconColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    }

    Widget content = Center(
      child: iconSize != null
          ? Icon(
              iconData,
              size: iconSize,
              color: iconColor,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final side = (constraints.maxWidth.isFinite &&
                        constraints.maxHeight.isFinite)
                    ? math.min(constraints.maxWidth, constraints.maxHeight)
                    : (constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : (constraints.maxHeight.isFinite
                            ? constraints.maxHeight
                            : 48.0));
                final computedSize = (side * 0.45).clamp(16.0, 56.0);
                return Icon(
                  iconData,
                  size: computedSize,
                  color: iconColor,
                );
              },
            ),
    );

    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return Container(
      decoration: decoration,
      child: content,
    );
  }
}
