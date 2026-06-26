import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import '../widgets/song_tile.dart';
import '../widgets/library_selection_panel.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/song_thumbnail.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import '../dialogs/transcode_dialog.dart';
import 'package:vynody/transcode/transcode_riverpod.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/player/settings/settings_service.dart';

// 目录页
class FoldersPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onOpenPlayback;

  const FoldersPage({super.key, this.onOpenPlayback});

  @override
  ConsumerState<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends ConsumerState<FoldersPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedSongPaths = {};
  final Set<String> _selectedFolderPaths = {};
  final Set<String> _selectedRootPaths = {};
  StreamSubscription<ScanProgress>? _scanProgressSubscription;
  ToastFuture? _scanToast;
  bool _wasScanning = false;
  Timer? _scanToastUpdateTimer;
  Timer? _scanToastAutoDismissTimer;
  ScanProgress? _pendingScanProgress;
  DateTime? _lastScanToastUpdateAt;
  AppLocalizations? _l10n;
  ScannerService? _scanner;
  late final LibrarySelectionScopeController _librarySelectionScopeController;
  final ValueNotifier<_ScanToastState?> _scanToastState =
      ValueNotifier<_ScanToastState?>(null);
  String? _highlightedSongPath;
  Timer? _highlightTimer;
  late final HeroController _heroController;

  void _setFolderSelectionMode(bool enabled) {
    _librarySelectionScopeController.setScope(
      enabled ? LibrarySelectionScope.folder : LibrarySelectionScope.none,
    );
  }

  bool _isUserRootSelectionContext(
    ScannerService scanner,
    MusicFolder? currentFolder,
    List<MusicFolder> navigationHistory,
  ) {
    if (currentFolder == null) return false;

    final rootPaths = scanner.rootFolders.map((folder) => folder.path).toSet();
    rootPaths.add('system');
    if (rootPaths.contains(currentFolder.path)) {
      return true;
    }

    if (navigationHistory.isNotEmpty) {
      final rootFolder = navigationHistory.first;
      if (rootPaths.contains(rootFolder.path)) {
        return true;
      }
    }

    return false;
  }

  void _navigateTo(MusicFolder folder, ScannerService scanner) {
    final history = List<MusicFolder>.from(scanner.navigationHistory);
    if (scanner.navigationCurrentFolder != null) {
      history.add(scanner.navigationCurrentFolder!);
    }
    scanner.setNavigationState(folder, history);
    _clearAllSelection();
    _setFolderSelectionMode(false);
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
      }
    });

    final scanner = _scanner;
    if (scanner == null) return;

    _setFolderSelectionMode(
      _isSelectionMode &&
          _isUserRootSelectionContext(
            scanner,
            scanner.navigationCurrentFolder,
            scanner.navigationHistory,
          ),
    );
  }

  void _toggleRootSelectionMode() {
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

  void _clearAllSelection() {
    final shouldClearSongSelection =
        _isSelectionMode ||
        _selectedSongPaths.isNotEmpty ||
        _selectedFolderPaths.isNotEmpty;
    final isRootSelectionMode =
        ref.read(librarySelectionScopeProvider) ==
        LibrarySelectionScope.folderRoot;
    final shouldClearRootSelection =
        isRootSelectionMode || _selectedRootPaths.isNotEmpty;
    if (!shouldClearSongSelection && !shouldClearRootSelection) return;

    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
      _selectedFolderPaths.clear();
      _selectedRootPaths.clear();
    });
    _setFolderSelectionMode(false);
    _librarySelectionScopeController.clear();
  }

  List<MusicFolder>? _findFolderHistory(MusicFolder root, String songPath) {
    List<MusicFolder>? recurse(MusicFolder folder) {
      for (final file in folder.files) {
        if (p.equals(file.path, songPath)) {
          return [folder];
        }
      }
      for (final sub in folder.subFolders) {
        final res = recurse(sub);
        if (res != null) {
          return [folder, ...res];
        }
      }
      return null;
    }

    return recurse(root);
  }

  void _locateCurrentSong() {
    final currentMusic = ref.read(audioCurrentMusicProvider);
    if (currentMusic == null) return;

    final scanner = ref.read(scannerServiceProvider);
    List<MusicFolder>? foundHistory;

    // Search in root folders
    for (final root in scanner.rootFolders) {
      foundHistory = _findFolderHistory(root, currentMusic.path);
      if (foundHistory != null) {
        break;
      }
    }

    // If not found in roots, search in system media library
    if (foundHistory == null && scanner.systemMediaFolder != null) {
      foundHistory = _findFolderHistory(scanner.systemMediaFolder!, currentMusic.path);
    }

    if (foundHistory != null && foundHistory.isNotEmpty) {
      final targetFolder = foundHistory.last;
      final history = foundHistory.sublist(0, foundHistory.length - 1);
      final alreadyInFolder = scanner.navigationCurrentFolder?.path == targetFolder.path;

      if (!alreadyInFolder) {
        scanner.setNavigationState(targetFolder, history);
      }

      setState(() {
        _highlightedSongPath = currentMusic.path;
      });

      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _highlightedSongPath = null;
          });
        }
      });
    } else {
      showToast(AppLocalizations.of(context)!.songNotInScannedFolders);
    }
  }

  void _ensureScanToastVisible() {
    if (_scanToast?.mounted == true) return;

    final l10n = _l10n;
    if (l10n == null) return;
    _scanToastState.value = const _ScanToastState(
      fileName: '',
      discoveredLabelText: '',
      preprocessedLabelText: '',
      completedLabelText: '',
    );
    _scanToast = showToastWidget(
      _ScanProgressToast(
        stateListenable: _scanToastState,
        label: l10n.scanningDirectory,
      ),
      position: ToastPosition.top.copyWith(offset: 28),
      duration: const Duration(days: 1),
      dismissOtherToast: true,
      animationDuration: const Duration(milliseconds: 180),
    );
  }

  void _dismissScanToast({bool notifyListeners = true}) {
    _scanToastUpdateTimer?.cancel();
    _scanToastUpdateTimer = null;
    _scanToastAutoDismissTimer?.cancel();
    _scanToastAutoDismissTimer = null;
    _pendingScanProgress = null;
    _lastScanToastUpdateAt = null;
    _scanToast?.dismiss(showAnim: false);
    _scanToast = null;
    if (notifyListeners) {
      _scanToastState.value = null;
    }
  }

  void _handleScannerChanged() {
    final scanner = _scanner;
    if (scanner == null) return;
    final isScanning = scanner.isScanning;
    if (_wasScanning && !isScanning) {
      _dismissScanToast();
    }
    _wasScanning = isScanning;
  }

  void _showScanProgressToast(ScanProgress progress) {
    if (!mounted) return;

    _pendingScanProgress = progress;

    final now = DateTime.now();
    final lastUpdate = _lastScanToastUpdateAt;
    final elapsed = lastUpdate == null ? null : now.difference(lastUpdate);

    if (_scanToastUpdateTimer?.isActive ?? false) {
      return;
    }

    if (elapsed == null || elapsed >= const Duration(seconds: 1)) {
      _flushPendingScanProgress();
      return;
    }

    _scanToastUpdateTimer = Timer(const Duration(seconds: 1) - elapsed, () {
      _scanToastUpdateTimer = null;
      if (!mounted) return;
      _flushPendingScanProgress();
    });
  }

  void _flushPendingScanProgress() {
    final progress = _pendingScanProgress;
    final l10n = _l10n;
    if (progress == null || l10n == null) return;

    _pendingScanProgress = null;
    _ensureScanToastVisible();
    _scanToastState.value = _ScanToastState(
      fileName: p.basename(progress.filePath),
      discoveredLabelText: l10n.filesDiscovered(progress.discoveredCount),
      preprocessedLabelText: l10n.filesPreprocessed(progress.preprocessedCount),
      completedLabelText: l10n.filesFullyProcessed(progress.completedCount),
    );
    _lastScanToastUpdateAt = DateTime.now();
    _scheduleScanToastAutoDismiss();
  }

  void _scheduleScanToastAutoDismiss() {
    _scanToastAutoDismissTimer?.cancel();
    _scanToastAutoDismissTimer = Timer(const Duration(seconds: 2), () {
      _scanToastAutoDismissTimer = null;
      if (!mounted) return;

      final scanner = _scanner;
      if (scanner != null && scanner.isScanning) {
        _scheduleScanToastAutoDismiss();
        return;
      }

      _dismissScanToast();
    });
  }

  void _toggleSelection(String path) {
    setState(() {
      if (_selectedSongPaths.contains(path)) {
        _selectedSongPaths.remove(path);
      } else {
        _selectedSongPaths.add(path);
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
    });
  }

  void _selectAllVisible(MusicFolder currentFolder) {
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
      _isUserRootSelectionContext(
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    _heroController = HeroController();
    _librarySelectionScopeController = ref.read(
      librarySelectionScopeProvider.notifier,
    );
    _scanner = ref.read(scannerServiceProvider);
    _wasScanning = _scanner!.isScanning;
    _scanner!.addListener(_handleScannerChanged);
    _scanProgressSubscription = _scanner!.scanProgressStream.listen(
      _showScanProgressToast,
    );
  }

  @override
  void dispose() {
    // Defer the provider write so it happens after the current widget tree
    // finishes unmounting. Doing it synchronously here can trip Riverpod's
    // "modifying a provider while building" assertion during tab switches.
    Future.microtask(() {
      if (!mounted) return;
      _setFolderSelectionMode(false);
      _librarySelectionScopeController.clear();
    });
    _scanToastUpdateTimer?.cancel();
    _scanToastAutoDismissTimer?.cancel();
    _highlightTimer?.cancel();
    _scanProgressSubscription?.cancel();
    _scanner?.removeListener(_handleScannerChanged);
    _dismissScanToast(notifyListeners: false);
    _scanToastState.dispose();
    super.dispose();
  }

  Future<String?> _getDirectoryPath() {
    if (Platform.isWindows) {
      debugPrint('[FoldersPage] picking directory with file_selector');
      return file_selector.getDirectoryPath();
    }

    debugPrint('[FoldersPage] picking directory with file_picker');
    return FilePicker.getDirectoryPath(lockParentWindow: true);
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    // 记住当前的工作目录，因为 Windows 原生目录选择器可能会改变它。
    // MSIX 下对话框返回后的短时间内尤其敏感，后续逻辑要尽量轻。
    Directory? cwd;
    try {
      cwd = Directory.current;
    } catch (_) {}

    String? selectedDirectory;
    AndroidOutputDirectory? androidOutputDirectory;

    if (Platform.isAndroid) {
      androidOutputDirectory = await ref.read(transcodeServiceProvider).pickAndroidOutputDirectory();
      selectedDirectory = androidOutputDirectory?.displayPath;
    } else {
      selectedDirectory = await _getDirectoryPath();
    }

    debugPrint(
      '[FoldersPage] directory picker returned '
      'hasSelection=${selectedDirectory != null}',
    );

    // 恢复工作目录
    if (cwd != null) {
      try {
        Directory.current = cwd;
      } catch (_) {}
    }

    if (selectedDirectory != null) {
      if (!mounted) return;

      // 给 Windows 一点时间完全关闭对话框并释放 COM 资源，避免卡死
      if (Platform.isWindows) {
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (Platform.isAndroid && androidOutputDirectory != null) {
        await AndroidSafStorageHelper.saveMapping(
          androidOutputDirectory.displayPath,
          androidOutputDirectory.treeUri,
        );
      }

      debugPrint('[FoldersPage] adding selected root path=$selectedDirectory');
      final result = await scanner.addRootPath(selectedDirectory);
      debugPrint(
        '[FoldersPage] add root path completed status=${result.status}',
      );

      if (!mounted) return;
      String message;
      switch (result.status) {
        case RootPathAddStatus.added:
        case RootPathAddStatus.alreadyAdded:
          message = AppLocalizations.of(context)!.directoryAddedSuccess;
          break;
        case RootPathAddStatus.noMusic:
          message = AppLocalizations.of(context)!.directoryAddedNoMusic;
          break;
        case RootPathAddStatus.persistentAccessDenied:
          message = AppLocalizations.of(context)!.persistentAccessDenied;
          break;
        case RootPathAddStatus.failed:
          message = AppLocalizations.of(context)!.folderAddFailed;
          break;
      }
      AppSnackBar.show(context, ref, SnackBar(content: Text(message)));
    }
  }

  final GlobalKey<NavigatorState> _nestedNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final scanner = ref.read(scannerServiceProvider);
    final navigationHistory = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.navigationHistory),
    );
    final currentFolder = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.navigationCurrentFolder),
    );

    // Sync _currentFolder if it's the system root and data has been loaded.
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

    final pages = <Page<dynamic>>[
      MaterialPage(
        key: const ValueKey('folder-root-page'),
        child: _FolderRootView(
          onOpenPlayback: widget.onOpenPlayback,
          isSelectionMode: _isSelectionMode,
          selectedRootPaths: _selectedRootPaths,
          onPickFolder: () => _pickFolder(scanner),
          onToggleRootSelection: _toggleRootSelection,
          onToggleRootSelectionMode: _toggleRootSelectionMode,
          onDeleteSelectedRootFolders: () => _deleteSelectedRootFolders(scanner),
          onNavigateTo: (folder) => _navigateTo(folder, scanner),
          onLocateCurrentSong: _locateCurrentSong,
          onShowFolderBottomSheet: (folder, {required isRoot}) =>
              _showFolderBottomSheet(context, folder, isRoot: isRoot),
        ),
      ),
      for (int i = 0; i < navigationHistory.length; i++)
        MaterialPage(
          key: ValueKey('folder-page-${navigationHistory[i].path}'),
          child: _FolderDetailView(
            folder: navigationHistory[i],
            onOpenPlayback: widget.onOpenPlayback,
            isSelectionMode: _isSelectionMode,
            selectedSongPaths: _selectedSongPaths,
            selectedFolderPaths: _selectedFolderPaths,
            onNavigateTo: (folder) => _navigateTo(folder, scanner),
            onGoBack: () => _goBack(scanner),
            onToggleSelectionMode: _toggleSelectionMode,
            onToggleFolderSelection: _toggleFolderSelection,
            onToggleSelection: _toggleSelection,
            onSelectAllVisible: () => _selectAllVisible(navigationHistory[i]),
            onClearAllSelection: _clearAllSelection,
            onLocateCurrentSong: _locateCurrentSong,
            onShowFolderBottomSheet: (folder, {required isRoot}) =>
                _showFolderBottomSheet(context, folder, isRoot: isRoot),
            highlightedSongPath: _highlightedSongPath,
          ),
        ),
      if (currentFolder != null)
        MaterialPage(
          key: ValueKey('folder-page-${currentFolder.path}'),
          child: _FolderDetailView(
            folder: currentFolder,
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
            onLocateCurrentSong: _locateCurrentSong,
            onShowFolderBottomSheet: (folder, {required isRoot}) =>
                _showFolderBottomSheet(context, folder, isRoot: isRoot),
            highlightedSongPath: _highlightedSongPath,
          ),
        ),
    ];

    return Navigator(
      key: _nestedNavigatorKey,
      pages: pages,
      observers: [_heroController],
      onDidRemovePage: (page) {
        _goBack(scanner);
      },
    );
  }

  Future<void> _showFolderBottomSheet(
    BuildContext context,
    MusicFolder folder, {
    required bool isRoot,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final songs = folder.allSongs;
    final audio = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);
    final scanner = ref.read(scannerServiceProvider);

    final canOpenLocation =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
        folder.path.trim().isNotEmpty &&
        folder.path != 'system';

    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final selectLabel = isZh ? '选择目录' : 'Select Folders';
    final removeLabel = isZh ? '移除目录' : 'Remove Directory';

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      isScrollControlled: true,
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: GestureDetector(
                  onTap:
                      () {}, // Prevent taps on the card itself from closing the sheet
                  child: Material(
                    elevation: 16,
                    color: theme.colorScheme.surface,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(24),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header showing Folder name and folder icon
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.4),
                                  child: Icon(
                                    isRoot
                                        ? Icons.folder_shared
                                        : Icons.folder_rounded,
                                    size: 30,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      folder.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    if (isRoot && folder.path.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        folder.path,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      l10n.songCount(songs.length),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          // Actions list
                          _buildFolderBottomSheetItem(
                            context: context,
                            value: 'play_all',
                            label: l10n.playAll,
                            icon: Icons.play_arrow_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildFolderBottomSheetItem(
                            context: context,
                            value: 'shuffle',
                            label: l10n.shufflePlay,
                            icon: Icons.shuffle_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildFolderBottomSheetItem(
                            context: context,
                            value: 'play_next',
                            label: l10n.playNext,
                            icon: Icons.queue_play_next_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildFolderBottomSheetItem(
                            context: context,
                            value: 'add_to_queue',
                            label: l10n.addToQueue,
                            icon: Icons.queue_music_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildFolderBottomSheetItem(
                            context: context,
                            value: 'add_to_playlist',
                            label: l10n.addToPlaylist,
                            icon: Icons.playlist_add_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          _buildFolderBottomSheetItem(
                            context: context,
                            value: 'transcode',
                            label: l10n.transcodeAction,
                            icon: Icons.sync_rounded,
                            enabled: songs.isNotEmpty,
                          ),
                          if (canOpenLocation)
                            _buildFolderBottomSheetItem(
                              context: context,
                              value: 'open_folder_location',
                              label: l10n.openFolderLocation,
                              icon: Icons.folder_open_rounded,
                            ),
                          if (isRoot) ...[
                            _buildFolderBottomSheetItem(
                              context: context,
                              value: 'multi_select',
                              label: selectLabel,
                              icon: Icons.checklist_rounded,
                            ),
                            _buildFolderBottomSheetItem(
                              context: context,
                              value: 'remove_root',
                              label: removeLabel,
                              icon: Icons.delete_rounded,
                              iconColor: theme.colorScheme.error,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!context.mounted || selected == null) return;

    switch (selected) {
      case 'play_all':
        await audio.playPlaylist(songs);
        break;
      case 'shuffle':
        await audio.playPlaylist(List.of(songs)..shuffle());
        break;
      case 'play_next':
        await audio.enqueueNext(songs);
        break;
      case 'add_to_queue':
        await audio.appendToQueue(songs);
        break;
      case 'add_to_playlist':
        await showAddSongsToPlaylistDialog(context, playlistService, songs);
        break;
      case 'transcode':
        await showTranscodeDialog(context, songs: songs);
        break;
      case 'open_folder_location':
        await openFolderLocation(folder.path);
        break;
      case 'multi_select':
        ref
            .read(librarySelectionScopeProvider.notifier)
            .setScope(LibrarySelectionScope.folderRoot);
        setState(() {
          _selectedRootPaths.add(folder.path);
        });
        break;
      case 'remove_root':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(removeLabel),
            content: Text(
              isZh
                  ? '确定要移除根目录 "${folder.name}" 吗？此操作不会删除磁盘上的物理文件。'
                  : 'Are you sure you want to remove the root directory "${folder.name}"? This will not delete physical files on disk.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.confirm),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          await scanner.removeRootPath(folder.path);
          if (context.mounted) {
            AppSnackBar.show(
              context,
              ref,
              SnackBar(content: Text(l10n.foldersDeleted(1))),
            );
          }
        }
        break;
    }
  }

  Widget _buildFolderBottomSheetItem({
    required BuildContext context,
    required String value,
    required String label,
    required IconData icon,
    bool enabled = true,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(
        icon,
        color: enabled
            ? (iconColor ?? theme.colorScheme.onSurfaceVariant)
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      title: Text(
        label,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: enabled
              ? (iconColor ?? theme.colorScheme.onSurface)
              : theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
      enabled: enabled,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => Navigator.pop(context, value),
    );
  }
}

class _ScanProgressToast extends StatelessWidget {
  const _ScanProgressToast({
    required this.label,
    required this.stateListenable,
  });

  final String label;
  final ValueListenable<_ScanToastState?> stateListenable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black;
    final accent = theme.colorScheme.primary;

    return ValueListenableBuilder<_ScanToastState?>(
      valueListenable: stateListenable,
      builder: (context, state, _) {
        final fileName = state?.fileName ?? '';
        final discoveredLabel = state?.discoveredLabelText ?? '';
        final preprocessedLabel = state?.preprocessedLabelText ?? '';
        final completedLabel = state?.completedLabelText ?? '';
        final summaryText = [
          discoveredLabel,
          preprocessedLabel,
          completedLabel,
        ].where((text) => text.isNotEmpty).join(' · ');

        return Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: null,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                    backgroundColor: onSurface.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withValues(alpha: 0.8),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ScanToastState {
  const _ScanToastState({
    required this.fileName,
    required this.discoveredLabelText,
    required this.preprocessedLabelText,
    required this.completedLabelText,
  });

  final String fileName;
  final String discoveredLabelText;
  final String preprocessedLabelText;
  final String completedLabelText;
}

// Helpers for folder_page
bool _isUserRootSelectionContext(
  ScannerService scanner,
  MusicFolder? currentFolder,
  List<MusicFolder> navigationHistory,
) {
  if (currentFolder == null) return false;

  final rootPaths = scanner.rootFolders.map((folder) => folder.path).toSet();
  rootPaths.add('system');
  if (rootPaths.contains(currentFolder.path)) {
    return true;
  }

  if (navigationHistory.isNotEmpty) {
    final rootFolder = navigationHistory.first;
    if (rootPaths.contains(rootFolder.path)) {
      return true;
    }
  }

  return false;
}

MusicFile? _findRepresentativeSong(MusicFolder folder) {
  for (final file in folder.files) {
    if (file.thumbnailPath != null || file.id != null) {
      return file;
    }
  }
  for (final song in folder.allSongs) {
    if (song.thumbnailPath != null || song.id != null) {
      return song;
    }
  }
  if (folder.files.isNotEmpty) {
    return folder.files.first;
  }
  if (folder.allSongs.isNotEmpty) {
    return folder.allSongs.first;
  }
  return null;
}

// Folder Root View
class _FolderRootView extends ConsumerStatefulWidget {
  const _FolderRootView({
    required this.onOpenPlayback,
    required this.isSelectionMode,
    required this.selectedRootPaths,
    required this.onPickFolder,
    required this.onToggleRootSelection,
    required this.onToggleRootSelectionMode,
    required this.onDeleteSelectedRootFolders,
    required this.onNavigateTo,
    required this.onLocateCurrentSong,
    required this.onShowFolderBottomSheet,
  });

  final Future<void> Function()? onOpenPlayback;
  final bool isSelectionMode;
  final Set<String> selectedRootPaths;
  final VoidCallback onPickFolder;
  final void Function(String) onToggleRootSelection;
  final VoidCallback onToggleRootSelectionMode;
  final Future<void> Function() onDeleteSelectedRootFolders;
  final void Function(MusicFolder) onNavigateTo;
  final VoidCallback onLocateCurrentSong;
  final void Function(MusicFolder, {required bool isRoot}) onShowFolderBottomSheet;

  @override
  ConsumerState<_FolderRootView> createState() => _FolderRootViewState();
}

class _FolderRootViewState extends ConsumerState<_FolderRootView> {
  late final ScrollController _localScrollController;

  @override
  void initState() {
    super.initState();
    final targetOffset = ref.read(scannerServiceProvider).getFolderScrollOffset('root');
    _localScrollController = ScrollController(initialScrollOffset: targetOffset);
    _localScrollController.addListener(_onScroll);
  }

  void _onScroll() {
    ref.read(scannerServiceProvider).setFolderScrollOffset(
      'root',
      _localScrollController.offset,
    );
  }

  @override
  void dispose() {
    _localScrollController.removeListener(_onScroll);
    _localScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final isRootSelectionMode =
        ref.watch(librarySelectionScopeProvider) ==
        LibrarySelectionScope.folderRoot;
    final rootFolders = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.rootFolders),
    );
    final hasPermission = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.hasPermission),
    );
    final currentMusic = ref.watch(audioCurrentMusicProvider);


    final selectionLabel = l10n.selectedFolders(widget.selectedRootPaths.length);
    final rootListBottomPadding = isRootSelectionMode ? 224.0 : 160.0;
    
    final selectedRootSongs = <MusicFile>[];
    final seenSelected = <String>{};
    for (final folder in rootFolders) {
      if (widget.selectedRootPaths.contains(folder.path)) {
        for (final song in folder.allSongs) {
          if (seenSelected.add(song.path)) {
            selectedRootSongs.add(song);
          }
        }
      }
    }
    final allRootSongs = <MusicFile>[];
    final seenAll = <String>{};
    for (final folder in rootFolders) {
      for (final song in folder.allSongs) {
        if (seenAll.add(song.path)) {
          allRootSongs.add(song);
        }
      }
    }

    Widget rootList;
    if (isRootSelectionMode) {
      rootList = ReorderableListView.builder(
        key: const ValueKey('root_folders_list'),
        buildDefaultDragHandles: false,
        scrollController: _localScrollController,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1000.0),
        padding: EdgeInsets.only(bottom: rootListBottomPadding),
        itemCount: rootFolders.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex--;
          unawaited(scanner.moveRootPath(oldIndex, newIndex));
        },
        itemBuilder: (context, index) {
          final folder = rootFolders[index];
          final isSelected = widget.selectedRootPaths.contains(folder.path);
          final isRootAvailable = scanner.isRootPathAvailable(folder.path);
          return GestureDetector(
            key: ValueKey(folder.path),
            behavior: HitTestBehavior.opaque,
            onSecondaryTapDown: (details) {
              widget.onShowFolderBottomSheet(folder, isRoot: true);
            },
            onLongPress: () {
              widget.onToggleRootSelection(folder.path);
            },
            child: AnimatedOpacity(
              opacity: isRootAvailable ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 180),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      MediaQuery.of(context).orientation ==
                          Orientation.portrait
                      ? 8
                      : 16,
                  vertical: 4,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  hoverColor: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.06),
                  enabled: isRootAvailable || isRootSelectionMode,
                  selected: isSelected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.45),
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) =>
                        widget.onToggleRootSelection(folder.path),
                  ),
                  title: Text(folder.name),
                  subtitle: Text(
                    ScannerPathUtils.cleanDisplayPath(folder.path),
                  ),
                  onTap: () => widget.onToggleRootSelection(folder.path),
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      rootList = GridView.builder(
          key: const ValueKey('root_folders_grid'),
          controller: _localScrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1000.0),
          padding: EdgeInsets.only(bottom: rootListBottomPadding, left: 16, right: 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: rootFolders.length,
          itemBuilder: (context, index) {
            final folder = rootFolders[index];
            final isRootAvailable = scanner.isRootPathAvailable(folder.path);
            final representativeSong = _findRepresentativeSong(folder);
            return AnimatedOpacity(
              opacity: isRootAvailable ? 1.0 : 0.45,
              duration: const Duration(milliseconds: 180),
              child: _HoverableCard(
                child: _FolderGridCard(
                  folder: folder,
                  songsCount: folder.allSongs.length,
                  representativeSong: representativeSong,
                  onTap: isRootAvailable ? () => widget.onNavigateTo(folder) : null,
                  onLongPress: () => widget.onShowFolderBottomSheet(folder, isRoot: true),
                  onSecondaryTapDown: (details) => widget.onShowFolderBottomSheet(folder, isRoot: true),
                ),
              ),
            );
          },
        );
    }

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.scanDirectory,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (currentMusic != null)
                        IconButton(
                          icon: const Icon(Icons.my_location_rounded),
                          onPressed: widget.onLocateCurrentSong,
                          tooltip: AppLocalizations.of(context)!.locateCurrentSong,
                        ),

                      IconButton(
                        icon: Icon(
                          Icons.sort,
                          color: isRootSelectionMode
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        onPressed: widget.onToggleRootSelectionMode,
                        tooltip: AppLocalizations.of(context)!.sort,
                      ),
                    ],
                  ),
                ),
                if (Platform.isAndroid)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          MediaQuery.of(context).orientation ==
                              Orientation.portrait
                          ? 8
                          : 16,
                      vertical: 4,
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      hoverColor: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.06),
                      leading: const Icon(
                        Icons.library_music,
                        color: Colors.purple,
                      ),
                      title: Text(
                        AppLocalizations.of(context)!.systemMediaLibrary,
                      ),
                      subtitle: hasPermission
                          ? null
                          : Text(
                              AppLocalizations.of(context)!.needPermissionToScan,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                      onTap: () {
                        widget.onNavigateTo(
                          scanner.systemMediaFolder ??
                              MusicFolder(
                                path: 'system',
                                name: AppLocalizations.of(
                                  context,
                                )!.systemMediaLibrary,
                              ),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).orientation == Orientation.portrait
                        ? 8
                        : 16,
                    vertical: 4,
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hoverColor: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.06),
                    leading: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.blue,
                    ),
                    title: Text(AppLocalizations.of(context)!.addRootDirectory),
                    onTap: widget.onPickFolder,
                  ),
                ),
                Expanded(child: rootList),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                reverseDuration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0, 1.0),
                    end: Offset.zero,
                  ).animate(animation);
                  return SlideTransition(position: offsetAnimation, child: child);
                },
                child: isRootSelectionMode
                    ? LibrarySelectionPanel(
                        key: const ValueKey('root-selection-panel'),
                        selectedSongs: selectedRootSongs,
                        allSongs: allRootSongs,
                        title: selectionLabel,
                        onToggleSelectAll: () {
                          final isAllSelected =
                              widget.selectedRootPaths.length == rootFolders.length;
                          if (isAllSelected) {
                            for (final f in rootFolders) {
                              widget.onToggleRootSelection(f.path);
                            }
                          } else {
                            for (final f in rootFolders) {
                              if (!widget.selectedRootPaths.contains(f.path)) {
                                widget.onToggleRootSelection(f.path);
                              }
                            }
                          }
                        },
                        onCancel: widget.onToggleRootSelectionMode,
                        onDelete: widget.selectedRootPaths.isEmpty
                            ? null
                            : widget.onDeleteSelectedRootFolders,
                        deleteLabel: l10n.delete,
                        onOpenLocation: widget.selectedRootPaths.length == 1
                            ? () => openFolderLocation(widget.selectedRootPaths.first)
                            : null,
                        openLocationLabel: l10n.openFolderLocation,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('root-selection-panel-hidden'),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Folder Detail View
class _FolderDetailView extends ConsumerStatefulWidget {
  const _FolderDetailView({
    required this.folder,
    required this.onOpenPlayback,
    required this.isSelectionMode,
    required this.selectedSongPaths,
    required this.selectedFolderPaths,
    required this.onNavigateTo,
    required this.onGoBack,
    required this.onToggleSelectionMode,
    required this.onToggleFolderSelection,
    required this.onToggleSelection,
    required this.onSelectAllVisible,
    required this.onClearAllSelection,
    required this.onLocateCurrentSong,
    required this.onShowFolderBottomSheet,
    required this.highlightedSongPath,
  });

  final MusicFolder folder;
  final Future<void> Function()? onOpenPlayback;
  final bool isSelectionMode;
  final Set<String> selectedSongPaths;
  final Set<String> selectedFolderPaths;
  final void Function(MusicFolder) onNavigateTo;
  final VoidCallback onGoBack;
  final VoidCallback onToggleSelectionMode;
  final void Function(String) onToggleFolderSelection;
  final void Function(String) onToggleSelection;
  final VoidCallback onSelectAllVisible;
  final VoidCallback onClearAllSelection;
  final VoidCallback onLocateCurrentSong;
  final void Function(MusicFolder, {required bool isRoot}) onShowFolderBottomSheet;
  final String? highlightedSongPath;

  @override
  ConsumerState<_FolderDetailView> createState() => _FolderDetailViewState();
}

class _FolderDetailViewState extends ConsumerState<_FolderDetailView> {
  late final ScrollController _localScrollController;
  late final TextEditingController _searchController;
  bool _isSearching = false;
  String _searchQuery = '';
  String? _lastHighlightedPath;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    final targetOffset = ref.read(scannerServiceProvider).getFolderScrollOffset(widget.folder.path);
    _localScrollController = ScrollController(initialScrollOffset: targetOffset);
    _localScrollController.addListener(_onScroll);

    if (widget.highlightedSongPath != null) {
      _lastHighlightedPath = widget.highlightedSongPath;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlightedSong());
    }
  }

  @override
  void didUpdateWidget(_FolderDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlightedSongPath != null && widget.highlightedSongPath != _lastHighlightedPath) {
      _lastHighlightedPath = widget.highlightedSongPath;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToHighlightedSong());
    }
  }

  void _onScroll() {
    ref.read(scannerServiceProvider).setFolderScrollOffset(
      widget.folder.path,
      _localScrollController.offset,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _localScrollController.removeListener(_onScroll);
    _localScrollController.dispose();
    super.dispose();
  }

  List<MusicFolder> _findMatchingFolders(MusicFolder root, String query) {
    final results = <MusicFolder>[];
    final lowercaseQuery = query.toLowerCase();

    void search(MusicFolder folder) {
      if (folder.name.toLowerCase().contains(lowercaseQuery)) {
        results.add(folder);
      }
      for (final sub in folder.subFolders) {
        search(sub);
      }
    }

    for (final sub in root.subFolders) {
      search(sub);
    }
    return results;
  }

  List<MusicFile> _findMatchingSongs(MusicFolder root, String query) {
    final results = <MusicFile>[];
    final lowercaseQuery = query.toLowerCase();

    void search(MusicFolder folder) {
      for (final file in folder.files) {
        final matchesName = file.name.toLowerCase().contains(lowercaseQuery);
        final matchesTitle = file.title?.toLowerCase().contains(lowercaseQuery) ?? false;
        final matchesArtist = file.artist?.toLowerCase().contains(lowercaseQuery) ?? false;
        final matchesAlbum = file.album?.toLowerCase().contains(lowercaseQuery) ?? false;
        if (matchesName || matchesTitle || matchesArtist || matchesAlbum) {
          results.add(file);
        }
      }
      for (final sub in folder.subFolders) {
        search(sub);
      }
    }

    search(root);
    return results;
  }

  void _scrollToHighlightedSong() {
    if (!mounted) return;
    final songPath = widget.highlightedSongPath;
    if (songPath == null) return;

    final fileIndex = widget.folder.files.indexWhere((file) => p.equals(file.path, songPath));
    if (fileIndex == -1) return;

    final hasPermission = ref.read(scannerServiceProvider).hasPermission;
    final showPermissionWarning = widget.folder.path == 'system' && !hasPermission;

    double fileOffset = 48.0; // Breadcrumbs
    fileOffset += 190.0; // Header Banner approx height

    if (showPermissionWarning) {
      fileOffset += 200.0;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final int crossAxisCount = ((screenWidth - 16) / 196).floor().clamp(2, 6);
    final double cardWidth = (screenWidth - 32 - (crossAxisCount - 1) * 16) / crossAxisCount;
    final double cardHeight = cardWidth / 0.72;

    final totalGridItems = widget.folder.subFolders.length;
    final int rows = (totalGridItems / crossAxisCount).ceil();
    fileOffset += rows * (cardHeight + 16);
    fileOffset += fileIndex * 80.0;

    if (_localScrollController.hasClients) {
      final double viewportHeight = _localScrollController.position.viewportDimension;
      double targetOffset = fileOffset - (viewportHeight / 2) + 40.0;
      final maxScroll = _localScrollController.position.maxScrollExtent;
      targetOffset = targetOffset.clamp(0.0, maxScroll);

      _localScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<MusicFile> _getSelectedSongs() {
    final songs = <MusicFile>[];
    songs.addAll(
      widget.folder.allSongs.where(
        (file) => widget.selectedSongPaths.contains(file.path),
      ),
    );
    for (final sub in widget.folder.subFolders) {
      if (widget.selectedFolderPaths.contains(sub.path)) {
        songs.addAll(sub.allSongs);
      }
    }
    final seen = <String>{};
    return songs.where((song) => seen.add(song.path)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    final hasPermission = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.hasPermission),
    );
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    final matchedFolders = _searchQuery.isNotEmpty
        ? _findMatchingFolders(widget.folder, _searchQuery)
        : widget.folder.subFolders;
    final matchedSongs = _searchQuery.isNotEmpty
        ? _findMatchingSongs(widget.folder, _searchQuery)
        : widget.folder.files;

    final showSelectionPanel =
        widget.isSelectionMode &&
        _isUserRootSelectionContext(
          scanner,
          widget.folder,
          scanner.navigationHistory,
        );
    final selectionPanelHeight = showSelectionPanel ? 220.0 : 0.0;

    final representativeSong = _findRepresentativeSong(widget.folder);

    Widget scrollBody;

    Widget subfoldersSliver;
    final gridItemsCount = matchedFolders.length;
    subfoldersSliver = gridItemsCount > 0
        ? SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final folder = matchedFolders[index];
                  final isSelected = widget.selectedFolderPaths.contains(folder.path);
                  final folderRepSong = _findRepresentativeSong(folder);
                  return _HoverableCard(
                    child: _FolderGridCard(
                      folder: folder,
                      songsCount: folder.allSongs.length,
                      representativeSong: folderRepSong,
                      isSelected: isSelected,
                      isSelectionMode: widget.isSelectionMode,
                      onTap: widget.isSelectionMode
                          ? () => widget.onToggleFolderSelection(folder.path)
                          : () => widget.onNavigateTo(folder),
                      onLongPress: () {
                        if (!widget.isSelectionMode) {
                          widget.onToggleSelectionMode();
                          widget.onToggleFolderSelection(folder.path);
                        } else {
                          widget.onToggleFolderSelection(folder.path);
                        }
                      },
                      onSecondaryTapDown: (details) {
                        if (!widget.isSelectionMode) {
                          widget.onShowFolderBottomSheet(folder, isRoot: false);
                        }
                      },
                    ),
                  );
                },
                childCount: gridItemsCount,
              ),
            ),
          )
        : const SliverToBoxAdapter(child: SizedBox.shrink());

    Widget songsSliver;
    final noResults = _searchQuery.isNotEmpty && matchedFolders.isEmpty && matchedSongs.isEmpty;
    if (noResults) {
      songsSliver = SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  Localizations.localeOf(context).languageCode == 'zh' ? '未找到匹配的文件夹或歌曲' : 'No matching folders or songs found',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      songsSliver = SliverPadding(
        padding: const EdgeInsets.only(top: 8),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, fileIndex) {
              final file = matchedSongs[fileIndex];
              final isCurrent = currentMusic?.path == file.path;
              final isSelected = widget.selectedSongPaths.contains(file.path);
              final songsToAdd =
                  (widget.selectedSongPaths.isNotEmpty ||
                      widget.selectedFolderPaths.isNotEmpty)
                  ? _getSelectedSongs()
                  : <MusicFile>[file];

              void handleShowMenu(
                BuildContext menuContext,
                Offset position,
              ) {
                showSongContextMenu(
                  menuContext,
                  position,
                  song: file,
                  songs: songsToAdd,
                  mode: SongContextMenuMode.full,
                  onAddToPlaylist: () => showAddSongsToPlaylistDialog(
                    menuContext,
                    ref.read(playlistServiceProvider),
                    songsToAdd,
                  ),
                  onPlayNext: () => ref
                      .read(audioServiceProvider)
                      .enqueueNext(songsToAdd),
                  onAddToQueue: () => ref
                      .read(audioServiceProvider)
                      .appendToQueue(songsToAdd),
                );
              }

              return GestureDetector(
                key: ValueKey(file.path),
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) {
                  handleShowMenu(context, details.globalPosition);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        MediaQuery.of(context).orientation ==
                            Orientation.portrait
                        ? 8
                        : 16,
                    vertical: 4,
                  ),
                  child: SongTile(
                    song: file,
                    isCurrent: isCurrent,
                    isSelected: isSelected,
                    isSelectionMode: widget.isSelectionMode,
                    isHighlighted: widget.highlightedSongPath == file.path,
                    onTap: widget.isSelectionMode
                        ? () => widget.onToggleSelection(file.path)
                        : () async {
                            unawaited(() async {
                              try {
                                await audio.playPlaylist(
                                  matchedSongs,
                                  initialIndex: fileIndex,
                                );
                              } catch (e, st) {
                                debugPrint(
                                  'FoldersPage: failed to start folder playback for ${file.path}: $e',
                                );
                                debugPrintStack(stackTrace: st);
                              }
                            }());

                            if (mounted) {
                              widget.onClearAllSelection();
                              await widget.onOpenPlayback?.call();
                            }
                          },
                    onLongPress: () {
                      if (!widget.isSelectionMode) {
                        widget.onToggleSelectionMode();
                        widget.onToggleSelection(file.path);
                      }
                    },
                    onSecondaryTapDown: (details) {
                      handleShowMenu(context, details.globalPosition);
                    },
                    onMorePressed: (buttonContext) {
                      final renderObject = buttonContext.findRenderObject();
                      final renderBox = renderObject is RenderBox ? renderObject : null;
                      if (renderBox == null) return;
                      final Offset offset = renderBox.localToGlobal(Offset.zero);
                      handleShowMenu(buttonContext, offset);
                    },
                  ),
                ),
              );
            },
            childCount: matchedSongs.length,
          ),
        ),
      );
    }

    scrollBody = CustomScrollView(
      key: ValueKey(widget.folder.path),
      controller: _localScrollController,
      scrollCacheExtent: const ScrollCacheExtent.pixels(1000.0),
      slivers: [
        SliverToBoxAdapter(
          child: _buildBreadcrumbs(widget.folder, scanner),
        ),
        SliverToBoxAdapter(
          child: _buildFolderHeaderBanner(
            context: context,
            folder: widget.folder,
            representativeSong: representativeSong,
            songsCount: widget.folder.allSongs.length,
            displayPath: ScannerPathUtils.cleanDisplayPath(widget.folder.path),
            onPlayAll: () => audio.playPlaylist(widget.folder.allSongs),
            onShuffle: () => audio.playPlaylist(List.of(widget.folder.allSongs)..shuffle()),
          ),
        ),
        if (widget.folder.path == 'system' && !hasPermission)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.noMediaLibraryPermission),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => scanner.checkAndRequestPermissions(),
                      child: Text(l10n.grantPermission),
                    ),
                  ],
                ),
              ),
            ),
          ),
        subfoldersSliver,
        songsSliver,
        SliverPadding(
          padding: EdgeInsets.only(bottom: 160 + selectionPanelHeight),
        ),
      ],
    );

    final selectedSongs = showSelectionPanel ? _getSelectedSongs() : <MusicFile>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        widget.onGoBack();
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (widget.isSelectionMode && !showSelectionPanel)
                    Container(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(l10n.selectedSongs(_getSelectedSongs().length)),
                          const Spacer(),
                          TextButton(
                            onPressed: widget.onToggleSelectionMode,
                            child: Text(l10n.cancel),
                          ),
                        ],
                      ),
                    ),
                  Expanded(child: scrollBody),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  reverseDuration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final offsetAnimation = Tween<Offset>(
                      begin: const Offset(0, 1.0),
                      end: Offset.zero,
                    ).animate(animation);
                    return SlideTransition(position: offsetAnimation, child: child);
                  },
                  child: showSelectionPanel
                      ? LibrarySelectionPanel(
                          key: const ValueKey('folder-selection-panel'),
                          selectedSongs: selectedSongs,
                          allSongs: widget.folder.allSongs,
                          onToggleSelectAll: () {
                            final isAllSelected =
                                selectedSongs.length == widget.folder.allSongs.length &&
                                widget.folder.allSongs.isNotEmpty;
                            if (isAllSelected) {
                              widget.onClearAllSelection();
                            } else {
                              widget.onSelectAllVisible();
                            }
                          },
                          onCancel: widget.onClearAllSelection,
                          onOpenLocation: (widget.selectedFolderPaths.length == 1 &&
                                  widget.selectedSongPaths.isEmpty)
                              ? () => openFolderLocation(widget.selectedFolderPaths.first)
                              : null,
                          openLocationLabel: (widget.selectedFolderPaths.length == 1 &&
                                  widget.selectedSongPaths.isEmpty)
                              ? l10n.openFolderLocation
                              : null,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('folder-selection-panel-hidden'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(MusicFolder current, ScannerService scanner) {
    final theme = Theme.of(context);
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final settings = ref.watch(settingsServiceProvider);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    List<Widget> breadcrumbItems = [];

    // Back Button
    breadcrumbItems.add(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onGoBack,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );

    breadcrumbItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );

    // Home Button
    breadcrumbItems.add(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            scanner.setNavigationState(null, []);
            widget.onClearAllSelection();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            child: Icon(
              Icons.home_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );

    for (int i = 0; i < scanner.navigationHistory.length; i++) {
      final folder = scanner.navigationHistory[i];
      breadcrumbItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      );
      breadcrumbItems.add(
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              scanner.setNavigationState(
                folder,
                scanner.navigationHistory.take(i).toList(),
              );
              widget.onClearAllSelection();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: Text(
                folder.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      );
    }

    breadcrumbItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(
          Icons.chevron_right_rounded,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
    breadcrumbItems.add(
      Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        child: Text(
          current.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: breadcrumbItems),
            ),
          ),
          const SizedBox(width: 8),
          if (currentMusic != null) ...[
            IconButton(
              icon: const Icon(Icons.my_location_rounded),
              onPressed: widget.onLocateCurrentSong,
              tooltip: AppLocalizations.of(context)!.locateCurrentSong,
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(
              settings.folderViewMode == FolderViewMode.grid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
            ),
            onPressed: () {
              settings.folderViewMode = settings.folderViewMode == FolderViewMode.grid
                  ? FolderViewMode.list
                  : FolderViewMode.grid;
            },
            tooltip: settings.folderViewMode == FolderViewMode.grid
                ? (isZh ? '列表视图' : 'List View')
                : (isZh ? '网格视图' : 'Grid View'),
          ),
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortDialog(context, scanner),
            tooltip: AppLocalizations.of(context)!.sort,
          ),
        ],
      ),
    );
  }

  void _showSortDialog(BuildContext context, ScannerService scanner) {
    final currentFolder = widget.folder;
    final currentFolderPath = currentFolder.path;
    final globalSettings = scanner.getGlobalSortSettings();
    final currentFolderSettings = scanner.getSortSettingsForFolder(currentFolderPath);
    final initialScope = scanner.hasSortOverrideForFolder(currentFolderPath)
        ? SortScope.currentFolder
        : SortScope.global;
    var selectedScope = initialScope;
    var selectedCriteria = initialScope == SortScope.currentFolder
        ? currentFolderSettings.criteria
        : globalSettings.criteria;
    var selectedOrder = initialScope == SortScope.currentFolder
        ? currentFolderSettings.order
        : globalSettings.order;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void syncSelectionForScope(SortScope scope) {
              final settings =
                  scope == SortScope.currentFolder
                  ? scanner.getSortSettingsForFolder(currentFolderPath)
                  : scanner.getGlobalSortSettings();
              selectedCriteria = settings.criteria;
              selectedOrder = settings.order;
            }

            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.sortBy),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.sortScope,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortScope>(
                    onChanged: (v) {
                      if (v == null || v == selectedScope) return;
                      setState(() {
                        selectedScope = v;
                        syncSelectionForScope(v);
                      });
                    },
                    groupValue: selectedScope,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.currentFolderScope,
                          ),
                          leading: const Radio(
                            value: SortScope.currentFolder,
                          ),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.globalScope,
                          ),
                          leading: const Radio(value: SortScope.global),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.sortBy,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortCriteria>(
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        selectedCriteria = v;
                      });
                      scanner.setSortCriteria(
                        v,
                        scope: selectedScope,
                        folderPath: currentFolder.path,
                      );
                    },
                    groupValue: selectedCriteria,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.title),
                          leading: const Radio(value: SortCriteria.title),
                        ),
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.fileName),
                          leading: const Radio(value: SortCriteria.filename),
                        ),
                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.trackNumber,
                          ),
                          leading: const Radio(value: SortCriteria.trackNumber),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.sortOrder,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<SortOrder>(
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        selectedOrder = v;
                      });
                      scanner.setSortOrder(
                        v,
                        scope: selectedScope,
                        folderPath: currentFolder.path,
                      );
                    },
                    groupValue: selectedOrder,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.ascending),
                          leading: const Radio(value: SortOrder.ascending),
                        ),
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.descending),
                          leading: const Radio(value: SortOrder.descending),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.confirm),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFolderHeaderBanner({
    required BuildContext context,
    required MusicFolder folder,
    required MusicFile? representativeSong,
    required int songsCount,
    required String displayPath,
    required VoidCallback onPlayAll,
    required VoidCallback onShuffle,
  }) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final int hash = folder.path.hashCode;
    final double hue = (hash.abs() % 360).toDouble();
    final Color startColor = HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
    final Color endColor = HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.75, 0.35).toColor();

    Widget coverWidget;
    if (representativeSong != null) {
      coverWidget = SongThumbnail(
        path: representativeSong.path,
        id: representativeSong.id,
        size: 100,
        width: 100,
        height: 100,
      );
    } else {
      coverWidget = Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
        ),
        child: const Center(
          child: Icon(Icons.folder_rounded, size: 40, color: Colors.white70),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.5),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Hero(
                tag: 'folder-cover-${folder.path}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: coverWidget,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isZh ? '$songsCount 首歌曲' : '$songsCount songs',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSearching
                ? Row(
                    key: const ValueKey('search-active-row'),
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: theme.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: isZh ? '在当前目录及子目录下搜索...' : 'Search in folder and subfolders...',
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 20),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _isSearching = false;
                            _searchQuery = '';
                          });
                        },
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('actions-normal-row'),
                    children: [
                      FilledButton.icon(
                        onPressed: onPlayAll,
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: Text(isZh ? '播放全部' : 'Play All'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: onShuffle,
                        icon: const Icon(Icons.shuffle_rounded, size: 16),
                        label: Text(isZh ? '随机播放' : 'Shuffle'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isSearching = true;
                          });
                        },
                        icon: const Icon(Icons.search_rounded, size: 16),
                        tooltip: isZh ? '搜索' : 'Search',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}



// Folder Grid Card
class _FolderGridCard extends StatelessWidget {
  const _FolderGridCard({
    required this.folder,
    required this.songsCount,
    this.representativeSong,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  final MusicFolder folder;
  final int songsCount;
  final MusicFile? representativeSong;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    final int hash = folder.path.hashCode;
    final double hue = (hash.abs() % 360).toDouble();
    final Color startColor = HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
    final Color endColor = HSLColor.fromAHSL(1.0, (hue + 40) % 360, 0.75, 0.35).toColor();

    Widget coverWidget;
    if (representativeSong != null) {
      coverWidget = SongThumbnail(
        path: representativeSong!.path,
        id: representativeSong!.id,
        size: 200,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      coverWidget = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.folder_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      );
    }

    return GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown,
      onLongPress: onLongPress,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Hero(
                    tag: 'folder-cover-${folder.path}',
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          coverWidget,
                          if (isSelectionMode)
                            Container(
                              color: isSelected
                                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                                  : Colors.black26,
                            ),
                          if (isSelectionMode)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                                color: isSelected ? theme.colorScheme.primary : Colors.white70,
                                size: 24,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isZh ? '$songsCount 首歌曲' : '$songsCount songs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
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
    );
  }
}

// Hoverable wrapper for grid cards
class _HoverableCard extends StatefulWidget {
  const _HoverableCard({required this.child});
  final Widget child;
  @override
  State<_HoverableCard> createState() => _HoverableCardState();
}

class _HoverableCardState extends State<_HoverableCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
