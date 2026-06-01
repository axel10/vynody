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
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/models/music_folder.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/player/scanner/scanner_sorting.dart';
import 'package:vibe_flow/player/scanner/scanner_service.dart';
import 'folder_page_riverpod.dart';
import 'package:vibe_flow/utils/song_context_menu_utils.dart';
import '../widgets/song_tile.dart';
import 'package:vibe_flow/utils/app_snack_bar.dart';

// 目录页
class FoldersPage extends ConsumerStatefulWidget {
  final Future<void> Function()? onOpenPlayback;

  const FoldersPage({super.key, this.onOpenPlayback});

  @override
  ConsumerState<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends ConsumerState<FoldersPage> {
  final ScrollController _scrollController = ScrollController();
  bool _isSelectionMode = false;
  final Set<String> _selectedSongPaths = {};
  final Set<String> _selectedRootPaths = {};
  late final FolderSelectionModeController _folderSelectionModeController;
  late final FolderRootSelectionModeController _folderRootSelectionModeController;
  StreamSubscription<ScanProgress>? _scanProgressSubscription;
  ToastFuture? _scanToast;
  bool _wasScanning = false;
  Timer? _scanToastUpdateTimer;
  Timer? _scanToastAutoDismissTimer;
  ScanProgress? _pendingScanProgress;
  DateTime? _lastScanToastUpdateAt;
  AppLocalizations? _l10n;
  ScannerService? _scanner;
  final ValueNotifier<_ScanToastState?> _scanToastState =
      ValueNotifier<_ScanToastState?>(null);

  void _setFolderSelectionMode(bool enabled) {
    _folderSelectionModeController.setEnabled(enabled);
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
    _scrollToTop();
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
    _scrollToTop();
  }

  void _goHome(ScannerService scanner) {
    scanner.setNavigationState(null, []);
    _clearAllSelection();
    _setFolderSelectionMode(false);
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedSongPaths.clear();
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
    final enabled = !ref.read(folderRootSelectionModeProvider);
    ref.read(folderRootSelectionModeProvider.notifier).setEnabled(enabled);
    if (!enabled) {
      setState(() {
        _selectedRootPaths.clear();
      });
    }
  }

  void _clearAllSelection() {
    final shouldClearSongSelection =
        _isSelectionMode || _selectedSongPaths.isNotEmpty;
    final isRootSelectionMode = ref.read(folderRootSelectionModeProvider);
    final shouldClearRootSelection =
        isRootSelectionMode || _selectedRootPaths.isNotEmpty;
    if (!shouldClearSongSelection && !shouldClearRootSelection) return;

    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
      _selectedRootPaths.clear();
    });
    _setFolderSelectionMode(false);
    ref.read(folderRootSelectionModeProvider.notifier).setEnabled(false);
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

  void _selectAllVisibleSongs(List<MusicFile> files) {
    setState(() {
      _selectedSongPaths
        ..clear()
        ..addAll(files.map((file) => file.path));
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

  Future<void> _addSelectedSongsToQueue(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    await ref.read(audioServiceProvider).appendToQueue(songs);
    if (!mounted) return;

    AppSnackBar.show(
      context,
      ref,
      SnackBar(content: Text(AppLocalizations.of(context)!.addedToQueue)),
    );
    _clearAllSelection();
  }

  Future<void> _addSelectedSongsToPlaylist(List<MusicFile> songs) async {
    if (songs.isEmpty) return;

    await showAddSongsToPlaylistDialog(
      context,
      ref.read(playlistServiceProvider),
      songs,
    );
    if (!mounted) return;

    _clearAllSelection();
  }

  Widget _buildSelectionActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color ?? theme.colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
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
    ref.read(folderRootSelectionModeProvider.notifier).setEnabled(false);

    AppSnackBar.show(
      context,
      ref,
      SnackBar(content: Text(l10n.foldersDeleted(selectedCount))),
    );
  }

  List<MusicFile> _selectedSongsFromFolder(List<MusicFile> files) {
    return files
        .where((file) => _selectedSongPaths.contains(file.path))
        .toList(growable: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _l10n = AppLocalizations.of(context);
  }

  @override
  void initState() {
    super.initState();
    _scanner = ref.read(scannerServiceProvider);
    _folderSelectionModeController = ref.read(
      folderSelectionModeProvider.notifier,
    );
    _folderRootSelectionModeController = ref.read(
      folderRootSelectionModeProvider.notifier,
    );
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
      _setFolderSelectionMode(false);
      _folderRootSelectionModeController.setEnabled(false);
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
    final isRootSelectionMode = ref.watch(folderRootSelectionModeProvider);
    final rootFolders = ref.watch(
      scannerServiceProvider.select((scanner) => scanner.rootFolders),
    );
    final currentFolder = ref.watch(
      scannerServiceProvider.select(
        (scanner) => scanner.navigationCurrentFolder,
      ),
    );
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

    Widget currentBody;
    if (currentFolder == null) {
      final l10n = AppLocalizations.of(context)!;
      final selectionLabel = l10n.selectedFolders(_selectedRootPaths.length);
      final rootListBottomPadding = isRootSelectionMode ? 224.0 : 160.0;
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
                      icon: const Icon(Icons.sort),
                      onPressed: () => _showSortDialog(context, scanner),
                      tooltip: AppLocalizations.of(context)!.sort,
                    ),
                  ],
                ),
              ),
              if (Platform.isAndroid)
                ListTile(
                  leading: const Icon(
                    Icons.library_music,
                    color: Colors.purple,
                  ),
                  title: Text(AppLocalizations.of(context)!.systemMediaLibrary),
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
              ListTile(
                leading: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.blue,
                ),
                title: Text(AppLocalizations.of(context)!.addRootDirectory),
                onTap: () => _pickFolder(scanner),
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
                          showFolderContextMenu(
                            context,
                            details.globalPosition,
                            folderPath: folder.path,
                          ),
                        );
                      },
                      onLongPress: () {
                        if (!isRootSelectionMode) {
                          ref
                              .read(folderRootSelectionModeProvider.notifier)
                              .setEnabled(true);
                          setState(() {
                            _selectedRootPaths.add(folder.path);
                          });
                        } else {
                          _toggleRootSelection(folder.path);
                        }
                      },
                      child: AnimatedOpacity(
                        opacity: isRootAvailable ? 1.0 : 0.45,
                        duration: const Duration(milliseconds: 180),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
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
                            subtitle: Text(folder.path),
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
                  ? Material(
                      key: const ValueKey('root-selection-bar'),
                      elevation: 8,
                      child: Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Text(selectionLabel),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: _selectedRootPaths.isEmpty
                                      ? null
                                      : () =>
                                            _deleteSelectedRootFolders(scanner),
                                  icon: const Icon(Icons.delete),
                                  label: Text(
                                    AppLocalizations.of(context)!.delete,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _toggleRootSelectionMode,
                                  child: Text(
                                    AppLocalizations.of(context)!.cancel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('root-selection-none')),
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
      final selectionPanelHeight = showSelectionPanel ? 152.0 : 0.0;
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
                      )!.selectedSongs(_selectedSongPaths.length),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
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
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) {
                        unawaited(
                          showFolderContextMenu(
                            context,
                            details.globalPosition,
                            folderPath: folder.path,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
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
                            Icons.folder_rounded,
                            color: Colors.amber,
                          ),
                          title: Text(folder.name),
                          onTap: () => _navigateTo(folder, scanner),
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
                    final songsToAdd = _selectedSongPaths.isNotEmpty
                        ? _selectedSongsFromFolder(currentFolder.files)
                        : <MusicFile>[file];

                    void handleShowMenu(BuildContext menuContext, Offset position) {
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
                        onPlayNext: () => ref.read(audioServiceProvider).enqueueNext(songsToAdd),
                        onAddToQueue: () => ref.read(audioServiceProvider).appendToQueue(songsToAdd),
                      );
                    }

                    return GestureDetector(
                      key: ValueKey(file.path),
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) {
                        handleShowMenu(context, details.globalPosition);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
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
                            final renderObject = buttonContext.findRenderObject();
                            final renderBox = renderObject is RenderBox ? renderObject : null;
                            if (renderBox == null) return;
                            final Offset offset = renderBox.localToGlobal(Offset.zero);
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
          ? _selectedSongsFromFolder(currentFolder.files)
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
                  ? Padding(
                      key: const ValueKey('folder-selection-panel'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SafeArea(
                        top: false,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 680),
                            child: Material(
                              elevation: 16,
                              color: Theme.of(context).colorScheme.surface,
                              shadowColor: Colors.black26,
                              borderRadius: BorderRadius.circular(24),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  14,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.selectedSongs(selectedSongs.length),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        _buildSelectionActionButton(
                                          icon: Icons.select_all,
                                          label: AppLocalizations.of(
                                            context,
                                          )!.selectAll,
                                          onPressed: currentFolder.files.isEmpty
                                              ? null
                                              : () => _selectAllVisibleSongs(
                                                  currentFolder.files,
                                                ),
                                        ),
                                        _buildSelectionActionButton(
                                          icon: Icons.queue_music_outlined,
                                          label: AppLocalizations.of(
                                            context,
                                          )!.addToQueue,
                                          onPressed: selectedSongs.isEmpty
                                              ? null
                                              : () => _addSelectedSongsToQueue(
                                                  selectedSongs,
                                                ),
                                        ),
                                        _buildSelectionActionButton(
                                          icon: Icons.playlist_add,
                                          label: AppLocalizations.of(
                                            context,
                                          )!.addToPlaylist,
                                          onPressed: selectedSongs.isEmpty
                                              ? null
                                              : () =>
                                                    _addSelectedSongsToPlaylist(
                                                      selectedSongs,
                                                    ),
                                        ),
                                        _buildSelectionActionButton(
                                          icon: Icons.close,
                                          label: AppLocalizations.of(
                                            context,
                                          )!.cancel,
                                          onPressed: _toggleSelectionMode,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
              _scrollToTop();
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
