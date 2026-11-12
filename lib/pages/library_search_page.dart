import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/album_summary.dart';
import '../models/artist_summary.dart';
import '../models/music_file.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/library/album_library.dart';
import '../player/library/artist_library.dart';
import '../player/library/playlist_service.dart';
import '../utils/layout_constants.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/album_cover.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/library_large_title.dart';
import '../widgets/library_search_field.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/playlist_cover.dart';
import '../widgets/song_thumbnail.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';
import 'playlist_detail_page.dart';

/// 本地媒体库的全局搜索页。
///
/// 与各分类页头里的过滤框并存：分类页是「在这一类里筛」，本页是「先找到东西，
/// 再决定它属于哪一类」。歌曲走数据库检索，专辑 / 艺术家 / 歌单直接在内存中的
/// summary 列表上筛，因此一次输入要同时喂两路数据源。
class LibrarySearchPage extends ConsumerStatefulWidget {
  const LibrarySearchPage({
    super.key,
    this.contentTopPadding = 0.0,
    this.contentLeftPadding = 0.0,
  });

  final double contentTopPadding;
  final double contentLeftPadding;

  @override
  ConsumerState<LibrarySearchPage> createState() => _LibrarySearchPageState();
}

class _LibrarySearchPageState extends ConsumerState<LibrarySearchPage> {
  static const int _songLimit = 60;
  static const int _entityLimit = 20;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  bool _isSearching = false;

  List<MusicFile> _songs = const [];

  @override
  void initState() {
    super.initState();
    // 进入本页就是为了搜东西，键盘直接弹出，省一次点击。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();
    setState(() => _query = query);
    if (query.isEmpty) {
      _clearResults();
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(_debounceDuration, () => _runSearch(query));
  }

  void _onQueryCleared() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _isSearching = false;
    });
    _clearResults();
  }

  void _clearResults() {
    setState(() {
      _songs = const [];
      _isSearching = false;
    });
  }

  Future<void> _runSearch(String query) async {
    final songs = await ref.read(scannerServiceProvider).searchSongs(query);
    // 迟到的结果不能覆盖：用户可能已经继续输入，此时按旧词回填会显示错列表。
    if (!mounted || _query != query) return;

    setState(() {
      _songs = songs.take(_songLimit).toList(growable: false);
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.sizeOf(context);
    final leftPadding = widget.contentLeftPadding;
    final horizontalPadding = size.width >= 780 ? 32.0 : 16.0;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final bottomInset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
    );

    // 专辑 / 艺术家 / 歌单都是内存里的 summary 列表，直接在构建时按当前词筛：
    // 这三类数据是异步流，防抖到期的那一刻可能还没加载完，若在搜索回调里快照
    // 一次，数据到达后分组会一直空着。分类页同样是每次构建重筛。
    final albums = _query.isEmpty
        ? const <AlbumSummary>[]
        : filterAlbums(
            ref.watch(albumLibraryProvider).value ?? const [],
            _query,
          ).take(_entityLimit).toList(growable: false);
    final artists = _query.isEmpty
        ? const <ArtistSummary>[]
        : filterArtists(
            ref.watch(artistLibraryProvider).value ?? const [],
            _query,
          ).take(_entityLimit).toList(growable: false);
    final playlists = _query.isEmpty
        ? const <Playlist>[]
        : filterPlaylists(
            ref.watch(playlistServiceProvider).playlists,
            _query,
          ).take(_entityLimit).toList(growable: false);

    // 四段共用同一个懒加载列表：命中歌曲可能上千条，一次性建出所有行
    // 会同时发起大量封面解析。顺序与远程搜索页一致，歌曲放最后一段，
    // 前面的段落各自带一条尾部间距。
    final artistLen = artists.isEmpty ? 0 : artists.length + 2;
    final playlistLen = playlists.isEmpty ? 0 : playlists.length + 2;
    final albumLen = albums.isEmpty ? 0 : 3;
    final songLen = _songs.isEmpty ? 0 : _songs.length + 1;
    final itemCount = artistLen + playlistLen + albumLen + songLen;
    final hasResults = itemCount > 0;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(left: leftPadding),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kSingleColumnContentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    widget.contentTopPadding + 16,
                    horizontalPadding,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LibraryLargeTitle(title: l10n.search),
                      const SizedBox(height: 10),
                      LibrarySearchField(
                        controller: _controller,
                        focusNode: _focusNode,
                        query: _query,
                        hintText: l10n.searchLibraryHint,
                        onChanged: _onQueryChanged,
                        onClear: _onQueryCleared,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !hasResults
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? l10n.typeToSearch
                                : _isSearching
                                ? l10n.searching
                                : l10n.noMatchingResults,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            4,
                            horizontalPadding,
                            bottomInset,
                          ),
                          itemCount: itemCount,
                          itemBuilder: (context, index) {
                            if (index < artistLen) {
                              if (index == 0) {
                                return _sectionHeader(
                                  '${l10n.artists} (${artists.length})',
                                );
                              }
                              if (index == artistLen - 1) {
                                return const SizedBox(height: 12);
                              }
                              return _artistRow(context, artists[index - 1]);
                            }
                            var local = index - artistLen;
                            if (local < playlistLen) {
                              if (local == 0) {
                                return _sectionHeader(
                                  '${l10n.playlists} (${playlists.length})',
                                );
                              }
                              if (local == playlistLen - 1) {
                                return const SizedBox(height: 12);
                              }
                              return _playlistRow(
                                context,
                                playlists[local - 1],
                              );
                            }
                            local -= playlistLen;
                            if (local < albumLen) {
                              if (local == 0) {
                                return _sectionHeader(
                                  '${l10n.albums} (${albums.length})',
                                );
                              }
                              if (local == albumLen - 1) {
                                return const SizedBox(height: 12);
                              }
                              return _albumStrip(context, theme, albums);
                            }
                            local -= albumLen;
                            if (local == 0) {
                              return _sectionHeader(
                                '${l10n.songs} (${_songs.length})',
                              );
                            }
                            return _songRow(
                              context,
                              ref,
                              _songs[local - 1],
                              local - 1,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
  );

  Widget _songRow(
    BuildContext context,
    WidgetRef ref,
    MusicFile song,
    int index,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final artist = song.artist?.trim();
    final album = song.album?.trim();
    final parts = [
      if (artist != null && artist.isNotEmpty) artist,
      if (album != null && album.isNotEmpty) album,
    ];

    void play() {
      ref.read(audioServiceProvider).playPlaylist(
        _songs,
        initialIndex: index,
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: 'library_search',
          name: l10n.search,
        ),
      );
    }

    void openMenu({Offset? globalPosition}) {
      void onPlayNext() => ref.read(audioServiceProvider).enqueueNext([song]);
      void onAddToQueue() =>
          ref.read(audioServiceProvider).appendToQueue([song]);
      Future<void> addToPlaylist() => showAddSongsToPlaylistDialog(
        context,
        ref.read(playlistServiceProvider),
        [song],
      );

      if (globalPosition == null) {
        showSongBottomSheet(
          context,
          song: song,
          songs: [song],
          onPlayNext: onPlayNext,
          onAddToQueue: onAddToQueue,
          onAddToPlaylist: addToPlaylist,
        );
        return;
      }
      showSongContextMenu(
        context,
        globalPosition,
        song: song,
        songs: [song],
        onPlayNext: onPlayNext,
        onAddToQueue: onAddToQueue,
        onAddToPlaylist: addToPlaylist,
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: play,
      onLongPress: () => openMenu(),
      onSecondaryTapDown: (details) =>
          openMenu(globalPosition: details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            SongThumbnail.fromSong(
              song,
              size: 44,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parts.isEmpty ? l10n.unknownArtist : parts.join(' - '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _albumStrip(
    BuildContext context,
    ThemeData theme,
    List<AlbumSummary> albums,
  ) {
    const coverSize = 100.0;
    const cardWidth = coverSize + 10.0;

    return SizedBox(
      height: 152,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        itemBuilder: (context, index) {
          final album = albums[index];
          return Container(
            width: cardWidth,
            margin: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openAlbumDetail(album),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AlbumCover(album: album, size: coverSize),
                    const SizedBox(height: 6),
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _artistRow(BuildContext context, ArtistSummary artist) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ArtistAvatar(diameter: 44, imagePath: artist.cachedImagePath),
      title: Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.songsCountFormat(artist.songCount)),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(
              name: '/artist_detail/${Uri.encodeComponent(artist.queryKey)}',
            ),
            builder: (_) => ArtistDetailPage(artist: artist),
          ),
        );
      },
    );
  }

  Widget _playlistRow(BuildContext context, Playlist playlist) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: PlaylistCover(playlist: playlist, size: 44),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(l10n.songsCountFormat(playlist.songs.length)),
      onTap: () {
        // 歌单详情页自己会复位 selectedPlaylistIdProvider 并出栈，这里不必再包一层返回回调。
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: RouteSettings(name: 'playlist_detail_${playlist.id}'),
            builder: (_) => PlaylistDetailPage(playlist: playlist),
          ),
        );
      },
    );
  }

  void _openAlbumDetail(AlbumSummary album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(
          name: '/album_detail/${Uri.encodeComponent(album.id)}',
        ),
        builder: (_) => AlbumDetailPage(album: album),
      ),
    );
  }
}

/// 专辑命中：标题或艺术家包含关键词即算，与专辑页头部过滤保持一致。
List<AlbumSummary> filterAlbums(List<AlbumSummary> albums, String query) {
  final lower = query.toLowerCase();
  if (lower.isEmpty) return albums;
  return albums
      .where(
        (album) =>
            album.title.toLowerCase().contains(lower) ||
            album.artist.toLowerCase().contains(lower),
      )
      .toList(growable: false);
}

/// 艺术家命中：与艺术家页一致，除艺人名外还认别名、全名、国籍与标签。
List<ArtistSummary> filterArtists(
  List<ArtistSummary> artists,
  String query,
) {
  final lower = query.toLowerCase();
  if (lower.isEmpty) return artists;
  return artists.where((artist) {
    return artist.name.toLowerCase().contains(lower) ||
        artist.queryKey.toLowerCase().contains(lower) ||
        (artist.canonicalName?.toLowerCase().contains(lower) ?? false) ||
        artist.alternateNames.any((alt) => alt.toLowerCase().contains(lower)) ||
        (artist.disambiguation?.toLowerCase().contains(lower) ?? false) ||
        (artist.country?.toLowerCase().contains(lower) ?? false) ||
        artist.tags.any((tag) => tag.toLowerCase().contains(lower));
  }).toList(growable: false);
}

/// 歌单命中：按歌单名筛。
List<Playlist> filterPlaylists(List<Playlist> playlists, String query) {
  final lower = query.toLowerCase();
  if (lower.isEmpty) return playlists;
  return playlists
      .where((playlist) => playlist.name.toLowerCase().contains(lower))
      .toList(growable: false);
}
