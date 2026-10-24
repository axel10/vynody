import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import '../l10n/app_localizations.dart';
import '../widgets/song_thumbnail.dart';
import 'default_cover_art.dart';
import 'draggable_folder_item.dart';
import 'folder_layout_utils.dart';
import 'hoverable_card.dart';

/// Unified folder item widget that smoothly morphs between List View and Grid View
/// based on [FolderZoomLayoutMetrics].
class FolderZoomItem extends StatelessWidget {
  const FolderZoomItem({
    super.key,
    required this.folder,
    required this.metrics,
    this.songsCount = 0,
    this.representativeSong,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isSortMode = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.trailing,
    this.subtitle,
    this.customTitle,
    this.enableHero = true,
    this.isIndexed = false,
  });

  final MusicFolder folder;
  final FolderZoomLayoutMetrics metrics;
  final int songsCount;
  final MusicFile? representativeSong;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isSortMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final Widget? trailing;
  final String? subtitle;
  final String? customTitle;
  final bool enableHero;
  final bool isIndexed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final gridMorph = metrics.gridMorph;
    final isGridTarget = metrics.isGridTarget;

    final isSystem = folder.path == 'system';
    final coverRadiusValue = lerpDouble(8.0, 12.0, gridMorph)!;
    final coverRadius = BorderRadius.circular(coverRadiusValue);
    final gridIconSize = switch (metrics.tier) {
      FolderZoomTier.smallGrid => 32.0,
      FolderZoomTier.mediumGrid => 40.0,
      FolderZoomTier.largeGrid || _ => 48.0,
    };
    final defaultIconSize = lerpDouble(26.0, gridIconSize, gridMorph)!;
    final defaultCoverWidget = DefaultCoverArt.folder(
      isSystem: isSystem,
      iconSize: defaultIconSize,
      borderRadius: coverRadius,
    );

    Widget coverWidget;
    if (representativeSong != null) {
      coverWidget = SongThumbnail.fromSong(
        representativeSong!,
        size: 200,
        width: double.infinity,
        height: double.infinity,
        borderRadius: coverRadius,
        fallbackWidget: defaultCoverWidget,
      );
    } else {
      coverWidget = defaultCoverWidget;
    }

    final coverStack = ExcludeSemantics(
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
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                      : Colors.black26,
                ),
              ),
            if (isSelectionMode)
              Align(
                alignment: Alignment.lerp(
                  Alignment.center,
                  Alignment.topLeft,
                  gridMorph,
                )!,
                child: Padding(
                  padding: EdgeInsets.all(lerpDouble(0.0, 8.0, gridMorph)!),
                  child: SizedBox(
                    width: lerpDouble(32.0, 28.0, gridMorph)!,
                    height: lerpDouble(32.0, 28.0, gridMorph)!,
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
              ),
            if (isIndexed)
              Positioned(
                top: lerpDouble(3.0, 8.0, gridMorph)!,
                right: lerpDouble(3.0, 8.0, gridMorph)!,
                child: Tooltip(
                  message: l10n.remoteFolderAlreadyIndexed,
                  child: Container(
                    padding: EdgeInsets.all(lerpDouble(3.0, 4.5, gridMorph)!),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6.0),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.6),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(
                      Icons.library_add_check_rounded,
                      size: lerpDouble(11.0, 13.0, gridMorph)!,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final heroCover = enableHero
        ? Hero(
            tag: 'folder-cover-${folder.path}',
            child: coverStack,
          )
        : coverStack;

    // Typography is discrete by tier rather than continuously scaled.
    final titleColor = isSelectionMode && isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    final TextStyle titleStyle;
    final TextStyle subtitleStyle;
    if (!isGridTarget) {
      titleStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: titleColor,
        fontWeight: FontWeight.normal,
        height: 1.2,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: 12.0,
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
    } else {
      // 字号按**卡片宽度**分档（不是屏幕宽度）：卡片窄到 142pt 时用宽屏字号会截断标题。
      final fonts = folderGridFontSizes(metrics.targetCardWidth);
      final double titleSize = fonts.title;
      final double subSize = fonts.subtitle;
      titleStyle = ((isPortrait
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium) ??
              const TextStyle())
          .copyWith(
        fontWeight: FontWeight.w600,
        fontSize: titleSize,
        color: titleColor,
        height: 1.25,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: subSize,
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.2,
      );
    }

    final textColumn = Align(
      alignment: Alignment.centerLeft,
      child: OverflowBox(
        minHeight: 0.0,
        maxHeight: double.infinity,
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              style: titleStyle,
              child: Text(
                customTitle ?? folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: lerpDouble(4.0, 2.0, gridMorph)!),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              style: subtitleStyle,
              child: Text(
                subtitle ?? l10n.songsCountFormat(songsCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    final listBgAlpha = (1.0 - gridMorph).clamp(0.0, 1.0);
    final itemContent = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelectionMode && isSelected && listBgAlpha > 0.01
              ? theme.colorScheme.primaryContainer
                  .withValues(alpha: 0.35 * listBgAlpha)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(coverRadiusValue),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(coverRadiusValue),
          child: InkWell(
            borderRadius: BorderRadius.circular(coverRadiusValue),
            enableFeedback: false,
            onTap: onTap,
            onLongPress: onLongPress,
            hoverColor: gridMorph < 0.5
                ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                : Colors.transparent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final W = constraints.maxWidth;
                final H = constraints.maxHeight.isFinite
                    ? constraints.maxHeight
                    : metrics.animatedListExtent;

                final listPadH = isPortrait ? 12.0 : 16.0;
                final listCoverSize = getFolderListCoverSize(
                  metrics.animatedZoomScale,
                ).clamp(32.0, math.max(32.0, H - 8.0));
                final listCoverLeft = listPadH;
                final listCoverTop =
                    ((H - listCoverSize) / 2.0).clamp(0.0, H);

                final gridCoverSize = math.max(
                  0.0,
                  math.min(W, H - metrics.animatedGridTextHeight),
                );
                final gridCoverLeft = (W - gridCoverSize) / 2.0;
                const gridCoverTop = 0.0;

                final coverLeft =
                    lerpDouble(listCoverLeft, gridCoverLeft, gridMorph)!;
                final coverTop =
                    lerpDouble(listCoverTop, gridCoverTop, gridMorph)!;
                final coverSize =
                    lerpDouble(listCoverSize, gridCoverSize, gridMorph)!;

                final hasTrailing = trailing != null;
                final trailingSpace =
                    hasTrailing ? lerpDouble(44.0, 0.0, gridMorph)! : 0.0;

                final listTextLeft = listCoverLeft + listCoverSize + 16.0;
                final listTextTop = listCoverTop;
                final listTextWidth = math.max(
                  0.0,
                  W - listTextLeft - listPadH - trailingSpace,
                );
                final listTextHeight = listCoverSize;

                const gridTextLeft = 0.0;
                final gridTextTop = gridCoverSize + 4.0;
                final gridTextWidth = W;
                final gridTextHeight = math.max(0.0, H - gridTextTop);

                final textLeft =
                    lerpDouble(listTextLeft, gridTextLeft, gridMorph)!;
                final textTop =
                    lerpDouble(listTextTop, gridTextTop, gridMorph)!;
                final textWidth =
                    lerpDouble(listTextWidth, gridTextWidth, gridMorph)!;
                final textHeight =
                    lerpDouble(listTextHeight, gridTextHeight, gridMorph)!;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: coverLeft,
                      top: coverTop,
                      width: coverSize,
                      height: coverSize,
                      child: heroCover,
                    ),
                    Positioned(
                      left: textLeft,
                      top: textTop,
                      width: textWidth,
                      height: textHeight,
                      child: textColumn,
                    ),
                    if (hasTrailing && gridMorph < 0.99)
                      Positioned(
                        right: listPadH,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
                          child: Center(child: trailing),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    final wrapped = isGridTarget
        ? HoverableCard(child: itemContent)
        : itemContent;

    return DraggableFolderItem(
      folder: folder,
      songsCount: songsCount,
      representativeSong: representativeSong,
      enabled: !isSelectionMode && !isSortMode,
      child: wrapped,
    );
  }
}
