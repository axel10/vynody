import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/clients/smb_client.dart';
import '../../player/remote/proxy/remote_media_resolver.dart';
import '../../player/remote/services/smb_metadata_helper.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../player/metadata/metadata_database.dart';
import '../../widgets/mini_player_wrapper.dart';
import '../../widgets/song_thumbnail.dart';
import 'remote_download_manager_page.dart';

class SmbBrowserPage extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String? initialShare;
  final String? initialPath;
  final bool wrapWithMiniPlayer;

  const SmbBrowserPage({
    super.key,
    required this.server,
    required this.password,
    this.initialShare,
    this.initialPath,
    this.wrapWithMiniPlayer = true,
  });

  @override
  ConsumerState<SmbBrowserPage> createState() => _SmbBrowserPageState();
}

class _SmbBrowserPageState extends ConsumerState<SmbBrowserPage> {
  late final SmbClient _client;

  String? _currentShare;
  String _currentPath = '';
  bool _isLoading = false;
  String? _error;

  List<String> _availableShares = [];
  List<SmbFile> _items = [];
  final Map<String, SongMetadata> _metadataMap = {};

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSearching = false;
  String _searchQuery = '';

  bool get _isAtSharesRoot => _currentShare == null;

  @override
  void initState() {
    super.initState();
    _client = SmbClient(
      server: widget.server,
      password: widget.password,
    );

    // If a default share was configured or provided:
    final defaultShare = widget.initialShare ?? _client.defaultShare;
    if (defaultShare != null && defaultShare.isNotEmpty) {
      _currentShare = defaultShare;
      _currentPath = widget.initialPath ?? '';
      _loadDirectory(_currentShare!, _currentPath);
    } else {
      _loadShares();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentShare = null;
      _currentPath = '';
      _items = [];
    });

    try {
      final shares = await _client.listShares();
      final validShares = shares
          .where((s) => !s.name.endsWith(r'$'))
          .map((s) => s.name)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      if (mounted) {
        setState(() {
          _availableShares = validShares;
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

  Future<void> _loadDirectory(String share, String relativePath) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentShare = share;
      _currentPath = relativePath;
    });

    try {
      final items = await _client.listFiles(share, relativePath);
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
        });

        // Trigger lightweight metadata preview in background
        _startMetadataExtraction(items);
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

  void _startMetadataExtraction(List<SmbFile> files) {
    SmbMetadataHelper.processBatchMetadata(
      files: files,
      server: widget.server,
      onMetadataLoaded: (virtualUri, metadata) {
        if (mounted) {
          setState(() {
            _metadataMap[virtualUri] = metadata;
          });
        }
      },
    );
  }

  void _navigateUp() {
    if (_isAtSharesRoot) return;

    if (_currentPath.isEmpty || _currentPath == '/') {
      // If user had no default share locked, go back to shares list
      if (_client.defaultShare == null) {
        _loadShares();
      }
      return;
    }

    final parent = p.dirname(_currentPath);
    final nextPath = (parent == '.' || parent == '/') ? '' : parent;
    _loadDirectory(_currentShare!, nextPath);
  }

  void _onItemTap(SmbFile item) {
    if (item.isDirectory) {
      _loadDirectory(item.share, item.path);
    } else if (item.isAudio) {
      _playAudioItem(item);
    }
  }

  List<MusicFile> _buildPlayableList() {
    final audioFiles = _items.where((i) => !i.isDirectory && i.isAudio).toList();
    return audioFiles.map((file) {
      final virtualUri = RemoteMediaResolver.buildSmbUri(widget.server.id, file.share, file.path);
      final meta = _metadataMap[virtualUri];
      return RemoteMediaResolver.buildMusicFileFromSmb(file, widget.server, metadata: meta);
    }).toList();
  }

  Future<void> _playAudioItem(SmbFile item) async {
    final playlist = _buildPlayableList();
    if (playlist.isEmpty) return;

    final targetUri = RemoteMediaResolver.buildSmbUri(widget.server.id, item.share, item.path);
    final index = playlist.indexWhere((s) => s.path == targetUri);
    final initialIndex = index >= 0 ? index : 0;

    final audioService = ref.read(audioServiceProvider);
    final folderName = _currentPath.isEmpty ? (_currentShare ?? widget.server.name) : p.basename(_currentPath);

    await audioService.playPlaylist(
      playlist,
      initialIndex: initialIndex,
      source: PlaybackSource(
        type: PlaybackSourceType.folder,
        id: 'smb-${widget.server.id}-$_currentShare-$_currentPath',
        name: folderName,
      ),
    );
  }

  Future<void> _playAll({bool shuffle = false}) async {
    final playlist = _buildPlayableList();
    if (playlist.isEmpty) {
      showToast('No playable audio files in this folder');
      return;
    }

    if (shuffle) playlist.shuffle();

    final audioService = ref.read(audioServiceProvider);
    final folderName = _currentPath.isEmpty ? (_currentShare ?? widget.server.name) : p.basename(_currentPath);

    await audioService.playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.folder,
        id: 'smb-${widget.server.id}-$_currentShare-$_currentPath',
        name: folderName,
      ),
    );
    showToast('Playing ${playlist.length} songs');
  }

  Future<void> _downloadAllAudio() async {
    final audioItems = _items.where((i) => !i.isDirectory && i.isAudio).toList();
    if (audioItems.isEmpty) {
      showToast('No audio files to download');
      return;
    }

    final downloadService = ref.read(remoteDownloadTasksProvider.notifier);
    final enqueued = await downloadService.enqueueSmbFiles(
      server: widget.server,
      files: audioItems,
    );

    showToast('Added ${enqueued.length} file(s) to download queue');
  }

  List<SmbFile> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    final query = _searchQuery.toLowerCase();
    return _items.where((item) {
      final virtualUri = RemoteMediaResolver.buildSmbUri(widget.server.id, item.share, item.path);
      final meta = _metadataMap[virtualUri];
      final title = meta?.title ?? item.name;
      final artist = meta?.artist ?? '';
      final album = meta?.album ?? '';
      return title.toLowerCase().contains(query) ||
          artist.toLowerCase().contains(query) ||
          album.toLowerCase().contains(query) ||
          item.name.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content = Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search files and songs...',
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              )
            : Text(
                _isAtSharesRoot
                    ? widget.server.name
                    : (_currentPath.isEmpty
                        ? _currentShare!
                        : p.basename(_currentPath)),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!_isAtSharesRoot && (_currentPath.isNotEmpty || _client.defaultShare == null)) {
              _navigateUp();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isAtSharesRoot && _items.any((i) => i.isAudio)) ...[
            IconButton(
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download All',
              onPressed: _downloadAllAudio,
            ),
            IconButton(
              icon: const Icon(Icons.downloading_outlined),
              tooltip: 'Download Manager',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RemoteDownloadManagerPage()),
                );
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              if (_isAtSharesRoot) {
                _loadShares();
              } else {
                _loadDirectory(_currentShare!, _currentPath);
              }
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isAtSharesRoot) _buildBreadcrumbs(theme),
          Expanded(
            child: _buildBody(theme),
          ),
        ],
      ),
      floatingActionButton: (!_isAtSharesRoot && _items.any((i) => i.isAudio))
          ? FloatingActionButton.extended(
              onPressed: () => _playAll(),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play All'),
            )
          : null,
    );

    if (widget.wrapWithMiniPlayer) {
      return MiniPlayerWrapper(child: content);
    }
    return content;
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (_client.defaultShare == null) ...[
              InkWell(
                onTap: _loadShares,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dns_outlined, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(widget.server.name, style: TextStyle(color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 16),
            ],
            InkWell(
              onTap: () => _loadDirectory(_currentShare!, ''),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_shared, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(_currentShare ?? '', style: TextStyle(color: theme.colorScheme.primary)),
                  ],
                ),
              ),
            ),
            for (int i = 0; i < parts.length; i++) ...[
              const Icon(Icons.chevron_right, size: 16),
              InkWell(
                onTap: () {
                  final targetPath = parts.sublist(0, i + 1).join('/');
                  _loadDirectory(_currentShare!, targetPath);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    parts[i],
                    style: TextStyle(
                      color: i == parts.length - 1
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.primary,
                      fontWeight: i == parts.length - 1 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('Connection Error', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  if (_isAtSharesRoot) {
                    _loadShares();
                  } else {
                    _loadDirectory(_currentShare!, _currentPath);
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_isAtSharesRoot) {
      return _buildSharesList(theme);
    }

    final items = _filteredItems;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No files match "$_searchQuery"' : 'Folder is empty',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemTile(item, theme);
      },
    );
  }

  Widget _buildSharesList(ThemeData theme) {
    if (_availableShares.isEmpty) {
      return Center(
        child: Text(
          'No shared folders available',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: _availableShares.length,
      itemBuilder: (context, index) {
        final share = _availableShares[index];
        return ListTile(
          leading: Icon(Icons.folder_shared_rounded, color: theme.colorScheme.primary, size: 36),
          title: Text(share, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('SMB Share'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _loadDirectory(share, ''),
        );
      },
    );
  }

  Widget _buildItemTile(SmbFile item, ThemeData theme) {
    if (item.isDirectory) {
      return ListTile(
        leading: Icon(Icons.folder_rounded, color: theme.colorScheme.primary, size: 36),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _onItemTap(item),
      );
    }

    final virtualUri = RemoteMediaResolver.buildSmbUri(widget.server.id, item.share, item.path);
    final meta = _metadataMap[virtualUri];
    final title = meta != null && meta.title.isNotEmpty ? meta.title : p.basenameWithoutExtension(item.name);
    final artist = meta?.artist != null && meta!.artist != 'Unknown' ? meta.artist : null;
    final album = meta?.album != null && meta!.album != 'Unknown' ? meta.album : null;

    final songModel = RemoteMediaResolver.buildMusicFileFromSmb(item, widget.server, metadata: meta);

    String? subtitleText;
    if (artist != null && album != null) {
      subtitleText = '$artist • $album';
    } else if (artist != null) {
      subtitleText = artist;
    } else {
      subtitleText = _formatBytes(item.contentLength);
    }

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: SongThumbnail(
            path: songModel.path,
            thumbnailPath: songModel.thumbnailPath,
            artworkPath: songModel.artworkPath,
            size: 44,
          ),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (meta?.duration != null && meta!.duration! > 0)
            Text(
              _formatDuration(meta.duration!),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => _handleAction(action, item, songModel),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'play', child: Text('Play Now')),
              const PopupMenuItem(value: 'enqueue_next', child: Text('Play Next')),
              const PopupMenuItem(value: 'enqueue_last', child: Text('Add to Queue')),
              const PopupMenuItem(value: 'download', child: Text('Download')),
            ],
          ),
        ],
      ),
      onTap: () => _onItemTap(item),
    );
  }

  void _handleAction(String action, SmbFile item, MusicFile song) async {
    final audioService = ref.read(audioServiceProvider);

    switch (action) {
      case 'play':
        _playAudioItem(item);
        break;
      case 'enqueue_next':
        await audioService.enqueueNext([song]);
        showToast('Added to next');
        break;
      case 'enqueue_last':
        await audioService.appendToQueue([song]);
        showToast('Added to queue');
        break;
      case 'download':
        final downloadService = ref.read(remoteDownloadTasksProvider.notifier);
        final task = await downloadService.enqueueSmbFile(
          server: widget.server,
          file: item,
        );
        if (task != null) {
          showToast('Added "${song.title}" to download queue');
        }
        break;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDuration(int millis) {
    final totalSeconds = millis ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
