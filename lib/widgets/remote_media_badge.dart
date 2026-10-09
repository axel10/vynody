import 'package:flutter/material.dart';
import 'package:vynody/utils/blur_constants.dart';
import '../dialogs/remote_source_info_dialog.dart';
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/remote/proxy/remote_media_resolver.dart';

/// Helper methods for determining remote media library status.
class RemoteMediaHelper {
  RemoteMediaHelper._();

  /// Checks if a single song belongs to a remote media library.
  static bool isRemote(MusicFile? song) {
    if (song == null) return false;
    return RemoteMediaResolver.isRemoteUri(song.path);
  }

  /// Checks if all songs in a collection are from remote media libraries.
  static bool isAllRemote(Iterable<MusicFile>? songs) {
    if (songs == null || songs.isEmpty) return false;
    return songs.every((s) => RemoteMediaResolver.isRemoteUri(s.path));
  }

  /// Checks if a collection is mixed (contains both local and remote songs).
  static bool isMixed(Iterable<MusicFile>? songs) {
    if (songs == null || songs.isEmpty) return false;
    bool hasRemote = false;
    bool hasLocal = false;
    for (final s in songs) {
      if (RemoteMediaResolver.isRemoteUri(s.path)) {
        hasRemote = true;
      } else {
        hasLocal = true;
      }
      if (hasRemote && hasLocal) return true;
    }
    return false;
  }
}

/// A versatile badge widget to indicate remote media library items.
///
/// Encapsulates visual presentation, self-gating visibility checks,
/// and source info dialog interactions on tap.
class RemoteMediaBadge extends StatelessWidget {
  const RemoteMediaBadge.corner({
    super.key,
    this.iconSize = 13.0,
    this.padding = const EdgeInsets.all(4.0),
    this.borderRadius = 6.0,
    this.onTap,
    this.song,
    this.songs,
    this.title,
    this.forceShow = false,
  })  : variant = RemoteMediaBadgeVariant.corner,
        label = null;

  const RemoteMediaBadge.chip({
    super.key,
    this.label,
    this.onTap,
    this.song,
    this.songs,
    this.title,
    this.forceShow = false,
  })  : variant = RemoteMediaBadgeVariant.chip,
        iconSize = 14.0,
        padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        borderRadius = 16.0;

  const RemoteMediaBadge.pill({
    super.key,
    this.label,
    this.onTap,
    this.song,
    this.songs,
    this.title,
    this.forceShow = false,
  })  : variant = RemoteMediaBadgeVariant.pill,
        iconSize = 12.0,
        padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        borderRadius = 8.0;

  const RemoteMediaBadge.songIndicator({
    super.key,
    this.iconSize = 14.0,
    this.onTap,
    this.song,
    this.songs,
    this.title,
    this.forceShow = false,
  })  : variant = RemoteMediaBadgeVariant.songIndicator,
        label = null,
        padding = EdgeInsets.zero,
        borderRadius = 0.0;

  final RemoteMediaBadgeVariant variant;
  final String? label;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final MusicFile? song;
  final List<MusicFile>? songs;
  final String? title;

  /// If true, bypasses the automatic isRemote / isAllRemote check.
  final bool forceShow;

  /// High-level wrapper that automatically decorates any cover widget with a
  /// top-right remote corner badge if all [songs] (or [song]) are remote.
  /// If not remote, returns [child] directly with zero extra layout cost.
  static Widget wrapCover({
    required Widget child,
    List<MusicFile>? songs,
    MusicFile? song,
    String? title,
    double top = 6.0,
    double right = 6.0,
    double iconSize = 13.0,
    double padding = 4.0,
    bool showRemoteBadge = true,
  }) {
    if (!showRemoteBadge) return child;
    final bool isTargetRemote = (songs != null && RemoteMediaHelper.isAllRemote(songs)) ||
        (song != null && RemoteMediaHelper.isRemote(song));

    if (!isTargetRemote) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: top,
          right: right,
          child: RemoteMediaBadge.corner(
            songs: songs,
            song: song,
            title: title,
            iconSize: iconSize,
            padding: EdgeInsets.all(padding),
            forceShow: true,
          ),
        ),
      ],
    );
  }

  /// High-level helper for single song row titles.
  /// Automatically renders an indented cloud icon if [song] is remote and [isMixed] is true.
  /// Returns [SizedBox.shrink] otherwise.
  static Widget songTrailing({
    required MusicFile song,
    bool isMixed = true,
    double iconSize = 14.0,
    double leftSpacing = 6.0,
  }) {
    if (!isMixed || !RemoteMediaHelper.isRemote(song)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(left: leftSpacing),
      child: RemoteMediaBadge.songIndicator(
        song: song,
        title: song.displayName,
        iconSize: iconSize,
        forceShow: true,
      ),
    );
  }

  /// High-level helper for artist list row titles.
  /// Automatically renders an indented pill badge if all [songs] are remote.
  /// Returns [SizedBox.shrink] otherwise.
  static Widget pillTrailing({
    required List<MusicFile> songs,
    String? title,
    double leftSpacing = 6.0,
  }) {
    if (!RemoteMediaHelper.isAllRemote(songs)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(left: leftSpacing),
      child: RemoteMediaBadge.pill(
        songs: songs,
        title: title,
        forceShow: true,
      ),
    );
  }

  bool _shouldDisplay() {
    if (forceShow) return true;
    if (songs != null) {
      return RemoteMediaHelper.isAllRemote(songs);
    }
    if (song != null) {
      return RemoteMediaHelper.isRemote(song);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldDisplay()) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tooltipText = l10n?.remoteLibraryTooltip ?? 'From remote media library';
    final badgeText = label ?? l10n?.remoteLibraryBadge ?? 'Cloud';

    final canTap = onTap != null || song != null || (songs != null && songs!.isNotEmpty);
    void handleTap() {
      if (onTap != null) {
        onTap!();
      } else if (song != null || (songs != null && songs!.isNotEmpty)) {
        showRemoteSourceInfoDialog(
          context,
          song: song,
          songs: songs,
          title: title,
        );
      }
    }

    Widget content;
    switch (variant) {
      case RemoteMediaBadgeVariant.corner:
        content = Tooltip(
          message: tooltipText,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: BackdropFilter(
              filter: AppBlur.lightFilter,
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(borderRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 0.75,
                  ),
                ),
                child: Icon(
                  Icons.cloud_rounded,
                  size: iconSize,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        );
        break;

      case RemoteMediaBadgeVariant.chip:
        content = Tooltip(
          message: tooltipText,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_rounded,
                  size: iconSize,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Text(
                  badgeText,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
        break;

      case RemoteMediaBadgeVariant.pill:
        content = Tooltip(
          message: tooltipText,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_rounded,
                  size: iconSize,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 3),
                Text(
                  badgeText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
        break;

      case RemoteMediaBadgeVariant.songIndicator:
        content = Tooltip(
          message: tooltipText,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Icon(
              Icons.cloud_outlined,
              size: iconSize,
              color: theme.colorScheme.primary.withValues(alpha: 0.85),
            ),
          ),
        );
        break;
    }

    if (canTap) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: handleTap,
          child: content,
        ),
      );
    }

    return content;
  }
}

enum RemoteMediaBadgeVariant {
  corner,
  chip,
  pill,
  songIndicator,
}
