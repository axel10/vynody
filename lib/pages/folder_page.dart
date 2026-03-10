import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/music_folder.dart';
import '../player/scanner_service.dart';
import '../player/audio_service.dart';
import '../player/playlist_service.dart';
import '../widgets/song_thumbnail.dart';

// 目录页
class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  MusicFolder? _currentFolder;
  final List<MusicFolder> _history = [];

  void _navigateTo(MusicFolder folder) {
    if (_currentFolder != null) {
      _history.add(_currentFolder!);
    }
    setState(() {
      _currentFolder = folder;
    });
  }

  void _goBack() {
    if (_history.isNotEmpty) {
      setState(() {
        _currentFolder = _history.removeLast();
      });
    } else {
      setState(() {
        _currentFolder = null;
      });
    }
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      await scanner.addRootPath(selectedDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerService>();
    final audio = context.read<AudioService>();

    // Sync _currentFolder if it's the system root and data has been loaded
    if (_currentFolder?.path == 'system' &&
        scanner.systemMediaFolder != null &&
        _currentFolder != scanner.systemMediaFolder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentFolder = scanner.systemMediaFolder;
          });
        }
      });
    }

    Widget currentBody;
    if (_currentFolder == null) {
      currentBody = Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '扫描目录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.sort),
                  onPressed: () => _showSortDialog(context, scanner),
                  tooltip: '排序',
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: Platform.isWindows ? 84 : 0),
              children: [
                // System Media Library Item
                if (!Platform.isWindows)
                  ListTile(
                    leading: const Icon(
                      Icons.library_music,
                      color: Colors.purple,
                    ),
                    title: const Text('系统媒体库'),
                    subtitle: scanner.hasPermission
                        ? null
                        : const Text(
                            '需授予权限以扫描本地音乐',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
                    onTap: () {
                      // Navigate to a virtual folder or the real system folder
                      _navigateTo(
                        scanner.systemMediaFolder ??
                            MusicFolder(path: 'system', name: '系统媒体库'),
                      );
                    },
                  ),

                // Add Root Directory Item
                ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.blue,
                  ),
                  title: const Text('添加根目录'),
                  onTap: () => _pickFolder(scanner),
                ),

                // User Added Root Folders
                ...scanner.rootFolders.map(
                  (folder) => ListTile(
                    leading: const Icon(
                      Icons.folder_shared,
                      color: Colors.amber,
                    ),
                    title: Text(folder.name),
                    subtitle: Text(
                      folder.path,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () => _navigateTo(folder),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.red,
                      ),
                      onPressed: () => scanner.removeRootPath(folder.path),
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
          if (_history.isNotEmpty || _currentFolder != null) {
            _goBack();
          }
        },
        child: Column(
          children: [
            if (Platform.isWindows) const SizedBox(height: 32),
            _buildBreadcrumbs(_currentFolder!, scanner),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(bottom: Platform.isWindows ? 84 : 0),
                children: [
                  ListTile(
                    leading: const Icon(Icons.arrow_back),
                    title: const Text('返回上一层'),
                    onTap: _goBack,
                  ),

                  // Show Permission Button if in system folder and no permission
                  if (_currentFolder!.path == 'system' &&
                      !scanner.hasPermission)
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
                            const Text('未获得媒体库访问权限'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () =>
                                  scanner.checkAndRequestPermissions(),
                              child: const Text('给予权限'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  ..._currentFolder!.subFolders.map(
                    (folder) => ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(folder.name),
                      onTap: () => _navigateTo(folder),
                    ),
                  ),
                  ..._currentFolder!.files.map(
                    (file) => ListTile(
                      leading: SongThumbnail(path: file.path, id: file.id),
                      title: Text(file.name),
                      onTap: () async {
                        final pageController = context.read<PageController>();
                        final playlistService = context.read<PlaylistService>();

                        if (Platform.isAndroid) {
                          final index = _currentFolder!.files.indexOf(file);
                          audio.playPlaylist(
                            _currentFolder!.files,
                            initialIndex: index,
                          );

                          // 在安卓下，自动将当前目录所有歌曲加入默认播放列表
                          final currentPlaylist =
                              playlistService.currentPlaylist;
                          if (currentPlaylist != null) {
                            await playlistService.clearPlaylist(
                              currentPlaylist.id,
                            );
                            await playlistService.addSongsToPlaylist(
                              currentPlaylist.id,
                              _currentFolder!.files,
                            );
                          }
                        } else {
                          audio.playFile(file.path, file.name, id: file.id);
                        }

                        if (mounted) {
                          pageController.animateToPage(
                            1,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
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
              tooltip: '重建标签数据库',
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
        title: const Text('重建数据库'),
        content: const Text('确定要手动刷新所有歌曲的标签信息吗？这可能需要一些时间来重新加载封面和元数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              scanner.rebuildMetadataDatabase();
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('正在重建歌曲标签数据库...')));
              }
            },
            child: const Text('确定'),
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
              title: const Text('排序方式'),
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
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        title: const Text('标题'),
                        leading: Radio(value: SortCriteria.title),
                      ),
                      ListTile(
                        title: const Text('文件名'),
                        leading: Radio(value: SortCriteria.filename),
                      ),

                      ListTile(
                        title: const Text('轨道号 (Track Number)'),
                        leading: Radio(value: SortCriteria.trackNumber),
                      ),
                    ]),
                  ),
                ],
                /*children: [
                  RadioListTile<SortCriteria>(
                    title: const Text('标题'),
                    value: SortCriteria.title,
                    groupValue: scanner.sortCriteria,
                    onChanged: (v) {
                      if (v != null) {
                        scanner.setSortCriteria(v);
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<SortCriteria>(
                    title: const Text('文件名'),
                    value: SortCriteria.filename,
                    groupValue: scanner.sortCriteria,
                    onChanged: (v) {
                      if (v != null) {
                        scanner.setSortCriteria(v);
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<SortCriteria>(
                    title: const Text('轨道号 (Track Number)'),
                    value: SortCriteria.trackNumber,
                    groupValue: scanner.sortCriteria,
                    onChanged: (v) {
                      if (v != null) {
                        scanner.setSortCriteria(v);
                        setState(() {});
                      }
                    },
                  ),
                  const Divider(),
                  RadioListTile<SortOrder>(
                    title: const Text('升序'),
                    value: SortOrder.ascending,
                    groupValue: scanner.sortOrder,
                    onChanged: (v) {
                      if (v != null) {
                        scanner.setSortOrder(v);
                        setState(() {});
                      }
                    },
                  ),
                  RadioListTile<SortOrder>(
                    title: const Text('降序'),
                    value: SortOrder.descending,
                    groupValue: scanner.sortOrder,
                    onChanged: (v) {
                      if (v != null) {
                        scanner.setSortOrder(v);
                        setState(() {});
                      }
                    },
                  ),
                ],*/
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('确定'),
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
          setState(() {
            _currentFolder = null;
            _history.clear();
          });
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Icon(Icons.home_outlined, size: 24),
        ),
      ),
    );

    // 历史路径段
    for (int i = 0; i < _history.length; i++) {
      final folder = _history[i];
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
            setState(() {
              _currentFolder = folder;
              _history.removeRange(i, _history.length);
            });
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
            tooltip: '排序',
          ),
        ],
      ),
    );
  }
}
