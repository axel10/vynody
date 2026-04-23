import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';
import '../player/playlist_service.dart';
import 'albums_tab.dart';
import 'artists_tab.dart';
import 'most_played_tab.dart';
import 'playlist_tab.dart';
import 'recently_added_tab.dart';

// 媒体库页面

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _tabIndex = 0;
  bool _mostPlayedTabLoaded = false;
  bool _recentlyAddedTabLoaded = false;
  bool _albumsTabLoaded = false;
  bool _artistsTabLoaded = false;

  bool get _isPlaylistTab => _tabIndex == 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this)
      ..addListener(() {
        if (_tabController.indexIsChanging) return;
        if (_tabIndex == _tabController.index) return;
        setState(() {
          _tabIndex = _tabController.index;
          if (_tabIndex == 1) {
            _mostPlayedTabLoaded = true;
          } else if (_tabIndex == 2) {
            _recentlyAddedTabLoaded = true;
          } else if (_tabIndex == 3) {
            _albumsTabLoaded = true;
          } else if (_tabIndex == 4) {
            _artistsTabLoaded = true;
          }
        });
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isFavoritePlaylist(Playlist playlist) {
    return playlist.id == PlaylistService.favoritePlaylistId;
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.createPlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.playlistName,
            hintText: AppLocalizations.of(context)!.enterPlaylistName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref.read(playlistServiceProvider).createPlaylist(name);
                Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.createPlaylist),
          ),
        ],
      ),
    );
  }

  void _showRenamePlaylistDialog(BuildContext context, Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.playlistName,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                ref
                    .read(playlistServiceProvider)
                    .renamePlaylist(playlist.id, name);
                Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }

  void _showDeletePlaylistDialog(BuildContext context, Playlist playlist) {
    if (_isFavoritePlaylist(playlist)) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deletePlaylist),
        content: Text(
          AppLocalizations.of(context)!.confirmDeletePlaylist(playlist.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(playlistServiceProvider).deletePlaylist(playlist.id);
              Navigator.pop(context);
            },
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptions(BuildContext context, Playlist playlist) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(AppLocalizations.of(context)!.rename),
              enabled: !_isFavoritePlaylist(playlist),
              onTap: () {
                if (_isFavoritePlaylist(playlist)) return;
                Navigator.pop(context);
                _showRenamePlaylistDialog(context, playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: Text(AppLocalizations.of(context)!.delete),
              enabled: !_isFavoritePlaylist(playlist),
              onTap: () {
                if (_isFavoritePlaylist(playlist)) return;
                Navigator.pop(context);
                _showDeletePlaylistDialog(context, playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistSelector(BuildContext context) {
    final playlistService = ref.read(playlistServiceProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...playlistService.playlists.map(
              (playlist) => ListTile(
                leading: Icon(
                  _isFavoritePlaylist(playlist)
                      ? Icons.favorite_rounded
                      : Icons.playlist_play,
                  color: _isFavoritePlaylist(playlist)
                      ? Colors.redAccent
                      : null,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  AppLocalizations.of(
                    context,
                  )!.songCount(playlist.songs.length),
                ),
                trailing: playlist.id == playlistService.currentPlaylist?.id
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  playlistService.setCurrentPlaylist(playlist.id);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(AppLocalizations.of(context)!.createNewPlaylist),
              onTap: () {
                Navigator.pop(context);
                _showCreatePlaylistDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPlaylistManager(BuildContext context) {
    final playlistService = ref.read(playlistServiceProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                AppLocalizations.of(context)!.managePlaylists,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(),
            ...playlistService.playlists.map(
              (playlist) => ListTile(
                leading: Icon(
                  _isFavoritePlaylist(playlist)
                      ? Icons.favorite_rounded
                      : Icons.playlist_play,
                  color: _isFavoritePlaylist(playlist)
                      ? Colors.redAccent
                      : null,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  '${AppLocalizations.of(context)!.songCount(playlist.songs.length)} · ${_formatDate(playlist.updatedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: _isFavoritePlaylist(playlist)
                      ? null
                      : () {
                          Navigator.pop(context);
                          _showPlaylistOptions(context, playlist);
                        },
                ),
                onTap: () {
                  playlistService.setCurrentPlaylist(playlist.id);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final playlistService = ref.watch(playlistServiceProvider);
    final currentPlaylist = playlistService.currentPlaylist;

    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(currentPlaylist, l10n),
        actions: _buildAppBarActions(
          context,
          l10n,
          playlistService,
          currentPlaylist,
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.playlist),
            Tab(text: l10n.mostPlayed),
            Tab(text: l10n.recentlyAdded),
            Tab(text: l10n.albums),
            Tab(text: l10n.artists),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const PlaylistTab(),
          _mostPlayedTabLoaded
              ? const MostPlayedTab()
              : const SizedBox.shrink(),
          _recentlyAddedTabLoaded
              ? const RecentlyAddedTab()
              : const SizedBox.shrink(),
          _albumsTabLoaded ? const AlbumsTab() : const SizedBox.shrink(),
          _artistsTabLoaded ? const ArtistsTab() : const SizedBox.shrink(),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle(Playlist? currentPlaylist, AppLocalizations l10n) {
    if (!_isPlaylistTab) {
      if (_tabIndex == 1) {
        return Text(l10n.mostPlayed);
      }
      if (_tabIndex == 2) {
        return Text(l10n.recentlyAdded);
      }
      if (_tabIndex == 3) {
        return Text(l10n.albums);
      }
      return Text(l10n.artists);
    }
    if (currentPlaylist == null) {
      return Text(l10n.playlist);
    }
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _showPlaylistSelector(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    currentPlaylist.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(
    BuildContext context,
    AppLocalizations l10n,
    PlaylistService playlistService,
    Playlist? currentPlaylist,
  ) {
    if (!_isPlaylistTab) {
      return const [];
    }

    return [
      if (currentPlaylist != null && currentPlaylist.songs.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear_all),
          tooltip: l10n.emptyList,
          onPressed: () => playlistService.clearPlaylist(currentPlaylist.id),
        ),
      PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'create') {
            _showCreatePlaylistDialog(context);
          } else if (value == 'manage') {
            _showPlaylistManager(context);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'create',
            child: ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.createPlaylist),
            ),
          ),
          PopupMenuItem(
            value: 'manage',
            child: ListTile(
              leading: const Icon(Icons.list),
              title: Text(l10n.managePlaylists),
            ),
          ),
        ],
      ),
    ];
  }
}
