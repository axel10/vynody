import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/sharing/sharing_service.dart';
import 'package:vynody/player/sharing/sharing_riverpod.dart';
import 'package:vynody/utils/app_snack_bar.dart';

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
                filesCount: 0,
                completedFilesCount: 0,
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
                  final isCancelled = session.status == TransferStatus.cancelled;
                  final text = isSuccess
                      ? (session.isSending 
                          ? '"${session.fileName}" 发送完毕' 
                          : '成功接收了 ${session.completedFilesCount ?? session.filesCount ?? 1} 首歌曲')
                      : (isCancelled
                          ? '${session.isSending ? "发送" : "接收"}已取消'
                          : '${session.isSending ? "发送" : "接收"} "${session.fileName}" 失败');
                  
                  AppSnackBar.show(
                    context,
                    ref,
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

            final completedCount = session.completedFilesCount ?? 0;
            final filesCount = session.filesCount ?? 0;
            final activeCount = session.activeFiles.length;
            final hasMoreFiles = filesCount > (completedCount + activeCount);
            final double? containerHeight = hasMoreFiles ? 156 : null;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45)),
              ),
              title: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
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
                    if (session.activeFiles.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 6),
                      Text(
                        '当前正在传输',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: containerHeight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 156),
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: Column(
                              children: session.activeFiles.map((activeFile) {
                                return Container(
                                  key: ValueKey(activeFile.fileName),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(10),
                                  width: double.maxFinite,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.audiotrack_rounded,
                                            size: 14,
                                            color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              activeFile.fileName,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${(activeFile.progress * 100).toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      LinearProgressIndicator(
                                        value: activeFile.progress,
                                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                                        minHeight: 4,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    ref.read(sharingServiceProvider).cancelTransfer(sessionId);
                  },
                  child: const Text('取消'),
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

Future<String?> showConflictDialog(BuildContext context, String fileName) {
  final theme = Theme.of(context);
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 12),
              const Text(
                '文件冲突',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '目标设备已存在同名文件：',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                fileName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Text(
                '请选择您要执行的操作：',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop('skip'),
                      child: const Text('跳过'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop('overwrite'),
                      child: const Text('覆盖'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop('skip_all'),
                      child: const Text('全部跳过'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop('overwrite_all'),
                      child: const Text('全部覆盖'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
