import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../pages/remote/remote_download_manager_page.dart';
import 'app_snack_bar.dart';

/// 下载入队后的统一反馈：「已加入下载队列」+「查看进度」入口。
///
/// 远程下载有十几处入口（单曲菜单、集合菜单、页头下载全部、多选面板、文件浏览器），
/// 以前每处都手抄一遍 SnackBar，改文案要改十几遍、还容易漏掉「查看进度」。
void showRemoteDownloadQueuedFeedback(
  BuildContext context,
  WidgetRef ref,
  int count,
) {
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  AppSnackBar.show(
    context,
    ref,
    SnackBar(
      // 单曲沿用短文案，批量才报数量。
      content: Text(
        count <= 1
            ? l10n.addedToDownloadQueue
            : l10n.batchAddedToDownloadQueue(count),
      ),
      action: SnackBarAction(
        label: l10n.viewDownloadProgress,
        onPressed: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const RemoteDownloadManagerPage(),
            ),
          );
        },
      ),
    ),
  );
}
