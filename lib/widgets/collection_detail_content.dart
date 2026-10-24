import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'album_sections.dart';
import 'collection_detail_header.dart';
import 'library_selection_panel.dart';
import 'library_selection_scope.dart';
import 'marquee/marquee_selection_region.dart';
import 'mini_player_wrapper.dart';

/// 流派 / 年份等「集合型」条目的详情内容。
///
/// 顶部为 [CollectionDetailHeader]，下方按专辑分组渲染曲目列表；
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

    // 框选区域包住列表与底部面板，拖动时框线不会被面板遮挡。
    final content = Stack(
      children: [
        CustomScrollView(
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
                  20,
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
                      (isSelectionMode && widget.showSelectionPanel),
                  selectionPanelHeight: 220.0,
                ),
              ),
            ),
          ],
        ),
        if (widget.showSelectionPanel)
          AnimatedSelectionPanel(
            isVisible: isSelectionMode,
            child: LibrarySelectionPanel(
              selectedSongs: selectedSongs,
              allSongs: displaySongs,
              onToggleSelectAll: () => toggleSelectAllSongs(displaySongs),
              onCancel: cancelSongSelection,
            ),
          ),
      ],
    );

    return MarqueeSelectionRegion(
      scope: selectionScope,
      scrollController: widget.scrollController,
      child: content,
    );
  }
}
