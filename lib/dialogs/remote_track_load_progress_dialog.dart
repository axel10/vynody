import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../player/remote/services/remote_track_load_progress.dart';

/// 慢于该阈值才把进度浮层弹出来，几十毫秒就能入队完的小批量不该闪一下。
const Duration _kProgressShowDelay = Duration(milliseconds: 120);

/// 浮层一旦露过面就至少停留这么久。多选几专辑时每张专辑只有一次请求，
/// 整个流程可能两百毫秒就结束，不兜一下就是「弹出来立刻消失」。
const Duration _kProgressMinVisible = Duration(milliseconds: 420);

/// 包住一次「下载准备」流程，期间展示曲目进度浮层。
///
/// 底层拉取曲目 / 入队时会把「共多少首、已处理多少首」写进
/// [remoteTrackLoadProgress]，这里只负责按需弹出与收起浮层。
/// 流程结束后浮层关闭，调用方可以照常弹结果提示。
///
/// [immediate] 为 true 时不等延迟直接弹出。批量下载（多选 / 全部下载）本来就
/// 预期要等，本地服务器几百毫秒就拉完的话，靠延迟阈值会连浮层都看不到。
Future<T?> runWithRemoteTrackLoadProgress<T>({
  required BuildContext context,
  required Future<T> Function() task,
  bool immediate = false,
}) async {
  final progress = remoteTrackLoadProgress;
  progress.begin();

  var dialogVisible = false;
  DateTime? shownAt;
  NavigatorState? dialogNavigator;
  Route<void>? dialogRoute;

  void show() {
    if (!progress.isActive || dialogVisible || !context.mounted) return;
    dialogVisible = true;
    shownAt = DateTime.now();
    _showProgressDialog(context, (navigator, route) {
      dialogNavigator = navigator;
      dialogRoute = route;
    });
  }

  if (immediate) {
    show();
  }
  final delayTimer = immediate ? null : Timer(_kProgressShowDelay, show);

  try {
    return await task();
  } finally {
    delayTimer?.cancel();
    if (dialogVisible && shownAt != null) {
      final elapsed = DateTime.now().difference(shownAt!).inMilliseconds;
      final remain = _kProgressMinVisible.inMilliseconds - elapsed;
      if (remain > 0) {
        await Future<void>.delayed(Duration(milliseconds: remain));
      }
    }
    progress.end();
    // 按路由对象收，而不是 pop 当前栈顶：流程极快时浮层的 builder 可能还没跑过，
    // 靠它的 context 会是 null；而有别的弹窗叠上来时 pop 又会关错人。
    final navigator = dialogNavigator;
    final route = dialogRoute;
    if (dialogVisible && navigator != null && route != null) {
      if (route.navigator == navigator) {
        if (route.isCurrent) {
          navigator.pop();
        } else {
          navigator.removeRoute(route);
        }
      }
    }
  }
}

void _showProgressDialog(
  BuildContext context,
  void Function(NavigatorState navigator, Route<void> route) onReady,
) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _RemoteTrackLoadProgressDialog(),
  );
  // 先登记再入栈：push 之后 task 可能立刻结束，pop 时拿得到 route 才收得掉。
  onReady(navigator, route);
  navigator.push(route);
}

class _RemoteTrackLoadProgressDialog extends StatelessWidget {
  const _RemoteTrackLoadProgressDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 268, maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
            child: AnimatedBuilder(
              animation: remoteTrackLoadProgress,
              builder: (context, _) {
                final progress = remoteTrackLoadProgress;
                final isLoadingTracks =
                    progress.stage == RemoteTrackLoadStage.loading;
                final title = isLoadingTracks
                    ? l10n.downloadPrepLoadingTracks
                    : l10n.downloadPrepQueueingTracks;
                final hasTotal = progress.total > 0;
                final String detail;
                if (isLoadingTracks) {
                  detail = hasTotal
                      ? l10n.trackLoadLoadedKnown(
                          progress.loaded,
                          progress.total,
                        )
                      : l10n.trackLoadLoadedUnknown(progress.loaded);
                } else {
                  detail = hasTotal
                      ? l10n.trackLoadQueuedKnown(
                          progress.loaded,
                          progress.total,
                        )
                      : l10n.trackLoadQueuedUnknown(progress.loaded);
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.5),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: 5,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    // 还没拿到任何首数时（比如单张专辑的一次请求）不摆「0 首」，
                    // 免得看着像卡住了。
                    if (hasTotal || progress.loaded > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
