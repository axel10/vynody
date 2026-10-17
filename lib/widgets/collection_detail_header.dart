import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 流派 / 年份详情页顶部信息区。
///
/// 不展示集合封面：集合的「代表曲」是伪概念（见 `library_catalog.dart` 的
/// 摘要算法），真正可辨识的封面在下方专辑分组里，页头只留标题、统计与播放操作。
/// 竖屏：标题 / 统计 / 播放 + 随机按钮纵向排列；
/// 横屏：播放 / 随机播放收为行尾的圆形图标按钮，与艺术家页保持一致。
class CollectionDetailHeader extends StatelessWidget {
  const CollectionDetailHeader({
    super.key,
    required this.title,
    required this.metaLine,
    required this.onPlayAll,
    required this.onShufflePlay,
  });

  final String title;
  final String metaLine;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;

    final titleWidget = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
    );

    final metaWidget = Text(
      metaLine,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (!isPortrait) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleWidget,
                const SizedBox(height: 4),
                metaWidget,
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            tooltip: l10n.playAll,
            onPressed: onPlayAll,
            icon: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary,
              ),
              child: Icon(
                Icons.play_arrow,
                size: 22,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: l10n.shuffle,
            onPressed: onShufflePlay,
            icon: Icon(
              Icons.shuffle,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        titleWidget,
        const SizedBox(height: 6),
        metaWidget,
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 260;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: onPlayAll,
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: Text(l10n.playAll),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (isNarrow)
                  Tooltip(
                    message: l10n.shuffle,
                    child: OutlinedButton(
                      onPressed: onShufflePlay,
                      style: OutlinedButton.styleFrom(
                        fixedSize: const Size(32, 32),
                        minimumSize: const Size(32, 32),
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Icon(Icons.shuffle_rounded, size: 18),
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: onShufflePlay,
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: Text(l10n.shuffle),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
