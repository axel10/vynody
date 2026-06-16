import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:oktoast/oktoast.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/sharing/sharing_riverpod.dart';
import 'package:vynody/player/sharing/sharing_service.dart';
import 'package:vynody/player/sharing/lan_device.dart';
import 'package:vynody/dialogs/transfer_dialogs.dart';

class SharingPage extends ConsumerStatefulWidget {
  const SharingPage({super.key});

  @override
  ConsumerState<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends ConsumerState<SharingPage> {
  late final SharingServerStateNotifier _sharingServerNotifier;

  @override
  void initState() {
    super.initState();
    _sharingServerNotifier = ref.read(sharingServerStateProvider.notifier);
    // Auto-start server when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sharingServerNotifier.start();
      }
    });
  }

  @override
  void dispose() {
    // Auto-stop server when page is closed/destroyed
    // Since this is a tab page, we want it to stop when user navigates away or it's unmounted.
    // However, if we want it to run only during this page session:
    // To ensure the server stops when we exit, we stop it in dispose.
    Future.microtask(() {
      _sharingServerNotifier.stop();
    });
    super.dispose();
  }

  Future<void> _handleSendFile(LanDevice device) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final path = result.files.single.path!;
      
      // We need to trigger the progress dialog on our screen
      // Final upload token/session ID will be created inside the sending function
      // In sharing_service, sendFile generates a session ID starting with 'send_'.
      // We can compute the expected session ID or let sharing_service notify us.
      // Better yet, we can listen for new active transfer sessions in state
      // and show the progress dialog. Let's start the file transfer:
      final service = ref.read(sharingServiceProvider);
      
      // Let's launch transfer in background, and show progress dialog
      // To show the progress dialog immediately, we can listen to activeTransfersProvider.
      // But we need the sessionId. Since the sessionId is derived from timestamp inside sendFile,
      // let's modify sendFile slightly or just search for the latest session in activeTransfersProvider.
      
      // Let's create a listener to catch the session ID as soon as it's added.
      late ProviderSubscription subscription;
      subscription = ref.listenManual(activeTransfersProvider, (previous, next) {
        final newSendSession = next.firstWhere(
          (s) => s.isSending && s.deviceName == device.name && s.status == TransferStatus.pending,
          orElse: () => TransferSession(
            id: '', fileName: '', totalBytes: 0, bytesTransferred: 0, isSending: true, deviceName: '', status: TransferStatus.failed, filesCount: 0, completedFilesCount: 0,
          ),
        );
        if (newSendSession.id.isNotEmpty) {
          subscription.close();
          showTransferProgressDialog(context, newSendSession.id);
        }
      });

      final success = await service.sendFile(device, path);
      if (!success) {
        // In case preflight fails immediately
        subscription.close();
      }
    } catch (e) {
      showToast('发送文件失败: $e');
    }
  }

  Future<void> _handleSendFolder(LanDevice device) async {
    try {
      final dirPath = await FilePicker.getDirectoryPath();

      if (dirPath == null) {
        return;
      }

      showToast('正在扫描文件夹中的音乐文件...');

      final dir = Directory(dirPath);
      final List<String> musicFiles = [];
      
      try {
        final entries = dir.listSync(recursive: true);
        for (final entry in entries) {
          if (entry is File && MusicFileUtils.isMusicFilePath(entry.path)) {
            musicFiles.add(entry.path);
          }
        }
      } catch (e) {
        showToast('扫描文件夹失败: $e');
        return;
      }

      if (musicFiles.isEmpty) {
        showToast('未在此文件夹中找到支持的音乐文件');
        return;
      }

      final parentPath = p.dirname(dirPath);
      final service = ref.read(sharingServiceProvider);

      late ProviderSubscription subscription;
      subscription = ref.listenManual(activeTransfersProvider, (previous, next) {
        final newSendSession = next.firstWhere(
          (s) => s.isSending && s.deviceName == device.name && s.status == TransferStatus.pending,
          orElse: () => TransferSession(
            id: '', fileName: '', totalBytes: 0, bytesTransferred: 0, isSending: true, deviceName: '', status: TransferStatus.failed, filesCount: 0, completedFilesCount: 0,
          ),
        );
        if (newSendSession.id.isNotEmpty) {
          subscription.close();
          showTransferProgressDialog(context, newSendSession.id);
        }
      });

      final success = await service.sendFiles(
        targetDevice: device,
        filePaths: musicFiles,
        baseSourcePath: parentPath,
      );
      
      if (!success) {
        subscription.close();
      }
    } catch (e) {
      showToast('发送文件夹失败: $e');
    }
  }

  Future<void> _handleSyncLyricsToDevice(LanDevice device) async {
    try {
      showToast('正在向 ${device.name} 同步歌词...');
      final service = ref.read(sharingServiceProvider);
      final stats = await service.syncLyricsToDevice(device);
      showToast('同步成功: 匹配 ${stats['matched']} 首, 更新 ${stats['overwritten']} 首, 忽略 ${stats['skipped']} 首');
    } catch (e) {
      showToast('同步歌词失败: $e');
    }
  }

  Future<void> _handleSyncLyricsFromDevice(LanDevice device) async {
    try {
      showToast('正在从 ${device.name} 同步歌词...');
      final service = ref.read(sharingServiceProvider);
      final stats = await service.pullLyricsFromDevice(device);
      showToast('同步成功: 本地匹配 ${stats['matched']} 首, 更新 ${stats['overwritten']} 首, 忽略 ${stats['skipped']} 首');
    } catch (e) {
      showToast('同步歌词失败: $e');
    }
  }

  IconData _getPlatformIcon(String type) {
    switch (type.toLowerCase()) {
      case 'macos':
      case 'ios':
        return Icons.apple;
      case 'windows':
        return Icons.laptop_windows;
      case 'android':
        return Icons.phone_android;
      case 'linux':
        return Icons.terminal;
      default:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverState = ref.watch(sharingServerStateProvider);
    final devicesAsync = ref.watch(discoveredDevicesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网文件共享', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            
            // 1. Local Device Status Card
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (serverState.isRunning ? Colors.green : Colors.red).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        serverState.isRunning ? Icons.wifi_tethering : Icons.portable_wifi_off,
                        color: serverState.isRunning ? Colors.green : Colors.red,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            serverState.isRunning ? '局域网共享已开启' : '局域网共享未开启',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            serverState.isRunning
                                ? '本机 IP: ${serverState.localIp} (端口: ${serverState.httpPort})'
                                : '正在启动服务...',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: serverState.isRunning,
                      onChanged: (val) {
                        if (val) {
                          ref.read(sharingServerStateProvider.notifier).start();
                        } else {
                          ref.read(sharingServerStateProvider.notifier).stop();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 2. Web Share / Browser upload collapsible card
            if (serverState.isRunning && serverState.localIp != null) ...[
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.language, color: theme.colorScheme.primary, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            '浏览器网页传输 (Web Share)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '同一局域网的手机/电脑可通过浏览器打开下方链接，直接向本设备上传或下载音乐：',
                        style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'http://${serverState.localIp}:${serverState.httpPort}/',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 14,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: 'http://${serverState.localIp}:${serverState.httpPort}/'));
                                showToast('链接已复制到剪贴板');
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // 3. Discovered Devices Section
            Text(
              '附近的设备',
              style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: devicesAsync.when(
                data: (devices) {
                  // Filter out local device if any
                  final remoteDevices = devices;
                  if (remoteDevices.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Text(
                            serverState.isRunning ? '正在寻找局域网内其他设备...' : '开启共享后开始寻找设备',
                            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: remoteDevices.length,
                    itemBuilder: (context, index) {
                      final device = remoteDevices[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: device.isOnline 
                                ? theme.colorScheme.primary.withValues(alpha: 0.3) 
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getPlatformIcon(device.deviceType),
                              color: device.isOnline ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                          title: Text(
                            device.name,
                            style: TextStyle(
                              color: device.isOnline ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                device.ip,
                                style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: device.isOnline ? Colors.green : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                device.isOnline ? '在线' : '已断开',
                                style: TextStyle(
                                  color: device.isOnline ? Colors.green : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          trailing: device.isOnline
                              ? PopupMenuButton<String>(
                                  icon: Icon(Icons.more_vert, color: theme.colorScheme.primary),
                                  onSelected: (value) {
                                    if (value == 'file') {
                                      _handleSendFile(device);
                                    } else if (value == 'folder') {
                                      _handleSendFolder(device);
                                    } else if (value == 'sync_to') {
                                      _handleSyncLyricsToDevice(device);
                                    } else if (value == 'sync_from') {
                                      _handleSyncLyricsFromDevice(device);
                                    }
                                  },
                                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(
                                      value: 'file',
                                      child: Row(
                                        children: [
                                          Icon(Icons.insert_drive_file, size: 18, color: theme.colorScheme.primary),
                                          const SizedBox(width: 8),
                                          const Text('发送音乐文件'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'folder',
                                      child: Row(
                                        children: [
                                          Icon(Icons.folder, size: 18, color: theme.colorScheme.primary),
                                          const SizedBox(width: 8),
                                          const Text('发送文件夹'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuDivider(),
                                    PopupMenuItem<String>(
                                      value: 'sync_to',
                                      child: Row(
                                        children: [
                                          Icon(Icons.cloud_upload_rounded, size: 18, color: theme.colorScheme.primary),
                                          const SizedBox(width: 8),
                                          const Text('同步歌词至该设备'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'sync_from',
                                      child: Row(
                                        children: [
                                          Icon(Icons.cloud_download_rounded, size: 18, color: theme.colorScheme.primary),
                                          const SizedBox(width: 8),
                                          const Text('从该设备同步歌词'),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      );
                    },
                  );
                },
                loading: () => Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
                error: (e, _) => Center(
                  child: Text('加载设备出错: $e', style: TextStyle(color: theme.colorScheme.error)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
