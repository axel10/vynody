import 'package:flutter/material.dart';
import 'package:vynody/utils/blur_constants.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import '../l10n/app_localizations.dart';
import '../widgets/song_thumbnail.dart';
import 'default_cover_art.dart';
import 'draggable_folder_item.dart';

/// Borderless folder card for grid layouts, matching [AlbumGridCard]'s
/// typography rhythm so folder and album grids read as one system.
class FolderGridCard extends StatelessWidget {
  const FolderGridCard({
    super.key,
    required this.folder,
    this.songsCount = 0,
    this.representativeSong,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isSortMode = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.subtitle,
    this.customTitle,
    this.enableHero = true,
    this.isIndexed = false,
  });

  final MusicFolder folder;
  final int songsCount;
  final MusicFile? representativeSong;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isSortMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final String? subtitle;
  final String? customTitle;
  final bool enableHero;
  final bool isIndexed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isWide = MediaQuery.of(context).size.width >= 780;

    final isSystem = folder.path == 'system';
    final coverRadius = BorderRadius.circular(12);
    final defaultCoverWidget = DefaultCoverArt.folder(
      isSystem: isSystem,
      iconSize: 48,
      borderRadius: coverRadius,
    );

    Widget coverWidget;
    if (representativeSong != null) {
      coverWidget = SongThumbnail.fromSong(
        representativeSong!,
        size: 200,
        width: double.infinity,
        height: double.infinity,
        // Hero flights are painted outside the card's clip, so the artwork
        // itself must carry the cover's corner radius.
        borderRadius: coverRadius,
        fallbackWidget: defaultCoverWidget,
      );
    } else {
      coverWidget = defaultCoverWidget;
    }

    final cardCover = ExcludeSemantics(
      child: ClipRRect(
        borderRadius: coverRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            coverWidget,
            if (isSelectionMode)
              Positioned.fill(
                child: Container(
                  color: isSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Colors.black26,
                ),
              ),
            if (isSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onTap?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            if (isIndexed)
              Positioned(
                top: 8,
                right: 8,
                child: Tooltip(
                  message: l10n.remoteFolderAlreadyIndexed,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6.0),
                    child: BackdropFilter(
                      filter: AppBlur.lightFilter,
                      child: Container(
                        padding: const EdgeInsets.all(4.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.5),
                            width: 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 4,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.library_add_check_rounded,
                          size: 13.0,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final card = MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: enableHero
                  ? Hero(
                      tag: 'folder-cover-${folder.path}',
                      child: cardCover,
                    )
                  : cardCover,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      customTitle ?? folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (isPortrait
                              ? theme.textTheme.titleSmall
                              : theme.textTheme.titleMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isWide ? 14.5 : 14.0,
                        color: isSelectionMode && isSelected
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? l10n.songsCountFormat(songsCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (isPortrait
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return DraggableFolderItem(
      folder: folder,
      songsCount: songsCount,
      representativeSong: representativeSong,
      enabled: !isSelectionMode && !isSortMode,
      child: card,
    );
  }
}

class HoverableCard extends StatefulWidget {
  const HoverableCard({super.key, required this.child});
  final Widget child;

  @override
  State<HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<HoverableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
