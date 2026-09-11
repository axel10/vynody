import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/library/playlist_service.dart';
import '../player/remote/clients/remote_media_library_client.dart';
import '../player/remote/proxy/remote_media_resolver.dart';
import '../player/remote/remote_server_models.dart';
import '../utils/app_snack_bar.dart';
import '../utils/playlist_name.dart';
import '../widgets/song_thumbnail.dart';

class RemoteAddToPlaylistDialog {
  static Future<void> show(
    BuildContext context, {
    required WidgetRef ref,
    required RemoteServer server,
    required String password,
    required List<MusicFile> songs,
  }) async {
    if (songs.isEmpty) return;
    final client = RemoteMediaLibraryClient.create(server: server, password: password);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Extract remote track IDs (used for server playlists)
    final List<String> songIds = [];
    for (final song in songs) {
      final trackId = RemoteMediaResolver.extractTrackId(song);
      if (trackId != null && trackId.isNotEmpty && trackId != 'null') {
        songIds.add(trackId);
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _RemotePlaylistDialogContent(
          client: client,
          songs: songs,
          songIds: songIds,
          theme: theme,
          l10n: l10n,
          ref: ref,
        );
      },
    );
  }
}

class _RemotePlaylistDialogContent extends StatefulWidget {
  final RemoteMediaLibraryClient client;
  final List<MusicFile> songs;
  final List<String> songIds;
  final ThemeData theme;
  final AppLocalizations l10n;
  final WidgetRef ref;

  const _RemotePlaylistDialogContent({
    required this.client,
    required this.songs,
    required this.songIds,
    required this.theme,
    required this.l10n,
    required this.ref,
  });

  @override
  State<_RemotePlaylistDialogContent> createState() =>
      _RemotePlaylistDialogContentState();
}

class _RemotePlaylistDialogContentState
    extends State<_RemotePlaylistDialogContent> {
  int _selectedTab = 0; // 0: Server Playlist, 1: Local Playlist
  bool _isLoading = true;
  List<Map<String, dynamic>> _serverPlaylists = [];
  String? _error;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchServerPlaylists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchServerPlaylists() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await widget.client.getPlaylists();
      if (mounted) {
        setState(() {
          _serverPlaylists = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addToExistingServerPlaylist(
    String playlistId,
    String playlistName,
  ) async {
    if (widget.songIds.isEmpty) {
      showToast(widget.l10n.emptyList);
      return;
    }
    try {
      final ok = await widget.client.updatePlaylist(
        playlistId: playlistId,
        songIdsToAdd: widget.songIds,
      );
      if (ok) {
        showToast(
          widget.l10n.addedTracksToPlaylistSuccess(
            widget.songs.length,
            playlistName,
          ),
        );
        if (mounted) Navigator.pop(context);
      } else {
        showToast(widget.l10n.addToPlaylistFailed);
      }
    } catch (e) {
      showToast(widget.l10n.errorAddingToPlaylist(e.toString()));
    }
  }

  Future<void> _addToExistingLocalPlaylist(Playlist playlist) async {
    final playlistService = widget.ref.read(playlistServiceProvider);
    await playlistService.addSongsToPlaylist(playlist.id, widget.songs);
    if (!mounted) return;
    Navigator.pop(context);

    final plName = localizedPlaylistName(context, playlist);
    AppSnackBar.show(
      context,
      null,
      SnackBar(
        content: Text(
          widget.l10n.addedToPlaylist(widget.songs.length, plName),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _showCreateServerPlaylistDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (createCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Text(widget.l10n.createNewServerPlaylist),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.l10n.playlistName,
              hintText: widget.l10n.enterPlaylistName,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(createCtx),
            child: Text(widget.l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(createCtx);

              try {
                final created = await widget.client.createPlaylist(
                  name: name,
                  songIds: widget.songIds,
                );
                if (created != null) {
                  showToast(
                    widget.l10n.createdPlaylistWithTracksSuccess(
                      name,
                      widget.songs.length,
                    ),
                  );
                  if (mounted) Navigator.pop(context);
                } else {
                  showToast(widget.l10n.createServerPlaylistFailed);
                }
              } catch (e) {
                showToast(widget.l10n.errorCreatingPlaylist(e.toString()));
              }
            },
            child: Text(widget.l10n.createPlaylist),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateLocalPlaylistDialog() async {
    final playlistService = widget.ref.read(playlistServiceProvider);
    final nameController = TextEditingController();
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() async {
            final name = nameController.text.trim();
            if (name.isEmpty) return;

            if (playlistService.playlistExists(name)) {
              setDialogState(() {
                errorText = widget.l10n.playlistNameExists;
              });
              return;
            }

            final newPlaylist = await playlistService.createPlaylist(name);
            await playlistService.addSongsToPlaylist(
              newPlaylist.id,
              widget.songs,
            );

            if (dialogCtx.mounted) {
              Navigator.pop(dialogCtx);
            }
            if (mounted) {
              Navigator.pop(context);
              AppSnackBar.show(
                context,
                null,
                SnackBar(
                  content: Text(
                    widget.l10n.createdPlaylist(name, widget.songs.length),
                  ),
                  duration: const Duration(seconds: 4),
                ),
              );
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Text(widget.l10n.createPlaylist),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.l10n.playlistName,
                  hintText: widget.l10n.enterPlaylistName,
                  errorText: errorText,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  if (errorText != null) {
                    setDialogState(() {
                      errorText = null;
                    });
                  }
                },
                onSubmitted: (_) => submit(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(widget.l10n.cancel),
              ),
              FilledButton(
                onPressed: submit,
                child: Text(widget.l10n.createPlaylist),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isFavorite(Playlist playlist) {
    return playlist.id == PlaylistService.favoritePlaylistId;
  }

  Widget _buildLocalLeadingIcon(Playlist playlist, ThemeData theme) {
    if (_isFavorite(playlist)) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.favorite_rounded,
          color: Colors.redAccent,
          size: 22,
        ),
      );
    }

    if (playlist.songs.isNotEmpty) {
      final firstSong = playlist.songs.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 44,
          height: 44,
          child: SongThumbnail(
            path: firstSong.path,
            id: firstSong.id,
            thumbnailPath: firstSong.thumbnailPath,
            size: 44,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        color: theme.colorScheme.onPrimaryContainer,
        size: 22,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistService = widget.ref.watch(playlistServiceProvider);
    final localPlaylists = playlistService.playlists;

    // Filter server playlists
    final filteredServerPlaylists = _searchQuery.isEmpty
        ? _serverPlaylists
        : _serverPlaylists.where((pl) {
            final name = (pl['name'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    // Filter local playlists
    final filteredLocalPlaylists = _searchQuery.isEmpty
        ? localPlaylists
        : localPlaylists.where((p) {
            final name = localizedPlaylistName(context, p).toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 440,
          minWidth: 320,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: widget.theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.playlist_add_rounded,
                      color: widget.theme.colorScheme.onPrimaryContainer,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.l10n.addToPlaylist,
                          style: widget.theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: widget.theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.l10n.songCount(widget.songs.length),
                            style: widget.theme.textTheme.labelSmall?.copyWith(
                              color: widget.theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Segmented Tab Switcher (Server vs Local)
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment<int>(
                      value: 0,
                      icon: const Icon(Icons.cloud_outlined, size: 18),
                      label: Text(widget.l10n.serverPlaylists),
                    ),
                    ButtonSegment<int>(
                      value: 1,
                      icon: const Icon(Icons.devices_rounded, size: 18),
                      label: Text(widget.l10n.localPlaylists),
                    ),
                  ],
                  selected: {_selectedTab},
                  onSelectionChanged: (set) {
                    setState(() {
                      _selectedTab = set.first;
                      _searchController.clear();
                      _searchQuery = '';
                    });
                  },
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: widget.l10n.search,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  isDense: true,
                  filled: true,
                  fillColor: widget.theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              ),
              const SizedBox(height: 12),

              // Tab View Content
              SizedBox(
                height: 280,
                child: _selectedTab == 0
                    ? _buildServerPlaylistsTab(filteredServerPlaylists)
                    : _buildLocalPlaylistsTab(filteredLocalPlaylists),
              ),
              const SizedBox(height: 16),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: Text(widget.l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _selectedTab == 0
                        ? _showCreateServerPlaylistDialog
                        : _showCreateLocalPlaylistDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(widget.l10n.createNewList),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerPlaylistsTab(
    List<Map<String, dynamic>> filteredServerPlaylists,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.l10n.errorWithMessage(_error!),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _fetchServerPlaylists,
              child: Text(widget.l10n.retry),
            ),
          ],
        ),
      );
    }
    if (filteredServerPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: widget.theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              widget.l10n.noServerPlaylistsFound,
              style: TextStyle(
                color: widget.theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredServerPlaylists.length,
      itemBuilder: (context, index) {
        final pl = filteredServerPlaylists[index];
        final name = pl['name'] as String? ?? widget.l10n.playlist;
        final id = pl['id'] as String? ?? '';
        final count = pl['songCount'] as int? ?? 0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _addToExistingServerPlaylist(id, name),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.queue_music_rounded,
                        color: Colors.orange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.l10n.songCount(count),
                            style: TextStyle(
                              color: widget.theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 20,
                      color: widget.theme.colorScheme.primary
                          .withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLocalPlaylistsTab(List<Playlist> filteredLocalPlaylists) {
    if (filteredLocalPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 40,
              color: widget.theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              widget.l10n.emptyList,
              style: TextStyle(
                color: widget.theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredLocalPlaylists.length,
      itemBuilder: (context, index) {
        final playlist = filteredLocalPlaylists[index];
        final name = localizedPlaylistName(context, playlist);
        final count = playlist.songs.length;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _addToExistingLocalPlaylist(playlist),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _buildLocalLeadingIcon(playlist, widget.theme),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.l10n.songCount(count),
                            style: TextStyle(
                              color: widget.theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 20,
                      color: widget.theme.colorScheme.primary
                          .withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
