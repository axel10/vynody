import 'dart:async';
import 'dart:io';
import 'dart:ui' show FrameTiming, TimingsCallback;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/folder_helpers.dart';
import '../utils/song_locator_helper.dart';
import 'package:collection/collection.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import '../widgets/library_selection_scope.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import '../widgets/folder_bottom_sheet.dart';
import 'folder_root_view.dart';
import 'folder_detail_view.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_riverpod.dart';
import 'remote/remote_library_page.dart';
import 'remote/remote_album_detail_page.dart';
import 'remote/remote_artist_detail_page.dart';
import 'remote/remote_playlist_detail_page.dart';
import 'remote/remote_folder_browser_page.dart';
import '../dialogs/music_folders_dialog.dart';
import 'package:vynody/player/pro/pro_license_service.dart';

class FoldersPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onOpenPlayback;

  const FoldersPage({super.key, this.onOpenPlayback});

  @override
  ConsumerState<FoldersPage> createState() => FoldersPageState();
}

class FoldersPageState extends ConsumerState<FoldersPage> {
  bool _isSelectionMode = false;
  bool _isRootSortMode = false;
  final Set<String> _selectedSongPaths = {};
  final Set<String> _selectedFolderPaths = {};
  final Set<String> _selectedRootPaths = {};
  ScannerService? _scanner;
  late final LibrarySelectionScopeController _librarySelectionScopeController;
  late final HeroController _heroController;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// 临时埋点：只在「刚点进目录」的 2 秒窗口内打印超时帧，
  /// 用来区分掉帧发生在 build（同步计算）还是 raster（图片解码 / 模糊）。
  TimingsCallback? _frameTimingsCallback;
  DateTime? _frameWatchUntil;

  void _handleFrameTimings(List<FrameTiming> timings) {
    final until = _frameWatchUntil;
    if (until == null || DateTime.now().isAfter(until)) return;
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMilliseconds;
      if (totalMs < 32) continue;
      debugPrint(
        '[Frame][timing] total=${totalMs}ms '
        'build=${timing.buildDuration.inMilliseconds}ms '
        'raster=${timing.rasterDuration.inMilliseconds}ms',
      );
    }
  }

  bool handleBackPressed() {
    if (_isRootSortMode) {
      setState(() {
        _isRootSortMode = false;
      });
      return true;
    }
    if (_isSelectionMode ||
        _selectedSongPaths.isNotEmpty ||
        _selectedFolderPaths.isNotEmpty ||
        _selectedRootPaths.isNotEmpty) {
      _clearAllSelection();
      return true;
    }
    if (_navigatorKey.currentState?.canPop() ?? false) {
      _navigatorKey.currentState?.maybePop();
      return true;
    }
    final session = ref.read(activeRemoteSessionProvider);
    if (session != null) {
      if (session.navidromeDetailStack.isNotEmpty) {
        ref.read(activeRemoteSessionProvider.notifier).popNavidromeDetail();
        return true;
      }
      if (session.webDavPathStack.isNotEmpty) {
        ref.read(activeRemoteSessionProvider.notifier).popWebDavPath();
        return true;
      }
      ref.read(activeRemoteSessionProvider.notifier).clear();
      return true;
    }
    final scanner = _scanner;
    if (scanner == null) return false;
    if (scanner.navigationCurrentFolder != null) {
      _goBack(scanner);
      return true;
    }
    return false;
  }

  void _setFolderSelectionMode(bool enabled) {
    _librarySelectionScopeController.setScope(
      enabled ? LibrarySelectionScope.folder : LibrarySelectionScope.none,
    );
  }

  Future<void> _navigateTo(MusicFolder folder, ScannerService scanner) async {
    // [FoldersPage][timing]：从「点击目录项」到「导航状态提交」的同步耗时。
    // 转场动画在这之后才由下一帧开始，所以这段越长，用户越觉得点了没反应。
    final totalSw = !kReleaseMode ? (Stopwatch()..start()) : null;
    if (!kReleaseMode) {
      // 转场动画约 300ms，留 2s 窗口足够覆盖「点进目录」这一整段。
      _frameWatchUntil = DateTime.now().add(const Duration(seconds: 2));
    }
    try {
      final rootPath = scanner.rootPaths.firstWhereOrNull(
        (root) => ScannerPathUtils.pathContains(root, folder.path),
      );

      if (rootPath != null) {
        await scanner.loadRootFolderSongs(rootPath);
        final rootFolder = scanner.rootFolders.firstWhereOrNull(
          (r) => ScannerPathUtils.pathsEqual(r.path, rootPath),
        );
        if (rootFolder != null) {
          final foundHistory = SongLocatorHelper.findFolderHistoryByFolderPath(
            rootFolder,
            folder.path,
          );
          if (foundHistory != null && foundHistory.isNotEmpty) {
            final targetFolder = foundHistory.last;
            final history = foundHistory.sublist(0, foundHistory.length - 1);
            scanner.setNavigationState(targetFolder, history);
            _clearAllSelection();
            _setFolderSelectionMode(false);
            return;
          }
        }
      } else if (folder.path == 'system' ||
          ScannerPathUtils.pathContains('system', folder.path)) {
        if (scanner.systemMediaFolder != null) {
          final foundHistory = SongLocatorHelper.findFolderHistoryByFolderPath(
            scanner.systemMediaFolder!,
            folder.path,
          );
          if (foundHistory != null && foundHistory.isNotEmpty) {
            final targetFolder = foundHistory.last;
            final history = foundHistory.sublist(0, foundHistory.length - 1);
            scanner.setNavigationState(targetFolder, history);
            _clearAllSelection();
            _setFolderSelectionMode(false);
            return;
          }
        }
      }

      final history = List<MusicFolder>.from(scanner.navigationHistory);
      if (scanner.navigationCurrentFolder != null) {
        history.add(scanner.navigationCurrentFolder!);
      }
      scanner.setNavigationState(folder, history);
      _clearAllSelection();
      _setFolderSelectionMode(false);
    } finally {
      if (!kReleaseMode) {
        debugPrint(
          '[FoldersPage][timing] navigateTo ${folder.path} '
          '${totalSw?.elapsedMilliseconds} ms '
          '(history=${scanner.navigationHistory.length})',
        );
      }
    }
  }

  void _goBack(ScannerService scanner) {
    if (scanner.navigationHistory.isEmpty) {
      scanner.setNavigationState(null, []);
    } else {
      final history = List<MusicFolder>.from(scanner.navigationHistory);
      final folder = history.removeLast();
      scanner.setNavigationState(folder, history);
    }
    _clearAllSelection();
    _setFolderSelectionMode(false);
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSongPaths.clear();
        _selectedFolderPaths.clear();
        _librarySelectionScopeController.clear();
      } else {
        _librarySelectionScopeController.setScope(LibrarySelectionScope.folder);
      }
    });

    final scanner = _scanner;
    if (scanner == null) return;

    _setFolderSelectionMode(
      _isSelectionMode &&
          isUserRootSelectionContext(
            scanner,
            scanner.navigationCurrentFolder,
            scanner.navigationHistory,
          ),
    );
  }

  void _toggleRootSortMode() {
    setState(() {
      _isRootSortMode = !_isRootSortMode;
      if (_isRootSortMode) {
        _isSelectionMode = false;
        _selectedSongPaths.clear();
        _selectedFolderPaths.clear();
        _selectedRootPaths.clear();
        _setFolderSelectionMode(false);
        _librarySelectionScopeController.clear();
      }
    });
  }

  void _toggleRootSelectionMode() {
    if (_isRootSortMode) {
      setState(() {
        _isRootSortMode = false;
      });
    }
    final enabled =
        ref.read(librarySelectionScopeProvider) !=
        LibrarySelectionScope.folderRoot;
    _librarySelectionScopeController.setScope(
      enabled ? LibrarySelectionScope.folderRoot : LibrarySelectionScope.none,
    );
    if (!enabled) {
      setState(() {
        _selectedRootPaths.clear();
      });
    }
  }

  void _clearAllSelection({bool clearSortMode = true}) {
    final shouldClearSongSelection =
        _isSelectionMode ||
        _selectedSongPaths.isNotEmpty ||
        _selectedFolderPaths.isNotEmpty;
    final isRootSelectionMode =
        ref.read(librarySelectionScopeProvider) ==
        LibrarySelectionScope.folderRoot;
    final shouldClearRootSelection =
        isRootSelectionMode || _selectedRootPaths.isNotEmpty;
    if (!shouldClearSongSelection &&
        !shouldClearRootSelection &&
        (!clearSortMode || !_isRootSortMode)) {
      return;
    }

    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
      _selectedFolderPaths.clear();
      _selectedRootPaths.clear();
      if (clearSortMode) {
        _isRootSortMode = false;
      }
    });
    _setFolderSelectionMode(false);
    _librarySelectionScopeController.clear();
  }



  void _toggleSelection(String path) {
    setState(() {
      if (_selectedSongPaths.contains(path)) {
        _selectedSongPaths.remove(path);
      } else {
        _selectedSongPaths.add(path);
      }
      if (_selectedSongPaths.isEmpty && _selectedFolderPaths.isEmpty) {
        _isSelectionMode = false;
        _librarySelectionScopeController.clear();
      } else {
        _librarySelectionScopeController.setScope(LibrarySelectionScope.folder);
      }
    });
  }

  void _toggleFolderSelection(String path) {
    setState(() {
      if (_selectedFolderPaths.contains(path)) {
        _selectedFolderPaths.remove(path);
      } else {
        _selectedFolderPaths.add(path);
      }
      if (_selectedSongPaths.isEmpty && _selectedFolderPaths.isEmpty) {
        _isSelectionMode = false;
        _librarySelectionScopeController.clear();
      } else {
        _librarySelectionScopeController.setScope(LibrarySelectionScope.folder);
      }
    });
  }

  /// 子目录右键 / 长按菜单里的「多选」入口，与详情页长按格子里同一套状态
  /// （`_selectedFolderPaths` + `folder` 作用域）。重复触发只保证选中，
  /// 不再反选，避免菜单项被点第二下时把已选目录取消掉。
  void _selectSubfolderFromMenu(String path) {
    if (!_isSelectionMode) {
      _toggleSelectionMode();
    }
    if (!_selectedFolderPaths.contains(path)) {
      _toggleFolderSelection(path);
    }
  }

  void _selectAllVisible(MusicFolder currentFolder) {
    _librarySelectionScopeController.setScope(LibrarySelectionScope.folder);
    setState(() {
      _selectedSongPaths
        ..clear()
        ..addAll(currentFolder.files.map((file) => file.path));
      _selectedFolderPaths
        ..clear()
        ..addAll(currentFolder.subFolders.map((folder) => folder.path));
      _isSelectionMode = true;
    });

    final scanner = _scanner;
    if (scanner == null) return;

    _setFolderSelectionMode(
      _isSelectionMode &&
          isUserRootSelectionContext(
            scanner,
            scanner.navigationCurrentFolder,
            scanner.navigationHistory,
          ),
    );
  }

  void _toggleRootSelection(String path) {
    setState(() {
      if (_selectedRootPaths.contains(path)) {
        _selectedRootPaths.remove(path);
      } else {
        _selectedRootPaths.add(path);
      }
    });
  }

  Future<void> _deleteSelectedRootFolders(ScannerService scanner) async {
    if (_selectedRootPaths.isEmpty) return;

    final selectedCount = _selectedRootPaths.length;
    final l10n = AppLocalizations.of(context)!;
    final paths = _selectedRootPaths.toList(growable: false);
    await scanner.removeRootPaths(paths);
    if (!mounted) return;

    setState(() {
      _selectedRootPaths.clear();
    });
    _librarySelectionScopeController.clear();

    AppSnackBar.show(
      context,
      ref,
      SnackBar(content: Text(l10n.foldersDeleted(selectedCount))),
    );
  }


  @override
  void initState() {
    super.initState();
    _heroController = HeroController();
    _librarySelectionScopeController = ref.read(
      librarySelectionScopeProvider.notifier,
    );
    _scanner = ref.read(scannerServiceProvider);
    if (!kReleaseMode) {
      _frameTimingsCallback = _handleFrameTimings;
      WidgetsBinding.instance.addTimingsCallback(_frameTimingsCallback!);
    }
  }

  @override
  void dispose() {
    final timingsCallback = _frameTimingsCallback;
    if (timingsCallback != null) {
      WidgetsBinding.instance.removeTimingsCallback(timingsCallback);
      _frameTimingsCallback = null;
    }
    Future.microtask(() {
      if (!mounted) return;
      _setFolderSelectionMode(false);
      _librarySelectionScopeController.clear();
    });
    super.dispose();
  }


  Page<dynamic> _buildPage({
    required LocalKey key,
    required Widget child,
  }) {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoPage<dynamic>(
        key: key,
        child: child,
      );
    }
    return MaterialPage<dynamic>(
      key: key,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.read(scannerServiceProvider);
    final navigationHistory = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.navigationHistory),
    );
    final currentFolder = ref.watch(
      scannerServiceProvider.select(
        (scanner) => scanner.navigationCurrentFolder,
      ),
    );

    if (Platform.isAndroid &&
        currentFolder?.path == 'system' &&
        scanner.systemMediaFolder != null &&
        currentFolder != scanner.systemMediaFolder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          scanner.setNavigationState(
            scanner.systemMediaFolder!,
            List.from(navigationHistory),
          );
        }
      });
    }

    final seenPaths = <String>{};
    final pages = <Page<dynamic>>[
      _buildPage(
        key: const ValueKey('folder-root-page'),
        child: FolderRootView(
          onOpenPlayback: widget.onOpenPlayback,
          isSelectionMode: _isSelectionMode,
          isSortMode: _isRootSortMode,
          selectedRootPaths: _selectedRootPaths,
          onPickFolder: () => MusicFoldersDialog.show(context),
          onToggleRootSelection: _toggleRootSelection,
          onToggleRootSelectionMode: _toggleRootSelectionMode,
          onToggleSortMode: _toggleRootSortMode,
          onDeleteSelectedRootFolders: () =>
              _deleteSelectedRootFolders(scanner),
          onNavigateTo: (folder) => _navigateTo(folder, scanner),
          onShowFolderBottomSheet: (folder, {required isRoot}) =>
              showFolderBottomSheet(
                context,
                ref,
                folder,
                isRoot: isRoot,
                onMultiSelect: (path) {
                  setState(() {
                    _selectedRootPaths.add(path);
                  });
                },
              ),
          onShowFolderContextMenu: (folder, position, {required isRoot}) =>
              showFolderContextMenu(
                context: context,
                globalPosition: position,
                ref: ref,
                folder: folder,
                isRoot: isRoot,
                onMultiSelect: (path) {
                  setState(() {
                    _selectedRootPaths.add(path);
                  });
                },
              ),
        ),
      ),
    ];

    for (int i = 0; i < navigationHistory.length; i++) {
      final folder = navigationHistory[i];
      if (seenPaths.add(folder.path)) {
        pages.add(
          _buildPage(
            key: ValueKey('folder-page-${folder.path}'),
            child: FolderDetailView(
              folder: folder,
              navigationHistory: navigationHistory.sublist(0, i),
              onOpenPlayback: widget.onOpenPlayback,
              isSelectionMode: _isSelectionMode,
              selectedSongPaths: _selectedSongPaths,
              selectedFolderPaths: _selectedFolderPaths,
              onNavigateTo: (folder) => _navigateTo(folder, scanner),
              onGoBack: () => _goBack(scanner),
              onToggleSelectionMode: _toggleSelectionMode,
              onToggleFolderSelection: _toggleFolderSelection,
              onToggleSelection: _toggleSelection,
              onSelectAllVisible: () => _selectAllVisible(folder),
              onClearAllSelection: _clearAllSelection,
              onShowFolderBottomSheet: (folder, {required isRoot}) =>
                  showFolderBottomSheet(
                    context,
                    ref,
                    folder,
                    isRoot: isRoot,
                    onMultiSelect: _selectSubfolderFromMenu,
                  ),
              onShowFolderContextMenu: (folder, position, {required isRoot}) =>
                  showFolderContextMenu(
                    context: context,
                    globalPosition: position,
                    ref: ref,
                    folder: folder,
                    isRoot: isRoot,
                    onMultiSelect: _selectSubfolderFromMenu,
                  ),
            ),
          ),
        );
      }
    }

    if (currentFolder != null && seenPaths.add(currentFolder.path)) {
      pages.add(
        _buildPage(
          key: ValueKey('folder-page-${currentFolder.path}'),
          child: FolderDetailView(
            folder: currentFolder,
            navigationHistory: navigationHistory,
            onOpenPlayback: widget.onOpenPlayback,
            isSelectionMode: _isSelectionMode,
            selectedSongPaths: _selectedSongPaths,
            selectedFolderPaths: _selectedFolderPaths,
            onNavigateTo: (folder) => _navigateTo(folder, scanner),
            onGoBack: () => _goBack(scanner),
            onToggleSelectionMode: _toggleSelectionMode,
            onToggleFolderSelection: _toggleFolderSelection,
            onToggleSelection: _toggleSelection,
            onSelectAllVisible: () => _selectAllVisible(currentFolder),
            onClearAllSelection: _clearAllSelection,
            onShowFolderBottomSheet: (folder, {required isRoot}) =>
                showFolderBottomSheet(
                  context,
                  ref,
                  folder,
                  isRoot: isRoot,
                  onMultiSelect: _selectSubfolderFromMenu,
                ),
            onShowFolderContextMenu: (folder, position, {required isRoot}) =>
                showFolderContextMenu(
                  context: context,
                  globalPosition: position,
                  ref: ref,
                  folder: folder,
                  isRoot: isRoot,
                  onMultiSelect: _selectSubfolderFromMenu,
                ),
          ),
        ),
      );
    }

    final activeRemoteSessionId = ref.watch(
      activeRemoteSessionProvider.select(
        (s) => s != null ? '${s.server.id}_${s.server.type}' : null,
      ),
    );
    final activeRemoteSession = ref.read(activeRemoteSessionProvider);
    final navidromeDetailStack = ref.watch(
      activeRemoteSessionProvider.select(
        (s) => s?.navidromeDetailStack ?? const [],
      ),
    );
    final webDavPathStack = ref.watch(
      activeRemoteSessionProvider.select(
        (s) => s?.webDavPathStack ?? const [],
      ),
    );

    final isProUnlocked = ref.watch(isProUnlockedProvider);

    if (activeRemoteSessionId != null &&
        activeRemoteSession != null &&
        isProUnlocked) {
      if (activeRemoteSession.server.type == RemoteServerType.subsonic ||
          activeRemoteSession.server.type == RemoteServerType.jellyfin) {
        pages.add(
          _buildPage(
            key: ValueKey('remote-page-${activeRemoteSession.server.id}'),
            child: RemoteLibraryPage(
              server: activeRemoteSession.server,
              password: activeRemoteSession.password,
              initialTabIndex: activeRemoteSession.initialTabIndex,
            ),
          ),
        );

        for (int i = 0; i < navidromeDetailStack.length; i++) {
          final route = navidromeDetailStack[i];
          if (route is NavidromeAlbumRoute) {
            pages.add(
              _buildPage(
                key: ValueKey('remote-album-${route.albumId}-$i'),
                child: RemoteAlbumDetailPage(
                  server: activeRemoteSession.server,
                  password: activeRemoteSession.password,
                  albumId: route.albumId,
                  albumName: route.albumName,
                  artistName: route.artistName,
                  coverArtId: route.coverArtId,
                  highlightedSongPath: route.highlightedSongPath,
                ),
              ),
            );
          } else if (route is NavidromeArtistRoute) {
            pages.add(
              _buildPage(
                key: ValueKey(
                    'remote-artist-${route.artistId}_${route.artistName}-$i'),
                child: RemoteArtistDetailPage(
                  server: activeRemoteSession.server,
                  password: activeRemoteSession.password,
                  artistId: route.artistId,
                  artistName: route.artistName,
                  coverArtId: route.coverArtId,
                  albumCount: route.albumCount,
                ),
              ),
            );
          } else if (route is NavidromePlaylistRoute) {
            pages.add(
              _buildPage(
                key: ValueKey('remote-playlist-${route.playlistId}-$i'),
                child: RemotePlaylistDetailPage(
                  server: activeRemoteSession.server,
                  password: activeRemoteSession.password,
                  playlistId: route.playlistId,
                  playlistName: route.playlistName,
                  coverArtId: route.coverArtId,
                  songCount: route.songCount,
                  duration: route.duration,
                  isStarred: route.isStarred,
                  highlightedSongPath: route.highlightedSongPath,
                ),
              ),
            );
          }
        }
      } else {
        final rootPath = normalizeRemotePath(
          activeRemoteSession.rootPath ??
              activeRemoteSession.server.customPath,
        );

        pages.add(
          _buildPage(
            key: ValueKey('remote-folder-root-${activeRemoteSession.server.id}'),
            child: RemoteFolderBrowserPage(
              server: activeRemoteSession.server,
              password: activeRemoteSession.password,
              initialPath: rootPath,
              rootPath: rootPath,
              highlightedSongPath: webDavPathStack.isEmpty
                  ? activeRemoteSession.webDavHighlightedSongPath
                  : null,
            ),
          ),
        );

        for (int i = 0; i < webDavPathStack.length; i++) {
          final currentPath = webDavPathStack[i];
          final isTopPage = i == webDavPathStack.length - 1;
          pages.add(
            _buildPage(
              key: ValueKey(
                  'remote-folder-page-${activeRemoteSession.server.id}-$currentPath-$i'),
              child: RemoteFolderBrowserPage(
                server: activeRemoteSession.server,
                password: activeRemoteSession.password,
                initialPath: currentPath,
                rootPath: rootPath,
                highlightedSongPath: isTopPage
                    ? activeRemoteSession.webDavHighlightedSongPath
                    : null,
              ),
            ),
          );
        }
      }
    }

    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        return true;
      },
      child: Navigator(
        key: _navigatorKey,
        pages: pages,
        observers: [_heroController],
        onDidRemovePage: (page) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final pageKeyStr = page.key?.toString() ?? '';
            if (pageKeyStr.contains('remote-folder-page-') ||
                pageKeyStr.contains('webdav-page-')) {
              ref.read(activeRemoteSessionProvider.notifier).popWebDavPath();
            } else if (pageKeyStr.contains('remote-folder-root-') ||
                pageKeyStr.contains('webdav-root-') ||
                pageKeyStr.contains('remote-page-')) {
              ref.read(activeRemoteSessionProvider.notifier).clear();
            } else if (pageKeyStr.contains('remote-album-') ||
                pageKeyStr.contains('remote-artist-') ||
                pageKeyStr.contains('remote-playlist-')) {
              ref.read(activeRemoteSessionProvider.notifier).popNavidromeDetail();
            } else if (pageKeyStr.contains('folder-page-')) {
              _goBack(scanner);
            }
          });
        },
      ),
    );
  }
}
