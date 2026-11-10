import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/library_action_bar.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/remote_library_playback.dart';
import '../../../widgets/folder_layout_utils.dart';
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

  Map<String, dynamic>? _resolveSelected(List<Map<String, dynamic>> visible) {
    if (visible.isEmpty) return null;
    final selectedId = _selectedGenreId;
    if (selectedId == null) return visible.first;
    for (final genre in visible) {
      if (_genreId(genre) == selectedId) return genre;
    }
    return visible.first;
  }

  void _openGenreDetail(Map<String, dynamic> genre) {
    final id = _genreId(genre);
    final name = genre['name'] as String? ??
        AppLocalizations.of(context)!.genres;
    setState(() => _selectedGenreId = id);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RemoteGenreDetailPage(
          server: widget.server,
          password: widget.password,
          genreId: id,
          genreName: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

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
    final toolbar = _buildToolbar(context, l10n);

    if (widget.genres.isEmpty) {
      return Column(
        children: [
          RemotePageHeaderSlot(child: toolbar),
          Expanded(
            child: Center(
              child: Text(
                l10n.emptyList,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 750;

        if (isWide) {
          final selected = _resolveSelected(visible);
          return Row(
            children: [
              SizedBox(
                width: 330,
                child: Column(
                  children: [
                    RemotePageHeaderSlot(
                      child: _buildToolbar(context, l10n, narrow: true),
                    ),
                    Expanded(
                      child: _buildGenreList(
                        visible,
                        selectedId: selected == null ? null : _genreId(selected),
                        isWide: true,
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? Center(
                        child: Text(
                          l10n.emptyList,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : RemoteGenreDetailContent(
                        key: ValueKey('remote-genre-${_genreId(selected)}'),
                        server: widget.server,
                        password: widget.password,
                        genreId: _genreId(selected),
                        genreName: selected['name'] as String? ?? l10n.genres,
                        bottomOffset: widget.bottomOffset,
                      ),
              ),
            ],
          );
        }

        return Column(
          children: [
            RemotePageHeaderSlot(child: toolbar),
            Expanded(
              child: _buildGenreList(
                visible,
                selectedId: null,
                isWide: false,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGenreList(
    List<Map<String, dynamic>> visible, {
    required String? selectedId,
    required bool isWide,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (visible.isEmpty) {
      return Center(
        child: Text(
          l10n.emptyList,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          kGridHorizontalPadding,
          0,
          kGridHorizontalPadding,
          widget.bottomOffset,
        ),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          final genre = visible[index];
          final id = _genreId(genre);
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _RemoteGenreItem(
              server: widget.server,
              password: widget.password,
              genre: genre,
              selected: isWide && id == selectedId,
              onTap: () {
                if (isWide) {
                  setState(() => _selectedGenreId = id);
                } else {
                  _openGenreDetail(genre);
                }
              },
            ),
          );
        },
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

  /// [narrow] 为真时强制折行布局：横屏主从分栏的左栏只有 330 宽，
  /// 按屏幕朝向判宽屏会把搜索框与全部动作挤进一行而溢出。
  Widget _buildToolbar(
    BuildContext context,
    AppLocalizations l10n, {
    bool narrow = false,
  }) {
    final sortOptions = <RemoteSortOption>[
      RemoteSortOption(
        value: 'name_true',
        label: 'A-Z (${l10n.sortAscending})',
        icon: Icons.sort_by_alpha_rounded,
        selected: _sortField == 'name' && _sortAsc,
      ),
      RemoteSortOption(
        value: 'name_false',
        label: 'Z-A (${l10n.sortDescending})',
        icon: Icons.sort_by_alpha_rounded,
        selected: _sortField == 'name' && !_sortAsc,
      ),
      RemoteSortOption(
        value: 'songCount_false',
        label: '${l10n.songs} (${l10n.sortDescending})',
        icon: Icons.format_list_numbered_rounded,
        selected: _sortField == 'songCount' && !_sortAsc,
      ),
      RemoteSortOption(
        value: 'songCount_true',
        label: '${l10n.songs} (${l10n.sortAscending})',
        icon: Icons.format_list_numbered_rounded,
        selected: _sortField == 'songCount' && _sortAsc,
      ),
    ];

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
      forceNarrow: narrow,
      trailingActions: widget.trailingActions,
      onPlayAll: _visibleGenres.isEmpty ? null : () => _playAllVisible(),
      onShufflePlay:
          _visibleGenres.isEmpty ? null : () => _playAllVisible(shuffle: true),
      actions: [
        remoteSortAction(
          label: l10n.sort,
          options: sortOptions,
          onSelected: (key) {
            final parts = key.split('_');
            setState(() {
              _sortField = parts[0];
              _sortAsc = parts[1] == 'true';
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
