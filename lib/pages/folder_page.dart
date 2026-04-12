import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
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

  void _navigateTo(MusicFolder folder, ScannerService scanner) {
    final history = List<MusicFolder>.from(scanner.navigationHistory);
    if (scanner.navigationCurrentFolder != null) {
      history.add(scanner.navigationCurrentFolder!);
    }
    scanner.setNavigationState(folder, history);
    _clearSelection();
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
    _clearSelection();
    _scrollToTop();
  }

  void _goHome(ScannerService scanner) {
    scanner.setNavigationState(null, []);
    _clearSelection();
    _scrollToTop();
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  void _clearSelection() {
    if (!_isSelectionMode && _selectedSongPaths.isEmpty) return;
    setState(() {
      _isSelectionMode = false;
      _selectedSongPaths.clear();
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

  List<MusicFile> _selectedSongsFromFolder(List<MusicFile> files) {
    return files
        .where((file) => _selectedSongPaths.contains(file.path))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.scanningDirectory),
        ),
      );

      final hasMusic = await scanner.addRootPath(selectedDirectory);

      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
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
      currentBody = Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.scanDirectory,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 160),
              children: [
                // System Media Library Item
                if (!Platform.isWindows)
                  ListTile(
                    leading: const Icon(
                      Icons.library_music,
                      color: Colors.purple,
                    ),
                    title: Text(
                      AppLocalizations.of(context)!.systemMediaLibrary,
                    ),
                    subtitle: scanner.hasPermission
                        ? null
                        : Text(
                            AppLocalizations.of(context)!.needPermissionToScan,
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                    onTap: () {
                      // Navigate to a virtual folder or the real system folder
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

                // Add Root Directory Item
                ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.blue,
                  ),
                  title: Text(AppLocalizations.of(context)!.addRootDirectory),
                  onTap: () => _pickFolder(scanner),
                ),

                // User Added Root Folders
                ...scanner.rootFolders.map(
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
                      leading: const Icon(
                        Icons.folder_shared,
                        color: Colors.amber,
                      ),
                      title: Text(folder.name),
                      subtitle: Text(
                        folder.path,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () => _navigateTo(folder, scanner),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => scanner.removeRootPath(folder.path),
                      ),
                    ),
                  ),
                ),
              ],
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
