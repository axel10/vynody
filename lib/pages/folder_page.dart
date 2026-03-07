import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../player/scanner_service.dart';
import '../player/audio_service.dart';

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
    }
  }

  Future<void> _pickFolder(ScannerService scanner) async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      await scanner.setRootPath(selectedDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerService>();
    final audio = context.read<AudioService>();

    // Reset view if scanner root changes or is empty
    if (scanner.rootFolder != null &&
        _currentFolder == null &&
        _history.isEmpty) {
      _currentFolder = scanner.rootFolder;
    }

    if (scanner.rootPath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '未选择扫描目录',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _pickFolder(scanner),
              child: const Text('选择扫描路径'),
            ),
          ],
        ),
      );
    }

    if (scanner.isScanning) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayFolder = _currentFolder ?? scanner.rootFolder;

    if (displayFolder == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '未发现音乐文件',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _pickFolder(scanner),
              child: const Text('重选扫描路径'),
            ),
          ],
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_history.isNotEmpty) {
          _goBack();
          return false;
        }
        return true;
      },
      child: Column(
        children: [
          _buildBreadcrumbs(displayFolder!),
          Expanded(
            child: ListView(
              children: [
                if (_history.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.arrow_upward),
                    title: const Text('...'),
                    onTap: _goBack,
                  ),
                ...displayFolder.subFolders.map(
                  (folder) => ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(folder.name),
                    onTap: () => _navigateTo(folder),
                  ),
                ),
                ...displayFolder.files.map(
                  (file) => ListTile(
                    leading: const Icon(Icons.music_note, color: Colors.blue),
                    title: Text(file.name),
                    onTap: () {
                      audio.playFile(file.path, file.name);
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
