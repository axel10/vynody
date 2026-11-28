import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/album_cover.dart';
import '../widgets/album_detail_widgets.dart';
import '../widgets/cover_flip_route.dart';
import '../widgets/playback/playback_cover_flight.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/playing_equalizer_icon.dart';
import '../widgets/mini_player_wrapper.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/draggable_song_item.dart';
import 'package:vynody/utils/layout_constants.dart';
import '../player/platform/right_queue_drawer_controller.dart';
import '../widgets/auto_hide_header.dart';
import '../widgets/app_top_nav_bar.dart';
import '../widgets/app_circular_back_button.dart';
import '../utils/app_log.dart';
import 'main_layout_riverpod.dart';

/// 供 FLIP 转场关联源封面与详情页封面的统一标识。
String albumCoverFlipTag(String albumId) => 'album_cover:$albumId';

/// 打开专辑详情页；当当前上下文存在可见的源封面锚点且 [enableFlip] 为 true 时，
/// 自动采用 FLIP 原位反向变换动画，否则无缝回退至标准页面路由。
Future<T?> pushAlbumDetailPage<T>(
  BuildContext context, {
  required AlbumSummary album,
  bool enableFlip = true,
  RouteSettings? settings,
}) {
  final effectiveSettings = settings ??
      RouteSettings(
        name: '/album_detail/${Uri.encodeComponent(album.id)}',
      );
  final CoverFlipOrigin? origin = enableFlip
      ? CoverFlipRegistry.captureOrigin(
          context,
          tag: albumCoverFlipTag(album.id),
        )
      : null;
  if (origin != null) {
    // 不要把源封面在这里就隐藏：新推入的路由在第一帧会被 HeroController
    // 置为 offstage（`to.offstage = to.animation.value == 0`），这一帧详情页
    // 根本不绘制，若此时源封面已隐藏，列表上被点的那张封面会空掉一帧 ——
    // 观感就是「点下去的瞬间条目闪一下」。隐藏交给详情页量到目标槽位后
    // （结束帧回调 → 下一帧生效）与飞行层同时生效。
    return Navigator.of(context).push<T>(
      CoverFlipPageRoute<T>(
        settings: effectiveSettings,
        origin: origin,
        builder: (_) => AlbumDetailPage(
          album: album,
          coverOrigin: origin,
        ),
      ),
    );
  }
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: effectiveSettings,
      builder: (_) => AlbumDetailPage(album: album),
    ),
  );
}

class AlbumDetailPage extends ConsumerStatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.album,
    this.coverOrigin,
  });

  final AlbumSummary album;
  final CoverFlipOrigin? coverOrigin;

  @override
  ConsumerState<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends ConsumerState<AlbumDetailPage>
    with
        SelectionStateMixin<AlbumDetailPage, String>,
        SongSelectionMixin<AlbumDetailPage> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  late final ScrollController _scrollController;
  late final IsAlbumDetailActiveNotifier _isAlbumDetailActiveNotifier;
  late final LandscapeMiniPlayerExtraLeftNotifier _landscapeMiniPlayerExtraLeftNotifier;
  final GlobalKey _flightLayerKey =
      GlobalKey(debugLabel: 'album_detail_flight_layer');
  final GlobalKey _coverSlotKey =
      GlobalKey(debugLabel: 'album_detail_cover_slot');
  final GlobalKey _coverContentKey =
      GlobalKey(debugLabel: 'album_detail_cover_content');
  Rect? _targetRect;
  Offset _overlayOrigin = Offset.zero;
  bool _isFlipActive = false;
  bool _useFallbackFadePop = false;
  bool _isPastTop = false;
  bool _isPopping = false;
  bool? _lastReportedDetailActive;
  double? _lastReportedExtraLeft;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _isAlbumDetailActiveNotifier =
        ref.read(isAlbumDetailActiveProvider.notifier);
    _landscapeMiniPlayerExtraLeftNotifier =
        ref.read(landscapeMiniPlayerExtraLeftProvider.notifier);
    if (widget.coverOrigin != null) {
      _isFlipActive = true;
      _scheduleInitialTargetMeasure();
    }
    AppLog.log(
      '[NavTrace] AlbumDetailPage.initState: album="${widget.album.title}" (id=${widget.album.id}, songs=${widget.album.songs.length})',
      mirrorToConsole: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isPopping) return;
      _isAlbumDetailActiveNotifier.set(true);
    });
  }

  void _scheduleInitialTargetMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _useFallbackFadePop) return;
      if (_routeAnimation?.status == AnimationStatus.completed) {
        widget.coverOrigin?.setSourceHidden(false);
        if (_isFlipActive) {
          setState(() => _isFlipActive = false);
        }
        return;
      }
      final measured = _measureCoverSlotRect();
      if (measured != null) {
        widget.coverOrigin?.setSourceHidden(true);
        setState(() {
          _targetRect = measured.rect;
          _overlayOrigin = measured.overlayOrigin;
        });
      } else {
        widget.coverOrigin?.setSourceHidden(false);
        setState(() {
          _isFlipActive = false;
        });
      }
    });
  }

  ({Rect rect, Offset overlayOrigin})? _measureCoverSlotRect() {
    final ctx = _coverSlotKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    if (size.width <= 1.0 || size.height <= 1.0) return null;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final bottomRight = renderObject.localToGlobal(
      Offset(size.width, size.height),
    );
    if (!topLeft.dx.isFinite ||
        !topLeft.dy.isFinite ||
        !bottomRight.dx.isFinite ||
        !bottomRight.dy.isFinite) {
      return null;
    }
    Offset overlayOrigin = Offset.zero;
    final overlayCtx = _flightLayerKey.currentContext;
    if (overlayCtx != null && overlayCtx.mounted) {
      final overlayBox = overlayCtx.findRenderObject();
      if (overlayBox is RenderBox &&
          overlayBox.attached &&
          overlayBox.hasSize) {
        final originPoint = overlayBox.localToGlobal(Offset.zero);
        if (originPoint.dx.isFinite && originPoint.dy.isFinite) {
          overlayOrigin = originPoint;
        }
      }
    }
    return (
      rect: Rect.fromPoints(topLeft, bottomRight),
      overlayOrigin: overlayOrigin,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null && modalRoute.animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = modalRoute.animation;
      _routeAnimation?.addStatusListener(_onRouteAnimationStatus);
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _isPopping = true;
      _isAlbumDetailActiveNotifier.set(false);
      _landscapeMiniPlayerExtraLeftNotifier.set(0.0);
      if (widget.coverOrigin != null && mounted) {
        final mediaSize = MediaQuery.sizeOf(context);
        final bool sameWindow = mediaSize == widget.coverOrigin!.windowSize;
        final measured = sameWindow ? _measureCoverSlotRect() : null;
        final bool isLandscape =
            ref.read(isEffectiveLandscapeProvider(mediaSize));
        final bool isShortLandscape = isLandscape && (mediaSize.height < 500);
        final double minVisibleBottom =
            isShortLandscape ? 0.0 : (getBarHeight(context) * 0.5);
        final bool isVisible = measured != null &&
            measured.rect.bottom > minVisibleBottom &&
            measured.rect.top < mediaSize.height;
        if (isVisible) {
          widget.coverOrigin!.setSourceHidden(true);
          setState(() {
            _targetRect = measured.rect;
            _overlayOrigin = measured.overlayOrigin;
            _isFlipActive = true;
            _useFallbackFadePop = false;
          });
        } else {
          widget.coverOrigin!.setSourceHidden(false);
          setState(() {
            _isFlipActive = false;
            _useFallbackFadePop = true;
          });
        }
      }
    } else if (status == AnimationStatus.completed) {
      _isPopping = false;
      _isAlbumDetailActiveNotifier.set(true);
      if (widget.coverOrigin != null && mounted && _isFlipActive) {
        setState(() {
          _isFlipActive = false;
          _useFallbackFadePop = false;
        });
      }
      if (mounted) {
        final mediaSize = MediaQuery.sizeOf(context);
        final isPortrait =
            MediaQuery.orientationOf(context) == Orientation.portrait;
        final bool isShortLandscape = !isPortrait && (mediaSize.height < 500);
        final double leftColWidth =
            (mediaSize.width * 0.36).clamp(240.0, 310.0);
        _landscapeMiniPlayerExtraLeftNotifier
            .set(isShortLandscape ? leftColWidth : 0.0);
      }
    } else if (status == AnimationStatus.dismissed) {
      widget.coverOrigin?.setSourceHidden(false);
      _isFlipActive = false;
    }
  }

  void _handleBack() {
    if (isSelectionMode) {
      cancelSongSelection();
      return;
    }
    _isPopping = true;
    _isAlbumDetailActiveNotifier.set(false);
    _landscapeMiniPlayerExtraLeftNotifier.set(0.0);
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    AppLog.log(
      '[NavTrace] AlbumDetailPage.dispose: album="${widget.album.title}" (id=${widget.album.id})',
      mirrorToConsole: true,
    );
    widget.coverOrigin?.setSourceHidden(false);
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    Future.microtask(() {
      _isAlbumDetailActiveNotifier.set(false);
      _landscapeMiniPlayerExtraLeftNotifier.set(0.0);
    });
    _scrollController.dispose();
    super.dispose();
  }

  static double getBarHeight(BuildContext context) =>
      AppTopNavBar.getBarHeight(context);

  Widget _buildSongSliverList({
    required MusicFile? currentMusic,
    required bool isMixedAlbum,
    required bool isLargeAlbum,
    required String unknownArtist,
    required double itemExtent,
  }) {
    return SliverFixedExtentList.builder(
      itemExtent: itemExtent,
      itemCount: widget.album.songs.length,
      itemBuilder: (context, index) {
        final song = widget.album.songs[index];
        final isCurrent = currentMusic?.path == song.path;
        final isSelected = isSongSelected(song.path);
        final showRemote =
            isMixedAlbum && RemoteMediaHelper.isRemote(song);

        return _AlbumSongItem(
          song: song,
          index: index,
          isCurrent: isCurrent,
          isSelected: isSelected,
          isSelectionMode: isSelectionMode,
          selectedPaths: selectedSongPaths,
          isLargeAlbum: isLargeAlbum,
          showRemoteIndicator: showRemote,
          unknownArtist: unknownArtist,
          onTap: () {
            handleSongTap(
              index: index,
              songPath: song.path,
              allSongs: widget.album.songs,
              onNormalTap: () {
                ref.read(audioServiceProvider).playPlaylist(
                  widget.album.songs,
                  initialIndex: index,
                  source: PlaybackSource(
                    type: PlaybackSourceType.album,
                    id: widget.album.id,
                    name: widget.album.title,
                  ),
                );
              },
            );
          },
          onLongPress: () {
            lastAnchorIndex = index;
            if (!isSelectionMode) {
              enterSongSelectionMode(song.path);
            }
          },
          onSecondaryTapDown: (details) {
            if (!isSelectionMode) {
              showSongContextMenu(
                context,
                details.globalPosition,
                song: song,
                songs: [song],
                mode: SongContextMenuMode.full,
                onMultiSelect: () {
                  lastAnchorIndex = index;
                  enterSongSelectionMode(song.path);
                },
                onPlayNext: () =>
                    ref.read(audioServiceProvider).enqueueNext([song]),
                onAddToQueue: () =>
                    ref.read(audioServiceProvider).appendToQueue([song]),
                onAddToPlaylist: () async {
                  await showAddSongsToPlaylistDialog(
                    context,
                    ref.read(playlistServiceProvider),
                    [song],
                  );
                },
              );
            }
          },
          onToggleSelection: () {
            lastAnchorIndex = index;
            toggleSongSelection(song.path);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final mediaSize = MediaQuery.sizeOf(context);
    final isLandscape = ref.watch(isEffectiveLandscapeProvider(mediaSize));
    final isPortrait = !isLandscape;
    final bool isShortLandscape = isLandscape && (mediaSize.height < 500);
    final double leftColWidth = (mediaSize.width * 0.36).clamp(240.0, 310.0);
    final modalRoute = ModalRoute.of(context);
    final bool isRoutePopping = _isPopping ||
        (modalRoute != null &&
            (modalRoute.animation?.status == AnimationStatus.reverse ||
                !modalRoute.isActive));
    final double targetExtraLeft =
        (isShortLandscape && !isRoutePopping) ? leftColWidth : 0.0;
    final bool targetDetailActive = !isRoutePopping;
    if (_lastReportedDetailActive != targetDetailActive ||
        _lastReportedExtraLeft != targetExtraLeft) {
      _lastReportedDetailActive = targetDetailActive;
      _lastReportedExtraLeft = targetExtraLeft;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _isAlbumDetailActiveNotifier.set(targetDetailActive);
        _landscapeMiniPlayerExtraLeftNotifier.set(targetExtraLeft);
      });
    }

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(widget.album.songs)
        : const <MusicFile>[];
    final isLargeAlbum = widget.album.songs.length >= 100;
    final isMixedAlbum = RemoteMediaHelper.isMixed(widget.album.songs);
    final unknownArtist = l10n.unknownArtist;
    final double barHeight = getBarHeight(context);
    final durationText =
        _formatDuration(widget.album.totalDurationMillis) ?? l10n.durationZero;
    final yearText = widget.album.yearRangeText;
    final genreText = widget.album.genresText;
    final trackCountText = l10n.songCount(widget.album.trackCount);

    final metadataParts = <String>[
      if (yearText != null && yearText.isNotEmpty) yearText,
      if (genreText != null && genreText.isNotEmpty) genreText,
      '$trackCountText · $durationText',
    ];

    final metadataWidget = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(
          metadataParts.join(' · '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontSize: isShortLandscape ? 12 : 14,
          ),
        ),
        if (RemoteMediaHelper.isAllRemote(widget.album.songs))
          RemoteMediaBadge.chip(
            songs: widget.album.songs,
            title: widget.album.title,
          ),
      ],
    );

    final actionButtons = [
      FilledButton.icon(
        onPressed: () => audio.playPlaylist(
          widget.album.songs,
          source: PlaybackSource(
            type: PlaybackSourceType.album,
            id: widget.album.id,
            name: widget.album.title,
          ),
        ),
        icon: Icon(Icons.play_arrow, size: isShortLandscape ? 18 : 20),
        label: Text(l10n.playAll),
        style: !isPortrait
            ? FilledButton.styleFrom(
                shape: const StadiumBorder(),
                visualDensity: isShortLandscape ? VisualDensity.compact : null,
                padding: EdgeInsets.symmetric(
                  horizontal: isShortLandscape ? 12 : 20,
                  vertical: isShortLandscape ? 8 : 12,
                ),
                textStyle: isShortLandscape ? theme.textTheme.labelMedium : null,
              )
            : null,
      ),
      isPortrait
          ? OutlinedButton.icon(
              onPressed: () => audio.playPlaylist(
                List.of(widget.album.songs)..shuffle(),
                source: PlaybackSource(
                  type: PlaybackSourceType.album,
                  id: widget.album.id,
                  name: widget.album.title,
                ),
              ),
              icon: const Icon(Icons.shuffle),
              label: Text(l10n.shufflePlay),
            )
          : FilledButton.tonalIcon(
              onPressed: () => audio.playPlaylist(
                List.of(widget.album.songs)..shuffle(),
                source: PlaybackSource(
                  type: PlaybackSourceType.album,
                  id: widget.album.id,
                  name: widget.album.title,
                ),
              ),
              icon: Icon(Icons.shuffle, size: isShortLandscape ? 18 : 20),
              label: Text(l10n.shufflePlay),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                visualDensity: isShortLandscape ? VisualDensity.compact : null,
                padding: EdgeInsets.symmetric(
                  horizontal: isShortLandscape ? 12 : 20,
                  vertical: isShortLandscape ? 8 : 12,
                ),
                textStyle: isShortLandscape ? theme.textTheme.labelMedium : null,
              ),
            ),
    ];

    final bool hasFlipOrigin = widget.coverOrigin != null && _routeAnimation != null;
    final bool isAnimatingFlip = hasFlipOrigin && _isFlipActive;
    final bool isAnimatingFallback = hasFlipOrigin && _useFallbackFadePop;
    final bool isTransitioningFlip = isAnimatingFlip || isAnimatingFallback;

    final double? sourceBucket = widget.coverOrigin?.sourceBucketSize;
    final double activeLayoutCoverSize = isShortLandscape
        ? (_targetRect?.width ?? (mediaSize.height * 0.36).clamp(92.0, 136.0))
        : (isPortrait ? 260.0 : 220.0);
    final double effectiveCacheSize = (isAnimatingFlip && sourceBucket != null)
        ? sourceBucket
        : ((sourceBucket == 250.0 && activeLayoutCoverSize <= 260.0)
            ? 250.0
            : activeLayoutCoverSize);

    Widget buildDecoratedCover({
      required double size,
      required double borderRadius,
      required double shadowBlur,
      required Offset shadowOffset,
      double shadowAlphaScale = 1.0,
    }) {
      final double shadowAlpha =
          (theme.brightness == Brightness.dark ? 0.35 : 0.12) *
              shadowAlphaScale;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: shadowAlphaScale <= 0.001
              ? const []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: shadowAlpha),
                    blurRadius: shadowBlur,
                    offset: shadowOffset,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: KeyedSubtree(
            key: _coverContentKey,
            child: AlbumCover(
              album: widget.album,
              size: size,
              width: size,
              height: size,
              borderRadius: BorderRadius.zero,
              cacheSize: effectiveCacheSize,
              gaplessPlayback: true,
            ),
          ),
        ),
      );
    }

    Widget buildHeaderCoverSlot({
      required double size,
      required double borderRadius,
      required double shadowBlur,
      required Offset shadowOffset,
    }) {
      return SizedBox(
        key: _coverSlotKey,
        width: size,
        height: size,
        child: isAnimatingFlip
            ? null
            : buildDecoratedCover(
                size: size,
                borderRadius: borderRadius,
                shadowBlur: shadowBlur,
                shadowOffset: shadowOffset,
              ),
      );
    }

    final Widget scrollBody = CustomScrollView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        if (!isPortrait)
          SliverToBoxAdapter(
            child: SizedBox(height: barHeight),
          ),
        SliverToBoxAdapter(
          child: isPortrait
              ? AlbumPortraitHeaderBanner(
                  title: widget.album.title,
                  subtitle: widget.album.artist,
                  metadata: metadataWidget,
                  actionButtons: actionButtons,
                  showCoverDecoration: false,
                  coverWidget: buildHeaderCoverSlot(
                    size: 260,
                    borderRadius: 12,
                    shadowBlur: 14,
                    shadowOffset: const Offset(0, 6),
                  ),
                  barHeight: barHeight,
                )
              : AlbumLandscapeHeaderBanner(
                  title: widget.album.title,
                  subtitle: widget.album.artist,
                  metadata: metadataWidget,
                  actionButtons: actionButtons,
                  showCoverDecoration: false,
                  alignActionsToBottom: true,
                  coverWidget: buildHeaderCoverSlot(
                    size: 220,
                    borderRadius: 12,
                    shadowBlur: 18,
                    shadowOffset: const Offset(0, 8),
                  ),
                ),
        ),
        _buildSongSliverList(
          currentMusic: currentMusic,
          isMixedAlbum: isMixedAlbum,
          isLargeAlbum: isLargeAlbum,
          unknownArtist: unknownArtist,
          itemExtent: 64.0,
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: MiniPlayerUiTuning.getListBottomPadding(
              context,
              hasPlayingMusic: currentMusic != null,
              isSelectionMode: isSelectionMode,
              selectionPanelHeight: 220.0,
            ),
          ),
        ),
      ],
    );

    final Widget shortLandscapeBody = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: leftColWidth,
          child: Container(
            decoration: BoxDecoration(
              color: isTransitioningFlip ? null : theme.colorScheme.surface,
              border: Border(
                right: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                  width: 0.8,
                ),
              ),
            ),
            child: SafeArea(
              top: true,
              bottom: true,
              left: true,
              right: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double coverSize =
                      (constraints.maxHeight * 0.36).clamp(92.0, 136.0);
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14.0,
                      vertical: 6.0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppCircularBackButton(
                            onPressed: _handleBack,
                          ),
                        ),
                        const SizedBox(height: 2),
                        buildHeaderCoverSlot(
                          size: coverSize,
                          borderRadius: 10,
                          shadowBlur: 14,
                          shadowOffset: const Offset(0, 4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.album.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.album.artist.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.album.artist,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        metadataWidget,
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: actionButtons,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            top: true,
            bottom: false,
            left: false,
            right: true,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 6)),
                _buildSongSliverList(
                  currentMusic: currentMusic,
                  isMixedAlbum: isMixedAlbum,
                  isLargeAlbum: isLargeAlbum,
                  unknownArtist: unknownArtist,
                  itemExtent: 64.0,
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: isSelectionMode
                        ? 220.0
                        : (currentMusic != null
                            ? (140.0 + MediaQuery.paddingOf(context).bottom)
                            : (32.0 + MediaQuery.paddingOf(context).bottom)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final double leftPadding = isShortLandscape
        ? 0.0
        : ref.watch(effectiveSidebarRailWidthProvider(mediaSize));

    final page = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical) return false;
        final past = notification.metrics.pixels > 36.0;
        if (_isPastTop != past) {
          setState(() => _isPastTop = past);
        }
        return false;
      },
      child: AutoHideHeaderScope(
        enabled: false,
        forceVisible: isSelectionMode,
        builder: (context, isHeaderVisible) {
          final Widget content = Scaffold(
            backgroundColor: isTransitioningFlip ? Colors.transparent : null,
            body: Padding(
              padding: EdgeInsets.only(left: leftPadding),
              child: Stack(
                children: [
                  isShortLandscape ? shortLandscapeBody : scrollBody,
                  if (!isShortLandscape)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AutoHideHeader(
                        isVisible: isHeaderVisible,
                        child: AppTopNavBar(
                          title: widget.album.title,
                          parentTitle: l10n.albums,
                          titleKey: const ValueKey('album_title'),
                          isFloatingCapsule: _isPastTop,
                          contentMaxWidth: kSingleColumnContentMaxWidth,
                          enableBlur: isTransitioningFlip ? false : null,
                          onBack: _handleBack,
                        ),
                      ),
                    ),
                  AnimatedSelectionPanel(
                    isVisible: isSelectionMode,
                    child: LibrarySelectionPanel(
                      key: const ValueKey('library-selection-panel'),
                      selectedSongs: selectedSongs,
                      allSongs: widget.album.songs,
                      onToggleSelectAll: () =>
                          toggleSelectAllSongs(widget.album.songs),
                      onCancel: cancelSongSelection,
                    ),
                  ),
                ],
              ),
            ),
          );

        final wrapped = MiniPlayerWrapper(child: content);
        final Widget bodyRoot;
        if (!hasFlipOrigin) {
          bodyRoot = wrapped;
        } else {
          final routeAnim = _routeAnimation!;
          final double targetRadius = isShortLandscape ? 10.0 : 12.0;
          final double shadowBlur = isPortrait ? 14.0 : (isShortLandscape ? 14.0 : 18.0);
          final Offset shadowOffset = isShortLandscape
              ? const Offset(0, 4)
              : (isPortrait ? const Offset(0, 6) : const Offset(0, 8));

          bodyRoot = Stack(
            key: _flightLayerKey,
            fit: StackFit.expand,
            children: [
              if (isTransitioningFlip)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: routeAnim,
                    builder: (context, _) {
                      final double p =
                          Curves.fastOutSlowIn.transform(routeAnim.value);
                      final double bgAlpha = isAnimatingFallback
                          ? p
                          : PlaybackCoverFlightGeometry.computeBackdropOpacity(p);
                      return ColoredBox(
                        color: theme.colorScheme.surface
                            .withValues(alpha: bgAlpha),
                      );
                    },
                  ),
                ),
              AnimatedBuilder(
                animation: routeAnim,
                child: RepaintBoundary(child: wrapped),
                builder: (context, childWidget) {
                  if (!isTransitioningFlip) return childWidget!;
                  final double p =
                      Curves.fastOutSlowIn.transform(routeAnim.value);
                  if (isAnimatingFallback) {
                    return Opacity(opacity: p, child: childWidget);
                  }
                  final double chromeOpacity =
                      PlaybackCoverFlightGeometry.computeChromeOpacity(p);
                  if (chromeOpacity >= 0.9999) {
                    return childWidget!;
                  }
                  return Opacity(
                    opacity: chromeOpacity,
                    child: childWidget,
                  );
                },
              ),
              if (isAnimatingFlip)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: routeAnim,
                      builder: (context, _) {
                        final Rect localStart =
                            widget.coverOrigin!.rect.shift(-_overlayOrigin);
                        if (_targetRect == null) {
                          return Stack(
                            children: [
                              Positioned(
                                left: localStart.left,
                                top: localStart.top,
                                width: localStart.width,
                                height: localStart.height,
                                child: buildDecoratedCover(
                                  size: localStart.width,
                                  borderRadius:
                                      widget.coverOrigin!.borderRadius,
                                  shadowBlur: shadowBlur,
                                  shadowOffset: shadowOffset,
                                  shadowAlphaScale: 0.0,
                                ),
                              ),
                            ],
                          );
                        }
                        final Rect localEnd =
                            _targetRect!.shift(-_overlayOrigin);
                        final double curved =
                            Curves.fastOutSlowIn.transform(routeAnim.value);
                        final flight = CoverFlipMath.computeTransform(
                          startRect: localStart,
                          startBorderRadius:
                              widget.coverOrigin!.borderRadius,
                          endRect: localEnd,
                          endBorderRadius: targetRadius,
                          progress: curved,
                        );
                        final double shadowAlphaScale =
                            ((curved - 0.15) / 0.85).clamp(0.0, 1.0);
                        return Stack(
                          children: [
                            Positioned(
                              left: localEnd.left,
                              top: localEnd.top,
                              width: localEnd.width,
                              height: localEnd.height,
                              child: Transform(
                                alignment: Alignment.topLeft,
                                transform: flight.transform,
                                child: buildDecoratedCover(
                                  size: localEnd.width,
                                  borderRadius: flight.localBorderRadius,
                                  shadowBlur: shadowBlur,
                                  shadowOffset: shadowOffset,
                                  shadowAlphaScale: shadowAlphaScale,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
            ],
          );
        }
        // PopScope 常驻、仅切换 canPop：避免多选开关导致根节点类型变化，
        // 否则整棵子树（含滚动位置）会被销毁重建。
        return PopScope(
          canPop: !isSelectionMode,
          onPopInvokedWithResult: (didPop, result) {
            AppLog.log(
              '[NavTrace] AlbumDetailPage.PopScope invoked (selection mode): didPop=$didPop, result=$result',
              mirrorToConsole: true,
            );
            if (didPop) {
              _isPopping = true;
              _isAlbumDetailActiveNotifier.set(false);
              _landscapeMiniPlayerExtraLeftNotifier.set(0.0);
              return;
            }
            cancelSongSelection();
          },
          child: bodyRoot,
        );
      },
    ),
  );
  return page;
}
}

String? _formatDuration(int? durationMs) {
  if (durationMs == null) return null;
  final duration = Duration(milliseconds: durationMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${duration.inMinutes}:${seconds.toString().padLeft(2, '0')}';
}

class _AlbumSongItem extends StatelessWidget {
  const _AlbumSongItem({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isSelected,
    required this.isSelectionMode,
    this.selectedPaths,
    required this.isLargeAlbum,
    required this.unknownArtist,
    this.showRemoteIndicator = false,
    required this.onTap,
    required this.onLongPress,
    required this.onSecondaryTapDown,
    required this.onToggleSelection,
  });

  final MusicFile song;
  final int index;
  final bool isCurrent;
  final bool isSelected;
  final bool isSelectionMode;
  final Iterable<String>? selectedPaths;
  final bool isLargeAlbum;
  final String unknownArtist;
  final bool showRemoteIndicator;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<TapDownDetails> onSecondaryTapDown;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final durationLabel = _formatDuration(song.durationMillis);
    final trackLabel = '${index + 1}'.padLeft(2, '0');
    final isTileSelected = isSelectionMode ? isSelected : isCurrent;

    final leadingWidget = isSelectionMode
        ? SizedBox(
            width: isLargeAlbum ? 40 : 32,
            child: Center(
              child: Checkbox(
                value: isSelected,
                onChanged: (_) => onToggleSelection(),
              ),
            ),
          )
        : SizedBox(
            width: isLargeAlbum ? 40 : 32,
            child: Center(
              child: isCurrent
                  ? PlayingEqualizerIcon(
                      color: theme.colorScheme.primary,
                      size: 16,
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        trackLabel,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
            ),
          );

    final tileWidget = Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSingleColumnContentMaxWidth),
        child: Container(
          decoration: (!isPortrait)
              ? BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: isDark ? 0.5 : 0.4,
                      ),
                      width: 0.8,
                    ),
                  ),
                )
              : null,
          child: Material(
            color: isTileSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                : Colors.transparent,
            borderRadius: !isPortrait ? BorderRadius.circular(8) : BorderRadius.zero,
            child: InkWell(
              borderRadius: !isPortrait ? BorderRadius.circular(8) : BorderRadius.zero,
              enableFeedback: false,
              canRequestFocus: false,
              onTap: onTap,
              onLongPress: onLongPress,
              onSecondaryTapDown: onSecondaryTapDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    leadingWidget,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  song.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: isCurrent ? theme.colorScheme.primary : null,
                                    fontWeight: isCurrent ? FontWeight.w700 : null,
                                  ),
                                ),
                              ),
                              RemoteMediaBadge.songTrailing(
                                song: song,
                                isMixed: showRemoteIndicator,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artist ?? unknownArtist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (durationLabel != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        durationLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return DraggableSongItem(
      song: song,
      enabled: !song.isMissing,
      isSelected: isSelected,
      isSelectionMode: isSelectionMode,
      selectedPaths: selectedPaths,
      child: tileWidget,
    );
  }
}
