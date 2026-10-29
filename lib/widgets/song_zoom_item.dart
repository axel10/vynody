import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show FontFeature, lerpDouble;
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

    // 字体样式与平滑字号
    final isPortrait = metrics.isPortrait;
    final titleSize = metrics.animatedTitleFontSize;
    final subSize = metrics.animatedSubtitleFontSize;
    final infoSize = metrics.animatedInfoFontSize;

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

    final scaffold = ZoomItemScaffold(
      metrics: metrics,
      cover: cover,
      textColumnBuilder: (context, textWidth, textHeight) => _SongZoomContent(
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
        width: textWidth,
        height: textHeight,
      ),
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
    this.width,
    this.height,
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
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (width != null && height != null) {
      return _buildContent(context, width!, height!);
    }
    return LayoutBuilder(
      builder: (context, constraints) => _buildContent(
        context,
        constraints.maxWidth,
        constraints.maxHeight,
      ),
    );
  }

  Widget _buildContent(BuildContext context, double W, double H) {
    final theme = Theme.of(context);
    final effectiveMetrics =
        ZoomItemEffectiveMetrics.maybeOf(context) ?? metrics;
    final isPortrait = effectiveMetrics.isPortrait;
    final compactMorph = effectiveMetrics.compactMorph;

    final effTitleStyle = identical(effectiveMetrics, metrics)
        ? titleStyle
        : titleStyle.copyWith(fontSize: effectiveMetrics.animatedTitleFontSize);
    final effSubtitleStyle = identical(effectiveMetrics, metrics)
        ? subtitleStyle
        : subtitleStyle.copyWith(
            fontSize: effectiveMetrics.animatedSubtitleFontSize,
          );
    final effInfoStyle = identical(effectiveMetrics, metrics)
        ? infoStyle
        : infoStyle.copyWith(fontSize: effectiveMetrics.animatedInfoFontSize);
    final effInfoSize = effectiveMetrics.animatedInfoFontSize;

    final titleLineHeight = effectiveMetrics.animatedTitleFontSize * 1.25;
    final subLineHeight = effectiveMetrics.animatedSubtitleFontSize * 1.2;
    final infoLineHeight = effectiveMetrics.animatedInfoFontSize * 1.2;
    const titleSubGap = 2.0;
    final titleSubHeight = titleLineHeight + titleSubGap + subLineHeight;

    // 任意时刻只构建当前侧的一份。
    //
    // 屏外条目本来就由 sliver 懒构建挡掉了，真正白花的是视口与 cacheExtent
    // 里那批：以前跨「网格 ↔ 列表」时两套布局同时存在、双层 Opacity 交叉
    // 淡化，每个可见条目每帧要排两份文字、做两次 saveLayer，且整段跟手
    // 手势期间一直持续。现在两套布局在交接点（metrics.contentIsGrid，按
    // 滞回翻转）直接互换，`contentReveal` 在交接点附近压暗盖住突变。
    final Widget content;
    if (effectiveMetrics.renderAsGrid) {
      content = _buildGridCaption(theme, W, effTitleStyle, effSubtitleStyle);
    } else if (isPortrait) {
      content = _buildPortraitList(
        context: context,
        theme: theme,
        W: W,
        H: H,
        compactMorph: compactMorph,
        titleLineHeight: titleLineHeight,
        subLineHeight: subLineHeight,
        infoLineHeight: infoLineHeight,
        effTitleStyle: effTitleStyle,
        effSubtitleStyle: effSubtitleStyle,
        effInfoStyle: effInfoStyle,
      );
    } else {
      content = _buildLandscapeTable(
        theme,
        W,
        H,
        titleSubHeight,
        titleLineHeight,
        subLineHeight,
        infoLineHeight,
        effTitleStyle,
        effSubtitleStyle,
        effInfoStyle,
        effInfoSize,
      );
    }

    final double reveal = effectiveMetrics.contentReveal;
    // 只有交接点附近才 < 1；其余时间不套 Opacity，省掉整条的一层合成。
    if (reveal >= 0.999) return content;
    return Opacity(opacity: reveal, child: content);
  }

  /// Grid view caption below the square cover
  Widget _buildGridCaption(
    ThemeData theme,
    double W,
    TextStyle effTitleStyle,
    TextStyle effSubtitleStyle,
  ) {
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
                style: effTitleStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.0),
        Text(
          artistAlbumText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: effSubtitleStyle,
        ),
      ],
    );
  }

  /// Portrait list: Seamlessly translates and morphs between 2-line compact layout and 3-line standard layout
  Widget _buildPortraitList({
    required BuildContext context,
    required ThemeData theme,
    required double W,
    required double H,
    required double compactMorph,
    required double titleLineHeight,
    required double subLineHeight,
    required double infoLineHeight,
    required TextStyle effTitleStyle,
    required TextStyle effSubtitleStyle,
    required TextStyle effInfoStyle,
  }) {
    final showEqualizer = isCurrent && !isMissing;
    final t = (1.0 - compactMorph).clamp(0.0, 1.0); // 0.0 = Compact, 1.0 = Standard

    // 测量紧凑模式下音频信息的宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: durationFormatText,
        style: effInfoStyle.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    final measuredInfoWidth = (textPainter.width + 2.0).ceilToDouble();
    final compactInfoWidth =
        math.min(measuredInfoWidth, math.max(0.0, W * 0.45));
    final compactTitleWidth =
        math.max(0.0, W - compactInfoWidth - 12.0);

    // 1. 紧凑模式坐标（2行文本，音频信息右侧垂直居中）
    const compactSubGap = 3.0;
    final compactBlockHeight = titleLineHeight + compactSubGap + subLineHeight;
    final compactTitleTop =
        ((H - compactBlockHeight) / 2.0).clamp(0.0, H);
    final compactInfoTop = ((H - infoLineHeight) / 2.0).clamp(0.0, H);
    final compactInfoLeft = math.max(0.0, W - compactInfoWidth);

    // 2. 标准模式坐标（3行文本，音频信息在第3行）
    const standardGap = 2.0;
    final standardBlockHeight =
        titleLineHeight + standardGap + subLineHeight + standardGap + infoLineHeight;
    final standardTitleTop =
        ((H - standardBlockHeight) / 2.0).clamp(0.0, H);
    final standardSubTop = standardTitleTop + titleLineHeight + standardGap;
    final standardInfoTop = standardSubTop + subLineHeight + standardGap;

    // 3. 动力学位移插值：
    // y 轴先向下滑出第 2 行区域（yt 提前完成），x 轴沿第 3 行横向滑入左侧（xt 紧随其后），
    // 保证过渡期间平滑位移且避免斜穿第 2 行副标题造成文字视觉重叠。
    final yt = math.pow(t, 0.5).toDouble();
    final xt = math.pow(t, 1.8).toDouble();

    final titleTop = lerpDouble(compactTitleTop, standardTitleTop, t)!;
    final titleWidth = lerpDouble(compactTitleWidth, W, yt)!;
    final subGap = lerpDouble(compactSubGap, standardGap, t)!;
    final subTop = titleTop + titleLineHeight + subGap;
    final subWidth = titleWidth;

    final infoTop = lerpDouble(compactInfoTop, standardInfoTop, yt)!;
    final infoLeft = lerpDouble(compactInfoLeft, 0.0, xt)!;
    final infoWidth = math.max(compactInfoWidth, W - infoLeft);

    final eqSize = lerpDouble(15.0, 16.0, t)!;
    final eqGap = lerpDouble(5.0, 6.0, t)!;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. 标题行（歌名 + 播放均衡器）
        Positioned(
          left: 0.0,
          top: titleTop,
          width: titleWidth,
          height: titleLineHeight,
          child: Row(
            children: [
              if (showEqualizer && titleWidth >= 40.0) ...[
                PlayingEqualizerIcon(
                  color: theme.colorScheme.primary,
                  size: eqSize,
                  isPlaying: isPlaying,
                ),
                SizedBox(width: eqGap),
              ],
              Expanded(
                child: Text(
                  song.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: effTitleStyle,
                ),
              ),
            ],
          ),
        ),

        // 2. 副标题行（艺术家与专辑）
        Positioned(
          left: 0.0,
          top: subTop,
          width: subWidth,
          height: subLineHeight,
          child: Text(
            artistAlbumText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: effSubtitleStyle,
          ),
        ),

        // 3. 音频信息行（音轨 | 时长 | 格式）：从右侧垂直居中连续平移到左下角第 3 行
        Positioned(
          left: infoLeft,
          top: infoTop,
          width: infoWidth,
          height: infoLineHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              durationFormatText,
              style: effInfoStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
    TextStyle effTitleStyle,
    TextStyle effSubtitleStyle,
    TextStyle effInfoStyle,
    double effInfoSize,
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
                    style: effTitleStyle,
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
              style: effSubtitleStyle,
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
              style: effSubtitleStyle.copyWith(
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
                    style: effInfoStyle.copyWith(
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
                style: effInfoStyle.copyWith(
                  fontSize: (effInfoSize - 1.0).clamp(10.0, 12.0),
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
              style: effInfoStyle.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
