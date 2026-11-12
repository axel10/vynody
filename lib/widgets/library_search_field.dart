import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/music_file.dart';
import 'song_thumbnail.dart';

/// 本地媒体库通用的搜索输入框。
///
/// 统一在这里定义外观（圆角 16、secondaryContainer 填充、紧凑内边距），
/// 分类列表页头与详情页内的搜索都复用它，避免两处各写一份后圆角/高度对不上。
class LibrarySearchField extends StatelessWidget {
  const LibrarySearchField({
    super.key,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
    this.focusNode,
    this.hintText,
  });

  final TextEditingController controller;

  /// 当前生效的搜索词，仅用于决定是否显示右侧清除按钮。
  final String query;

  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final FocusNode? focusNode;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          fontSize: 14,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
          size: 20,
        ),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                onPressed: onClear,
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.onSecondaryContainer
                      .withValues(alpha: 0.8),
                  size: 18,
                ),
              ),
        filled: true,
        fillColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
      ),
      style: TextStyle(
        color: theme.colorScheme.onSecondaryContainer,
        fontSize: 14,
      ),
    );
  }
}

/// 搜索结果分类区块标题（例如“歌曲 (15)”、“文件夹 (3)”）。
class SearchSectionHeader extends StatelessWidget {
  const SearchSectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.symmetric(vertical: 8.0),
  });

  final String title;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 搜索结果通用的歌曲行组件。
///
/// 对齐本地媒体库搜索页的设计（44dp 封面、6dp 圆角、600 字重标题、灰色副标题），
/// 供本地媒体库、本地目录、远程目录搜索结果统一复用。
class SearchSongTile extends StatelessWidget {
  const SearchSongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.parentFolderName,
    this.customSubtitle,
  });

  final MusicFile song;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails details)? onSecondaryTapDown;

  /// 可选的所属文件夹名称标签（用于跨目录搜索时标识来源）。
  final String? parentFolderName;

  /// 自定义副标题（未提供时按「艺术家 - 专辑」回退展示）。
  final String? customSubtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final artist = song.artist?.trim();
    final album = song.album?.trim();
    final parts = [
      if (artist != null && artist.isNotEmpty) artist,
      if (album != null && album.isNotEmpty) album,
    ];
    final defaultSubtitle =
        parts.isEmpty ? l10n.unknownArtist : parts.join(' - ');
    final subtitleText = customSubtitle ?? defaultSubtitle;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            SongThumbnail.fromSong(
              song,
              size: 44,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    song.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (parentFolderName != null)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            parentFolderName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            subtitleText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      subtitleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索结果通用的文件夹行组件。
///
/// 对齐本地搜索页行级视觉（44dp 图标卡片、600 字重标题、灰色副标题、chevron 引导），
/// 供本地目录、远程目录搜索结果统一复用。
class SearchFolderTile extends StatelessWidget {
  const SearchFolderTile({
    super.key,
    required this.name,
    required this.path,
    required this.onTap,
    this.countText,
  });

  final String name;
  final String path;
  final VoidCallback onTap;
  final String? countText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.folder_rounded,
                color: theme.colorScheme.primary,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (countText != null) ...[
              const SizedBox(width: 8),
              Text(
                countText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

