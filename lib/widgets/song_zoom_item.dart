import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/music_file.dart';
import '../l10n/app_localizations.dart';
import '../utils/time_format_utils.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/playing_equalizer_icon.dart';
import '../player/audio/audio_riverpod.dart';
import 'remote_media_badge.dart';
import 'draggable_song_item.dart';
import 'folder_layout_utils.dart';
import 'hoverable_card.dart';
import 'library_selection_scope.dart';

/// Unified song item widget that smoothly morphs between Compact List (`< 0.25`),
/// Standard List (`0.25 .. < 0.50`), Small Grid (`0.50 .. < 0.75`), and Large Grid (`>= 0.75`)
/// based on [FolderZoomLayoutMetrics].
class SongZoomItem extends ConsumerWidget {
  const SongZoomItem({
    super.key,
    required this.song,
    required this.metrics,
    required this.isCurrent,
    required this.isPlaying,
    this.isSelected,
    this.isSelectionMode,
    this.selectedPaths,
    this.isHighlighted = false,
    this.dragHandle,
    this.enableDrag = true,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onMorePressed,
  });

  final MusicFile song;
  final FolderZoomLayoutMetrics metrics;
  final bool isCurrent;
  final bool isPlaying;
  final bool? isSelected;
  final bool? isSelectionMode;
  final Iterable<String>? selectedPaths;
  final bool isHighlighted;
  final Widget? dragHandle;
  final bool enableDrag;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final void Function(BuildContext context)? onMorePressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final gridMorph = metrics.gridMorph;
    final compactMorph = metrics.compactMorph;
    final isGridTarget = metrics.isGridTarget;

    final isGlobalSelectionActive = ref.watch(
      librarySelectionStateProvider.select(
        (s) => s.isActive && s.scope != LibrarySelectionScope.none,
      ),
    );
    final isGlobalSongSelected = isGlobalSelectionActive
        ? ref.watch(
            librarySelectionStateProvider.select(
              (s) => s.selectedKeys.contains(song.path),
            ),
          )
        : false;

    final effectiveSelectionMode = isSelectionMode ?? isGlobalSelectionActive;
    final effectiveSelected = isSelected ??
        selectedPaths?.contains(song.path) ??
        isGlobalSongSelected;

    VoidCallback? effectiveOnTap = onTap;
    if (effectiveOnTap == null && effectiveSelectionMode) {
      effectiveOnTap = () {
        ref.read(librarySelectionStateProvider.notifier).toggle(song.path);
      };
    }

    final metadata = ref.watch(
      scannerServiceProvider.select((s) => s.metadataMap[song.path]),
    );

    final isMissing = song.isMissing;
    final artist = metadata?.artist ?? song.artist ?? l10n.unknownArtist;
    final album = metadata?.album ?? song.album ?? l10n.unknownAlbum;
    final artistAlbumText = '$artist - $album';

    final trackNumber = metadata?.trackNumber ?? song.trackNumber;
    final trackStr = (trackNumber != null && trackNumber > 0)
        ? trackNumber.toString().padLeft(2, '0')
        : null;
    final durationStr =
        (metadata?.duration ?? song.durationMillis).toFormattedDuration();
    final ext = p.extension(song.path).replaceAll('.', '').toUpperCase();
    final formatStr = ext.isNotEmpty ? ext : 'UNKNOWN';
    final durationFormatText = [
      ?trackStr,
      durationStr,
      formatStr,
    ].join(' | ');

    final coverRadiusValue = lerpDouble(8.0, 12.0, gridMorph)!;
    final coverRadius = BorderRadius.circular(coverRadiusValue);

    final coverStack = ClipRRect(
      borderRadius: coverRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: Opacity(
              opacity: isMissing ? 0.35 : 1.0,
              child: Hero(
                tag: 'song-cover-${song.path}',
                child: RemoteMediaBadge.wrapCover(
                  child: SongThumbnail.fromSong(
                    song,
                    size: 200,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: coverRadius,
                  ),
                  song: song,
                  title: song.displayName,
                  top: lerpDouble(4.0, 8.0, gridMorph)!,
                  right: lerpDouble(4.0, 8.0, gridMorph)!,
                ),
              ),
            ),
          ),
          if (isHighlighted && gridMorph > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: gridMorph.clamp(0.0, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: coverRadius,
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (effectiveSelectionMode)
            Positioned.fill(
              child: Container(
                color: effectiveSelected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                    : Colors.black26,
              ),
            ),
          if (effectiveSelectionMode)
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
                    value: effectiveSelected,
                    onChanged: (_) => effectiveOnTap?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    Widget? trailingWidget;
    if (effectiveSelectionMode) {
      if (dragHandle != null) {
        trailingWidget = IconTheme(
          data: theme.iconTheme.copyWith(
            color: isCurrent && !isMissing
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          child: dragHandle!,
        );
      }
    } else if (isDesktop) {
      if (dragHandle != null) {
        trailingWidget = IconTheme(
          data: theme.iconTheme.copyWith(
            color: isCurrent && !isMissing
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          child: dragHandle!,
        );
      }
    } else if (onMorePressed != null) {
      trailingWidget = Builder(
        builder: (buttonContext) {
          return IconButton(
            icon: Icon(
              Icons.more_vert_rounded,
              size: 20,
              color:
                  isCurrent && !isMissing ? theme.colorScheme.primary : null,
            ),
            onPressed: () => onMorePressed!(buttonContext),
          );
        },
      );
    }

    // Discrete typography tiers
    final titleColor = isMissing
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : isCurrent
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;
    final subtitleColor = isMissing
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : isCurrent && !isGridTarget
            ? theme.colorScheme.primary.withValues(alpha: 0.8)
            : theme.colorScheme.onSurfaceVariant;
    final infoColor = isMissing
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
        : isCurrent
            ? theme.colorScheme.primary.withValues(alpha: 0.6)
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7);

    // 网格档位的字号按**卡片宽度**分档（不是屏幕宽度）；列表档位与宽度无关。
    final gridFonts = folderGridFontSizes(metrics.targetCardWidth);
    final (double titleSize, double subSize, double infoSize) =
        switch (metrics.tier) {
      FolderZoomTier.minimalList => (13.5, 11.5, 11.0),
      FolderZoomTier.compactList => (14.0, 12.0, 11.0),
      FolderZoomTier.standardList => (14.0, 12.0, 11.0),
      FolderZoomTier.largeList => (15.5, 13.0, 11.5),
      FolderZoomTier.smallGrid ||
      FolderZoomTier.mediumGrid ||
      FolderZoomTier.largeGrid =>
        (gridFonts.title, gridFonts.subtitle, gridFonts.info),
    };

    final TextStyle titleStyle;
    final TextStyle subtitleStyle;
    if (!isGridTarget) {
      titleStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: titleColor,
        fontWeight:
            isCurrent && !isMissing ? FontWeight.bold : FontWeight.normal,
        fontSize: titleSize,
        height: 1.25,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: subSize,
        height: 1.2,
        color: subtitleColor,
      );
    } else {
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
        height: 1.2,
        color: subtitleColor,
      );
    }

    final infoStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: infoSize,
      height: 1.2,
      color: infoColor,
    );

    final titleLineHeight = titleSize * 1.25;
    final subLineHeight = subSize * 1.2;
    final infoLineHeight = infoSize * 1.2;
    const titleSubGap = 2.0;
    const subInfoGap = 2.0;
    final titleSubHeight = titleLineHeight + titleSubGap + subLineHeight;
    final totalCombinedHeight = titleSubHeight + subInfoGap + infoLineHeight;

    final listBgAlpha = (1.0 - gridMorph).clamp(0.0, 1.0);
    final Color itemBgColor;
    if (listBgAlpha > 0.01 && effectiveSelectionMode && effectiveSelected) {
      itemBgColor = theme.colorScheme.primaryContainer
          .withValues(alpha: 0.35 * listBgAlpha);
    } else if (listBgAlpha > 0.01 && isHighlighted) {
      itemBgColor =
          theme.colorScheme.primary.withValues(alpha: 0.2 * listBgAlpha);
    } else {
      itemBgColor = Colors.transparent;
    }

    final content = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: itemBgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            enableFeedback: false,
            onTap: effectiveOnTap,
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
                ).clamp(0.0, math.max(0.0, H - 8.0));
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

                final hasTrailing = trailingWidget != null;
                final trailingSpace =
                    hasTrailing ? lerpDouble(44.0, 0.0, gridMorph)! : 0.0;

                final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
                final listCoverGap = 16.0 * coverProgress;
                final selectionOffset = (effectiveSelectionMode && gridMorph < 0.5)
                    ? (28.0 * (1.0 - coverProgress))
                    : 0.0;

                final listTextLeft =
                    listCoverLeft + listCoverSize + listCoverGap + selectionOffset;
                final listTextHeight =
                    math.max(listCoverSize, math.max(0.0, H - 8.0));
                final listTextTop = ((H - listTextHeight) / 2.0).clamp(0.0, H);
                final listTextWidth = math.max(
                  0.0,
                  W - listTextLeft - listPadH - trailingSpace,
                );

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

                // Reserve space on the right when in Compact List mode (`compactMorph -> 1.0`)
                final estimatedInfoWidth =
                    (durationFormatText.length * 6.2 + 12.0).clamp(
                  68.0,
                  math.max(68.0, textWidth * 0.45),
                );

                final titleTopStandard =
                    (textHeight - totalCombinedHeight) / 2.0;
                final titleTopCompact = (textHeight - titleSubHeight) / 2.0;

                final currentTitleTop = lerpDouble(
                  lerpDouble(titleTopStandard, titleTopCompact, compactMorph)!,
                  titleTopStandard,
                  gridMorph,
                )!;

                final currentTitleRightPadding = lerpDouble(
                  lerpDouble(0.0, estimatedInfoWidth + 8.0, compactMorph)!,
                  0.0,
                  gridMorph,
                )!;

                final infoTopStandard =
                    currentTitleTop + titleSubHeight + subInfoGap;
                final infoTopCompact = (textHeight - infoLineHeight) / 2.0;

                final targetInfoTop = lerpDouble(
                  lerpDouble(infoTopStandard, infoTopCompact, compactMorph)!,
                  infoTopStandard,
                  gridMorph,
                )!;

                final targetInfoLeft = lerpDouble(
                  lerpDouble(
                    0.0,
                    textWidth - estimatedInfoWidth,
                    compactMorph,
                  )!,
                  0.0,
                  gridMorph,
                )!;

                final targetInfoWidth = lerpDouble(
                  lerpDouble(textWidth, estimatedInfoWidth, compactMorph)!,
                  textWidth,
                  gridMorph,
                )!;

                final targetTextAlign =
                    compactMorph > 0.6 ? TextAlign.right : TextAlign.left;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (coverSize > 0.5)
                      Positioned(
                        left: coverLeft,
                        top: coverTop,
                        width: coverSize,
                        height: coverSize,
                        child: coverStack,
                      )
                    else if (effectiveSelectionMode && gridMorph < 0.5)
                      Positioned(
                        left: listCoverLeft,
                        top: ((H - 24.0) / 2.0).clamp(0.0, H),
                        width: 24.0,
                        height: 24.0,
                        child: Checkbox(
                          value: effectiveSelected,
                          onChanged: (_) => effectiveOnTap?.call(),
                          fillColor: WidgetStateProperty.all(Colors.white),
                          checkColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    Positioned(
                      left: textLeft,
                      top: textTop,
                      width: textWidth,
                      height: textHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: 0.0,
                            top: currentTitleTop,
                            width: math.max(
                              0.0,
                              textWidth - currentTitleRightPadding,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    if (isCurrent && !isMissing && textWidth >= 40.0) ...[
                                      PlayingEqualizerIcon(
                                        color: theme.colorScheme.primary,
                                        size: 16,
                                        isPlaying: isPlaying,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: AnimatedDefaultTextStyle(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        style: titleStyle,
                                        child: Text(
                                          song.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: titleSubGap),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  style: subtitleStyle,
                                  child: Text(
                                    artistAlbumText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            left: targetInfoLeft.clamp(0.0, textWidth),
                            top: targetInfoTop,
                            width: targetInfoWidth.clamp(0.0, textWidth),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              style: infoStyle,
                              textAlign: targetTextAlign,
                              child: Text(
                                durationFormatText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasTrailing && gridMorph < 0.99)
                      Positioned(
                        right: listPadH,
                        top: 0,
                        bottom: 0,
                        child: Opacity(
                          opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
                          child: Center(child: trailingWidget),
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
        ? HoverableCard(child: content)
        : content;

    return DraggableSongItem(
      song: song,
      enabled: !isMissing && enableDrag,
      isSelected: effectiveSelected,
      isSelectionMode: effectiveSelectionMode,
      selectedPaths: selectedPaths,
      child: wrapped,
    );
  }
}
