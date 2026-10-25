import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/album_detail_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_log.dart';
import 'album_context_menu.dart';
import 'album_sections.dart';
import 'album_zoom_item.dart';
import 'collection_detail_header.dart';
import 'draggable_album_item.dart';
import 'folder_layout_utils.dart';
import 'folder_zoom_gesture_layer.dart';
import 'library_selection_panel.dart';
import 'library_selection_scope.dart';
import 'mini_player_wrapper.dart';

/// 流派 / 年份等「集合型」条目的详情内容。
///
/// 顶部为 [CollectionDetailHeader]，
/// 竖屏下像艺术家详情页一样展示专辑网格；
/// 横屏下按专辑分组渲染曲目列表；
/// 分组、播放、多选与底部避让逻辑在此统一实现，各页面只负责提供数据与播放来源。
class CollectionDetailContent extends ConsumerStatefulWidget {
  const CollectionDetailContent({
    super.key,
    required this.title,
    required this.songCount,
    required this.albumCount,
    required this.totalDurationMillis,
    required this.songs,
    required this.source,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final String title;
  final int songCount;
  final int albumCount;
  final int totalDurationMillis;

  /// 该集合下的全部歌曲（未分组），分组由内部完成并缓存。
  final List<MusicFile> songs;

  /// 播放全部、随机播放与单曲播放共用的播放来源。
  final PlaybackSource source;

  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  ConsumerState<CollectionDetailContent> createState() =>
      _CollectionDetailContentState();
}

class _CollectionDetailContentState extends ConsumerState<CollectionDetailContent>
    with
        SelectionStateMixin<CollectionDetailContent, String>,
        SongSelectionMixin<CollectionDetailContent> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  final AlbumSectionsCache _albumCache = AlbumSectionsCache();

  void _playAll(List<MusicFile> songs) {
    ref.read(audioServiceProvider).playPlaylist(songs, source: widget.source);
  }

  List<AlbumSummary> _buildAlbums(
    List<AlbumSection> sections,
    List<AlbumSummary>? libraryAlbums,
    String unknownArtistLabel,
  ) {
    final libraryMap = <String, AlbumSummary>{};
    if (libraryAlbums != null) {
      for (final album in libraryAlbums) {
        libraryMap[album.id] = album;
      }
    }

    return sections.map((section) {
      final firstSong = section.songs.firstOrNull;
      final effectiveArtist =
          (firstSong?.albumArtist ?? firstSong?.artist ?? '').trim();
      final expectedId =
          '${section.title.toLowerCase()}::${effectiveArtist.toLowerCase()}';

      final matched = libraryMap[expectedId];
      if (matched != null) return matched;

      if (libraryAlbums != null && effectiveArtist.isNotEmpty) {
        final matchedByArtist = libraryAlbums.firstWhereOrNull(
          (a) =>
              a.title.toLowerCase() == section.title.toLowerCase() &&
              (a.artist.toLowerCase() == effectiveArtist.toLowerCase() ||
                  a.songs.any((s) =>
                      (s.albumArtist ?? s.artist ?? '')
                          .trim()
                          .toLowerCase() ==
                      effectiveArtist.toLowerCase())),
        );
        if (matchedByArtist != null) return matchedByArtist;
      }

      if (libraryAlbums != null) {
        final titleMatched = libraryAlbums.firstWhereOrNull(
          (a) => a.title.toLowerCase() == section.title.toLowerCase(),
        );
        if (titleMatched != null) return titleMatched;
      }

      final albumYears = <int>{};
      for (final s in section.songs) {
        if (s.year != null && s.year! > 0) {
          albumYears.add(s.year!);
        }
      }

      return AlbumSummary(
        id: expectedId,
        title: section.title,
        artist: effectiveArtist.isNotEmpty ? effectiveArtist : unknownArtistLabel,
        songs: section.songs,
        representativeSong: section.representativeSong,
        totalDurationMillis: section.totalDurationMillis,
        minYear: albumYears.isEmpty ? null : albumYears.reduce(math.min),
        maxYear: albumYears.isEmpty ? null : albumYears.reduce(math.max),
      );
    }).toList();
  }

  void _openAlbumDetail(AlbumSummary album) {
    AppLog.log(
      '[NavTrace] CollectionDetailContent _openAlbumDetail: pushing AlbumDetailPage for album="${album.title}" (id=${album.id})',
      mirrorToConsole: true,
    );
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: '/album_detail/${Uri.encodeComponent(album.id)}',
        ),
        builder: (_) => AlbumDetailPage(album: album),
      ),
    );
  }

  List<Widget> _buildPortraitAlbumGridSlivers({
    required BuildContext context,
    required WidgetRef ref,
    required List<AlbumSummary> albums,
    required double contentWidth,
    required double albumZoomScale,
  }) {
    final audio = ref.read(audioServiceProvider);

    return [
      FolderZoomSliverBuilder(
        zoomScale: snapFolderZoomScale(albumZoomScale),
        width: contentWidth,
        builder: (context, metrics) {
          final hPad = folderContentHorizontalPadding(
            isPortrait: true,
            gridMorph: metrics.gridMorph,
          );

          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverGrid(
              gridDelegate: SliverAnimatedZoomGridDelegate(metrics: metrics),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final album = albums[index];
                  return DraggableAlbumItem(
                    album: album,
                    enabled: true,
                    child: AlbumZoomItem(
                      album: album,
                      metrics: metrics,
                      isSelected: false,
                      isSelectionMode: false,
                      enableHero: true,
                      onTap: () => _openAlbumDetail(album),
                      onSecondaryTapDown: (details) {
                        showAlbumContextMenu(
                          context: context,
                          globalPosition: details.globalPosition,
                          ref: ref,
                          album: album,
                        );
                      },
                      onPlay: () => audio.playPlaylist(
                        album.songs,
                        source: PlaybackSource(
                          type: PlaybackSourceType.album,
                          id: album.id,
                          name: album.title,
                        ),
                      ),
                    ),
                  );
                },
                childCount: albums.length,
              ),
            ),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final audio = ref.read(audioServiceProvider);
    final currentMusicPath = ref.watch(audioCurrentMusicProvider)?.path;

    _albumCache.update(widget.songs, l10n.unknownAlbum);
    final sections = _albumCache.sections;
    final displaySongs = _albumCache.allSongs;

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(displaySongs)
        : const <MusicFile>[];

    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final horizontalPadding = isPortrait ? 20.0 : 28.0;

    final durationLabel =
        formatDurationClock(widget.totalDurationMillis) ?? l10n.durationZero;

    final libraryAlbums = ref.watch(albumLibraryProvider).asData?.value;
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );
    final albums = _buildAlbums(sections, libraryAlbums, l10n.unknownArtist);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.min(constraints.maxWidth, kFolderPageMaxWidth);

        final scrollView = CustomScrollView(
          controller: widget.scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  widget.topPadding > 0 ? widget.topPadding + 12 : 24,
                  horizontalPadding,
                  isPortrait ? 30.0 : 20.0,
                ),
                child: CollectionDetailHeader(
                  title: widget.title,
                  metaLine:
                      '${l10n.songCount(widget.songCount)} · ${l10n.albumCount(widget.albumCount)} · $durationLabel',
                  onPlayAll: () => _playAll(displaySongs),
                  onShufflePlay: () =>
                      _playAll(List<MusicFile>.of(displaySongs)..shuffle()),
                ),
              ),
            ),
            if (sections.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(l10n.emptyList, style: theme.textTheme.titleMedium),
                ),
              )
            else if (isPortrait)
              ..._buildPortraitAlbumGridSlivers(
                context: context,
                ref: ref,
                albums: albums,
                contentWidth: contentWidth,
                albumZoomScale: albumZoomScale,
              )
            else
              for (int i = 0; i < sections.length; i++) ...[
                if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 36)),
                AlbumSectionSliver(
                  section: sections[i],
                  currentMusicPath: currentMusicPath,
                  onSongTap: (section, songIndex) {
                    final song = section.songs[songIndex];
                    final globalIndex = section.startIndex + songIndex;
                    handleSongTap(
                      index: globalIndex,
                      songPath: song.path,
                      allSongs: displaySongs,
                      onNormalTap: () {
                        audio.playPlaylist(
                          displaySongs,
                          initialIndex: globalIndex,
                          source: widget.source,
                        );
                      },
                    );
                  },
                  onSongLongPress: (section, song) {
                    final songIndex = section.songs.indexOf(song);
                    if (songIndex != -1) {
                      lastAnchorIndex = section.startIndex + songIndex;
                    }
                    if (!isSelectionMode) {
                      enterSongSelectionMode(song.path);
                    }
                  },
                  isSelectionMode: isSelectionMode,
                  selectedSongPaths: selectedSongPaths,
                ),
              ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: MiniPlayerUiTuning.getListBottomPadding(
                  context,
                  hasPlayingMusic: currentMusicPath != null,
                  isSelectionMode: widget.hasBottomPanel ||
                      (!isPortrait && isSelectionMode && widget.showSelectionPanel),
                  selectionPanelHeight: 220.0,
                ),
              ),
            ),
          ],
        );

        final scrollContent = isPortrait
            ? FolderZoomGestureLayer(
                scope: LibraryZoomScope.album,
                child: scrollView,
              )
            : scrollView;

        return Stack(
          children: [
            scrollContent,
            AnimatedSelectionPanel(
              isVisible: !isPortrait && isSelectionMode && widget.showSelectionPanel,
              child: LibrarySelectionPanel(
                key: const ValueKey('library-selection-panel'),
                selectedSongs: selectedSongs,
                allSongs: displaySongs,
                onToggleSelectAll: () => toggleSelectAllSongs(displaySongs),
                onCancel: cancelSongSelection,
              ),
            ),
          ],
        );
      },
    );
  }
}
