import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/music_file.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/platform/right_queue_drawer_controller.dart';
import '../../player/remote/clients/smb_client.dart';
import '../../player/remote/clients/webdav_client.dart';
import '../../player/remote/proxy/remote_media_resolver.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/remote_server_riverpod.dart';
import '../../player/scanner/scanner_path_utils.dart';
import '../../utils/folder_helpers.dart';
import '../../utils/song_context_menu_utils.dart';
import '../../widgets/folder_layout_utils.dart';
import '../../widgets/folder_zoom_gesture_layer.dart';
import '../../widgets/library_large_title.dart';
import '../../widgets/library_search_field.dart';
import '../../widgets/playback_ui_tuning.dart';
import 'widgets/webdav_content_slivers.dart';

/// 远程目录独立搜索页。
///
/// 具备两阶段搜索能力：
/// 1. 第一阶段（即时秒搜）：零网络开销，直接在内存/本地已拉取的 [webDavDirectoryCache] 目录树中匹配；
/// 2. 第二阶段（受控深搜）：用户可显式触发在远程服务器上递归搜索当前目录，流式展示并发掘深层文件。
class RemoteFolderSearchPage extends ConsumerStatefulWidget {
  const RemoteFolderSearchPage({
    super.key,
    required this.server,
    required this.password,
    required this.currentPath,
    this.rootPath,
    this.contentTopPadding,
    this.contentLeftPadding,
  });

  final RemoteServer server;
  final String password;
  final String currentPath;
  final String? rootPath;
  final double? contentTopPadding;
  final double? contentLeftPadding;

  @override
  ConsumerState<RemoteFolderSearchPage> createState() =>
      _RemoteFolderSearchPageState();
}

class _RemoteFolderSearchPageState
    extends ConsumerState<RemoteFolderSearchPage> {
  static const Duration _debounceDuration = Duration(milliseconds: 250);

  late final RemoteDirectoryClient _client;
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  String _query = '';

  // 阶段一：本地缓存即时命中
  List<WebDavFile> _cachedFolders = const [];
  List<WebDavFile> _cachedSongs = const [];

  // 阶段二：服务器递归深度搜索
  List<WebDavFile> _deepFolders = const [];
  List<WebDavFile> _deepSongs = const [];
  bool _isDeepSearching = false;
  bool _isDeepSearchCancelled = false;
  int _deepSearchedDirCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.server.type == RemoteServerType.smb) {
      _client = SmbClient(
        server: widget.server,
        password: widget.password,
      );
    } else {
      _client = WebDavClient(
        server: widget.server,
        password: widget.password,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _isDeepSearchCancelled = true;
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final trimmed = raw.trim();
    if (trimmed == _query) return;

    // 若在深度搜索中途修改搜索词，立即中止当前深搜
    if (_isDeepSearching) {
      _stopDeepSearch();
    }

    if (trimmed.isEmpty) {
      setState(() {
        _query = '';
        _cachedFolders = const [];
        _cachedSongs = const [];
        _deepFolders = const [];
        _deepSongs = const [];
        _isDeepSearching = false;
      });
      return;
    }

    setState(() {
      _query = trimmed;
      _deepFolders = const [];
      _deepSongs = const [];
    });

    _debounce = Timer(_debounceDuration, () => _searchInLocalCache(trimmed));
  }

  void _onQueryCleared() {
    _debounce?.cancel();
    if (_isDeepSearching) {
      _stopDeepSearch();
    }
    _controller.clear();
    setState(() {
      _query = '';
      _cachedFolders = const [];
      _cachedSongs = const [];
      _deepFolders = const [];
      _deepSongs = const [];
      _isDeepSearching = false;
    });
  }

  /// 阶段一：在已加载的目录树缓存中即时搜索
  void _searchInLocalCache(String query) {
    final session = ref.read(activeRemoteSessionProvider);
    if (session == null) return;

    final cache = session.webDavDirectoryCache;
    final lowerQuery = query.toLowerCase();

    final matchedFolders = <WebDavFile>[];
    final matchedSongs = <WebDavFile>[];
    final seenPaths = <String>{};

    for (final entry in cache.entries) {
      final dirPath = entry.key;
      // 仅检索属于当前目录分支下的缓存条目
      if (!ScannerPathUtils.pathContains(widget.currentPath, dirPath) &&
          !ScannerPathUtils.pathsEqual(widget.currentPath, dirPath)) {
        continue;
      }

      for (final file in entry.value) {
        if (!file.name.toLowerCase().contains(lowerQuery)) continue;
        if (!seenPaths.add(file.path)) continue;

        if (file.isDirectory) {
          matchedFolders.add(file);
        } else if (file.isAudio) {
          matchedSongs.add(file);
        }
      }
    }

    if (!mounted || query != _query) return;

    setState(() {
      _cachedFolders = matchedFolders;
      _cachedSongs = matchedSongs;
    });
  }

  /// 阶段二：受控并发递归深搜远程服务器
  Future<void> _startDeepSearch() async {
    final query = _query.trim();
    if (query.isEmpty || _isDeepSearching) return;

    setState(() {
      _isDeepSearching = true;
      _isDeepSearchCancelled = false;
      _deepSearchedDirCount = 0;
      _deepFolders = const [];
      _deepSongs = const [];
    });

    final lowerQuery = query.toLowerCase();
    final queue = Queue<String>()..add(widget.currentPath);
    final visited = <String>{widget.currentPath};
    final session = ref.read(activeRemoteSessionProvider);
    final existingDirCache = session?.webDavDirectoryCache ?? const {};

    // 记录已经由缓存呈现的路径，避免深搜重复展现
    final seenFolderPaths = _cachedFolders.map((f) => f.path).toSet();
    final seenSongPaths = _cachedSongs.map((f) => f.path).toSet();

    final newlyFoundFolders = <WebDavFile>[];
    final newlyFoundSongs = <WebDavFile>[];

    try {
      while (queue.isNotEmpty && !_isDeepSearchCancelled) {
        // 取出一批待扫描目录（并发度控制在 2）
        final batch = <String>[];
        while (queue.isNotEmpty && batch.length < 2) {
          batch.add(queue.removeFirst());
        }

        final futures = batch.map((dir) async {
          if (_isDeepSearchCancelled) return const <WebDavFile>[];
          try {
            // 如果此目录已经在缓存中，则直接复用
            if (existingDirCache.containsKey(dir)) {
              return existingDirCache[dir]!;
            }
            final list = await _client.listFiles(dir);
            // 存入当前会话的缓存
            ref.read(activeRemoteSessionProvider.notifier).updateWebDavState(
                  currentPath: dir,
                  items: list,
                );
            return list;
          } catch (_) {
            return const <WebDavFile>[];
          }
        });

        final results = await Future.wait(futures);
        if (_isDeepSearchCancelled || !mounted) break;

        _deepSearchedDirCount += batch.length;

        for (final fileList in results) {
          for (final file in fileList) {
            if (file.isDirectory) {
              if (visited.add(file.path)) {
                queue.add(file.path);
              }
              if (file.name.toLowerCase().contains(lowerQuery)) {
                if (seenFolderPaths.add(file.path)) {
                  newlyFoundFolders.add(file);
                }
              }
            } else if (file.isAudio) {
              if (file.name.toLowerCase().contains(lowerQuery)) {
                if (seenSongPaths.add(file.path)) {
                  newlyFoundSongs.add(file);
                }
              }
            }
          }
        }

        if (mounted && query == _query) {
          setState(() {
            _deepFolders = List.of(newlyFoundFolders);
            _deepSongs = List.of(newlyFoundSongs);
          });
        }
      }
    } finally {
      if (mounted && query == _query) {
        setState(() {
          _isDeepSearching = false;
        });
      }
    }
  }

  void _stopDeepSearch() {
    _isDeepSearchCancelled = true;
    setState(() {
      _isDeepSearching = false;
    });
  }

  void _navigateToRemoteFolder(WebDavFile folder) {
    ref.read(activeRemoteSessionProvider.notifier).pushWebDavPath(folder.path);
    Navigator.of(context).pop();
  }

  List<MusicFile> _buildMusicFiles(List<WebDavFile> files) {
    final session = ref.read(activeRemoteSessionProvider);
    final metaCache = session?.webDavMetadataCache ?? const {};
    final scannerMeta = ref.read(scannerServiceProvider).metadataMap;

    return files.map((file) {
      final uri = RemoteMediaResolver.buildRemoteUri(widget.server, file.path);
      return RemoteMediaResolver.buildMusicFile(
        file,
        widget.server,
        metadata: metaCache[uri] ?? scannerMeta[uri],
      );
    }).toList(growable: false);
  }

  Future<void> _playSong(
    WebDavFile file,
    int index,
    List<WebDavFile> playlist,
  ) async {
    final musicFiles = _buildMusicFiles(playlist);
    final target = musicFiles[index];
    final audio = ref.read(audioServiceProvider);

    await audio.playPlaylist(
      musicFiles,
      initialIndex: index,
      source: PlaybackSource(
        type: PlaybackSourceType.folder,
        id: 'remote_search',
        name: target.displayName,
      ),
    );
  }

  void _openSongMenu(WebDavFile file, [Offset? globalPosition]) {
    final session = ref.read(activeRemoteSessionProvider);
    final metaCache = session?.webDavMetadataCache ?? const {};
    final uri = RemoteMediaResolver.buildRemoteUri(widget.server, file.path);
    final musicFile = RemoteMediaResolver.buildMusicFile(
      file,
      widget.server,
      metadata:
          metaCache[uri] ?? ref.read(scannerServiceProvider).metadataMap[uri],
    );

    void onPlayNext() =>
        ref.read(audioServiceProvider).enqueueNext([musicFile]);
    void onAddToQueue() =>
        ref.read(audioServiceProvider).appendToQueue([musicFile]);
    Future<void> addToPlaylist() => showAddSongsToPlaylistDialog(
          context,
          ref.read(playlistServiceProvider),
          [musicFile],
        );

    final isTouch = Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;

    if (isTouch || globalPosition == null) {
      showSongBottomSheet(
        context,
        song: musicFile,
        songs: [musicFile],
        onPlayNext: onPlayNext,
        onAddToQueue: onAddToQueue,
        onAddToPlaylist: addToPlaylist,
      );
    } else {
      showSongContextMenu(
        context,
        globalPosition,
        song: musicFile,
        songs: [musicFile],
        onPlayNext: onPlayNext,
        onAddToQueue: onAddToQueue,
        onAddToPlaylist: addToPlaylist,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.sizeOf(context);
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final isLandscape = ref.watch(isEffectiveLandscapeProvider(size));
    final double safeTop = getTitleBarTopPadding(
      context,
      defaultWindowPadding: isLandscape ? 32.0 : 36.0,
    );
    final double topPadding = widget.contentTopPadding ??
        (isLandscape ? (safeTop + 8.0) : safeTop);
    final double leftPadding = widget.contentLeftPadding ?? 0.0;
    final horizontalPadding = size.width >= 780 ? 32.0 : 16.0;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isAudioPlaying = ref.watch(audioIsPlayingProvider);
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;
    final session = ref.watch(activeRemoteSessionProvider);
    final metadataMap = session?.webDavMetadataCache ?? const {};

    final bottomInset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
    );

    final hasCachedResults =
        _cachedFolders.isNotEmpty || _cachedSongs.isNotEmpty;
    final hasDeepResults = _deepFolders.isNotEmpty || _deepSongs.isNotEmpty;
    final hasAnyResults = hasCachedResults || hasDeepResults;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(left: leftPadding),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: folderPageMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding + 16,
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
                        hintText: l10n.searchInFolderAndSubfolders,
                        onChanged: _onQueryChanged,
                        onClear: _onQueryCleared,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: !hasAnyResults && !_isDeepSearching
                      ? Center(
                          child: Text(
                            _query.isEmpty
                                ? l10n.typeToSearch
                                : l10n.noMatchingResults,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final crossAxisExtent = constraints.maxWidth;
                            return FolderZoomGestureLayer(
                              child: FolderZoomSliverBuilder(
                                zoomScale: snapFolderZoomScale(zoomScale),
                                width: crossAxisExtent,
                                controller: _scrollController,
                                builder: (context, metrics) {
                                  final sectionHPad =
                                      folderContentHorizontalPadding(
                                    isPortrait: isPortrait,
                                    gridMorph: metrics.gridMorph,
                                  );

                                  return CustomScrollView(
                                    controller: _scrollController,
                                    slivers: [
                                      const SliverPadding(
                                        padding: EdgeInsets.only(top: 4),
                                      ),
                                      if (hasCachedResults) ...[
                                        SliverToBoxAdapter(
                                          child: SearchSectionHeader(
                                            title: l10n.remoteSearchCachedTitle,
                                            padding: EdgeInsets.symmetric(
                                              horizontal: sectionHPad,
                                              vertical: 8.0,
                                            ),
                                          ),
                                        ),
                                        if (_cachedFolders.isNotEmpty)
                                          WebDavSubfoldersSliver(
                                            folders: _cachedFolders,
                                            zoomScale: zoomScale,
                                            server: widget.server,
                                            password: widget.password,
                                            onOpenFolder:
                                                _navigateToRemoteFolder,
                                            crossAxisExtent: crossAxisExtent,
                                            section: 'cached_folders',
                                          ),
                                        if (_cachedSongs.isNotEmpty)
                                          WebDavSongsSliver(
                                            files: _cachedSongs,
                                            zoomScale: zoomScale,
                                            server: widget.server,
                                            password: widget.password,
                                            metadataMap: metadataMap,
                                            currentMusicPath:
                                                currentMusic?.path,
                                            isAudioPlaying: isAudioPlaying,
                                            allAudioFiles:
                                                _buildMusicFiles(_cachedSongs),
                                            onSongTap: (file, index) =>
                                                _playSong(
                                              file,
                                              index,
                                              _cachedSongs,
                                            ),
                                            onSongLongPress: (file) =>
                                                _openSongMenu(file),
                                            onSongSecondaryTapDown:
                                                (file, details) =>
                                                    _openSongMenu(
                                              file,
                                              details.globalPosition,
                                            ),
                                            bottomPadding: 0.0,
                                            crossAxisExtent: crossAxisExtent,
                                            section: 'cached_songs',
                                          ),
                                        const SliverToBoxAdapter(
                                          child: SizedBox(height: 16),
                                        ),
                                      ],
                                      if (hasDeepResults) ...[
                                        SliverToBoxAdapter(
                                          child: SearchSectionHeader(
                                            title:
                                                '${l10n.remoteSearchDeepCompleted} (${_deepFolders.length + _deepSongs.length})',
                                            padding: EdgeInsets.symmetric(
                                              horizontal: sectionHPad,
                                              vertical: 8.0,
                                            ),
                                          ),
                                        ),
                                        if (_deepFolders.isNotEmpty)
                                          WebDavSubfoldersSliver(
                                            folders: _deepFolders,
                                            zoomScale: zoomScale,
                                            server: widget.server,
                                            password: widget.password,
                                            onOpenFolder:
                                                _navigateToRemoteFolder,
                                            crossAxisExtent: crossAxisExtent,
                                            section: 'deep_folders',
                                          ),
                                        if (_deepSongs.isNotEmpty)
                                          WebDavSongsSliver(
                                            files: _deepSongs,
                                            zoomScale: zoomScale,
                                            server: widget.server,
                                            password: widget.password,
                                            metadataMap: metadataMap,
                                            currentMusicPath:
                                                currentMusic?.path,
                                            isAudioPlaying: isAudioPlaying,
                                            allAudioFiles:
                                                _buildMusicFiles(_deepSongs),
                                            onSongTap: (file, index) =>
                                                _playSong(
                                              file,
                                              index,
                                              _deepSongs,
                                            ),
                                            onSongLongPress: (file) =>
                                                _openSongMenu(file),
                                            onSongSecondaryTapDown:
                                                (file, details) =>
                                                    _openSongMenu(
                                              file,
                                              details.globalPosition,
                                            ),
                                            bottomPadding: 0.0,
                                            crossAxisExtent: crossAxisExtent,
                                            section: 'deep_songs',
                                          ),
                                        const SliverToBoxAdapter(
                                          child: SizedBox(height: 16),
                                        ),
                                      ],
                                      // 深度搜索控制卡片
                                      SliverToBoxAdapter(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: sectionHPad,
                                          ),
                                          child: _buildDeepSearchCard(
                                            context,
                                            theme,
                                            l10n,
                                          ),
                                        ),
                                      ),
                                      SliverPadding(
                                        padding: EdgeInsets.only(
                                          bottom: bottomInset + 24,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
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

  Widget _buildDeepSearchCard(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    if (_isDeepSearching) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${l10n.remoteSearchDeepSearching} ($_deepSearchedDirCount)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _stopDeepSearch,
                  child: Text(l10n.remoteSearchDeepStop),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.travel_explore_rounded,
            color: theme.colorScheme.primary,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.remoteSearchDeepAction,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.currentPath,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _startDeepSearch,
            child: Text(l10n.search),
          ),
        ],
      ),
    );
  }
}
