import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/sharing/lan_sync_history.dart';
import 'package:vynody/player/sharing/lan_sync_models.dart';
import 'package:vynody/player/sharing/lan_sync_progress.dart';

/// 进度对话框当前是否开着。
bool _progressDialogOpen = false;

/// 已经请求关闭、但路由可能还没 push 完。
///
/// 同步失败得比 `showDialog` 铺开还快时（比如同设备互斥直接抛
/// `LanSyncBusyException`），`hide` 会先于路由入栈执行。这时如果直接用全局
/// navigator 去 pop，弹掉的是**页面**。所以关闭只置标志 + 用对话框自己的
/// context 退栈；路由晚到就由它自己的 build 兜底退出。
bool _hideRequested = false;
BuildContext? _dialogContext;

/// 已经在退栈中。
///
/// `whenComplete` 要等退场动画跑完才触发，这中间 `_progressDialogOpen` 还是
/// true。接口的两端（服务的 finally 和调用方的 finally）几乎同时收尾，
/// 没有这个标记就会 pop 两次 —— 第二次弹掉的是**页面**。
bool _closing = false;

/// 打开进度对话框。已经开着就不重复开。
///
/// 这里不用 `showDialog().then()` 串起任务，是因为任务本身在调用方手里：
/// 对话框只是这块屏幕上的一个「正在做什么」的显示器，任务结束由调用方摘掉它。
void showLanSyncProgressDialog(BuildContext context) {
  if (_progressDialogOpen) return;
  _progressDialogOpen = true;
  _hideRequested = false;
  _closing = false;
  _dialogContext = null;
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => const _LanSyncProgressDialog(),
  ).whenComplete(() {
    _progressDialogOpen = false;
    _hideRequested = false;
    _closing = false;
    _dialogContext = null;
  });
}

/// 关闭进度对话框。找不到可弹的路由时静默 — 用户可能已经切到别的页面，
/// 或者整个导航树正在被销毁（退出应用），这时不该抛异常打断同步收尾。
void hideLanSyncProgressDialog() {
  if (!_progressDialogOpen || _closing) return;
  _closing = true;
  _hideRequested = true;
  final dialogContext = _dialogContext;
  if (dialogContext != null && dialogContext.mounted) {
    Navigator.of(dialogContext).pop();
  }
}

bool get isLanSyncProgressDialogOpen => _progressDialogOpen;

class _LanSyncProgressDialog extends ConsumerStatefulWidget {
  const _LanSyncProgressDialog();

  @override
  ConsumerState<_LanSyncProgressDialog> createState() =>
      _LanSyncProgressDialogState();
}

class _LanSyncProgressDialogState
    extends ConsumerState<_LanSyncProgressDialog> {
  @override
  void initState() {
    super.initState();
    _dialogContext = context;
  }

  @override
  void dispose() {
    if (identical(_dialogContext, context)) _dialogContext = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final progress = ref.watch(lanSyncProgressProvider);

    // 关闭已请求 / 任务已经结束但对话框才刚铺开：自己退栈。
    // 不这么做的话，「同步失败得比弹窗还快」会留下一个关不掉的模态框。
    //
    // 用 `pop()` 而不是 `maybePop()`：外层 PopScope 的 `canPop: false` 会拦掉
    // maybePop，于是自己永远关不掉。
    if (_hideRequested || progress == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_hideRequested || ref.read(lanSyncProgressProvider) == null) {
          if (_closing) return;
          _closing = true;
          Navigator.of(context).pop();
        }
      });
    }

    final stage = progress?.stage ?? LanSyncStage.preparing;
    final fraction = progress?.fraction;

    final String deviceName = progress?.deviceName ?? '';
    final Object title = deviceName.isEmpty
        ? l10n.lanSyncProgressTransferring
        : (progress?.direction == LanSyncDirection.incoming
              ? l10n.lanSyncReceivingFrom(deviceName)
              : l10n.lanSyncSendingTo(deviceName));

    final String stageText = switch (stage) {
      LanSyncStage.preparing => l10n.lanSyncProgressPreparing,
      LanSyncStage.transferring => l10n.lanSyncProgressTransferring,
      LanSyncStage.waitingPeer => l10n.lanSyncProgressWaitingPeer,
      LanSyncStage.importing => l10n.lanSyncProgressImporting,
      LanSyncStage.ingesting => l10n.lanSyncProgressIngesting,
    };

    return PopScope(
      // 系统返回键不能关：中途退出去只剩一个「同步中」的僵尸状态。
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$title',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stageText,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (progress != null && progress.total > 0)
                  Text(
                    l10n.lanSyncProgressCount(
                      progress.processed,
                      progress.total,
                    ),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.primary,
                minHeight: 6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: (progress?.cancelRequested ?? false)
                ? null
                : () => ref
                      .read(lanSyncProgressProvider.notifier)
                      .requestCancel(),
            child: Text(
              (progress?.cancelRequested ?? false)
                  ? l10n.lanSyncCancelling
                  : l10n.lanSyncCancel,
            ),
          ),
        ],
      ),
    );
  }
}

/// 把回执压成一句人话。
///
/// SnackBar、「最近一次同步」卡片、结果卡片标题都用它 —— 此前这段映射写在
/// main_layout 的 `ref.listen` 里，要在别处展示就得复制一份 switch。
String lanSyncReceiptSummary(AppLocalizations l10n, LanSyncReceipt receipt) {
  final String text;
  switch ((receipt.kind, receipt.direction)) {
    case (LanSyncKind.lyrics, LanSyncDirection.incoming):
      text = l10n.lanSyncLyricsReceived(
        receipt.added,
        receipt.updated,
        receipt.skipped,
      );
    case (LanSyncKind.lyrics, LanSyncDirection.outgoing):
      text = l10n.lanSyncLyricsSent(receipt.added);
    case (LanSyncKind.playlists, LanSyncDirection.incoming):
      text = receipt.missing > 0
          ? l10n.lanSyncPlaylistsReceivedPartial(
              receipt.containers,
              receipt.added,
              receipt.missing,
            )
          : l10n.lanSyncPlaylistsReceived(receipt.containers, receipt.added);
    case (LanSyncKind.playlists, LanSyncDirection.outgoing):
      text = l10n.lanSyncPlaylistsSent(receipt.containers, receipt.added);
  }

  // 命中多首本地歌（同名不同版本 / 重复目录）时单独提一句，用户才知道结果
  // 不完全确定，而不是以为「导入 N 首」就是 N 首准确的歌。
  if (receipt.ambiguous > 0) {
    return '$text\n${l10n.lanSyncPlaylistsAmbiguous(receipt.ambiguous)}';
  }
  return text;
}

/// 统一结果卡片。
///
/// 统计口径固定为「新增 / 更新 / 跳过 / 未匹配 / 多候选」五项，不再按链路各写
/// 一套文案 —— 之前歌词用 matched/overwritten/skipped，歌单用
/// imported_playlists/imported_songs/missing_songs，同一个概念三个名字。
Future<void> showLanSyncResultDialog(
  BuildContext context,
  LanSyncReceipt receipt,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => _LanSyncResultDialog(receipt: receipt),
  );
}

class _LanSyncResultDialog extends StatelessWidget {
  const _LanSyncResultDialog({required this.receipt});

  final LanSyncReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final rows = <({String label, int value})>[
      if (receipt.kind == LanSyncKind.playlists)
        (label: l10n.lanSyncResultPlaylists, value: receipt.containers),
      (label: l10n.lanSyncResultAdded, value: receipt.added),
      (label: l10n.lanSyncResultUpdated, value: receipt.updated),
      (label: l10n.lanSyncResultSkipped, value: receipt.skipped),
      if (receipt.missing > 0)
        (label: l10n.lanSyncResultMissing, value: receipt.missing),
      if (receipt.ambiguous > 0)
        (label: l10n.lanSyncResultAmbiguous, value: receipt.ambiguous),
    ];

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        l10n.lanSyncResultTitle,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (receipt.deviceName != null && receipt.deviceName!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    receipt.deviceName!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.label,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${row.value}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (receipt.missingSamples.isNotEmpty) ...[
                const SizedBox(height: 14),
                _SampleList(
                  title: l10n.lanSyncResultMissing,
                  total: receipt.missing,
                  samples: receipt.missingSamples,
                ),
              ],
              if (receipt.ambiguousSamples.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SampleList(
                  title: l10n.lanSyncResultAmbiguous,
                  total: receipt.ambiguous,
                  samples: receipt.ambiguousSamples,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLocalizations.of(context)!.done),
        ),
      ],
    );
  }
}

/// 明细样本。
///
/// 只列前 [LanSyncReceipt.maxSamples] 条并显示「还有 N 条」：整库级别的未匹配
/// 清单本来就没法在对话框里看完，用户真正需要的是「大致是哪些歌」。
class _SampleList extends StatelessWidget {
  const _SampleList({
    required this.title,
    required this.total,
    required this.samples,
  });

  final String title;
  final int total;
  final List<String> samples;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final remaining = total - samples.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        for (final sample in samples)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              '· $sample',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.lanSyncResultMoreSamples(remaining),
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// 结果对话框 + 进度对话框的组合入口。
///
/// [task] 返回结果后先关进度框再弹结果卡片，避免两个对话框在路由栈里打架。
/// 抛 [LanSyncCancelledException] 时关掉进度框并返回 null —— 取消不是失败，
/// 由调用方决定要不要给一句「已取消」。
Future<LanSyncOutcome?> runLanSyncWithFeedback({
  required BuildContext context,
  required Future<LanSyncOutcome> Function() task,
  required LanSyncReceipt Function(LanSyncOutcome outcome) toReceipt,
  bool showResultDialog = true,
}) async {
  showLanSyncProgressDialog(context);
  try {
    final outcome = await task();
    hideLanSyncProgressDialog();
    final receipt = toReceipt(outcome);
    // 发起方也要写历史，否则「最近一次同步」只在被动方看得到。
    await LanSyncHistoryStore.record(receipt);
    if (showResultDialog && context.mounted) {
      await showLanSyncResultDialog(context, receipt);
    }
    return outcome;
  } on LanSyncCancelledException {
    hideLanSyncProgressDialog();
    return null;
  } catch (_) {
    hideLanSyncProgressDialog();
    rethrow;
  }
}
