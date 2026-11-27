import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/blur_constants.dart';

/// Corner badge indicating that a folder or song originates from the system
/// media library.
class SystemMediaBadge extends StatelessWidget {
  const SystemMediaBadge.corner({
    super.key,
    this.iconSize = 13.0,
    this.padding = const EdgeInsets.all(4.0),
    this.borderRadius = 6.0,
  });

  final double iconSize;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// Returns whether [folderPath] belongs to the virtual `system` media tree.
  static bool isSystemFolderPath(String folderPath) {
    return folderPath == 'system' ||
        ScannerPathUtils.pathContains('system', folderPath);
  }

  /// Wraps [child] with a top-right [SystemMediaBadge.corner] when [show] is true.
  static Widget wrapCover({
    required Widget child,
    required bool show,
    double top = 4.0,
    double right = 4.0,
    double iconSize = 13.0,
    double padding = 4.0,
    StackFit fit = StackFit.loose,
  }) {
    if (!show) return child;
    return Stack(
      fit: fit,
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: top,
          right: right,
          child: SystemMediaBadge.corner(
            iconSize: iconSize,
            padding: EdgeInsets.all(padding),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tooltipText = l10n?.systemMediaLibrary ?? 'System Media Library';

    return Tooltip(
      message: tooltipText,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: AppBackdropFilter(
          filter: AppBlur.lightFilter,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                alpha: AppBlur.badgeAlpha(
                  isBlurEnabled: AppBlur.isBlurEnabled(context),
                ),
              ),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 0.75,
              ),
            ),
            child: Icon(
              Icons.library_music_rounded,
              size: iconSize,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
