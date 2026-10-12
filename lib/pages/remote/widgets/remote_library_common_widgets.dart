import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../player/remote/remote_server_models.dart';
import '../../../utils/layout_constants.dart';

/// 统一步调的远程媒体库内容宽度约束容器
class RemoteContentConstraint extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  const RemoteContentConstraint({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.maxWidth = kSingleColumnContentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// 专为 CustomScrollView Slivers 提供的受控最大宽度适配器
class SliverRemoteContentConstraint extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  const SliverRemoteContentConstraint({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 4),
    this.maxWidth = kSingleColumnContentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: RemoteContentConstraint(
        padding: padding,
        maxWidth: maxWidth,
        child: child,
      ),
    );
  }
}

/// 统一风格的远程服务器全屏加载态（带有服务器品牌标识与旋转微动）
class RemoteLibraryLoadingView extends StatelessWidget {
  final RemoteServer server;
  final IconData icon;
  final String? message;

  const RemoteLibraryLoadingView({
    super.key,
    required this.server,
    required this.icon,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isJellyfin = server.type == RemoteServerType.jellyfin;
    final brandColor = isJellyfin ? const Color(0xFF9D65C9) : Colors.orange;
    final serverName = isJellyfin ? 'Jellyfin' : 'Navidrome';
    final isZh = l10n.localeName.startsWith('zh');

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(brandColor),
                  ),
                ),
                Icon(
                  icon,
                  size: 28,
                  color: brandColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message ?? (isZh ? '正在载入远程媒体库...' : 'Loading Remote Library...'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: brandColor.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isJellyfin
                      ? Icons.movie_filter_rounded
                      : Icons.cloud_done_rounded,
                  size: 13,
                  color: brandColor,
                ),
                const SizedBox(width: 5),
                Text(
                  server.name.isNotEmpty
                      ? '${server.name} ($serverName)'
                      : serverName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一风格的远程数据加载失败与重试界面
class RemoteLibraryErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final String? title;

  const RemoteLibraryErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              title ?? error,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
