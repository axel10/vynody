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
    this.index,
    this.section,
  });

  final MusicFile song;
  final FolderZoomLayoutMetrics metrics;
  final int? index;

  /// 本条目所属的网格段，必须与 `SliverAnimatedZoomGridDelegate.section` 一致。
  ///
  /// 一页里只有一个网格时留空即可；一页挂多个网格（目录 + 歌曲）时，冻结的
  /// 「单侧可见条目」表按段分开，索引才对得上。
  final Object? section;
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
    // 远程曲目的 path 是虚拟 URI（subsonic://<server>/<id>、jellyfin://…），
    // 不带扩展名；真实后缀在 name 里（`<title>.<suffix>`）。两者都取不到就当作
    // 未知，直接把格式这一段以及横屏表格的格式列整列去掉，不要显示 UNKNOWN。
    final pathExt = _fileExtensionOf(song.path);
    final ext = pathExt.isNotEmpty ? pathExt : _fileExtensionOf(song.name);
    final formatStr = ext.isEmpty ? null : ext.toUpperCase();
    final durationFormatText = [
      ?trackStr,
      durationStr,
      ?formatStr,
    ].join(' | ');

    // 封面
    final thumbnail = SongThumbnail.fromSong(
      song,
      size: zoomItemThumbnailSizeFor(metrics),
      width: double.infinity,
      height: double.infinity,
      borderRadius: BorderRadius.zero,
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

    // 拖拽把手与行尾内容
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
    }

    // 字体样式与平滑字号：
    // 统一使用插件提供的锁定整数字号（render*FontSize），避免过渡期每帧改字号
    // 触发底层文字引擎重建字形图集（CreateGlyphAtlas）；视觉上的连续字号缩放由
    // ZoomItemScaffold 内的 ZoomScaledTextBox 在 GPU 矩阵层平滑完成。
    final isPortrait = metrics.isPortrait;
    final titleSize = metrics.renderTitleFontSize;
    final subSize = metrics.renderSubtitleFontSize;
    final infoSize = metrics.renderInfoFontSize;

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
      index: index,
      section: section,
      cover: cover,
      textColumn: _SongZoomContent(
        metrics: metrics,
        childIndex: index,
        section: section,
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

    final String songA11yLabel = [
      ?trackStr,
      song.displayName,
      artistAlbumText,
      durationStr,
    ].join(', ');

    return Semantics(
      container: true,
      button: true,
      label: songA11yLabel,
      selected: effectiveSelectionMode ? effectiveSelected : null,
      enabled: !isMissing,
      child: ExcludeSemantics(
        child: DraggableSongItem(
          song: song,
          enabled: !isMissing && enableDrag,
          isSelected: effectiveSelected,
          isSelectionMode: effectiveSelectionMode,
          selectedPaths: selectedPaths,
          child: scaffold,
        ),
      ),
    );
  }
}

FolderZoomLayoutMetrics _resolveLiveSongMetrics({
  required FolderZoomLayoutMetrics fallback,
  required ZoomTransitionListenable? listenable,
  required int? childIndex,
  required Object? section,
}) {
  final live = listenable?.metrics;
  if (live == null) return fallback;
  if (childIndex != null) {
    return live
        .resolveItemTransition(childIndex, section: section)
        .effectiveMetrics;
  }
  // 无显式索引时（老调用点走 ZoomItemScaffold 的 LayoutBuilder 回退路径），
  // 单侧条目已由 ZoomItemEffectiveMetrics 锁定为稳态端点度量，不可被全局 live 覆盖。
  if (!fallback.isTransitioning && live.isTransitioning) {
    return fallback;
  }
  return live;
}

/// 竖屏列表第三行音频信息在翻面阈值前的淡出系数（与插件 `_morphingInfoFade` 同口径）。
double _songPortraitInfoFade(double gridMorph) {
  if (gridMorph <= 0.001) return 1.0;
  return (1.0 - gridMorph / kFolderZoomContentHandoffLower).clamp(0.0, 1.0);
}

/// 横屏列表附加列（专辑/音轨/格式/时长）先在 `g ∈ [0, 0.35]` 淡出至不可见，
/// 随后 `g ∈ [0.35, 0.45]` 标题列平滑展开至全宽，避免文字重叠并在翻面帧无缝衔接网格态。
const double _kLandscapeExtraFadeEnd = 0.35;

double _songLandscapeExtraFade(double gridMorph) {
  if (gridMorph <= 0.001) return 1.0;
  return (1.0 - gridMorph / _kLandscapeExtraFadeEnd).clamp(0.0, 1.0);
}

double _songLandscapeTitleExpand(double gridMorph) {
  if (gridMorph <= _kLandscapeExtraFadeEnd) return 0.0;
  final span = kFolderZoomContentHandoffLower - _kLandscapeExtraFadeEnd;
  if (span <= 0.0) return 1.0;
  return ((gridMorph - _kLandscapeExtraFadeEnd) / span).clamp(0.0, 1.0);
}

/// Dynamic content layout for [SongZoomItem], adapting between:
/// - Grid mode: 2-line caption below square cover.
/// - Portrait List mode: Smooth morph between Compact 2-line flex layout and Standard 3-line layout.
/// - Landscape List mode: Structured desktop multi-column table aligned to top headline baseline.
class _SongZoomContent extends StatelessWidget {
  const _SongZoomContent({
    required this.metrics,
    required this.childIndex,
    required this.section,
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
  });

  final FolderZoomLayoutMetrics metrics;
  final int? childIndex;
  final Object? section;
  final MusicFile song;
  final bool isCurrent;
  final bool isPlaying;
  final bool isMissing;
  final String artist;
  final String album;
  final String artistAlbumText;
  final String? trackStr;
  final String durationStr;
  final String? formatStr;
  final String durationFormatText;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final TextStyle infoStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveMetrics =
        ZoomItemEffectiveMetrics.maybeOf(context) ?? metrics;
    final itemScope = (childIndex == null || section == null)
        ? ZoomableSliverItemScope.maybeOf(context)
        : null;
    final int? resolvedIndex = childIndex ?? itemScope?.index;
    final Object? resolvedSection = section ?? itemScope?.section;
    final listenable = ZoomTransitionScope.maybeListenableOf(context);
    final isPortrait = effectiveMetrics.isPortrait;

    // 统一使用锁定渲染字号（render*FontSize），避免与外层 ZoomScaledTextBox 脱节或行高偏小。
    final effTitleFontSize = effectiveMetrics.renderTitleFontSize;
    final effSubFontSize = effectiveMetrics.renderSubtitleFontSize;
    final effInfoFontSize = effectiveMetrics.renderInfoFontSize;

    final effTitleStyle = identical(effectiveMetrics, metrics)
        ? titleStyle
        : titleStyle.copyWith(fontSize: effTitleFontSize);
    final effSubtitleStyle = identical(effectiveMetrics, metrics)
        ? subtitleStyle
        : subtitleStyle.copyWith(fontSize: effSubFontSize);
    final effInfoStyle = identical(effectiveMetrics, metrics)
        ? infoStyle
        : infoStyle.copyWith(fontSize: effInfoFontSize);

    final textScaler = MediaQuery.textScalerOf(context);
    final titleLineHeight = textScaler.scale(effTitleFontSize) * 1.25;
    final subLineHeight = textScaler.scale(effSubFontSize) * 1.2;
    final infoLineHeight = textScaler.scale(effInfoFontSize) * 1.2;
    const titleSubGap = 2.0;
    final titleSubHeight = titleLineHeight + titleSubGap + subLineHeight;

    // 任意时刻只构建当前侧的一份，且不再用 contentReveal 把共同可见条目的整块文字压暗至透明：
    // 列表与网格两侧均通过 ZoomTransitionListenable 在 RenderObject 布局阶段按实时 gridMorph
    // 连续插值对齐方式，并在翻面阈值前提前淡出仅列表侧可见的附加信息，使翻面帧前后无缝衔接。
    if (effectiveMetrics.renderAsGrid) {
      return _buildGridCaption(
        theme: theme,
        effectiveMetrics: effectiveMetrics,
        titleLineHeight: titleLineHeight,
        subLineHeight: subLineHeight,
        effTitleStyle: effTitleStyle,
        effSubtitleStyle: effSubtitleStyle,
        listenable: listenable,
        resolvedIndex: resolvedIndex,
        resolvedSection: resolvedSection,
      );
    }
    if (isPortrait) {
      return _buildPortraitList(
        context: context,
        theme: theme,
        effectiveMetrics: effectiveMetrics,
        titleLineHeight: titleLineHeight,
        subLineHeight: subLineHeight,
        infoLineHeight: infoLineHeight,
        effTitleStyle: effTitleStyle,
        effSubtitleStyle: effSubtitleStyle,
        effInfoStyle: effInfoStyle,
        listenable: listenable,
        resolvedIndex: resolvedIndex,
        resolvedSection: resolvedSection,
      );
    }
    return _buildLandscapeTable(
      theme: theme,
      effectiveMetrics: effectiveMetrics,
      titleSubHeight: titleSubHeight,
      titleLineHeight: titleLineHeight,
      subLineHeight: subLineHeight,
      effTitleStyle: effTitleStyle,
      effSubtitleStyle: effSubtitleStyle,
      effInfoStyle: effInfoStyle,
      effInfoSize: effInfoFontSize,
      listenable: listenable,
      resolvedIndex: resolvedIndex,
      resolvedSection: resolvedSection,
    );
  }

  Widget _buildTitleLine({
    required ThemeData theme,
    required TextStyle style,
    double eqSize = 16.0,
    double eqGap = 6.0,
  }) {
    final titleText = Text(
      song.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (!isCurrent || isMissing) {
      return titleText;
    }
    return _SongTitleWithEqualizer(
      equalizer: PlayingEqualizerIcon(
        color: theme.colorScheme.primary,
        size: eqSize,
        isPlaying: isPlaying,
      ),
      eqSize: eqSize,
      eqGap: eqGap,
      title: titleText,
    );
  }

  /// Grid view caption below the square cover, aligned continuously with list side via [gridMorph].
  Widget _buildGridCaption({
    required ThemeData theme,
    required FolderZoomLayoutMetrics effectiveMetrics,
    required double titleLineHeight,
    required double subLineHeight,
    required TextStyle effTitleStyle,
    required TextStyle effSubtitleStyle,
    required ZoomTransitionListenable? listenable,
    required int? resolvedIndex,
    required Object? resolvedSection,
  }) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: titleLineHeight,
          child: _buildTitleLine(theme: theme, style: effTitleStyle),
        ),
        const SizedBox(height: 2.0),
        SizedBox(
          height: subLineHeight,
          child: Text(
            artistAlbumText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: effSubtitleStyle,
          ),
        ),
      ],
    );

    return CustomSingleChildLayout(
      delegate: _SongGridAlignLayoutDelegate(
        metrics: effectiveMetrics,
        listenable: listenable,
        childIndex: resolvedIndex,
        section: resolvedSection,
      ),
      child: column,
    );
  }

  /// Portrait list: Seamlessly translates and morphs between 2-line compact layout and 3-line standard layout.
  Widget _buildPortraitList({
    required BuildContext context,
    required ThemeData theme,
    required FolderZoomLayoutMetrics effectiveMetrics,
    required double titleLineHeight,
    required double subLineHeight,
    required double infoLineHeight,
    required TextStyle effTitleStyle,
    required TextStyle effSubtitleStyle,
    required TextStyle effInfoStyle,
    required ZoomTransitionListenable? listenable,
    required int? resolvedIndex,
    required Object? resolvedSection,
  }) {
    final t = (1.0 - effectiveMetrics.compactMorph).clamp(0.0, 1.0);
    final bool needsCompactMeasure = t < 1.0 ||
        (effectiveMetrics.startEndpointMetrics?.compactMorph ?? 0.0) > 0.0 ||
        (effectiveMetrics.targetEndpointMetrics?.compactMorph ?? 0.0) > 0.0;

    final double measuredInfoWidth = !needsCompactMeasure
        ? 0.0
        : _measureInfoWidth(
            durationFormatText,
            effInfoStyle,
            Directionality.of(context),
          );

    final eqSize = lerpDouble(15.0, 16.0, t)!;
    final eqGap = lerpDouble(5.0, 6.0, t)!;

    final titleChild = _buildTitleLine(
      theme: theme,
      style: effTitleStyle,
      eqSize: eqSize,
      eqGap: eqGap,
    );

    final subtitleChild = Text(
      artistAlbumText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: effSubtitleStyle,
    );

    final rawInfoChild = Align(
      alignment: Alignment.centerLeft,
      child: Text(
        durationFormatText,
        style: effInfoStyle.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    final Widget infoChild;
    if (listenable != null) {
      infoChild = AnimatedBuilder(
        animation: listenable,
        child: rawInfoChild,
        builder: (context, cachedChild) {
          final active = _resolveLiveSongMetrics(
            fallback: effectiveMetrics,
            listenable: listenable,
            childIndex: resolvedIndex,
            section: resolvedSection,
          );
          final double opacity = _songPortraitInfoFade(active.gridMorph);
          return Opacity(opacity: opacity, child: cachedChild);
        },
      );
    } else {
      final double opacity = _songPortraitInfoFade(effectiveMetrics.gridMorph);
      infoChild = opacity >= 0.999
          ? rawInfoChild
          : Opacity(opacity: opacity, child: rawInfoChild);
    }

    return CustomMultiChildLayout(
      delegate: _PortraitSongListLayoutDelegate(
        metrics: effectiveMetrics,
        titleLineHeight: titleLineHeight,
        subLineHeight: subLineHeight,
        infoLineHeight: infoLineHeight,
        measuredInfoWidth: measuredInfoWidth,
        listenable: listenable,
        childIndex: resolvedIndex,
        section: resolvedSection,
      ),
      children: [
        LayoutId(id: _PortraitSongSlot.title, child: titleChild),
        LayoutId(id: _PortraitSongSlot.subtitle, child: subtitleChild),
        LayoutId(id: _PortraitSongSlot.info, child: infoChild),
      ],
    );
  }

  /// Landscape desktop multi-column table: All primary information is aligned horizontally.
  Widget _buildLandscapeTable({
    required ThemeData theme,
    required FolderZoomLayoutMetrics effectiveMetrics,
    required double titleSubHeight,
    required double titleLineHeight,
    required double subLineHeight,
    required TextStyle effTitleStyle,
    required TextStyle effSubtitleStyle,
    required TextStyle effInfoStyle,
    required double effInfoSize,
    required ZoomTransitionListenable? listenable,
    required int? resolvedIndex,
    required Object? resolvedSection,
  }) {
    // 格式未知时整列不占位，否则会留下一个写着 UNKNOWN 的空胶囊。
    final hasFormat = formatStr != null;

    final titleChild = _buildTitleLine(theme: theme, style: effTitleStyle);
    final artistChild = Text(
      artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: effSubtitleStyle,
    );

    final rawExtraColumns = CustomMultiChildLayout(
      delegate: _LandscapeSongExtraColumnsDelegate(
        hasFormat: hasFormat,
        subLineHeight: subLineHeight,
      ),
      children: [
        LayoutId(
          id: _LandscapeExtraSlot.album,
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
        LayoutId(
          id: _LandscapeExtraSlot.track,
          child: Center(
            child: trackStr != null
                ? Text(
                    trackStr!,
                    style: effInfoStyle.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                  )
                : const SizedBox.shrink(),
          ),
        ),
        if (hasFormat)
          LayoutId(
            id: _LandscapeExtraSlot.format,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  formatStr!,
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
        LayoutId(
          id: _LandscapeExtraSlot.duration,
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

    final Widget extraColumnsChild;
    if (listenable != null) {
      extraColumnsChild = AnimatedBuilder(
        animation: listenable,
        child: rawExtraColumns,
        builder: (context, cachedChild) {
          final active = _resolveLiveSongMetrics(
            fallback: effectiveMetrics,
            listenable: listenable,
            childIndex: resolvedIndex,
            section: resolvedSection,
          );
          final double opacity = _songLandscapeExtraFade(active.gridMorph);
          return Opacity(opacity: opacity, child: cachedChild);
        },
      );
    } else {
      final double opacity =
          _songLandscapeExtraFade(effectiveMetrics.gridMorph);
      extraColumnsChild = opacity >= 0.999
          ? rawExtraColumns
          : Opacity(opacity: opacity, child: rawExtraColumns);
    }

    return CustomMultiChildLayout(
      delegate: _LandscapeSongTableLayoutDelegate(
        metrics: effectiveMetrics,
        hasFormat: hasFormat,
        titleSubHeight: titleSubHeight,
        titleLineHeight: titleLineHeight,
        subLineHeight: subLineHeight,
        listenable: listenable,
        childIndex: resolvedIndex,
        section: resolvedSection,
      ),
      children: [
        LayoutId(id: _LandscapeSongSlot.title, child: titleChild),
        LayoutId(id: _LandscapeSongSlot.artist, child: artistChild),
        LayoutId(id: _LandscapeSongSlot.extraColumns, child: extraColumnsChild),
      ],
    );
  }
}

enum _TitleEqSlot { equalizer, title }

/// 标题行带播放均衡器：宽度不足 40dp 时在纯布局阶段收起均衡器，避免窄容器溢出，
/// 同时免去内层 `LayoutBuilder` 重建。
class _SongTitleWithEqualizer extends StatelessWidget {
  const _SongTitleWithEqualizer({
    required this.equalizer,
    required this.eqSize,
    required this.eqGap,
    required this.title,
  });

  final Widget equalizer;
  final double eqSize;
  final double eqGap;
  final Widget title;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _SongTitleWithEqualizerDelegate(eqSize: eqSize, eqGap: eqGap),
      children: [
        LayoutId(
          id: _TitleEqSlot.equalizer,
          child: ClipRect(child: equalizer),
        ),
        LayoutId(id: _TitleEqSlot.title, child: title),
      ],
    );
  }
}

class _SongTitleWithEqualizerDelegate extends MultiChildLayoutDelegate {
  _SongTitleWithEqualizerDelegate({
    required this.eqSize,
    required this.eqGap,
  });

  final double eqSize;
  final double eqGap;

  @override
  void performLayout(Size size) {
    final bool showEq = size.width >= 40.0;
    if (hasChild(_TitleEqSlot.equalizer)) {
      if (showEq) {
        layoutChild(
          _TitleEqSlot.equalizer,
          BoxConstraints.tightFor(width: eqSize, height: eqSize),
        );
        positionChild(
          _TitleEqSlot.equalizer,
          Offset(0.0, ((size.height - eqSize) / 2.0).clamp(0.0, size.height)),
        );
      } else {
        layoutChild(
          _TitleEqSlot.equalizer,
          const BoxConstraints.tightFor(width: 0.0, height: 0.0),
        );
        positionChild(_TitleEqSlot.equalizer, Offset.zero);
      }
    }
    if (hasChild(_TitleEqSlot.title)) {
      final double textLeft = showEq ? (eqSize + eqGap) : 0.0;
      final double textWidth = math.max(0.0, size.width - textLeft);
      layoutChild(
        _TitleEqSlot.title,
        BoxConstraints.tightFor(width: textWidth, height: size.height),
      );
      positionChild(_TitleEqSlot.title, Offset(textLeft, 0.0));
    }
  }

  @override
  bool shouldRelayout(_SongTitleWithEqualizerDelegate oldDelegate) =>
      oldDelegate.eqSize != eqSize || oldDelegate.eqGap != eqGap;
}

class _SongGridAlignLayoutDelegate extends SingleChildLayoutDelegate {
  _SongGridAlignLayoutDelegate({
    required this.metrics,
    this.listenable,
    this.childIndex,
    this.section,
  }) : super(relayout: listenable);

  final FolderZoomLayoutMetrics metrics;
  final ZoomTransitionListenable? listenable;
  final int? childIndex;
  final Object? section;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
      minHeight: 0.0,
      maxHeight: double.infinity,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final active = _resolveLiveSongMetrics(
      fallback: metrics,
      listenable: listenable,
      childIndex: childIndex,
      section: section,
    );
    final double g = active.gridMorph.clamp(0.0, 1.0);
    final double vAlign = lerpDouble(0.5, 0.0, g)!;
    final double top =
        ((size.height - childSize.height) * vAlign).clamp(0.0, size.height);
    return Offset(0.0, top);
  }

  @override
  bool shouldRelayout(_SongGridAlignLayoutDelegate oldDelegate) {
    return !identical(oldDelegate.metrics, metrics) ||
        oldDelegate.childIndex != childIndex ||
        oldDelegate.section != section ||
        !identical(oldDelegate.listenable, listenable);
  }
}

enum _PortraitSongSlot { title, subtitle, info }

class _PortraitSongListLayoutDelegate extends MultiChildLayoutDelegate {
  _PortraitSongListLayoutDelegate({
    required this.metrics,
    required this.titleLineHeight,
    required this.subLineHeight,
    required this.infoLineHeight,
    required this.measuredInfoWidth,
    this.listenable,
    this.childIndex,
    this.section,
  }) : super(relayout: listenable);

  final FolderZoomLayoutMetrics metrics;
  final double titleLineHeight;
  final double subLineHeight;
  final double infoLineHeight;
  final double measuredInfoWidth;
  final ZoomTransitionListenable? listenable;
  final int? childIndex;
  final Object? section;

  @override
  void performLayout(Size size) {
    final active = _resolveLiveSongMetrics(
      fallback: metrics,
      listenable: listenable,
      childIndex: childIndex,
      section: section,
    );
    final double g = active.gridMorph.clamp(0.0, 1.0);
    final double t = (1.0 - active.compactMorph).clamp(0.0, 1.0);
    final double vAlign = lerpDouble(0.5, 0.0, g)!;

    // 跨向网格侧时，第三行 info 在翻面阈值前平滑淡出并收起其高度权重，
    // 使块高在翻面帧前后与网格侧 2 行块高严格衔接，消除垂直跳动。
    final double infoFade = _songPortraitInfoFade(g);
    final double infoWeight = infoFade * infoFade;

    final double W = size.width;
    final double H = size.height;

    final double compactInfoWidth =
        t >= 1.0 ? 0.0 : math.min(measuredInfoWidth, math.max(0.0, W * 0.45));
    final double compactTitleWidth = math.max(0.0, W - compactInfoWidth - 12.0);

    // 1. 紧凑模式坐标（2 行文本，音频信息右侧垂直居中）
    const double compactSubGap = 3.0;
    final double compactBlockHeight =
        titleLineHeight + compactSubGap + subLineHeight;
    final double compactTitleTop =
        ((H - compactBlockHeight) * vAlign).clamp(0.0, H);
    final double compactInfoTop = ((H - infoLineHeight) * vAlign).clamp(0.0, H);
    final double compactInfoLeft = math.max(0.0, W - compactInfoWidth);

    // 2. 标准模式坐标（3 行文本，音频信息在第 3 行）
    const double standardGap = 2.0;
    final double twoLineBlockHeight =
        titleLineHeight + standardGap + subLineHeight;
    final double standardBlockHeight =
        twoLineBlockHeight + (standardGap + infoLineHeight) * infoWeight;
    final double standardTitleTop =
        ((H - standardBlockHeight) * vAlign).clamp(0.0, H);
    final double standardSubTop =
        standardTitleTop + titleLineHeight + standardGap;
    final double standardInfoTop = standardSubTop + subLineHeight + standardGap;

    // 3. 动力学位移插值：
    // y 轴先向下滑出第 2 行区域（yt 提前完成），x 轴沿第 3 行横向滑入左侧（xt 紧随其后），
    // 保证过渡期间平滑位移且避免斜穿第 2 行副标题造成文字视觉重叠。
    final double yt = math.pow(t, 0.5).toDouble();
    final double xt = math.pow(t, 1.8).toDouble();

    final double titleTop = lerpDouble(compactTitleTop, standardTitleTop, t)!;
    final double titleWidth = lerpDouble(compactTitleWidth, W, yt)!;
    final double subGap = lerpDouble(compactSubGap, standardGap, t)!;
    final double subTop = titleTop + titleLineHeight + subGap;
    final double subWidth = titleWidth;

    final double infoTop = lerpDouble(compactInfoTop, standardInfoTop, yt)!;
    final double infoLeft = lerpDouble(compactInfoLeft, 0.0, xt)!;
    final double infoWidth = math.max(compactInfoWidth, W - infoLeft);

    if (hasChild(_PortraitSongSlot.title)) {
      layoutChild(
        _PortraitSongSlot.title,
        BoxConstraints.tightFor(width: titleWidth, height: titleLineHeight),
      );
      positionChild(_PortraitSongSlot.title, Offset(0.0, titleTop));
    }
    if (hasChild(_PortraitSongSlot.subtitle)) {
      layoutChild(
        _PortraitSongSlot.subtitle,
        BoxConstraints.tightFor(width: subWidth, height: subLineHeight),
      );
      positionChild(_PortraitSongSlot.subtitle, Offset(0.0, subTop));
    }
    if (hasChild(_PortraitSongSlot.info)) {
      layoutChild(
        _PortraitSongSlot.info,
        BoxConstraints.tightFor(width: infoWidth, height: infoLineHeight),
      );
      positionChild(_PortraitSongSlot.info, Offset(infoLeft, infoTop));
    }
  }

  @override
  bool shouldRelayout(_PortraitSongListLayoutDelegate oldDelegate) {
    return !identical(oldDelegate.metrics, metrics) ||
        oldDelegate.titleLineHeight != titleLineHeight ||
        oldDelegate.subLineHeight != subLineHeight ||
        oldDelegate.infoLineHeight != infoLineHeight ||
        oldDelegate.measuredInfoWidth != measuredInfoWidth ||
        oldDelegate.childIndex != childIndex ||
        oldDelegate.section != section ||
        !identical(oldDelegate.listenable, listenable);
  }
}

enum _LandscapeSongSlot { title, artist, extraColumns }

enum _LandscapeExtraSlot { album, track, format, duration }

({
  double titleArtistWidth,
  double albumLeft,
  double albumWidth,
  double trackLeft,
  double formatLeft,
  double durationLeft,
}) _computeLandscapeColumns(double W, {required bool hasFormat}) {
  const durationColWidth = 56.0;
  const trackColWidth = 36.0;
  const colGap = 16.0;
  final formatColWidth = hasFormat ? 60.0 : 0.0;

  final durationLeft = W - durationColWidth;
  final formatLeft =
      durationLeft - (hasFormat ? colGap + formatColWidth : 0.0);
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
  return (
    titleArtistWidth: titleArtistWidth,
    albumLeft: albumLeft,
    albumWidth: albumWidth,
    trackLeft: trackLeft,
    formatLeft: formatLeft,
    durationLeft: durationLeft,
  );
}

class _LandscapeSongTableLayoutDelegate extends MultiChildLayoutDelegate {
  _LandscapeSongTableLayoutDelegate({
    required this.metrics,
    required this.hasFormat,
    required this.titleSubHeight,
    required this.titleLineHeight,
    required this.subLineHeight,
    this.listenable,
    this.childIndex,
    this.section,
  }) : super(relayout: listenable);

  final FolderZoomLayoutMetrics metrics;
  final bool hasFormat;
  final double titleSubHeight;
  final double titleLineHeight;
  final double subLineHeight;
  final ZoomTransitionListenable? listenable;
  final int? childIndex;
  final Object? section;

  @override
  void performLayout(Size size) {
    final active = _resolveLiveSongMetrics(
      fallback: metrics,
      listenable: listenable,
      childIndex: childIndex,
      section: section,
    );
    final double g = active.gridMorph.clamp(0.0, 1.0);
    final double vAlign = lerpDouble(0.5, 0.0, g)!;
    final double expandT = _songLandscapeTitleExpand(g);

    final double W = size.width;
    final double H = size.height;
    final cols = _computeLandscapeColumns(W, hasFormat: hasFormat);
    final double titleArtistWidth =
        lerpDouble(cols.titleArtistWidth, W, expandT)!.clamp(0.0, W);

    final double topBaseline = ((H - titleSubHeight) * vAlign).clamp(0.0, H);
    final double secondLineTop = topBaseline + titleLineHeight + 2.0;

    if (hasChild(_LandscapeSongSlot.title)) {
      layoutChild(
        _LandscapeSongSlot.title,
        BoxConstraints.tightFor(
          width: titleArtistWidth,
          height: titleLineHeight,
        ),
      );
      positionChild(_LandscapeSongSlot.title, Offset(0.0, topBaseline));
    }
    if (hasChild(_LandscapeSongSlot.artist)) {
      layoutChild(
        _LandscapeSongSlot.artist,
        BoxConstraints.tightFor(
          width: titleArtistWidth,
          height: subLineHeight,
        ),
      );
      positionChild(_LandscapeSongSlot.artist, Offset(0.0, secondLineTop));
    }
    if (hasChild(_LandscapeSongSlot.extraColumns)) {
      layoutChild(
        _LandscapeSongSlot.extraColumns,
        BoxConstraints.tightFor(width: W, height: H),
      );
      positionChild(_LandscapeSongSlot.extraColumns, Offset.zero);
    }
  }

  @override
  bool shouldRelayout(_LandscapeSongTableLayoutDelegate oldDelegate) {
    return !identical(oldDelegate.metrics, metrics) ||
        oldDelegate.hasFormat != hasFormat ||
        oldDelegate.titleSubHeight != titleSubHeight ||
        oldDelegate.titleLineHeight != titleLineHeight ||
        oldDelegate.subLineHeight != subLineHeight ||
        oldDelegate.childIndex != childIndex ||
        oldDelegate.section != section ||
        !identical(oldDelegate.listenable, listenable);
  }
}

class _LandscapeSongExtraColumnsDelegate extends MultiChildLayoutDelegate {
  _LandscapeSongExtraColumnsDelegate({
    required this.hasFormat,
    required this.subLineHeight,
  });

  final bool hasFormat;
  final double subLineHeight;

  @override
  void performLayout(Size size) {
    const durationColWidth = 56.0;
    const formatColWidth = 60.0;
    const trackColWidth = 36.0;

    final double W = size.width;
    final double H = size.height;
    final cols = _computeLandscapeColumns(W, hasFormat: hasFormat);

    if (hasChild(_LandscapeExtraSlot.album)) {
      if (cols.albumWidth > 20.0) {
        layoutChild(
          _LandscapeExtraSlot.album,
          BoxConstraints.tightFor(
            width: cols.albumWidth,
            height: subLineHeight,
          ),
        );
        positionChild(
          _LandscapeExtraSlot.album,
          Offset(cols.albumLeft, ((H - subLineHeight) / 2.0).clamp(0.0, H)),
        );
      } else {
        layoutChild(
          _LandscapeExtraSlot.album,
          const BoxConstraints.tightFor(width: 0.0, height: 0.0),
        );
        positionChild(_LandscapeExtraSlot.album, Offset.zero);
      }
    }

    if (hasChild(_LandscapeExtraSlot.track)) {
      layoutChild(
        _LandscapeExtraSlot.track,
        BoxConstraints.tightFor(width: trackColWidth, height: H),
      );
      positionChild(_LandscapeExtraSlot.track, Offset(cols.trackLeft, 0.0));
    }

    if (hasChild(_LandscapeExtraSlot.format)) {
      layoutChild(
        _LandscapeExtraSlot.format,
        BoxConstraints.tightFor(width: formatColWidth, height: H),
      );
      positionChild(_LandscapeExtraSlot.format, Offset(cols.formatLeft, 0.0));
    }

    if (hasChild(_LandscapeExtraSlot.duration)) {
      layoutChild(
        _LandscapeExtraSlot.duration,
        BoxConstraints.tightFor(width: durationColWidth, height: H),
      );
      positionChild(
        _LandscapeExtraSlot.duration,
        Offset(cols.durationLeft, 0.0),
      );
    }
  }

  @override
  bool shouldRelayout(_LandscapeSongExtraColumnsDelegate oldDelegate) {
    return oldDelegate.hasFormat != hasFormat ||
        oldDelegate.subLineHeight != subLineHeight;
  }
}

/// 取扩展名（去掉前导点，保持原大小写）。取不到返回空串。
///
/// 本地文件的 path 带真实后缀；远程曲目的 path 是虚拟 URI
/// （`subsonic://<server>/<id>`），没有后缀，只能退回 name（`<title>.<suffix>`）。
String _fileExtensionOf(String value) {
  if (value.isEmpty) return '';
  final ext = p.extension(value);
  return ext.startsWith('.') ? ext.substring(1) : ext;
}

class _InfoWidthCacheKey {
  const _InfoWidthCacheKey({
    required this.text,
    required this.fontSize,
    required this.fontWeight,
    required this.textDirection,
  });

  final String text;
  final double fontSize;
  final FontWeight? fontWeight;
  final TextDirection textDirection;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _InfoWidthCacheKey &&
          other.text == text &&
          other.fontSize == fontSize &&
          other.fontWeight == fontWeight &&
          other.textDirection == textDirection;

  @override
  int get hashCode => Object.hash(text, fontSize, fontWeight, textDirection);
}

final _infoWidthCache = <_InfoWidthCacheKey, double>{};
const int _kMaxInfoWidthCacheSize = 1000;

double _measureInfoWidth(
  String text,
  TextStyle style,
  TextDirection textDirection,
) {
  if (text.isEmpty) return 0.0;
  final key = _InfoWidthCacheKey(
    text: text,
    fontSize: style.fontSize ?? 12.0,
    fontWeight: style.fontWeight,
    textDirection: textDirection,
  );
  final cached = _infoWidthCache[key];
  if (cached != null) return cached;

  final textPainter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: textDirection,
    maxLines: 1,
  )..layout();
  final measuredWidth = (textPainter.width + 2.0).ceilToDouble();
  textPainter.dispose();

  if (_infoWidthCache.length >= _kMaxInfoWidthCacheSize) {
    _infoWidthCache.clear();
  }
  _infoWidthCache[key] = measuredWidth;
  return measuredWidth;
}
