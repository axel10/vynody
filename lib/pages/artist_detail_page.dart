import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/metadata/theaudiodb_artist_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/app_log.dart';
import '../widgets/album_context_menu.dart';
import '../widgets/album_sections.dart';
import '../widgets/album_zoom_item.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/draggable_album_item.dart';
import '../widgets/folder_layout_utils.dart';
import '../widgets/remote_media_badge.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/library_search_field.dart';
import '../widgets/detail_content_scaffold.dart';
import '../widgets/detail_page_shell.dart';
import '../widgets/library_selection_back_guard.dart';
import 'album_detail_page.dart';

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({
    super.key,
    required this.artist,
    this.onGoBack,
  });

  final ArtistSummary artist;
  final VoidCallback? onGoBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LibrarySelectionBackGuard(
      child: DetailPageShell(
        title: artist.name,
        parentTitle: l10n?.artists,
        titleKey: const ValueKey('album_title'),
        onGoBack: onGoBack,
        contentBuilder: (context, scrollController, topPadding) =>
            ArtistDetailContent(
          artist: artist,
          scrollController: scrollController,
          topPadding: topPadding,
        ),
      ),
    );
  }
}

class ArtistDetailContent extends ConsumerStatefulWidget {
  const ArtistDetailContent({
    super.key,
    required this.artist,
    this.showSelectionPanel = true,
    this.hasBottomPanel = false,
    this.scrollController,
    this.topPadding = 0.0,
  });

  final ArtistSummary artist;
  final bool showSelectionPanel;
  final bool hasBottomPanel;
  final ScrollController? scrollController;
  final double topPadding;

  @override
  ConsumerState<ArtistDetailContent> createState() => _ArtistDetailContentState();
}

class _ArtistDetailContentState extends ConsumerState<ArtistDetailContent>
    with
        SelectionStateMixin<ArtistDetailContent, String>,
        SongSelectionMixin<ArtistDetailContent> {
  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.library;

  String? _cachedImagePath;
  StreamSubscription<String>? _imageUpdateSub;

  final AlbumSectionsCache _albumCache = AlbumSectionsCache();

  /// 艺术家内搜索：默认收起，点页头下方的放大镜展开。
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  bool _searchOpen = false;
  String _query = '';

  /// 输入防抖。一位艺术家可能挂着几十张专辑全集，
  /// 每敲一个字都重建一遍分组会掉帧。
  Timer? _queryDebounce;

  @override
  void initState() {
    super.initState();
    _cachedImagePath = widget.artist.cachedImagePath;
    _imageUpdateSub = TheAudioDbArtistService.instance.onArtistImageUpdated
        .listen((queryKey) {
      if (queryKey == widget.artist.queryKey && mounted) {
        _refreshImage();
      }
    });
    _fetchArtistImageIfNeeded();
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _queryController.dispose();
    _queryFocus.dispose();
    _imageUpdateSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArtistDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artist.queryKey != widget.artist.queryKey) {
      // 换艺术家时别把上一位的搜索词带过来。
      _queryDebounce?.cancel();
      _queryController.clear();
      _query = '';
      _searchOpen = false;
      _cachedImagePath = widget.artist.cachedImagePath;
      _fetchArtistImageIfNeeded();
    } else if (widget.artist.cachedImagePath != null &&
        widget.artist.cachedImagePath != _cachedImagePath) {
      _cachedImagePath = widget.artist.cachedImagePath;
    }
  }

  /// 当前搜索词命中后的分组，空词时原样返回。
  ///
  /// 命中口径统一走 [filterAlbumSections]：整页都是这位艺术家，
  /// 再按歌手名过滤没有意义，但口径保持一致可以少一套分支。
  List<AlbumSection> _visibleSections(List<AlbumSection> sections) =>
      filterAlbumSections(sections, _query);

  void _onQueryChanged(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final next = value.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
  }

  void _toggleSearch() {
    final open = !_searchOpen;
    setState(() {
      _queryDebounce?.cancel();
      _searchOpen = open;
      if (!open) {
        // 收起必须连带清空，否则列表还停在旧结果上，看起来像数据丢了。
        _queryController.clear();
        _query = '';
      }
    });
    if (open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _queryFocus.requestFocus();
      });
    } else {
      _queryFocus.unfocus();
    }
  }

  void _clearQuery() {
    _queryDebounce?.cancel();
    _queryController.clear();
    setState(() => _query = '');
    _queryFocus.requestFocus();
  }

  Future<void> _refreshImage() async {
    final imagePath = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist, priority: true);
    if (!mounted) return;
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        imagePath != _cachedImagePath) {
      setState(() {
        _cachedImagePath = imagePath;
      });
      ref.invalidate(artistLibraryProvider);
    }
  }

  Future<void> _fetchArtistImageIfNeeded() async {
    if (_cachedImagePath != null &&
        _cachedImagePath!.isNotEmpty &&
        File(_cachedImagePath!).existsSync()) {
      return;
    }
    final imagePath = await TheAudioDbArtistService.instance
        .fetchAndCacheArtistImage(widget.artist, priority: true);
    if (!mounted) return;
    if (imagePath != null &&
        imagePath.isNotEmpty &&
        imagePath != _cachedImagePath) {
      setState(() {
        _cachedImagePath = imagePath;
      });
      ref.invalidate(artistLibraryProvider);
    }
  }

  PlaybackSource get _artistSource => PlaybackSource(
        type: PlaybackSourceType.artist,
        id: widget.artist.queryKey,
        name: widget.artist.name,
      );

  List<AlbumSummary> _buildAlbums(
    List<AlbumSection> sections,
    List<AlbumSummary>? libraryAlbums,
    String artistName,
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
          (firstSong?.albumArtist ?? firstSong?.artist ?? artistName).trim();
      final expectedId =
          '${section.title.toLowerCase()}::${effectiveArtist.toLowerCase()}';

      final matched = libraryMap[expectedId];
      if (matched != null) return matched;

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
        artist: effectiveArtist.isNotEmpty ? effectiveArtist : artistName,
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
      '[NavTrace] ArtistDetailPage _openAlbumDetail: pushing AlbumDetailPage for album="${album.title}" (id=${album.id})',
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
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    _albumCache.update(widget.artist.songs, l10n.unknownAlbum);
    final sections = _albumCache.sections;
    final displaySongs = _albumCache.allSongs;

    final visibleSections = _visibleSections(sections);
    final visibleSongs = identical(visibleSections, sections)
        ? displaySongs
        : [
            for (final section in visibleSections) ...section.songs,
          ];

    final selectedSongs = isSelectionMode
        ? getSelectedSongs(visibleSongs)
        : const <MusicFile>[];

    final libraryAlbums = ref.watch(albumLibraryProvider).asData?.value;
    final albumZoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.albumZoomScale),
    );
    final albums = _buildAlbums(
      visibleSections,
      libraryAlbums,
      widget.artist.name,
    );

    return DetailContentScaffold(
      scrollController: widget.scrollController,
      topPadding: widget.topPadding,
      hasPlayingMusic: currentMusic != null,
      hasBottomPanel: widget.hasBottomPanel,
      isSelectionMode: isSelectionMode,
      showSelectionPanel: widget.showSelectionPanel,
      portraitZoomScope: LibraryZoomScope.album,
      isSearchOpen: _searchOpen,
      searchField: DetailSearchBox(
        isOpen: _searchOpen,
        child: LibrarySearchField(
          controller: _queryController,
          focusNode: _queryFocus,
          hintText: l10n.searchInArtist,
          query: _query,
          onChanged: _onQueryChanged,
          onClear: _clearQuery,
        ),
      ),
      headerBuilder: (context, isPortrait) => _buildArtistHeader(
        l10n: l10n,
        audio: audio,
        visibleSongs: visibleSongs,
        isPortrait: isPortrait,
      ),
      bodySliversBuilder: (context, isPortrait, contentWidth) {
        if (sections.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(l10n.emptyList, style: theme.textTheme.titleMedium),
              ),
            ),
          ];
        }
        if (visibleSections.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: DetailNoMatchView(
                message: l10n.noMatchingInArtist,
                onClear: _clearQuery,
              ),
            ),
          ];
        }
        if (isPortrait) {
          return _buildPortraitAlbumGridSlivers(
            context: context,
            ref: ref,
            albums: albums,
            contentWidth: contentWidth,
            albumZoomScale: albumZoomScale,
          );
        }
        return [
          for (int i = 0; i < visibleSections.length; i++) ...[
            if (i > 0) const SliverToBoxAdapter(child: SizedBox(height: 36)),
            AlbumSectionSliver(
              section: visibleSections[i],
              currentMusicPath: currentMusic?.path,
              onSongTap: (section, songIndex) {
                final song = section.songs[songIndex];
                final globalIndex = section.startIndex + songIndex;
                handleSongTap(
                  index: globalIndex,
                  songPath: song.path,
                  allSongs: visibleSongs,
                  onNormalTap: () {
                    audio.playPlaylist(
                      visibleSongs,
                      initialIndex: globalIndex,
                      source: _artistSource,
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
              onOpenAlbum: i < albums.length
                  ? () => _openAlbumDetail(albums[i])
                  : null,
            ),
          ],
        ];
      },
      selectionPanel: LibrarySelectionPanel(
        key: const ValueKey('library-selection-panel'),
        selectedSongs: selectedSongs,
        allSongs: visibleSongs,
        onToggleSelectAll: () => toggleSelectAllSongs(visibleSongs),
        onCancel: cancelSongSelection,
      ),
    );
  }

  Widget _buildArtistHeader({
    required AppLocalizations l10n,
    required dynamic audio,
    required List<MusicFile> visibleSongs,
    required bool isPortrait,
  }) {
    final songCountLabel =
        l10n.songCount(_query.isEmpty ? widget.artist.songCount : visibleSongs.length);
    final metaParts = <String>[
      songCountLabel,
      if ((widget.artist.country?.trim().isNotEmpty ?? false))
        widget.artist.country!.trim(),
      if ((widget.artist.areaName?.trim().isNotEmpty ?? false))
        widget.artist.areaName!.trim(),
      if (widget.artist.tags.isNotEmpty)
        widget.artist.tags.take(3).join(', '),
    ];

    final subtitles = <DetailHeaderSubtitle>[
      if (widget.artist.hasDistinctCanonicalName)
        DetailHeaderSubtitle(
          widget.artist.canonicalName!.trim(),
          isEmphasized: true,
          topSpacing: 2,
        ),
      if (widget.artist.disambiguation?.trim().isNotEmpty ?? false)
        DetailHeaderSubtitle(
          widget.artist.disambiguation!.trim(),
          topSpacing: 2,
        ),
      if (metaParts.isNotEmpty) DetailHeaderSubtitle(metaParts.join(' · ')),
    ];

    return DetailHeader(
      title: widget.artist.name,
      titleTrailing: RemoteMediaBadge.pillTrailing(
        songs: widget.artist.songs,
        title: widget.artist.name,
      ),
      subtitles: subtitles,
      avatarBuilder: (size) {
        final avatar = ArtistAvatar(
          diameter: size,
          imagePath: _cachedImagePath ?? widget.artist.cachedImagePath,
          imageUrl: widget.artist.imageUrl,
        );
        if (!isPortrait) return avatar;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: avatar,
        );
      },
      onPlayAll: () =>
          audio.playPlaylist(visibleSongs, source: _artistSource),
      onShufflePlay: () => audio.playPlaylist(
        List.of(visibleSongs)..shuffle(),
        source: _artistSource,
      ),
      searchToggle: DetailSearchToggleButton(
        isOpen: _searchOpen,
        onPressed: _toggleSearch,
      ),
    );
  }
}
