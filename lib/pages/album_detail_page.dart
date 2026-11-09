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

class AlbumDetailPage extends ConsumerStatefulWidget {
  const AlbumDetailPage({super.key, required this.album});

  final AlbumSummary album;

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
  bool _isPastTop = false;
  bool _isPopping = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _isAlbumDetailActiveNotifier =
        ref.read(isAlbumDetailActiveProvider.notifier);
    _landscapeMiniPlayerExtraLeftNotifier =
        ref.read(landscapeMiniPlayerExtraLeftProvider.notifier);
    AppLog.log(
      '[NavTrace] AlbumDetailPage.initState: album="${widget.album.title}" (id=${widget.album.id}, songs=${widget.album.songs.length})',
      mirrorToConsole: true,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isPopping) return;
      _isAlbumDetailActiveNotifier.set(true);
    });
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
    } else if (status == AnimationStatus.completed) {
      _isPopping = false;
      _isAlbumDetailActiveNotifier.set(true);
      if (mounted) {
        final mediaSize = MediaQuery.sizeOf(context);
        final isPortrait =
            MediaQuery.of(context).orientation == Orientation.portrait;
        final bool isShortLandscape = !isPortrait && (mediaSize.height < 500);
        final double leftColWidth =
            (mediaSize.width * 0.36).clamp(240.0, 310.0);
        _landscapeMiniPlayerExtraLeftNotifier
            .set(isShortLandscape ? leftColWidth : 0.0);
      }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (isRoutePopping) {
        _isAlbumDetailActiveNotifier.set(false);
        _landscapeMiniPlayerExtraLeftNotifier.set(0.0);
      } else {
        _isAlbumDetailActiveNotifier.set(true);
        _landscapeMiniPlayerExtraLeftNotifier.set(targetExtraLeft);
      }
    });

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
                  coverWidget: AlbumCover(
                    album: widget.album,
                    size: 260,
                    enableHero: true,
                  ),
                  barHeight: barHeight,
                )
              : AlbumLandscapeHeaderBanner(
                  title: widget.album.title,
                  subtitle: widget.album.artist,
                  metadata: metadataWidget,
                  actionButtons: actionButtons,
                  alignActionsToBottom: true,
                  coverWidget: AlbumCover(
                    album: widget.album,
                    size: 220,
                    enableHero: true,
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
              color: theme.colorScheme.surface,
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
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.35
                                      : 0.12,
                                ),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AlbumCover(
                              album: widget.album,
                              size: coverSize,
                            ),
                          ),
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
                            ? (140.0 + MediaQuery.of(context).padding.bottom)
                            : (32.0 + MediaQuery.of(context).padding.bottom)),
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
          child: wrapped,
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
        MediaQuery.of(context).orientation == Orientation.portrait;
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
