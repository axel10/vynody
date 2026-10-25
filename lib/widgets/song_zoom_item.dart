import 'dart:io' show Platform;
import 'dart:math' as math;
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
import 'library_selection_scope.dart';

/// Unified song item widget that smoothly morphs between Compact List,
/// Standard List, Small Grid, and Large Grid based on [FolderZoomLayoutMetrics].
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
    this.customCover,
    this.showRemoteBadge = true,
    this.trailing,
    this.trailingWidth,
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

  /// Optional custom cover widget to override default [SongThumbnail.fromSong].
  final Widget? customCover;

  /// Whether to show the remote media badge (cloud icon) in the corner of the cover.
  final bool showRemoteBadge;

  /// Optional trailing widget in list mode (e.g. favorite button + context menu).
  final Widget? trailing;

  /// Width reserved for [trailing] in list mode. Defaults to 44.0.
  final double? trailingWidth;

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
    final gridMorph = metrics.gridMorph;
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

    // 封面
    final thumbnail = SongThumbnail.fromSong(
      song,
      size: 200,
      width: double.infinity,
      height: double.infinity,
    );

    final coverWidget = ExcludeSemantics(
      child: Opacity(
        opacity: isMissing ? 0.35 : 1.0,
        child: RemoteMediaBadge.wrapCover(
          showRemoteBadge: showRemoteBadge,
          fit: StackFit.expand,
          song: song,
          title: song.displayName,
          top: 4.0,
          right: 4.0,
          child: customCover ?? thumbnail,
        ),
      ),
    );

    final cover = ZoomItemCover(
      metrics: metrics,
      isSelected: effectiveSelected,
      isSelectionMode: effectiveSelectionMode,
      isHighlighted: isHighlighted,
      onToggleSelect: effectiveOnTap,
      child: coverWidget,
    );

    // 拖拽把手与末尾操作按钮
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
    } else if (trailing != null) {
      trailingWidget = trailing;
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

    // 字体样式与分档字号
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final gridFonts = folderGridFontSizes(metrics.targetCardWidth);
    final (double titleSize, double subSize, double infoSize) =
        switch (metrics.tier) {
      FolderZoomTier.minimalList =>
        isPortrait ? (13.5, 11.5, 11.0) : (14.0, 12.0, 12.0),
      FolderZoomTier.compactList =>
        isPortrait ? (14.0, 12.0, 11.0) : (14.5, 12.5, 12.0),
      FolderZoomTier.standardList =>
        isPortrait ? (14.0, 12.0, 11.0) : (15.5, 13.0, 13.0),
      FolderZoomTier.largeList =>
        isPortrait ? (15.5, 13.0, 11.5) : (16.5, 13.5, 13.5),
      FolderZoomTier.smallGrid ||
      FolderZoomTier.mediumGrid ||
      FolderZoomTier.largeGrid =>
        (gridFonts.title, gridFonts.subtitle, gridFonts.info),
    };

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

    final titleStyle = (!isGridTarget
            ? (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
                fontWeight: isCurrent && !isMissing
                    ? FontWeight.bold
                    : FontWeight.normal,
              )
            : ((isPortrait
                        ? theme.textTheme.titleSmall
                        : theme.textTheme.titleMedium) ??
                    const TextStyle())
                .copyWith(fontWeight: FontWeight.w600))
        .copyWith(
      color: titleColor,
      fontSize: titleSize,
      height: 1.25,
    );

    final subtitleStyle =
        (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: subSize,
      height: 1.2,
      color: subtitleColor,
    );

    final infoStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: infoSize,
      height: 1.2,
      color: infoColor,
    );

    final listCoverSize = getFolderListCoverSize(metrics.animatedZoomScale);
    final coverProgress = (listCoverSize / 40.0).clamp(0.0, 1.0);
    final selectionOffset = (effectiveSelectionMode && gridMorph < 0.5)
        ? (28.0 * (1.0 - coverProgress))
        : 0.0;

    final Widget? fallbackLeading = effectiveSelectionMode && gridMorph < 0.5
        ? Checkbox(
            value: effectiveSelected,
            onChanged: (_) => effectiveOnTap?.call(),
            fillColor: WidgetStateProperty.all(Colors.white),
            checkColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          )
        : null;

    final songContent = _SongZoomContent(
      metrics: metrics,
      song: song,
      isCurrent: isCurrent,
      isPlaying: isPlaying,
      isMissing: isMissing,
      artist: artist,
      album: album,
      artistAlbumText: artistAlbumText,
      trackStr: trackStr,
      durationStr: durationStr,
      formatStr: formatStr,
      durationFormatText: durationFormatText,
      titleStyle: titleStyle,
      subtitleStyle: subtitleStyle,
      infoStyle: infoStyle,
      titleSize: titleSize,
      subSize: subSize,
      infoSize: infoSize,
    );

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      cover: cover,
      textColumn: songContent,
      isSelected: effectiveSelected,
      isSelectionMode: effectiveSelectionMode,
      isHighlighted: isHighlighted,
      selectionOffset: selectionOffset,
      trailing: trailingWidget,
      trailingWidth: trailingWidth ?? (trailingWidget != null ? 44.0 : 0.0),
      fallbackLeadingWhenNoCover: fallbackLeading,
      onTap: effectiveOnTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
    );

    return DraggableSongItem(
      song: song,
      enabled: !isMissing && enableDrag,
      isSelected: effectiveSelected,
      isSelectionMode: effectiveSelectionMode,
      selectedPaths: selectedPaths,
      child: scaffold,
    );
  }
}

/// Dynamic content layout for [SongZoomItem], adapting between:
/// - Grid mode: 2~3 line caption below square cover.
/// - Portrait List mode: Smooth morph between Compact 2-line flex layout and Standard 3-line layout.
/// - Landscape List mode: Structured desktop multi-column table aligned to top headline baseline.
class _SongZoomContent extends StatelessWidget {
  const _SongZoomContent({
    required this.metrics,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.isMissing,
    required this.artist,
    required this.album,
    required this.artistAlbumText,
    required this.trackStr,
    required this.durationStr,
    required this.formatStr,
    required this.durationFormatText,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.infoStyle,
    required this.titleSize,
    required this.subSize,
    required this.infoSize,
  });

  final FolderZoomLayoutMetrics metrics;
  final MusicFile song;
  final bool isCurrent;
  final bool isPlaying;
  final bool isMissing;
  final String artist;
  final String album;
  final String artistAlbumText;
  final String? trackStr;
  final String durationStr;
  final String formatStr;
  final String durationFormatText;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final TextStyle infoStyle;
  final double titleSize;
  final double subSize;
  final double infoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final gridMorph = metrics.gridMorph;
    final compactMorph = metrics.compactMorph;

    final titleLineHeight = titleSize * 1.25;
    final subLineHeight = subSize * 1.2;
    final infoLineHeight = infoSize * 1.2;
    const titleSubGap = 2.0;
    final titleSubHeight = titleLineHeight + titleSubGap + subLineHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final W = constraints.maxWidth;
        final H = constraints.maxHeight;

        // 1. 网格模式布局（gridMorph -> 1.0 时展示）
        if (gridMorph >= 0.99) {
          return _buildGridCaption(theme, W);
        }

        // 2. 纯列表模式下
        if (gridMorph <= 0.01) {
          if (isPortrait) {
            return _buildPortraitList(theme, W, H, compactMorph, titleSubHeight);
          } else {
            return _buildLandscapeTable(
              theme,
              W,
              H,
              titleSubHeight,
              titleLineHeight,
              subLineHeight,
              infoLineHeight,
            );
          }
        }

        // 3. 正在发生 列表 <-> 网格 几何缩放动画
        return Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: (1.0 - gridMorph).clamp(0.0, 1.0),
              child: isPortrait
                  ? _buildPortraitList(theme, W, H, compactMorph, titleSubHeight)
                  : _buildLandscapeTable(
                      theme,
                      W,
                      H,
                      titleSubHeight,
                      titleLineHeight,
                      subLineHeight,
                      infoLineHeight,
                    ),
            ),
            Opacity(
              opacity: gridMorph.clamp(0.0, 1.0),
              child: _buildGridCaption(theme, W),
            ),
          ],
        );
      },
    );
  }

  /// Grid view caption below the square cover
  Widget _buildGridCaption(ThemeData theme, double W) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (isCurrent && !isMissing && W >= 40.0) ...[
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
                style: titleStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          artistAlbumText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
      ],
    );
  }

  /// Portrait list: Seamlessly switches between 2-line flex layout and 3-line layout
  Widget _buildPortraitList(
    ThemeData theme,
    double W,
    double H,
    double compactMorph,
    double titleSubHeight,
  ) {
    final showEqualizer = isCurrent && !isMissing;

    // A. 紧凑2行弹性布局（Minimal & Compact List）：左右两栏均在行高内垂直居中
    final compactLayout = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (showEqualizer) ...[
                    PlayingEqualizerIcon(
                      color: theme.colorScheme.primary,
                      size: 15,
                      isPlaying: isPlaying,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      song.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3.0),
              Text(
                artistAlbumText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subtitleStyle,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          durationFormatText,
          style: infoStyle.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
        ),
      ],
    );

    // B. 标准3行布局（Standard & Large List）
    final standardLayout = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (showEqualizer) ...[
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
                style: titleStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          artistAlbumText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: subtitleStyle,
        ),
        const SizedBox(height: 2.0),
        Text(
          durationFormatText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: infoStyle,
        ),
      ],
    );

    if (compactMorph >= 0.99) {
      return Center(child: compactLayout);
    }
    if (compactMorph <= 0.01) {
      return Center(child: standardLayout);
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: compactMorph.clamp(0.0, 1.0),
          child: Center(child: compactLayout),
        ),
        Opacity(
          opacity: (1.0 - compactMorph).clamp(0.0, 1.0),
          child: Center(child: standardLayout),
        ),
      ],
    );
  }

  /// Landscape desktop multi-column table: All primary information is aligned horizontally
  Widget _buildLandscapeTable(
    ThemeData theme,
    double W,
    double H,
    double titleSubHeight,
    double titleLineHeight,
    double subLineHeight,
    double infoLineHeight,
  ) {
    const durationColWidth = 56.0;
    const formatColWidth = 60.0;
    const trackColWidth = 36.0;
    const colGap = 16.0;

    final showEqualizer = isCurrent && !isMissing;

    // 计算各列的横向位置
    final rightEnd = W;
    final durationLeft = rightEnd - durationColWidth;
    final formatLeft = durationLeft - colGap - formatColWidth;
    final trackLeft = formatLeft - colGap - trackColWidth;
    final albumRight = trackLeft - colGap;

    final middleAvailable = math.max(0.0, albumRight);
    final double albumWidth;
    final double titleArtistWidth;

    if (middleAvailable > 320.0) {
      albumWidth = (middleAvailable * 0.35).clamp(120.0, 320.0);
      titleArtistWidth = math.max(0.0, middleAvailable - albumWidth - colGap);
    } else if (middleAvailable > 180.0) {
      albumWidth = (middleAvailable * 0.30).clamp(60.0, 120.0);
      titleArtistWidth = math.max(0.0, middleAvailable - albumWidth - 8.0);
    } else {
      albumWidth = 0.0;
      titleArtistWidth = middleAvailable;
    }

    final albumLeft = titleArtistWidth + colGap;

    // 垂直对齐核心：首行基准线对齐（各列主要信息与首行歌名在同一水平线上）
    final topBaseline = ((H - titleSubHeight) / 2.0).clamp(0.0, H);
    final secondLineTop = topBaseline + titleLineHeight + 2.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. 标题与艺术家列
        if (titleArtistWidth > 0) ...[
          // 首行：歌名（带播放图标）
          Positioned(
            left: 0.0,
            top: topBaseline,
            width: titleArtistWidth,
            height: titleLineHeight,
            child: Row(
              children: [
                if (showEqualizer && titleArtistWidth >= 40.0) ...[
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
                    style: titleStyle,
                  ),
                ),
              ],
            ),
          ),
          // 次行：艺术家
          Positioned(
            left: 0.0,
            top: secondLineTop,
            width: titleArtistWidth,
            height: subLineHeight,
            child: Text(
              artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ),
        ],

        // 2. 专辑列（垂直居中对齐）
        if (albumWidth > 20.0)
          Positioned(
            left: albumLeft,
            top: ((H - subLineHeight) / 2.0).clamp(0.0, H),
            width: albumWidth,
            height: subLineHeight,
            child: Text(
              album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle.copyWith(
                color: isMissing
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        // 3. 音轨号列（垂直居中对齐）
        Positioned(
          left: trackLeft,
          top: 0,
          bottom: 0,
          width: trackColWidth,
          child: Center(
            child: trackStr != null
                ? Text(
                    trackStr!,
                    style: infoStyle.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                  )
                : const SizedBox.shrink(),
          ),
        ),

        // 4. 格式列（徽章胶囊，垂直居中对齐）
        Positioned(
          left: formatLeft,
          top: 0,
          bottom: 0,
          width: formatColWidth,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                formatStr,
                style: infoStyle.copyWith(
                  fontSize: (infoSize - 1.0).clamp(10.0, 12.0),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),

        // 5. 时长列（右对齐，垂直居中对齐）
        Positioned(
          left: durationLeft,
          top: 0,
          bottom: 0,
          width: durationColWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              durationStr,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: infoStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
