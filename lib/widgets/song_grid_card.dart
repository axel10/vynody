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
import 'folder_grid_card.dart';
import 'folder_layout_utils.dart';
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
    final isWide = MediaQuery.of(context).size.width >= 780;

    final gridMorph = metrics.gridMorph;
    final compactMorph = metrics.compactMorph;
    final isGridTarget = metrics.isGridTarget;
    final isLargeGridTarget = metrics.isLargeGridTarget;

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

    final isDark = theme.brightness == Brightness.dark;
    final capsuleBgColor = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.75);
    final capsuleTextColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.9);

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
          if (gridMorph > 0.02)
            Positioned(
              left: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Opacity(
                  opacity: gridMorph.clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: capsuleBgColor,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.1),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      '$formatStr • $durationStr',
                      style: TextStyle(
                        fontSize: isLargeGridTarget ? 10.0 : 9.0,
                        fontWeight: FontWeight.bold,
                        color: capsuleTextColor,
                      ),
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

    final TextStyle titleStyle;
    final TextStyle subtitleStyle;
    if (!isGridTarget) {
      titleStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: titleColor,
        fontWeight:
            isCurrent && !isMissing ? FontWeight.bold : FontWeight.normal,
        height: 1.2,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: 12.0,
        height: 1.2,
        color: subtitleColor,
      );
    } else if (!isLargeGridTarget) {
      titleStyle = ((isPortrait
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.titleMedium) ??
              const TextStyle())
          .copyWith(
        fontWeight: FontWeight.w600,
        fontSize: isWide ? 13.0 : 12.5,
        color: titleColor,
        height: 1.25,
      );
      subtitleStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
        fontSize: 11.0,
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
        fontSize: isWide ? 14.5 : 14.0,
        color: titleColor,
        height: 1.25,
      );
      subtitleStyle = ((isPortrait
                  ? theme.textTheme.bodySmall
                  : theme.textTheme.bodyMedium) ??
              const TextStyle())
          .copyWith(
        fontSize: isWide ? 12.5 : 12.0,
        height: 1.2,
        color: subtitleColor,
      );
    }

    final infoStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: 11.0,
      height: 1.2,
      color: infoColor,
    );

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

                final hasTrailing = trailingWidget != null;
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
                final gridTextTop = gridCoverSize + 6.0;
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
                final titleRightPadding = lerpDouble(
                  lerpDouble(0.0, estimatedInfoWidth, compactMorph)!,
                  0.0,
                  gridMorph,
                )!;

                final titleAlignment = Alignment.lerp(
                  Alignment.lerp(
                    Alignment.topLeft,
                    Alignment.centerLeft,
                    compactMorph,
                  )!,
                  Alignment.topLeft,
                  gridMorph,
                )!;

                final infoAlignment = Alignment.lerp(
                  Alignment.bottomLeft,
                  Alignment.centerRight,
                  compactMorph,
                )!;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: coverLeft,
                      top: coverTop,
                      width: coverSize,
                      height: coverSize,
                      child: coverStack,
                    ),
                    Positioned(
                      left: textLeft,
                      top: textTop,
                      width: textWidth,
                      height: textHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Align(
                            alignment: titleAlignment,
                            child: Padding(
                              padding: EdgeInsets.only(
                                right: titleRightPadding,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      if (isCurrent && !isMissing) ...[
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
                                  const SizedBox(height: 2),
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
                          ),
                          if (gridMorph < 0.99)
                            Align(
                              alignment: infoAlignment,
                              child: Opacity(
                                opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
                                child: Text(
                                  durationFormatText,
                                  style: infoStyle,
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

/// Borderless song card for grid layouts, matching [AlbumGridCard] and
/// [FolderGridCard] so every grid in the app shares one typography rhythm.
class SongGridCard extends ConsumerWidget {
  const SongGridCard({
    super.key,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    this.isSelected,
    this.isSelectionMode,
    this.selectedPaths,
    this.isHighlighted = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  final MusicFile song;
  final bool isCurrent;
  final bool isPlaying;
  final bool? isSelected;
  final bool? isSelectionMode;
  final Iterable<String>? selectedPaths;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isWide = MediaQuery.of(context).size.width >= 780;

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

    // Resolve metadata (artist and album)
    final artist = metadata?.artist ?? song.artist ?? l10n.unknownArtist;
    final album = metadata?.album ?? song.album ?? l10n.unknownAlbum;
    final artistAlbumText = '$artist - $album';

    // Format duration and file format
    final durationStr = (metadata?.duration ?? song.durationMillis).toFormattedDuration();
    final ext = p.extension(song.path).replaceAll('.', '').toUpperCase();
    final formatStr = ext.isNotEmpty ? ext : 'UNKNOWN';

    final isDark = theme.brightness == Brightness.dark;
    final capsuleBgColor = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.75);
    final capsuleTextColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.9);

    final titleColor = isCurrent ? theme.colorScheme.primary : null;
    final coverRadius = BorderRadius.circular(12);

    final coverStack = ClipRRect(
      borderRadius: coverRadius,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Hero(
                tag: 'song-cover-${song.path}',
                child: RemoteMediaBadge.wrapCover(
                  child: SongThumbnail.fromSong(
                    song,
                    size: 200,
                    width: double.infinity,
                    height: double.infinity,
                    // Hero flights are painted outside the card's clip, so the
                    // artwork itself must carry the cover's corner radius.
                    borderRadius: coverRadius,
                  ),
                  song: song,
                  title: song.displayName,
                  top: 8,
                  right: 8,
                ),
              ),
            ),
            if (isHighlighted)
              Positioned.fill(
                child: IgnorePointer(
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
            if (effectiveSelectionMode)
              Positioned.fill(
                child: Container(
                  color: effectiveSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Colors.black26,
                ),
              ),
            if (effectiveSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: SizedBox(
                  width: 28,
                  height: 28,
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
            // Format / duration capsule in the bottom-left corner
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: capsuleBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '$formatStr • $durationStr',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: capsuleTextColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final card = MouseRegion(
      cursor: effectiveOnTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: effectiveOnTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            coverStack,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          PlayingEqualizerIcon(
                            color: theme.colorScheme.primary,
                            size: 16,
                            isPlaying: isPlaying,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            song.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (isPortrait
                                    ? theme.textTheme.titleSmall
                                    : theme.textTheme.titleMedium)
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: isWide ? 14.5 : 14.0,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artistAlbumText,
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

    return DraggableSongItem(
      song: song,
      enabled: true,
      isSelected: effectiveSelected,
      isSelectionMode: effectiveSelectionMode,
      selectedPaths: selectedPaths,
      child: card,
    );
  }
}
