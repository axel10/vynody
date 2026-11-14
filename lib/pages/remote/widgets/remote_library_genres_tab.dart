import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../dialogs/sort_options_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/audio/audio_riverpod.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_library_playback.dart';
import '../../../widgets/library_action_bar.dart';
import '../../../widgets/library_large_title.dart';
import '../../../widgets/library_master_pane_header.dart';
import '../../../widgets/master_detail_scaffold.dart';
import '../../../widgets/remote_artwork_widget.dart';
import '../remote_genre_detail_page.dart';
import 'remote_library_common_widgets.dart';
import 'remote_library_toolbar_widgets.dart';

/// 远程媒体库的流派栏目。
///
/// 竖屏：流派列表 → 点按 push 详情页；
/// 横屏：左侧流派列表 + 右侧当前流派的专辑网格，与艺术家栏目同构。
class RemoteLibraryGenresView extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final List<Map<String, dynamic>> genres;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final double bottomOffset;

  /// 页头大标题与返回概览页（与本地流派页同形）。
  final String? title;
  final VoidCallback? onBack;

  /// 库级动作（定位当前播放、下载管理器），由父页统一提供。
  final List<LibraryToolbarAction> trailingActions;

  const RemoteLibraryGenresView({
    super.key,
    required this.server,
    required this.password,
    required this.genres,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    this.bottomOffset = 0.0,
    this.title,
    this.onBack,
    this.trailingActions = const <LibraryToolbarAction>[],
  });

  @override
  ConsumerState<RemoteLibraryGenresView> createState() =>
      _RemoteLibraryGenresViewState();
}

class _RemoteLibraryGenresViewState
    extends ConsumerState<RemoteLibraryGenresView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortField = 'name'; // 'name' | 'songCount'
  bool _sortAsc = true;
  String? _selectedGenreId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _genreId(Map<String, dynamic> genre) =>
      (genre['id'] ?? genre['name'] ?? '').toString();

  List<Map<String, dynamic>> get _visibleGenres {
    final query = _searchQuery.toLowerCase();
    final list = widget.genres.where((genre) {
      if (query.isEmpty) return true;
      final name = (genre['name'] as String? ?? '').toLowerCase();
      return name.contains(query);
    }).toList();

    list.sort((a, b) {
      int cmp;
      if (_sortField == 'songCount') {
        cmp = ((a['songCount'] as num?)?.toInt() ?? 0)
            .compareTo((b['songCount'] as num?)?.toInt() ?? 0);
      } else {
        cmp = (a['name'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['name'] as String? ?? '').toLowerCase());
      }
      // 次级排序固定按名字升序，保证列表顺序稳定。
      if (cmp == 0) {
        cmp = (a['name'] as String? ?? '')
            .toLowerCase()
            .compareTo((b['name'] as String? ?? '').toLowerCase());
      }
      return _sortAsc ? cmp : -cmp;
    });
    return list;
  }

  Future<void> _openSortDialog(
    BuildContext dialogHostContext,
    AppLocalizations l10n,
  ) async {
    final result = await showSortOptionsDialog<String>(
      context: dialogHostContext,
      title: l10n.sort,
      currentField: _sortField,
      sortAscending: _sortAsc,
      options: _sortOptions(l10n),
    );
    if (result != null) {
      setState(() {
        _sortField = result.field;
        _sortAsc = result.sortAscending;
      });
    }
  }

  List<SortOptionItem<String>> _sortOptions(AppLocalizations l10n) => [
        SortOptionItem(
          value: 'name',
          label: l10n.sortByName,
          icon: Icons.sort_by_alpha_rounded,
        ),
        SortOptionItem(
          value: 'songCount',
          label: l10n.sortTrackCount,
          icon: Icons.format_list_numbered_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasPlayingMusic = ref.watch(
      audioCurrentMusicProvider.select((m) => m != null),
    );
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    if (widget.isLoading) {
      return RemoteLibraryLoadingView(
        server: widget.server,
        icon: Icons.style_rounded,
      );
    }
    if (widget.error != null) {
      return RemoteLibraryErrorView(
        error: widget.error!,
        onRetry: () => widget.onRefresh(),
      );
    }

    final visible = _visibleGenres;
    final countLabel = isZh
        ? '共 ${visible.length} 个流派'
        : '${visible.length} ${l10n.genres}';

    return MasterDetailScaffold<Map<String, dynamic>>(
      items: visible,
      itemKey: _genreId,
      selectedKey: _selectedGenreId,
      onSelectedKeyChanged: (id) {
        if (_selectedGenreId != id) {
          setState(() => _selectedGenreId = id);
        }
      },
      routeName: 'remote_genre_detail',
      contentTopPadding: LibrarySubHostScope.maybeOf(context)?.topPadding ?? 0.0,
      hasPlayingMusic: hasPlayingMusic,
      onRefresh: widget.onRefresh,
      masterPaneHeaderBuilder: (headerContext) => LibraryMasterPaneHeader(
        searchController: _searchController,
        searchQuery: _searchQuery,
        searchHintText: l10n.genres,
        onSearchChanged: (value) => setState(() => _searchQuery = value.trim()),
        onSearchCleared: () {
          _searchController.clear();
          setState(() => _searchQuery = '');
        },
        onSortPressed: () => _openSortDialog(headerContext, l10n),
      ),
      masterToolbarBuilder: (context, isWide) =>
          _buildToolbar(context, l10n, isWide: isWide, countLabel: countLabel),
      masterItemBuilder: (context, genre, index, isSelected, isWide, onTap) =>
          _RemoteGenreItem(
        server: widget.server,
        password: widget.password,
        genre: genre,
        selected: isWide && isSelected,
        onTap: onTap,
      ),
      detailBuilder: (context, genre) => RemoteGenreDetailContent(
        key: ValueKey('remote-genre-${_genreId(genre)}'),
        server: widget.server,
        password: widget.password,
        genreId: _genreId(genre),
        genreName: genre['name'] as String? ?? l10n.genres,
        bottomOffset: widget.bottomOffset,
      ),
      detailPageBuilder: (context, genre) => RemoteGenreDetailPage(
        server: widget.server,
        password: widget.password,
        genreId: _genreId(genre),
        genreName: genre['name'] as String? ?? l10n.genres,
      ),
      emptyMasterBuilder: (context) => Center(
        child: Text(
          l10n.emptyList,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
      emptyDetailBuilder: (context) => Center(
        child: Text(
          l10n.emptyList,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// 播放当前列出的流派（已含搜索 / 排序后的可见集合）名下的全部曲目。
  Future<void> _playAllVisible({bool shuffle = false}) async {
    final genres = _visibleGenres;
    if (genres.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    await playRemoteLibraryEntities(
      context: context,
      ref: ref,
      server: widget.server,
      password: widget.password,
      kind: RemoteLibraryEntityKind.genre,
      entities: genres,
      sourceId: 'remote-${widget.server.id}-genres',
      sourceName: l10n.genres,
      shuffle: shuffle,
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    AppLocalizations l10n, {
    required bool isWide,
    String? countLabel,
  }) {
    return RemoteLibraryActionBar(
      searchController: _searchController,
      searchQuery: _searchQuery,
      searchHintText: l10n.genres,
      onSearchChanged: (value) => setState(() => _searchQuery = value.trim()),
      onSearchCleared: () {
        _searchController.clear();
        setState(() => _searchQuery = '');
      },
      title: widget.title,
      onBack: widget.onBack,
      countLabel: countLabel,
      showSearch: !isWide,
      showSortActionInWide: false,
      trailingActions: widget.trailingActions,
      onPlayAll: _visibleGenres.isEmpty ? null : () => _playAllVisible(),
      onShufflePlay:
          _visibleGenres.isEmpty ? null : () => _playAllVisible(shuffle: true),
      actions: [
        if (!isWide)
          remoteSortAction<String>(
            context: context,
            label: l10n.sort,
            currentField: _sortField,
            sortAscending: _sortAsc,
            options: _sortOptions(l10n),
            onSelected: (field, asc) {
              setState(() {
                _sortField = field;
                _sortAsc = asc;
              });
            },
          ),
      ],
    );
  }
}

class _RemoteGenreItem extends StatelessWidget {
  final RemoteServer server;
  final String password;
  final Map<String, dynamic> genre;
  final bool selected;
  final VoidCallback onTap;

  const _RemoteGenreItem({
    required this.server,
    required this.password,
    required this.genre,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = genre['name'] as String? ?? l10n.genres;
    final songCount = (genre['songCount'] as num?)?.toInt() ?? 0;
    final coverArtId = genre['coverArt'] as String?;

    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.7)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: RemoteArtworkWidget(
                  server: server,
                  password: password,
                  coverArtId: coverArtId,
                  size: 38,
                  width: 38,
                  height: 38,
                  fallbackIcon: Icons.style_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 13,
                        color: selected ? theme.colorScheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.songCount(songCount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
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
}
