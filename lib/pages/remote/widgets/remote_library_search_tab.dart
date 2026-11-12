import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/music_file.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/remote_library_navigation.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../player/remote/remote_server_riverpod.dart';
import '../../../utils/remote_context_menu_utils.dart';
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

class RemoteLibrarySearchView extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final TextEditingController searchController;
  final List<MusicFile> searchedSongs;
  final List<Map<String, dynamic>> searchedAlbums;
  final List<Map<String, dynamic>> searchedArtists;
  final bool isSearching;
  final double bottomOffset;
  final bool isArtistSelectionMode;
  final bool isAlbumSelectionMode;
  final bool isSongSelectionMode;
  final Set<String> selectedArtistIds;
  final Set<String> selectedAlbumIds;
  final Set<String> selectedSongPaths;
  final int? lastSongAnchorIndex;
  final void Function(Set<String> keys) onSetSongSelection;
  final void Function(String path) onToggleSongSelection;
  final void Function(int? index) onUpdateSongAnchor;
  final void Function(String artistId) onToggleArtistSelection;
  final void Function(String albumId) onToggleAlbumSelection;
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
    required this.isArtistSelectionMode,
    required this.isAlbumSelectionMode,
    required this.isSongSelectionMode,
    required this.selectedArtistIds,
    required this.selectedAlbumIds,
    required this.selectedSongPaths,
    required this.lastSongAnchorIndex,
    required this.onSetSongSelection,
    required this.onToggleSongSelection,
    required this.onUpdateSongAnchor,
    required this.onToggleArtistSelection,
    required this.onToggleAlbumSelection,
    this.toolbar,
  });

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

  Widget _artistRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
    Map<String, dynamic> artist,
  ) {
    final artistId = artist['id'] as String? ?? '';
    final artistName = artist['name'] as String? ?? l10n.unknownArtist;
    final coverArtId = artist['coverArt'] as String?;
    final albumCount = artist['albumCount'] as int?;
    final isMultiSelected = selectedArtistIds.contains(artistId);
    final isStarred = (ref
                .watch(activeRemoteSessionProvider)
                ?.navidromeStarredArtistIds
                ?.contains(artistId) ==
            true) ||
        artist['isFavorite'] == true ||
        artist['starred'] != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        if (!isArtistSelectionMode) {
          showRemoteArtistContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: server,
            password: password,
            artistId: artistId,
            artistName: artistName,
            isStarred: isStarred,
            onViewDetails: () {
              RemoteLibraryNavUtils.openArtist(
                context,
                server: server,
                password: password,
                artistId: artistId,
                artistName: artistName,
                coverArtId: coverArtId,
                albumCount: albumCount,
              );
            },
          );
        }
      },
      onLongPressStart: (details) {
        onToggleArtistSelection(artistId);
      },
      child: Material(
        color: isArtistSelectionMode && isMultiSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (isArtistSelectionMode) {
              onToggleArtistSelection(artistId);
            } else {
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
          },
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
                fontWeight: isArtistSelectionMode && isMultiSelected
                    ? FontWeight.bold
                    : null,
                color: isArtistSelectionMode && isMultiSelected
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),
            subtitle: albumCount != null
                ? Text(l10n.albumCount(albumCount))
                : null,
            trailing: isArtistSelectionMode
                ? Icon(
                    isMultiSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isMultiSelected
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
  /// 多选、右键菜单、长按多选行为原样保留，只从横向列表换成网格。
  Widget _albumGridSliver(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    ThemeData theme,
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
          ref,
          l10n,
          theme,
          searchedAlbums[index],
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
    double coverSize,
  ) {
    final albumId = album['id'] as String? ?? '';
    final title = album['name'] as String? ??
        album['title'] as String? ??
        l10n.unknownAlbum;
    final artist = album['artist'] as String? ?? l10n.unknownArtist;
    final coverId = album['coverArt'] as String?;
    final isSelected = selectedAlbumIds.contains(albumId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        if (!isAlbumSelectionMode) {
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
            onViewDetails: () {
              RemoteLibraryNavUtils.openAlbum(
                context,
                server: server,
                password: password,
                albumId: albumId,
                albumName: title,
                artistName: artist,
                coverArtId: coverId,
              );
            },
          );
        }
      },
      onLongPressStart: (details) {
        onToggleAlbumSelection(albumId);
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (isAlbumSelectionMode) {
              onToggleAlbumSelection(albumId);
            } else {
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
          },
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
                        color: isAlbumSelectionMode && isSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: isAlbumSelectionMode && isSelected ? 2 : 0,
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
                  if (isAlbumSelectionMode)
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
                  if (isAlbumSelectionMode)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (_) => onToggleAlbumSelection(albumId),
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
                  fontWeight: isAlbumSelectionMode && isSelected
                      ? FontWeight.bold
                      : FontWeight.w600,
                  color: isAlbumSelectionMode && isSelected
                      ? theme.colorScheme.primary
                      : null,
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
    int index,
  ) {
    final isSelected = selectedSongPaths.contains(song.path);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: (details) {
        if (!isSongSelectionMode) {
          showRemoteSongContextMenu(
            context: context,
            globalPosition: details.globalPosition,
            ref: ref,
            server: server,
            password: password,
            song: song,
            onMultiSelect: () {
              onUpdateSongAnchor(index);
              onToggleSongSelection(song.path);
            },
          );
        }
      },
      onLongPressStart: (details) {
        onUpdateSongAnchor(index);
        onToggleSongSelection(song.path);
      },
      child: Material(
        color: isSongSelectionMode && isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            SelectionActionHelper.handleItemTap(
              index: index,
              itemKey: song.path,
              items: searchedSongs,
              keySelector: (s) => s.path,
              isSelectionMode: isSongSelectionMode,
              selectedKeys: selectedSongPaths,
              lastAnchorIndex: lastSongAnchorIndex,
              onUpdateAnchor: onUpdateSongAnchor,
              onSetSelection: onSetSongSelection,
              onToggleSelection: onToggleSongSelection,
              onNormalTap: () async {
                final audioService = ref.read(audioServiceProvider);
                await audioService.playPlaylist(
                  searchedSongs,
                  initialIndex: index,
                );
              },
            );
          },
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: isSongSelectionMode
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
                fontWeight: isSongSelectionMode && isSelected
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isSongSelectionMode && isSelected
                    ? theme.colorScheme.primary
                    : null,
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
                                      searchedArtists[index]),
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
                                      index),
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
