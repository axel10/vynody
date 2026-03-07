import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../player/scanner_service.dart';
import '../player/audio_service.dart';
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
          if (Platform.isWindows) const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            alignment: Alignment.centerLeft,
            child: const Text(
              '扫描目录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
      currentBody = WillPopScope(
        onWillPop: () async {
          if (_history.isNotEmpty || _currentFolder != null) {
            _goBack();
            return false;
          }
          return true;
        },
        child: Column(
          children: [
            if (Platform.isWindows) const SizedBox(height: 32),
            _buildBreadcrumbs(_currentFolder!),
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
                      onTap: () {
                        if (Platform.isAndroid) {
                          final index = _currentFolder!.files.indexOf(file);
                          audio.playPlaylist(
                            _currentFolder!.files,
                            initialIndex: index,
                          );
                        } else {
                          audio.playFile(file.path, file.name, id: file.id);
                        }
                        context.read<PageController>().animateToPage(
                          1,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
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
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('正在重建歌曲标签数据库...')));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(MusicFolder current) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      width: double.infinity,
      child: Text(
        current.path,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
