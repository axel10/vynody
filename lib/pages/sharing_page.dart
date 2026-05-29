import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vibe_flow/player/sharing/sharing_riverpod.dart';
import 'package:vibe_flow/player/sharing/sharing_service.dart';
import 'package:vibe_flow/player/sharing/lan_device.dart';
import 'package:vibe_flow/dialogs/transfer_dialogs.dart';

class SharingPage extends ConsumerStatefulWidget {
  const SharingPage({super.key});

  @override
  ConsumerState<SharingPage> createState() => _SharingPageState();
}

class _SharingPageState extends ConsumerState<SharingPage> {
  @override
  void initState() {
    super.initState();
    // Auto-start server when page opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(sharingServerStateProvider.notifier).start();
      }
    });
  }

  @override
  void dispose() {
    // Auto-stop server when page is closed/destroyed
    // Since this is a tab page, we want it to stop when user navigates away or it's unmounted.
    // However, if we want it to run only during this page session:
    // To ensure the server stops when we exit, we stop it in dispose.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sharingServerStateProvider.notifier).stop();
    });
    super.dispose();
  }

  Future<void> _handleSendFile(LanDevice device) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.audio,
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
            id: '', fileName: '', totalBytes: 0, bytesTransferred: 0, isSending: true, deviceName: '', status: TransferStatus.failed
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网文件共享', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.purple.withOpacity(0.05),
              Colors.blue.withOpacity(0.05),
              Colors.black,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              
              // 1. Local Device Status Card
              Card(
                color: Colors.white.withOpacity(0.04),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (serverState.isRunning ? Colors.green : Colors.red).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          serverState.isRunning ? Icons.wifi_tethering : Icons.portable_wifi_off,
                          color: serverState.isRunning ? Colors.greenAccent : Colors.redAccent,
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
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              serverState.isRunning
                                  ? '本机 IP: ${serverState.localIp} (端口: ${serverState.httpPort})'
                                  : '正在启动服务...',
                              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: serverState.isRunning,
                        activeColor: Colors.purpleAccent,
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
                  color: Colors.white.withOpacity(0.02),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.language, color: Colors.blueAccent, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              '浏览器网页传输 (Web Share)',
                              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '同一局域网的手机/电脑可通过浏览器打开下方链接，直接向本设备上传或下载音乐：',
                          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'http://${serverState.localIp}:${serverState.httpPort}/',
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
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
              const Text(
                '附近的设备',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                            Icon(Icons.wifi, size: 48, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 12),
                            Text(
                              serverState.isRunning ? '正在寻找局域网内其他设备...' : '开启共享后开始寻找设备',
                              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
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
                          color: Colors.white.withOpacity(device.isOnline ? 0.04 : 0.01),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: device.isOnline 
                                  ? Colors.purpleAccent.withOpacity(0.2) 
                                  : Colors.white.withOpacity(0.04)
                            ),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.04),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getPlatformIcon(device.deviceType),
                                color: device.isOnline ? Colors.white : Colors.grey,
                              ),
                            ),
                            title: Text(
                              device.name,
                              style: TextStyle(
                                color: device.isOnline ? Colors.white : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Text(
                                  device.ip,
                                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: device.isOnline ? Colors.greenAccent : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  device.isOnline ? '在线' : '已断开',
                                  style: TextStyle(
                                    color: device.isOnline ? Colors.greenAccent : Colors.grey,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            trailing: device.isOnline
                                ? IconButton(
                                    icon: const Icon(Icons.send_rounded, color: Colors.purpleAccent),
                                    onPressed: () => _handleSendFile(device),
                                  )
                                : null,
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator(color: Colors.purpleAccent)),
                  error: (e, _) => Center(
                    child: Text('加载设备出错: $e', style: const TextStyle(color: Colors.redAccent)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
