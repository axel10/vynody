import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibe_flow/player/sharing/sharing_service.dart';

void showIncomingTransferDialog(BuildContext context, IncomingTransferRequest request) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final totalSize = request.files.fold<int>(0, (sum, f) => sum + f.size);
      final sizeMb = (totalSize / (1024 * 1024)).toStringAsFixed(1);
      
      String fileNames;
      if (request.files.length > 2) {
        fileNames = '${request.files[0].name}, ${request.files[1].name} 等共 ${request.files.length} 个文件';
      } else {
        fileNames = request.files.map((f) => f.name).join(', ');
      }

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
          ),
          title: Row(
            children: [
              Icon(Icons.share, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              const Text(
                '收到文件共享请求',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '来自 "${request.senderName}" 的发送请求:',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileNames,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '文件大小: $sizeMb MB',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '提示：接收后文件将自动保存至本地音乐文件夹并加入媒体库。',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 11),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                request.onDecision(false);
              },
              child: const Text('拒绝'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                request.onDecision(true);
              },
              child: const Text('接收', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    },
  );
}

void showTransferProgressDialog(BuildContext context, String sessionId) {
  final theme = Theme.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Consumer(
          builder: (context, ref, child) {
            final sessions = ref.watch(activeTransfersProvider);
            final session = sessions.firstWhere(
              (s) => s.id == sessionId,
              orElse: () => TransferSession(
                id: sessionId,
                fileName: 'Unknown',
                totalBytes: 0,
                bytesTransferred: 0,
                isSending: false,
                deviceName: 'Device',
                status: TransferStatus.failed,
              ),
            );

            // Auto close on completion/failure/cancellation
            if (session.status == TransferStatus.success ||
                session.status == TransferStatus.failed ||
                session.status == TransferStatus.cancelled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                  
                  // Show quick status toast or SnackBar
                  final isSuccess = session.status == TransferStatus.success;
                  final text = isSuccess
                      ? '${session.isSending ? "发送" : "接收"} "${session.fileName}" 成功'
                      : '${session.isSending ? "发送" : "接收"} "${session.fileName}" 失败';
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(text),
                    ),
                  );
                }
              });
            }

            final speed = (session.bytesTransferred / (1024 * 1024)).toStringAsFixed(1);
            final total = (session.totalBytes / (1024 * 1024)).toStringAsFixed(1);
            final title = session.isSending ? '正在发送到 ${session.deviceName}' : '正在从 ${session.deviceName} 接收';

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
              ),
              title: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.fileName,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: session.progress,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: theme.colorScheme.primary,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '进度: ${(session.progress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                      Text(
                        '$speed / $total MB',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}
