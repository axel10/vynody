import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/music_file.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../player/remote/remote_server_riverpod.dart';
import '../../../player/remote/services/remote_download_service.dart';
import '../../../utils/remote_context_menu_utils.dart';
import '../../../utils/search_selection_utils.dart';
import '../../../utils/selection_utils.dart';
import '../../../widgets/library_large_title.dart';
import '../../../widgets/remote_artwork_widget.dart';
import 'remote_library_common_widgets.dart';
import 'remote_library_toolbar_widgets.dart';

class RemoteLibrarySearchToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final bool isSearching;
  final VoidCallback onClearSearch;

  /// 页头标题与返回概览页。搜索是独立子页，与本地各分类页一样需要
  /// 一个大标题行来承载返回入口。
  final String? title;
  final VoidCallback? onBack;

  const RemoteLibrarySearchToolbar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.isSearching,
    required this.onClearSearch,
    this.title,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      // 搜索页没有 `LibraryCategoryHeader` 那层自带 16 的容器，
      // 水平内边距要自己给，否则标题与搜索框会贴到屏幕边缘。
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            LibraryLargeTitle(
              title: title!,
              showBackButton: onBack != null,
              onBack: onBack,
            ),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RemoteSearchBar(
              controller: searchController,
              hintText: l10n.searchRemoteHint,
              searchQuery: searchController.text,
              onChanged: onSearchChanged,
              onClear: onClearSearch,
              trailing: isSearching
                  ? const UnconstrainedBox(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 远程媒体库搜索页的结果区。
///
/// 多选与本地搜索页同构：艺术家 / 专辑 / 歌曲三段共用**一套**选择集，键是
/// `<类型>:<id>`（见 `search_selection_utils.dart`）。勾选艺术家或专辑时按
/// 「它包含的全部歌曲」参与批量动作，所以同一页里可以自由混选，Shift 连选也
/// 能按视觉顺序（艺术家 → 专辑 → 歌曲）跨段连起来。
///
/// 索引与键必须同源：页面视觉顺序由 [entryKeysFor] 唯一决定，视图内部按这个
/// 序列算各段 base 索引，调用方算「全选」也用同一份，禁止各自推一遍。
class RemoteLibrarySearchView extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final TextEditingController searchController;
  final List<MusicFile> searchedSongs;
  final List<Map<String, dynamic>> searchedAlbums;
  final List<Map<String, dynamic>> searchedArtists;
  final bool isSearching;
  final double bottomOffset;

  /// 整页是否处于多选态（选择集非空）。
  final bool isSelectionMode;

  /// 当前选择集，键为 `album:<id>` / `artist:<id>` / `song:<path>`。
  final Set<String> selectedKeys;

  /// Shift 连选的锚点（[entryKeysFor] 序列里的下标）。
  final int? lastAnchorIndex;

  final void Function(Set<String> keys) onSetSelection;
  final void Function(String key) onToggleSelection;
  final void Function(int? index) onUpdateAnchor;

  /// 多选态下右键歌曲时，把整份选择集展开成曲目批次。
  ///
  /// 远程的专辑 / 艺术家条目不带曲目，展开必须走网络，所以交给页面注入。
  final Future<List<RemoteDownloadBatch>> Function()? resolveSelectionBatches;

  final Widget? toolbar;

  const RemoteLibrarySearchView({
    super.key,
    required this.server,
    required this.password,
    required this.searchController,
    required this.searchedSongs,
    required this.searchedAlbums,
    required this.searchedArtists,
    this.isSearching = false,
    required this.bottomOffset,
    required this.isSelectionMode,
    required this.selectedKeys,
    required this.lastAnchorIndex,
    required this.onSetSelection,
    required this.onToggleSelection,
    required this.onUpdateAnchor,
    this.resolveSelectionBatches,
    this.toolbar,
  });

  /// 页面条目的扁平键序列，顺序即视觉顺序：艺术家 → 专辑 → 歌曲。
  ///
  /// 全选、Shift 连选、各段 base 索引都只认这一份，避免「键的顺序」和
  /// 「行渲染的顺序」各推一遍后错位。空 id 也照样占位，否则某一段里出现
  /// 一条残缺数据就会让后面所有条目的下标整体偏移。
  static List<String> entryKeysFor({
    required List<Map<String, dynamic>> artists,
    required List<Map<String, dynamic>> albums,
    required List<MusicFile> songs,
  }) {
    return [
      for (final artist in artists)
        artistSelectionKey(artist['id']?.toString() ?? ''),
      for (final album in albums) albumSelectionKey(album['id']?.toString() ?? ''),
      for (final song in songs) songSelectionKey(song.path),
    ];
  }

  String _buildSongSubtitle(MusicFile song, AppLocalizations l10n) {
    final album = song.album?.trim();
    final artist = song.artist?.trim();
    final parts = [
      if (album != null && album.isNotEmpty) album,
      if (artist != null && artist.isNotEmpty) artist,
    ];
    if (parts.isNotEmpty) {
      return parts.join(' - ');
    }
    return l10n.unknownArtist;
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

  /// 长按 / 右键「多选」共用的入口：记锚点再切一条。
  void _enterSelection(int index, String key) {
    onUpdateAnchor(index);
    onToggleSelection(key);
  }

  /// 三段行共用的一条点击：Shift 连选、Ctrl 点选、普通点击各走各的。
  ///
  /// 键从 `entryKeys[index]` 取，索引与键天然同源；`onNormalTap` 只在非多选态
  /// 且没按修饰键时执行（进详情 / 播放）。
  void _handleTap({
    required int index,
    required String key,
    required List<String> entryKeys,
    required VoidCallback onNormalTap,
  }) {
    SelectionActionHelper.handleItemTap<String, String>(
      index: index,
      itemKey: key,
      items: entryKeys,
      keySelector: (entry) => entry,
      isSelectionMode: isSelectionMode,
      selectedKeys: selectedKeys,
      lastAnchorIndex: lastAnchorIndex,
      onUpdateAnchor: onUpdateAnchor,
      onSetSelection: onSetSelection,
      onToggleSelection: onToggleSelection,
      onNormalTap: onNormalTap,
    );
  }

  Widget _artistRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    Map<String, dynamic> artist,
    int index,
    List<String> entryKeys,
  ) {
    final artistId = artist['id'] as String? ?? '';
    final artistName = artist['name'] as String? ?? l10n.unknownArtist;
    final coverArtId = artist['coverArt'] as String?;
    final albumCount = artist['albumCount'] as int?;
    final key = entryKeys[index];
    final isSelected = isSelectionMode && selectedKeys.contains(key);
    final isStarred = (ref
                .watch(activeRemoteSessionProvider)
                ?.navidromeStarredArtistIds
                ?.contains(artistId) ==
            true) ||
        artist['isFavorite'] == true ||
        artist['starred'] != null;

    void openDetails() {
      RemoteLibraryNavUtils.openArtist(
        context,
        server: server,
        password: password,
        artistId: artistId,
        artistName: artistName,
        coverArtId: coverArtId,
        albumCount: albumCount,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 多选态下菜单照常弹，只是不再提供「多选」入口 —— 与本地搜索页一致。
      onSecondaryTapDown: (details) {
        showRemoteArtistContextMenu(
          context: context,
          globalPosition: details.globalPosition,
          ref: ref,
          server: server,
          password: password,
          artistId: artistId,
          artistName: artistName,
          isStarred: isStarred,
          onMultiSelect: isSelectionMode
              ? null
              : () => _enterSelection(index, key),
          onViewDetails: openDetails,
        );
      },
      onLongPressStart: (details) => _enterSelection(index, key),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _handleTap(
            index: index,
            key: key,
            entryKeys: entryKeys,
            onNormalTap: openDetails,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: RemoteArtworkWidget(
                server: server,
                password: password,
                coverArtId: coverArtId,
                size: 40,
              ),
            ),
            title: Text(
              artistName,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : null,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
            subtitle: albumCount != null
                ? Text(l10n.albumCount(albumCount))
                : null,
            trailing: isSelectionMode
                ? Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    size: 20,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// 专辑段改为竖向封面网格，网格数学与远程流派详情页同一套：
  /// 列数按 168 一列自适应，行高按封面 + 标题/艺人两行文本预留。
  Widget _albumGridSliver(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    double contentWidth,
    int baseIndex,
    List<String> entryKeys,
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
          ref,
          l10n,
          theme,
          searchedAlbums[index],
          baseIndex + index,
          entryKeys,
          cellWidth,
        ),
        childCount: searchedAlbums.length,
      ),
    );
  }

  Widget _albumCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    Map<String, dynamic> album,
    int index,
    List<String> entryKeys,
    double coverSize,
  ) {
    final albumId = album['id'] as String? ?? '';
    final title = album['name'] as String? ??
        album['title'] as String? ??
        l10n.unknownAlbum;
    final artist = album['artist'] as String? ?? l10n.unknownArtist;
    final coverId = album['coverArt'] as String?;
    final key = entryKeys[index];
    final isSelected = isSelectionMode && selectedKeys.contains(key);

    void openDetails() {
      RemoteLibraryNavUtils.openAlbum(
        context,
        server: server,
        password: password,
        albumId: albumId,
        albumName: title,
        artistName: artist,
        coverArtId: coverId,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        showRemoteAlbumContextMenu(
          context: context,
          globalPosition: details.globalPosition,
          ref: ref,
          server: server,
          password: password,
          albumId: albumId,
          albumTitle: title,
          artistName: artist,
          coverArtId: coverId,
          onMultiSelect: isSelectionMode
              ? null
              : () => _enterSelection(index, key),
          onViewDetails: openDetails,
        );
      },
      onLongPressStart: (details) => _enterSelection(index, key),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _handleTap(
            index: index,
            key: key,
            entryKeys: entryKeys,
            onNormalTap: openDetails,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: isSelected ? 2 : 0,
                      ),
                    ),
                    child: RemoteArtworkWidget(
                      server: server,
                      password: password,
                      coverArtId: coverId,
                      size: coverSize,
                      width: coverSize,
                      height: coverSize,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  if (isSelectionMode)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: isSelected
                              ? theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.3)
                              : Colors.black26,
                        ),
                      ),
                    ),
                  if (isSelectionMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (_) => onToggleSelection(key),
                          fillColor: WidgetStateProperty.all(Colors.white),
                          checkColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? theme.colorScheme.primary : null,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _songRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    MusicFile song,
    int songIndex,
    int index,
    List<String> entryKeys,
  ) {
    final key = entryKeys[index];
    final isSelected = isSelectionMode && selectedKeys.contains(key);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        showRemoteSongContextMenu(
          context: context,
          globalPosition: details.globalPosition,
          ref: ref,
          server: server,
          password: password,
          song: song,
          onMultiSelect: isSelectionMode
              ? null
              : () => _enterSelection(index, key),
          // 多选态下整份选择集才是动作对象：专辑 / 艺术家的曲目要现拉，
          // 由页面注入的批次解析负责。非多选态仍是单曲。
          resolveSelectionBatches:
              isSelectionMode ? resolveSelectionBatches : null,
        );
      },
      onLongPressStart: (details) => _enterSelection(index, key),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _handleTap(
            index: index,
            key: key,
            entryKeys: entryKeys,
            onNormalTap: () async {
              final audioService = ref.read(audioServiceProvider);
              await audioService.playPlaylist(
                searchedSongs,
                initialIndex: songIndex,
              );
            },
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: isSelectionMode
                ? Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    size: 20,
                  )
                : const Icon(Icons.music_note_rounded),
            title: Text(
              song.title ?? song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : null,
              ),
            ),
            subtitle: Text(
              _buildSongSubtitle(song, l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final isEmpty = searchedSongs.isEmpty &&
        searchedAlbums.isEmpty &&
        searchedArtists.isEmpty;

    // 各段拆成独立 sliver 挂进 CustomScrollView：专辑段改为竖向封面网格
    // （SliverGrid 保持懒加载），其余段落仍是按需构建的行列表。
    // 水平 16 内边距由外层 Padding 统一扣，列数按可用宽度自适应。
    final hasResults = !isEmpty;

    // 视觉顺序的唯一来源：艺术家 → 专辑 → 歌曲。各段 base 索引也按它算，
    // 与调用方算「全选」用的是同一份序列。
    final entryKeys = RemoteLibrarySearchView.entryKeysFor(
      artists: searchedArtists,
      albums: searchedAlbums,
      songs: searchedSongs,
    );
    final albumBase = searchedArtists.length;
    final songBase = albumBase + searchedAlbums.length;

    return RemoteContentConstraint(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (toolbar != null) RemotePageHeaderSlot(child: toolbar!),
          Expanded(
            child: !hasResults
                ? Center(
                    child: isSearching
                        ? const CircularProgressIndicator()
                        : Text(
                            searchController.text.trim().isEmpty
                                ? l10n.typeToSearch
                                : l10n.noMatchingResults,
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = constraints.maxWidth - 32;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CustomScrollView(
                          slivers: [
                            const SliverPadding(
                              padding: EdgeInsets.only(top: 4),
                            ),
                            if (searchedArtists.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: _sectionHeader(
                                    '${l10n.artists} (${searchedArtists.length})'),
                              ),
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _artistRow(
                                      context,
                                      ref,
                                      l10n,
                                      theme,
                                      searchedArtists[index],
                                      index,
                                      entryKeys),
                                  childCount: searchedArtists.length,
                                ),
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 12),
                              ),
                            ],
                            if (searchedAlbums.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: _sectionHeader(
                                    '${l10n.albums} (${searchedAlbums.length})'),
                              ),
                              _albumGridSliver(
                                context,
                                ref,
                                l10n,
                                theme,
                                contentWidth,
                                albumBase,
                                entryKeys,
                              ),
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 12),
                              ),
                            ],
                            if (searchedSongs.isNotEmpty) ...[
                              SliverToBoxAdapter(
                                child: _sectionHeader(
                                    '${l10n.songs} (${searchedSongs.length})'),
                              ),
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _songRow(
                                      context,
                                      ref,
                                      l10n,
                                      theme,
                                      searchedSongs[index],
                                      index,
                                      songBase + index,
                                      entryKeys),
                                  childCount: searchedSongs.length,
                                ),
                              ),
                            ],
                            SliverPadding(
                              padding: EdgeInsets.only(bottom: bottomOffset),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

typedef NavidromeSearchToolbar = RemoteLibrarySearchToolbar;
typedef NavidromeSearchView = RemoteLibrarySearchView;
