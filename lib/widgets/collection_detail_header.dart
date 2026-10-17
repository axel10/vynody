import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'song_thumbnail.dart';

/// 流派 / 年份等「集合型」条目的封面。
///
/// 有代表封面时展示专辑封面，缺失时回退为渐变底色 + 图标。
class CollectionCover extends StatelessWidget {
  const CollectionCover({
    super.key,
    required this.size,
    required this.songPath,
    required this.fallbackIcon,
    this.artworkPath,
    this.thumbnailPath,
    this.borderRadius = 16,
  });

  final double size;
  final String songPath;
  final String? artworkPath;
  final String? thumbnailPath;
  final IconData fallbackIcon;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCover = (artworkPath?.isNotEmpty ?? false) ||
        (thumbnailPath?.isNotEmpty ?? false);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: hasCover
            ? SongThumbnail(
                path: songPath,
                artworkPath: artworkPath,
                thumbnailPath: thumbnailPath,
                size: size,
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                      theme.colorScheme.secondary.withValues(alpha: 0.4),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    fallbackIcon,
                    size: size * 0.45,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
      ),
    );
  }
}

/// 流派 / 年份详情页顶部信息区。
///
/// 竖屏：左侧封面 + 右侧标题、统计信息与播放按钮；
/// 横屏：不展示封面（封面已在专辑分组中呈现），标题与统计信息占满一行，
/// 播放 / 随机播放收为行尾的圆形图标按钮，与艺术家页保持一致。
class CollectionDetailHeader extends StatelessWidget {
  const CollectionDetailHeader({
    super.key,
    required this.title,
    required this.metaLine,
    required this.onPlayAll,
    required this.onShufflePlay,
    this.cover,
  });

  final String title;
  final String metaLine;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;

  /// 竖屏使用的封面；横屏不展示。
  final Widget? cover;

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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (cover != null) ...[
          cover!,
          const SizedBox(width: 20),
        ],
        Expanded(
          child: Column(
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
          ),
        ),
      ],
    );
  }
}
