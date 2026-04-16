import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import '../player/audio_riverpod.dart';
import '../player/scanner_service.dart';
import '../utils/song_context_menu_utils.dart';
import '../widgets/song_thumbnail.dart';

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
  bool _isRootSelectionMode = false;
  final Set<String> _selectedRootPaths = {};
  StreamSubscription<ScanProgress>? _scanProgressSubscription;
  ToastFuture? _scanToast;
  bool _wasScanning = false;
  Timer? _scanToastUpdateTimer;
  ScanProgress? _pendingScanProgress;
  DateTime? _lastScanToastUpdateAt;
  AppLocalizations? _l10n;
  ScannerService? _scanner;
  final ValueNotifier<_ScanToastState?> _scanToastState =
      ValueNotifier<_ScanToastState?>(null);

  void _navigateTo(MusicFolder folder, ScannerService scanner) {
    final history = List<MusicFolder>.from(scanner.navigationHistory);
    if (scanner.navigationCurrentFolder != null) {
      history.add(scanner.navigationCurrentFolder!);
    }
    scanner.setNavigationState(folder, history);
    _clearAllSelection();
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
    _scrollToTop();
  }

  void _goHome(ScannerService scanner) {
    scanner.setNavigationState(null, []);
    _clearAllSelection();
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
  }

  void _toggleRootSelectionMode() {
    setState(() {
      _isRootSelectionMode = !_isRootSelectionMode;
      if (!_isRootSelectionMode) {
        _selectedRootPaths.clear();
      }
    });
  }

  void _clearAllSelection() {
    final shouldClearSongSelection =
        _isSelectionMode || _selectedSongPaths.isNotEmpty;
    final shouldClearRootSelection =
        _isRootSelectionMode || _selectedRootPaths.isNotEmpty;
    if (!shouldClearSongSelection && !shouldClearRootSelection) return;

    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
      _isRootSelectionMode = false;
      _selectedRootPaths.clear();
    });
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
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final paths = _selectedRootPaths.toList(growable: false);
    await scanner.removeRootPaths(paths);
    if (!mounted) return;

    setState(() {
      _selectedRootPaths.clear();
      _isRootSelectionMode = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isZh ? '已删除 $selectedCount 个目录' : '$selectedCount folders deleted',
        ),
      ),
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
    _wasScanning = _scanner!.isScanning;
    _scanner!.addListener(_handleScannerChanged);
    _scanProgressSubscription = _scanner!.scanProgressStream.listen(
      _showScanProgressToast,
    );
  }

  @override
  void dispose() {
    _scanToastUpdateTimer?.cancel();
    _scanProgressSubscription?.cancel();
    _scanner?.removeListener(_handleScannerChanged);
    _dismissScanToast(notifyListeners: false);
    _scanToastState.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      if (!mounted) return;

      final hasMusic = await scanner.addRootPath(selectedDirectory);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasMusic
                ? AppLocalizations.of(context)!.directoryAddedSuccess
                : AppLocalizations.of(context)!.directoryAddedNoMusic,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerServiceProvider);
    final audio = ref.read(audioServiceProvider);

    // Sync _currentFolder if it's the system root and data has been loaded
    if (scanner.navigationCurrentFolder?.path == 'system' &&
        scanner.systemMediaFolder != null &&
        scanner.navigationCurrentFolder != scanner.systemMediaFolder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          scanner.setNavigationState(
            scanner.systemMediaFolder,
            List.from(scanner.navigationHistory),
          );
        }
      });
    }

    final currentFolder = scanner.navigationCurrentFolder;

    Widget currentBody;
    if (currentFolder == null) {
      final isZh = Localizations.localeOf(context).languageCode == 'zh';
      final selectionLabel = isZh
          ? '已选中 ${_selectedRootPaths.length} 个目录'
          : '${_selectedRootPaths.length} folders selected';
      final rootListBottomPadding = _isRootSelectionMode ? 224.0 : 160.0;
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
              if (!Platform.isWindows)
                ListTile(
                  leading: const Icon(
                    Icons.library_music,
                    color: Colors.purple,
                  ),
                  title: Text(AppLocalizations.of(context)!.systemMediaLibrary),
                  subtitle: scanner.hasPermission
                      ? null
                      : Text(
                          AppLocalizations.of(context)!.needPermissionToScan,
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                  onTap: () {
                    _navigateTo(
                      scanner.systemMediaFolder ??
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
                  padding: EdgeInsets.only(bottom: rootListBottomPadding),
                  itemCount: scanner.rootFolders.length,
                  onReorder: (oldIndex, newIndex) {
                    if (!_isRootSelectionMode) return;
                    if (newIndex > oldIndex) newIndex--;
                    unawaited(scanner.moveRootPath(oldIndex, newIndex));
                  },
                  itemBuilder: (context, index) {
                    final folder = scanner.rootFolders[index];
                    final isShortcut = scanner.isShortcutRoot(folder.path);
                    final isSelected = _selectedRootPaths.contains(folder.path);
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
                        if (!_isRootSelectionMode) {
                          setState(() {
                            _isRootSelectionMode = true;
                            _selectedRootPaths.add(folder.path);
                          });
                        } else {
                          _toggleRootSelection(folder.path);
                        }
                      },
                      child: ListTile(
                        selected: _isRootSelectionMode && isSelected,
                        selectedTileColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
                        leading: _isRootSelectionMode
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (_) =>
                                    _toggleRootSelection(folder.path),
                              )
                            : Icon(
                                isShortcut
                                    ? Icons.shortcut
                                    : Icons.folder_shared,
                                color: isShortcut ? Colors.blue : Colors.amber,
                              ),
                        title: Text(folder.name),
                        subtitle: Text(folder.path),
                        onTap: _isRootSelectionMode
                            ? () => _toggleRootSelection(folder.path)
                            : () => _navigateTo(folder, scanner),
                        trailing: _isRootSelectionMode
                            ? ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isRootSelectionMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
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
                                : () => _deleteSelectedRootFolders(scanner),
                            icon: const Icon(Icons.delete),
                            label: Text(AppLocalizations.of(context)!.delete),
                          ),
                          TextButton(
                            onPressed: _toggleRootSelectionMode,
                            child: Text(AppLocalizations.of(context)!.cancel),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    } else {
      currentBody = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (scanner.navigationHistory.isNotEmpty ||
              scanner.navigationCurrentFolder != null) {
            _goBack(scanner);
          }
        },
        child: Column(
          children: [
            if (Platform.isWindows) const SizedBox(height: 32),
            _buildBreadcrumbs(currentFolder, scanner),
            if (_isSelectionMode)
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
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 160),
                children: [
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: Text(AppLocalizations.of(context)!.goBack),
                    onTap: () => _goBack(scanner),
                  ),

                  // Show Permission Button if in system folder and no permission
                  if (currentFolder.path == 'system' && !scanner.hasPermission)
                    Padding(
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
                    ),

                  ...currentFolder.subFolders.map(
                    (folder) => GestureDetector(
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
                      child: ListTile(
                        leading: const Icon(Icons.folder, color: Colors.amber),
                        title: Text(folder.name),
                        onTap: () => _navigateTo(folder, scanner),
                      ),
                    ),
                  ),
                  ...currentFolder.files.map(
                    (file) => GestureDetector(
                      key: ValueKey(file.path),
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapDown: (details) {
                        final songsToAdd = _selectedSongPaths.isNotEmpty
                            ? _selectedSongsFromFolder(currentFolder.files)
                            : <MusicFile>[file];
                        unawaited(
                          showSongContextMenu(
                            context,
                            details.globalPosition,
                            song: file,
                            mode: SongContextMenuMode.full,
                            onAddToPlaylist: () => showAddSongsToPlaylistDialog(
                              context,
                              ref.read(playlistServiceProvider),
                              songsToAdd,
                            ),
                          ),
                        );
                      },
                      child: ListTile(
                        leading: SizedBox(
                          width: 40,
                          height: 40,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: _isSelectionMode
                                    ? (_selectedSongPaths.contains(file.path)
                                          ? 0.5
                                          : 0.7)
                                    : 1.0,
                                child: SongThumbnail(
                                  path: file.path,
                                  id: file.id,
                                ),
                              ),
                              if (_isSelectionMode)
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: Checkbox(
                                        value: _selectedSongPaths.contains(
                                          file.path,
                                        ),
                                        onChanged: (_) =>
                                            _toggleSelection(file.path),
                                        fillColor: WidgetStateProperty.all(
                                          Colors.white,
                                        ),
                                        checkColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        title: Text(file.displayName),
                        subtitle: Text(
                          '${file.artist ?? AppLocalizations.of(context)!.unknownArtist} - ${file.album ?? AppLocalizations.of(context)!.unknownAlbum}',
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode();
                            _toggleSelection(file.path);
                          }
                        },
                        onTap: _isSelectionMode
                            ? () => _toggleSelection(file.path)
                            : () async {
                                final index = currentFolder.files.indexOf(file);
                                await audio.playPlaylist(
                                  currentFolder.files,
                                  initialIndex: index,
                                );
                                if (mounted) {
                                  await widget.onOpenPlayback?.call();
                                }
                              },
                      ),
                    ),
                  ),
                  if (_isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: _selectedSongPaths.isEmpty
                                ? null
                                : () {
                                    final selectedSongs =
                                        _selectedSongsFromFolder(
                                          currentFolder.files,
                                        );
                                    showAddSongsToPlaylistDialog(
                                      context,
                                      ref.read(playlistServiceProvider),
                                      selectedSongs,
                                    );
                                  },
                            icon: const Icon(Icons.playlist_add),
                            label: Text(
                              AppLocalizations.of(context)!.addToPlaylist,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _toggleSelectionMode,
                            child: Text(AppLocalizations.of(context)!.cancel),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (Platform.isWindows) {
      return Stack(
        children: [
          currentBody,
          Positioned(
            right: 24,
            bottom: 84, // 24 + 60 (NavigationBar height)
            child: FloatingActionButton(
              tooltip: AppLocalizations.of(context)!.rebuildTagDatabase,
              onPressed: () => _showRebuildDialog(context, scanner),
              child: scanner.isScanning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
        ],
      );
    }

    return SafeArea(bottom: true, child: currentBody);
  }

  void _showRebuildDialog(BuildContext context, ScannerService scanner) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.rebuildDatabase),
        content: Text(AppLocalizations.of(context)!.confirmRebuildDatabase),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              scanner.rebuildMetadataDatabase();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.rebuildingDatabase,
                    ),
                  ),
                );
              }
            },
            child: Text(AppLocalizations.of(context)!.confirm),
          ),
        ],
      ),
    );
  }

  void _showSortDialog(BuildContext context, ScannerService scanner) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.sortBy),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup(
                    onChanged: (v) {
                      if (v != null) {
                        scanner.setSortCriteria(v);
                        setState(() {});
                      }
                    },
                    groupValue: scanner.sortCriteria,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.title),
                          leading: Radio(value: SortCriteria.title),
                        ),
                        ListTile(
                          title: Text(AppLocalizations.of(context)!.fileName),
                          leading: Radio(value: SortCriteria.filename),
                        ),

                        ListTile(
                          title: Text(
                            AppLocalizations.of(context)!.trackNumber,
                          ),
                          leading: Radio(value: SortCriteria.trackNumber),
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
      InkWell(
        onTap: () {
          _goHome(scanner);
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Icon(Icons.home_outlined, size: 24),
        ),
      ),
    );

    // 历史路径段
    for (int i = 0; i < scanner.navigationHistory.length; i++) {
      final folder = scanner.navigationHistory[i];
      breadcrumbItems.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.chevron_right,
            size: 20,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      );
      breadcrumbItems.add(
        InkWell(
          onTap: () {
            scanner.setNavigationState(
              folder,
              scanner.navigationHistory.take(i).toList(),
            );
            _scrollToTop();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Text(folder.name, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );
    }

    // 当前路径段
    breadcrumbItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          Icons.chevron_right,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
    breadcrumbItems.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Text(
          current.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            constraints: const BoxConstraints(maxWidth: 360),
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
                Expanded(
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
