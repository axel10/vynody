import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../player/scanner_service.dart';
import '../player/audio_service.dart';
import '../widgets/song_thumbnail.dart';

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

    // Top level view: System Media Library + User Root Folders + Add Folder button
    if (_currentFolder == null) {
      return Column(
        children: [
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
    }

    // Navigating inside a folder
    return WillPopScope(
      onWillPop: () async {
        if (_history.isNotEmpty || _currentFolder != null) {
          _goBack();
          return false;
        }
        return true;
      },
      child: Column(
        children: [
          _buildBreadcrumbs(_currentFolder!),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.arrow_back),
                  title: const Text('返回上一层'),
                  onTap: _goBack,
                ),

                // Show Permission Button if in system folder and no permission
                if (_currentFolder!.path == 'system' && !scanner.hasPermission)
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
                      audio.playFile(file.path, file.name, id: file.id);
                      DefaultTabController.of(context).animateTo(1);
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

  Widget _buildBreadcrumbs(MusicFolder current) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      width: double.infinity,
      child: Text(
        current.path,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
