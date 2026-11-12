import 'dart:async';
import 'dart:math' as math;

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
import '../utils/search_selection_utils.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/album_context_menu.dart';
import '../widgets/album_cover.dart';
import '../widgets/artist_avatar.dart';
import '../widgets/artist_context_menu.dart';
import '../widgets/library_large_title.dart';
import '../widgets/library_search_field.dart';
import '../widgets/library_selection_back_guard.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/playlist_context_menu.dart';
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
///
/// 多选不按分节拆：整页只有一套选择集，键是 `<类型>:<id>`（见
/// `search_selection_utils.dart`）。选中专辑 / 艺术家 / 歌单时按「它包含的
/// 全部歌曲」参与批量动作，所以 Shift 连选、全选都能跨段连起来。
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

class _LibrarySearchPageState extends ConsumerState<LibrarySearchPage>
    with SelectionStateMixin<LibrarySearchPage, String> {
  static const int _songLimit = 60;
  static const int _entityLimit = 20;
  static const Duration _debounceDuration = Duration(milliseconds: 300);

  @override
  LibrarySelectionScope get selectionScope => LibrarySelectionScope.librarySearch;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  bool _isSearching = false;

  List<MusicFile> _songs = const [];

  /// 当前选择集展开后的歌曲。集合类条目（专辑 / 艺术家 / 歌单）取全部歌曲，
  /// 单曲取自身。批量面板与多选态下的右键菜单都拿它当作用对象。
  List<MusicFile> _selectedSongs = const [];

  /// 展开结果对应的选择集签名。选择集一变就重算，异步回来时签名不符则丢弃，
  /// 避免「先点专辑再点歌曲」时旧结果覆盖新结果。
  String _expandedSignature = '';

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
    // 结果会整体换掉，选择集里留着旧条目只会让面板统计对不上。
    if (isSelectionMode) cancelSelection();
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
    if (isSelectionMode) cancelSelection();
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

  /// 点击 / 长按 / 右键「多选」共用的入口。
  ///
  /// 长按一律进多选（与目录详情页、远程搜索页一致），移动端要操作单个条目
  /// 时走底部选择面板。
  void _enterSelection(String key, int index) {
    lastAnchorIndex = index;
    if (!isSelectionMode) {
      enterSelectionMode(key);
    } else {
      toggleSelection(key);
    }
  }

  /// 把当前选择集展开成歌曲，供面板与右键菜单复用。
  ///
  /// 在 build 里调用：签名没变就直接返回，变了才起异步展开。空选择集是同步
  /// 清空的，因为那一步没有 IO。
  void _syncSelectedSongs(List<SearchEntry> entries) {
    final keys = selectedKeys;
    final signature = (keys.toList()..sort()).join('\u0000');
    if (signature == _expandedSignature) return;
    _expandedSignature = signature;

    if (keys.isEmpty) {
      _selectedSongs = const [];
      return;
    }

    final selected = entries
        .where((entry) => keys.contains(entry.key))
        .toList(growable: false);
    unawaited(_expandSelectedSongs(selected, signature));
  }

  Future<void> _expandSelectedSongs(
    List<SearchEntry> entries,
    String signature,
  ) async {
    final scanner = ref.read(scannerServiceProvider);
    try {
      final songs = await expandSearchEntries(
        entries,
        scanner.getSongsForFolder,
      );
      if (!mounted || _expandedSignature != signature) return;
      setState(() => _selectedSongs = songs);
    } catch (error) {
      // 单个目录读不出来（外接盘拔了、权限丢了）不该让整份选择集失去作用，
      // 保留上一次展开结果即可。
      debugPrint('[SearchSelection] expand failed: $error');
    }
  }

  /// 多选态下右键某个条目：动作作用于整个选择集；否则只作用于这一条。
  List<MusicFile> _menuSongsFor(MusicFile song) {
    if (isSelectionMode && _selectedSongs.isNotEmpty) return _selectedSongs;
    return [song];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.sizeOf(context);
    final leftPadding = widget.contentLeftPadding;
    final horizontalPadding = size.width >= 780 ? 32.0 : 16.0;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final selectionActive = isSelectionMode;
    final bottomInset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: selectionActive,
      selectionPanelHeight: 120.0,
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

    // 页面视觉顺序的扁平条目序列：艺术家 → 歌单 → 专辑 → 歌曲。
    // Shift 连选、全选、展开成歌曲都按这一份算，所以跨段连选天然成立。
    final entries = <SearchEntry>[
      for (final artist in artists) SearchEntry.artist(artist),
      for (final playlist in playlists) SearchEntry.playlist(playlist),
      for (final album in albums) SearchEntry.album(album),
      for (final song in _songs) SearchEntry.song(song),
    ];
    final entryKeys = [for (final entry in entries) entry.key];
    final playlistBase = artists.length;
    final albumBase = playlistBase + playlists.length;
    final songBase = albumBase + albums.length;

    _syncSelectedSongs(entries);
    final allEntriesSelected =
        entries.isNotEmpty && selectedKeys.length == entries.length;

    // 各段拆成独立 sliver 挂进 CustomScrollView：专辑段改为竖向封面网格
    // （SliverGrid 保持懒加载），其余段落仍是按需构建的行列表。顺序与远程
    // 搜索页一致，歌曲放最后一段。
    final hasResults = entries.isNotEmpty;
    final contentWidth =
        math.min(size.width - leftPadding, kSingleColumnContentMaxWidth) -
        horizontalPadding * 2;

    return LibrarySelectionBackGuard(
      scope: LibrarySelectionScope.librarySearch,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
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
                            : Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: horizontalPadding,
                                ),
                                child: CustomScrollView(
                                  slivers: [
                                    const SliverPadding(
                                      padding: EdgeInsets.only(top: 4),
                                    ),
                                    if (artists.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: _sectionHeader(
                                          '${l10n.artists} (${artists.length})',
                                        ),
                                      ),
                                      SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => _artistRow(
                                            context,
                                            artists[index],
                                            index,
                                            entryKeys,
                                          ),
                                          childCount: artists.length,
                                        ),
                                      ),
                                      const SliverToBoxAdapter(
                                        child: SizedBox(height: 12),
                                      ),
                                    ],
                                    if (playlists.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: _sectionHeader(
                                          '${l10n.playlists} (${playlists.length})',
                                        ),
                                      ),
                                      SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => _playlistRow(
                                            context,
                                            playlists[index],
                                            playlistBase + index,
                                            entryKeys,
                                          ),
                                          childCount: playlists.length,
                                        ),
                                      ),
                                      const SliverToBoxAdapter(
                                        child: SizedBox(height: 12),
                                      ),
                                    ],
                                    if (albums.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: _sectionHeader(
                                          '${l10n.albums} (${albums.length})',
                                        ),
                                      ),
                                      _albumGridSliver(
                                        context,
                                        theme,
                                        albums,
                                        albumBase,
                                        entryKeys,
                                        contentWidth,
                                      ),
                                      const SliverToBoxAdapter(
                                        child: SizedBox(height: 12),
                                      ),
                                    ],
                                    if (_songs.isNotEmpty) ...[
                                      SliverToBoxAdapter(
                                        child: _sectionHeader(
                                          '${l10n.songs} (${_songs.length})',
                                        ),
                                      ),
                                      SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => _songRow(
                                            context,
                                            ref,
                                            _songs[index],
                                            index,
                                            songBase + index,
                                            entryKeys,
                                          ),
                                          childCount: _songs.length,
                                        ),
                                      ),
                                    ],
                                    SliverPadding(
                                      padding: EdgeInsets.only(
                                        bottom: bottomInset,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSelectionPanel(
              isVisible: selectionActive,
              child: LibrarySelectionPanel(
                key: const ValueKey('library-search-selection-panel'),
                selectedSongs: _selectedSongs,
                title: l10n.selectedItemsCount(selectedCount),
                isSelectionEmpty: selectedKeys.isEmpty,
                isAllSelected: allEntriesSelected,
                onToggleSelectAll: () => toggleSelectAll(entryKeys),
                onCancel: cancelSelection,
              ),
            ),
          ],
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

  /// 多选态下的勾选圈，行类的 leading 统一换成它。
  Widget _selectionLeading(ThemeData theme, bool selected) => Icon(
    selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
    color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
    size: 20,
  );

  Widget _songRow(
    BuildContext context,
    WidgetRef ref,
    MusicFile song,
    int localIndex,
    int index,
    List<String> entryKeys,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final key = songSelectionKey(song.path);
    final isSelected = isSelectionMode && selectedKeys.contains(key);
    final artist = song.artist?.trim();
    final album = song.album?.trim();
    final parts = [
      if (artist != null && artist.isNotEmpty) artist,
      if (album != null && album.isNotEmpty) album,
    ];

    void play() {
      ref.read(audioServiceProvider).playPlaylist(
        _songs,
        initialIndex: localIndex,
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: 'library_search',
          name: l10n.search,
        ),
      );
    }

    void openMenu(Offset globalPosition) {
      final songs = _menuSongsFor(song);
      showSongContextMenu(
        context,
        globalPosition,
        song: song,
        songs: songs,
        onMultiSelect: isSelectionMode
            ? null
            : () => _enterSelection(key, index),
        onPlayNext: () => ref.read(audioServiceProvider).enqueueNext(songs),
        onAddToQueue: () =>
            ref.read(audioServiceProvider).appendToQueue(songs),
        onAddToPlaylist: () => showAddSongsToPlaylistDialog(
          context,
          ref.read(playlistServiceProvider),
          songs,
        ),
      );
    }

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => handleItemTap(
          index: index,
          itemKey: key,
          allKeys: entryKeys,
          onNormalTap: play,
        ),
        onLongPress: () => _enterSelection(key, index),
        onSecondaryTapDown: (details) =>
            openMenu(details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              if (isSelectionMode) ...[
                _selectionLeading(theme, isSelected),
                const SizedBox(width: 10),
              ],
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
                        color: isSelected ? theme.colorScheme.primary : null,
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
      ),
    );
  }

  /// 专辑段改为竖向封面网格，网格数学与远程流派详情页同一套：
  /// 列数按 168 一列自适应，行高按封面 + 标题/艺人两行文本预留。
  Widget _albumGridSliver(
    BuildContext context,
    ThemeData theme,
    List<AlbumSummary> albums,
    int baseIndex,
    List<String> entryKeys,
    double contentWidth,
  ) {
    final columns = (contentWidth / 168).floor().clamp(2, 6);
    const spacing = 14.0;
    final cellWidth = (contentWidth - spacing * (columns - 1)) / columns;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final cellHeight = cellWidth + 54 * textScale;

    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: spacing,
        mainAxisSpacing: 18,
        mainAxisExtent: cellHeight,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _albumCard(
          context,
          theme,
          albums[index],
          baseIndex + index,
          entryKeys,
          cellWidth,
        ),
        childCount: albums.length,
      ),
    );
  }

  Widget _albumCard(
    BuildContext context,
    ThemeData theme,
    AlbumSummary album,
    int index,
    List<String> entryKeys,
    double coverSize,
  ) {
    final key = albumSelectionKey(album.id);
    final isSelected = isSelectionMode && selectedKeys.contains(key);

    void openDetails() => _openAlbumDetail(album);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => showAlbumContextMenu(
        context: context,
        globalPosition: details.globalPosition,
        ref: ref,
        album: album,
        onMultiSelect: isSelectionMode
            ? null
            : (selectionKey) => _enterSelection(key, index),
        onViewDetails: openDetails,
      ),
      onLongPress: () => _enterSelection(key, index),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => handleItemTap(
          index: index,
          itemKey: key,
          allKeys: entryKeys,
          onNormalTap: openDetails,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                AlbumCover(
                  album: album,
                  size: coverSize,
                  borderRadius: const BorderRadius.all(Radius.circular(10)),
                ),
                // 选中边框叠一层而不是给封面加 border：加 border 会把封面
                // inset 2px，进出多选时整个网格会抖一下。
                if (isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isSelectionMode)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artistRow(
    BuildContext context,
    ArtistSummary artist,
    int index,
    List<String> entryKeys,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final key = artistSelectionKey(artist.queryKey);
    final isSelected = isSelectionMode && selectedKeys.contains(key);

    void openDetails() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            name: '/artist_detail/${Uri.encodeComponent(artist.queryKey)}',
          ),
          builder: (_) => ArtistDetailPage(artist: artist),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => showArtistContextMenu(
        context: context,
        globalPosition: details.globalPosition,
        ref: ref,
        artist: artist,
        onMultiSelect: isSelectionMode
            ? null
            : (selectionKey) => _enterSelection(key, index),
        onViewDetails: openDetails,
      ),
      onLongPress: () => _enterSelection(key, index),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          onTap: () => handleItemTap(
            index: index,
            itemKey: key,
            allKeys: entryKeys,
            onNormalTap: openDetails,
          ),
          leading: isSelectionMode
              ? SizedBox(
                  width: 44,
                  child: Center(
                    child: _selectionLeading(theme, isSelected),
                  ),
                )
              : ArtistAvatar(
                  diameter: 44,
                  imagePath: artist.cachedImagePath,
                ),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : null,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
          ),
          subtitle: Text(l10n.songsCountFormat(artist.songCount)),
        ),
      ),
    );
  }

  Widget _playlistRow(
    BuildContext context,
    Playlist playlist,
    int index,
    List<String> entryKeys,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final key = playlistSelectionKey(playlist.id);
    final isSelected = isSelectionMode && selectedKeys.contains(key);

    void openDetails() {
      // 歌单详情页自己会复位 selectedPlaylistIdProvider 并出栈，这里不必再包一层返回回调。
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: 'playlist_detail_${playlist.id}'),
          builder: (_) => PlaylistDetailPage(playlist: playlist),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) => showPlaylistContextMenu(
        context: context,
        globalPosition: details.globalPosition,
        ref: ref,
        playlist: playlist,
        onMultiSelect: isSelectionMode
            ? null
            : (selectionKey) => _enterSelection(key, index),
        onViewDetails: openDetails,
      ),
      onLongPress: () => _enterSelection(key, index),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          onTap: () => handleItemTap(
            index: index,
            itemKey: key,
            allKeys: entryKeys,
            onNormalTap: openDetails,
          ),
          leading: isSelectionMode
              ? SizedBox(
                  width: 44,
                  child: Center(
                    child: _selectionLeading(theme, isSelected),
                  ),
                )
              : PlaylistCover(playlist: playlist, size: 44),
          title: Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : null,
              color: isSelected ? theme.colorScheme.primary : null,
            ),
          ),
          subtitle: Text(l10n.songsCountFormat(playlist.songs.length)),
        ),
      ),
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
