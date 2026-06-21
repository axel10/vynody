import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:vynody/utils/app_snack_bar.dart';
import '../dialogs/transcode_dialog.dart';

// 目录页
class FoldersPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onOpenPlayback;

  const FoldersPage({super.key, this.onOpenPlayback});

  @override
  ConsumerState<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends ConsumerState<FoldersPage> {
  final ScrollController _scrollController = ScrollController();
  String? _lastFolderPath = 'sentinel_initial_path';
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

  void _goHome(ScannerService scanner) {
    scanner.setNavigationState(null, []);
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

  List<MusicFile> _getSelectedSongs(MusicFolder currentFolder) {
    final songs = <MusicFile>[];
    songs.addAll(
      currentFolder.files.where(
        (file) => _selectedSongPaths.contains(file.path),
      ),
    );
    for (final folder in currentFolder.subFolders) {
      if (_selectedFolderPaths.contains(folder.path)) {
        songs.addAll(folder.allSongs);
      }
    }
    final seen = <String>{};
    return songs.where((song) => seen.add(song.path)).toList(growable: false);
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
    if (_scrollController.hasClients &&
        _lastFolderPath != 'sentinel_initial_path') {
      final scanner = ref.read(scannerServiceProvider);
      scanner.setFolderScrollOffset(_lastFolderPath, _scrollController.offset);
    }
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
    _scanProgressSubscription?.cancel();
    _scanner?.removeListener(_handleScannerChanged);
    _dismissScanToast(notifyListeners: false);
    _scanToastState.dispose();
    _scrollController.dispose();
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

    final selectedDirectory = await _getDirectoryPath();
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

  @override
  Widget build(BuildContext context) {
    final scanner = ref.read(scannerServiceProvider);
    final l10n = AppLocalizations.of(context)!;
    Widget currentBody;
    final isRootSelectionMode =
        ref.watch(librarySelectionScopeProvider) ==
        LibrarySelectionScope.folderRoot;
    final rootFolders = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.rootFolders),
    );
    final currentFolder = ref.watch(
      scannerServiceProvider.select(
        (scanner) => scanner.navigationCurrentFolder,
      ),
    );

    // Save and restore scroll position when current folder changes
    final currentFolderPath = currentFolder?.path;
    if (currentFolderPath != _lastFolderPath) {
      if (_scrollController.hasClients &&
          _lastFolderPath != 'sentinel_initial_path') {
        final oldOffset = _scrollController.offset;
        scanner.setFolderScrollOffset(_lastFolderPath, oldOffset);
      }
      _lastFolderPath = currentFolderPath;

      final targetPath = currentFolderPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final currentScanner = ref.read(scannerServiceProvider);
        if (currentScanner.navigationCurrentFolder?.path != targetPath) {
          return;
        }
        if (_scrollController.hasClients) {
          final targetOffset = currentScanner.getFolderScrollOffset(targetPath);
          final maxExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(targetOffset.clamp(0.0, maxExtent));
        }
      });
    }

    final navigationHistory = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.navigationHistory),
    );
    final systemMediaFolder = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.systemMediaFolder),
    );
    final hasPermission = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.hasPermission),
    );
    final audio = ref.read(audioServiceProvider);
    final currentMusic = ref.watch(audioCurrentMusicProvider);

    // Sync _currentFolder if it's the system root and data has been loaded.
    if (Platform.isAndroid &&
        currentFolder?.path == 'system' &&
        systemMediaFolder != null &&
        currentFolder != systemMediaFolder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          scanner.setNavigationState(
            systemMediaFolder,
            List.from(navigationHistory),
          );
        }
      });
    }

    if (currentFolder == null) {
      final selectionLabel = l10n.selectedFolders(_selectedRootPaths.length);
      final rootListBottomPadding = isRootSelectionMode ? 224.0 : 160.0;
      final selectedRootSongs = <MusicFile>[];
      final seenSelected = <String>{};
      for (final folder in rootFolders) {
        if (_selectedRootPaths.contains(folder.path)) {
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
      currentBody = Stack(
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.sort,
                        color: isRootSelectionMode
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: _toggleRootSelectionMode,
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
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                    onTap: () {
                      _navigateTo(
                        systemMediaFolder ??
                            MusicFolder(
                              path: 'system',
                              name: AppLocalizations.of(
                                context,
                              )!.systemMediaLibrary,
                            ),
                        scanner,
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
                  onTap: () => _pickFolder(scanner),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  scrollController: _scrollController,
                  cacheExtent: 1000,
                  padding: EdgeInsets.only(bottom: rootListBottomPadding),
                  itemCount: rootFolders.length,
                  onReorder: (oldIndex, newIndex) {
                    if (!isRootSelectionMode) return;
                    if (newIndex > oldIndex) newIndex--;
                    unawaited(scanner.moveRootPath(oldIndex, newIndex));
                  },
                  itemBuilder: (context, index) {
                    final folder = rootFolders[index];
                    final isSelected = _selectedRootPaths.contains(folder.path);
                    final isRootAvailable = scanner.isRootPathAvailable(
                      folder.path,
                    );
                    return GestureDetector(
                      key: ValueKey(folder.path),
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) {
                        unawaited(
                          _showFolderBottomSheet(context, folder, isRoot: true),
                        );
                      },
                      onLongPress: () {
                        if (!isRootSelectionMode) {
                          unawaited(
                            _showFolderBottomSheet(
                              context,
                              folder,
                              isRoot: true,
                            ),
                          );
                        } else {
                          _toggleRootSelection(folder.path);
                        }
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
                            selected: isRootSelectionMode && isSelected,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.45),
                            leading: isRootSelectionMode
                                ? Checkbox(
                                    value: isSelected,
                                    onChanged: (_) =>
                                        _toggleRootSelection(folder.path),
                                  )
                                : const Icon(
                                    Icons.folder_shared,
                                    color: Colors.amber,
                                  ),
                            title: Text(folder.name),
                            subtitle: Text(
                              ScannerPathUtils.cleanDisplayPath(folder.path),
                            ),
                            onTap: isRootSelectionMode
                                ? () => _toggleRootSelection(folder.path)
                                : (isRootAvailable
                                      ? () => _navigateTo(folder, scanner)
                                      : null),
                            trailing: isRootSelectionMode
                                ? ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(Icons.drag_handle),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
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
                            _selectedRootPaths.length == rootFolders.length;
                        if (isAllSelected) {
                          setState(() {
                            _selectedRootPaths.clear();
                          });
                        } else {
                          setState(() {
                            _selectedRootPaths
                              ..clear()
                              ..addAll(rootFolders.map((f) => f.path));
                          });
                        }
                      },
                      onCancel: _toggleRootSelectionMode,
                      onDelete: _selectedRootPaths.isEmpty
                          ? null
                          : () => _deleteSelectedRootFolders(scanner),
                      deleteLabel: l10n.delete,
                      onOpenLocation: _selectedRootPaths.length == 1
                          ? () => openFolderLocation(_selectedRootPaths.first)
                          : null,
                      openLocationLabel: l10n.openFolderLocation,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('root-selection-panel-hidden'),
                    ),
            ),
          ),
        ],
      );
    } else {
      final showSelectionPanel =
          _isSelectionMode &&
          _isUserRootSelectionContext(
            scanner,
            currentFolder,
            navigationHistory,
          );
      final selectionPanelHeight = showSelectionPanel ? 220.0 : 0.0;
      currentBody = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _goBack(scanner);
        },
        child: Column(
          children: [
            _buildBreadcrumbs(currentFolder, scanner),
            if (_isSelectionMode && !showSelectionPanel)
              Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.selectedSongs(_getSelectedSongs(currentFolder).length),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _toggleSelectionMode,
                      child: Text(AppLocalizations.of(context)!.cancel),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                cacheExtent: 1000,
                padding: EdgeInsets.only(bottom: 160 + selectionPanelHeight),
                itemCount:
                    1 +
                    (currentFolder.path == 'system' && !hasPermission ? 1 : 0) +
                    currentFolder.subFolders.length +
                    currentFolder.files.length,
                itemBuilder: (context, index) {
                  var cursor = 0;

                  if (index == cursor) {
                    return Padding(
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
                        leading: const Icon(Icons.arrow_back_rounded),
                        title: Text(AppLocalizations.of(context)!.goBack),
                        onTap: () => _goBack(scanner),
                      ),
                    );
                  }
                  cursor++;

                  if (currentFolder.path == 'system' && !hasPermission) {
                    if (index == cursor) {
                      return Padding(
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
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.noMediaLibraryPermission,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () =>
                                    scanner.checkAndRequestPermissions(),
                                child: Text(
                                  AppLocalizations.of(context)!.grantPermission,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    cursor++;
                  }

                  final folderIndex = index - cursor;
                  if (folderIndex >= 0 &&
                      folderIndex < currentFolder.subFolders.length) {
                    final folder = currentFolder.subFolders[folderIndex];
                    final isSelected = _selectedFolderPaths.contains(
                      folder.path,
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) {
                        if (!_isSelectionMode) {
                          unawaited(
                            _showFolderBottomSheet(
                              context,
                              folder,
                              isRoot: false,
                            ),
                          );
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _toggleSelectionMode();
                          _toggleFolderSelection(folder.path);
                        } else {
                          _toggleFolderSelection(folder.path);
                        }
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
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          hoverColor: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.06),
                          selected: _isSelectionMode && isSelected,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.45),
                          leading: _isSelectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (_) =>
                                      _toggleFolderSelection(folder.path),
                                )
                              : const Icon(
                                  Icons.folder_rounded,
                                  color: Colors.amber,
                                ),
                          title: Text(folder.name),
                          onTap: _isSelectionMode
                              ? () => _toggleFolderSelection(folder.path)
                              : () => _navigateTo(folder, scanner),
                        ),
                      ),
                    );
                  }
                  cursor += currentFolder.subFolders.length;

                  final fileIndex = index - cursor;
                  if (fileIndex >= 0 &&
                      fileIndex < currentFolder.files.length) {
                    final file = currentFolder.files[fileIndex];
                    final isCurrent = currentMusic?.path == file.path;
                    final isSelected = _selectedSongPaths.contains(file.path);
                    final songsToAdd =
                        (_selectedSongPaths.isNotEmpty ||
                            _selectedFolderPaths.isNotEmpty)
                        ? _getSelectedSongs(currentFolder)
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
                          isSelectionMode: _isSelectionMode,
                          onTap: _isSelectionMode
                              ? () => _toggleSelection(file.path)
                              : () async {
                                  unawaited(() async {
                                    try {
                                      await audio.playPlaylist(
                                        currentFolder.files,
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
                                    _clearAllSelection();
                                    await widget.onOpenPlayback?.call();
                                  }
                                },
                          onLongPress: () {
                            if (!_isSelectionMode) {
                              _toggleSelectionMode();
                              _toggleSelection(file.path);
                            }
                          },
                          onSecondaryTapDown: (details) {
                            handleShowMenu(context, details.globalPosition);
                          },
                          onMorePressed: (buttonContext) {
                            final renderObject = buttonContext
                                .findRenderObject();
                            final renderBox = renderObject is RenderBox
                                ? renderObject
                                : null;
                            if (renderBox == null) return;
                            final Offset offset = renderBox.localToGlobal(
                              Offset.zero,
                            );
                            handleShowMenu(buttonContext, offset);
                          },
                        ),
                      ),
                    );
                  }
                  cursor += currentFolder.files.length;

                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      );

      final selectedSongs = showSelectionPanel
          ? _getSelectedSongs(currentFolder)
          : <MusicFile>[];
      currentBody = Stack(
        children: [
          currentBody,
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
                      allSongs: currentFolder.allSongs,
                      onToggleSelectAll: () {
                        final isAllSelected =
                            selectedSongs.length ==
                                currentFolder.allSongs.length &&
                            currentFolder.allSongs.isNotEmpty;
                        if (isAllSelected) {
                          setState(() {
                            _selectedSongPaths.clear();
                            _selectedFolderPaths.clear();
                          });
                        } else {
                          _selectAllVisible(currentFolder);
                        }
                      },
                      onCancel: _clearAllSelection,
                      onOpenLocation:
                          (_selectedFolderPaths.length == 1 &&
                              _selectedSongPaths.isEmpty)
                          ? () => openFolderLocation(_selectedFolderPaths.first)
                          : null,
                      openLocationLabel:
                          (_selectedFolderPaths.length == 1 &&
                              _selectedSongPaths.isEmpty)
                          ? l10n.openFolderLocation
                          : null,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('folder-selection-panel-hidden'),
                    ),
            ),
          ),
        ],
      );
    }

    return SafeArea(bottom: true, child: currentBody);
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

  void _showSortDialog(BuildContext context, ScannerService scanner) {
    final currentFolder = scanner.navigationCurrentFolder;
    final currentFolderPath = currentFolder?.path ?? '';
    final hasCurrentFolder = currentFolder != null;
    final globalSettings = scanner.getGlobalSortSettings();
    final currentFolderSettings = hasCurrentFolder
        ? scanner.getSortSettingsForFolder(currentFolderPath)
        : globalSettings;
    final initialScope =
        hasCurrentFolder && scanner.hasSortOverrideForFolder(currentFolderPath)
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
                  scope == SortScope.currentFolder && hasCurrentFolder
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
                  if (hasCurrentFolder) ...[
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
                  ],
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
                        folderPath: currentFolder?.path,
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
                        folderPath: currentFolder?.path,
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

  Widget _buildBreadcrumbs(MusicFolder current, ScannerService scanner) {
    final theme = Theme.of(context);

    List<Widget> breadcrumbItems = [];

    // 首页/根目录图标
    breadcrumbItems.add(
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _goHome(scanner);
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

    // 历史路径段
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

    // 当前路径段
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
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortDialog(context, scanner),
            tooltip: AppLocalizations.of(context)!.sort,
          ),
        ],
      ),
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
