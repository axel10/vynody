import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/song_locator_helper.dart';
import 'folder_layout_utils.dart';
import 'folder_nav_bar_scaffold.dart';
import 'folder_scan_widgets.dart';
import 'library_zoom_popover.dart';
import 'locate_song_button.dart';
export 'folder_nav_bar_scaffold.dart';
export 'library_zoom_popover.dart';

/// 档位弹窗与图标已抽到 `library_zoom_popover.dart`，这里保留同名转调，
/// 避免目录页的既有调用点全部改签名。
Future<void> showFolderZoomPopover(BuildContext anchorContext) =>
    showLibraryZoomPopover(anchorContext, scope: LibraryZoomScope.folder);

/// Reusable navigation bar icon button that opens the folder zoom slider popover.
class FolderZoomNavButton extends ConsumerWidget {
  const FolderZoomNavButton({
    super.key,
    required this.style,
  });

  final FolderNavBarStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.folderZoomScale),
    );
    final isGrid = isFolderZoomGrid(zoomScale);

    return Builder(
      builder: (btnContext) {
        return FolderNavIconButton(
          style: style,
          tooltip: isGrid ? l10n.gridView : l10n.listView,
          icon: ZoomTierIcon(
            zoomScale: zoomScale,
            size: 20,
            color: style.iconColor,
            shadows: style.shadows,
          ),
          onPressed: () => showFolderZoomPopover(btnContext),
        );
      },
    );
  }
}

class FolderHeaderNavBar extends ConsumerWidget {
  const FolderHeaderNavBar({
    super.key,
    required this.isOverlay,
    required this.scrollProgress,
    this.currentFolder,
    this.navigationHistory = const [],
    this.onGoBack,
    this.onLocateCurrentSong,
    this.onSortPressed,
    this.isSortActive = false,
    this.isSortHighlighted = false,
    this.onClearAllSelection,
    this.scrollController,
    this.onRefresh,
    this.hideBreadcrumbs = false,
    this.onPlayAll,
    this.onShufflePlay,
    this.onSearch,
    this.totalSongsCount = 0,
    this.isSearching = false,
  });

  final bool isOverlay;
  final ValueListenable<double> scrollProgress;
  final MusicFolder? currentFolder;
  final List<MusicFolder> navigationHistory;
  final VoidCallback? onGoBack;
  final VoidCallback? onLocateCurrentSong;
  /// 传 null 表示本页没有独立排序入口（排序并入多选态），
  /// 此时顶栏的排序按钮与菜单里的排序项都不渲染。
  final VoidCallback? onSortPressed;

  /// 排序按钮处于「进行中的模式」（根目录拖拽排序）：图标换成对勾，带底色
  final bool isSortActive;

  /// 当前目录有独立排序覆盖：只给图标着色，不加底色
  final bool isSortHighlighted;
  final VoidCallback? onClearAllSelection;
  final ScrollController? scrollController;
  final VoidCallback? onRefresh;

  /// 顶栏不渲染面包屑（面包屑由页面嵌进 Banner，随内容一起滚动）
  final bool hideBreadcrumbs;

  /// 滚动展开的快捷操作：播放全部
  final VoidCallback? onPlayAll;

  /// 滚动展开的快捷操作：随机播放
  final VoidCallback? onShufflePlay;

  /// 滚动展开的快捷操作：搜索
  final VoidCallback? onSearch;

  /// 当前目录（或根目录）下的歌曲总数
  final int totalSongsCount;

  /// 是否正处于搜索状态
  final bool isSearching;

  bool get _sortHighlighted => isSortActive || isSortHighlighted;

  void _handleLocate(WidgetRef ref, BuildContext context) {
    if (onLocateCurrentSong != null) {
      onLocateCurrentSong!();
    } else {
      SongLocatorHelper.locateCurrentPlayingSong(ref, context);
    }
  }

  List<Widget> _buildBreadcrumbItems(
    BuildContext context,
    WidgetRef ref,
    FolderNavBarStyle style,
    AppLocalizations l10n,
  ) {
    final List<Widget> items = [];

    // Home item
    items.add(
      FolderBreadcrumbItem(
        style: style,
        icon: Icons.home_rounded,
        onTap: () {
          final scanner = ref.read(scannerServiceProvider);
          scanner.setNavigationState(null, []);
          onClearAllSelection?.call();
        },
      ),
    );

    if (currentFolder == null) {
      // Root View breadcrumb
      items.add(FolderBreadcrumbSeparator(style: style));
      items.add(
        FolderBreadcrumbItem(
          style: style,
          label: l10n.scanDirectory,
        ),
      );
    } else {
      // Subfolder View breadcrumbs
      for (int i = 0; i < navigationHistory.length; i++) {
        final folder = navigationHistory[i];
        if (currentFolder != null &&
            ScannerPathUtils.pathsEqual(folder.path, currentFolder!.path)) {
          continue;
        }
        items.add(FolderBreadcrumbSeparator(style: style));
        items.add(
          FolderBreadcrumbItem(
            style: style,
            label: folder.name,
            onTap: () {
              final scanner = ref.read(scannerServiceProvider);
              scanner.setNavigationState(
                folder,
                navigationHistory.take(i).toList(),
              );
              onClearAllSelection?.call();
            },
          ),
        );
      }

      items.add(FolderBreadcrumbSeparator(style: style));
      items.add(
        FolderBreadcrumbItem(
          style: style,
          label: currentFolder!.name,
        ),
      );
    }

    return items;
  }

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref,
    FolderNavBarStyle style,
    AppLocalizations l10n,
  ) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.folderZoomScale),
    );

    final bool showQuickActions = style.progress > 0.15;
    final bool hasPlayableSongs = totalSongsCount > 0 && onPlayAll != null;
    final bool canSearch = onSearch != null;
    final bool hasAnyQuickAction = hasPlayableSongs || canSearch;

    if (style.isPortrait) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FolderScanSpinner(style: style),
          FolderNavActionMenu<String>(
            style: style,
            onSelected: (value) {
              if (value == 'play_all') {
                onPlayAll?.call();
              } else if (value == 'shuffle_play') {
                onShufflePlay?.call();
              } else if (value == 'search') {
                onSearch?.call();
              } else if (value == 'locate') {
                _handleLocate(ref, context);
              } else if (value == 'refresh') {
                onRefresh?.call();
              } else if (value == 'sort') {
                onSortPressed?.call();
              } else if (value == 'view_mode') {
                showFolderZoomPopover(context);
              }
            },
            itemBuilder: (context) => [
              if (showQuickActions && hasAnyQuickAction) ...[
                if (onPlayAll != null)
                  PopupMenuItem(
                    value: 'play_all',
                    enabled: hasPlayableSongs,
                    child: Row(
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: hasPlayableSongs
                              ? null
                              : Theme.of(context).disabledColor,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          l10n.playAll,
                          style: hasPlayableSongs
                              ? null
                              : TextStyle(
                                  color: Theme.of(context).disabledColor,
                                ),
                        ),
                      ],
                    ),
                  ),
                if (onShufflePlay != null)
                  PopupMenuItem(
                    value: 'shuffle_play',
                    enabled: hasPlayableSongs,
                    child: Row(
                      children: [
                        Icon(
                          Icons.shuffle_rounded,
                          size: 20,
                          color: hasPlayableSongs
                              ? null
                              : Theme.of(context).disabledColor,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          l10n.shufflePlay,
                          style: hasPlayableSongs
                              ? null
                              : TextStyle(
                                  color: Theme.of(context).disabledColor,
                                ),
                        ),
                      ],
                    ),
                  ),
                if (canSearch)
                  PopupMenuItem(
                    value: 'search',
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, size: 20),
                        const SizedBox(width: 12),
                        Text(l10n.search),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
              ],
              if (currentMusic != null)
                PopupMenuItem(
                  value: 'locate',
                  child: Row(
                    children: [
                      const Icon(Icons.my_location_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.locateCurrentSong),
                    ],
                  ),
                ),
              if (onRefresh != null)
                PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      const Icon(Icons.refresh_rounded, size: 20),
                      const SizedBox(width: 12),
                      Text(l10n.refresh),
                    ],
                  ),
                ),
              if (onSortPressed != null)
                PopupMenuItem(
                  value: 'sort',
                  child: Row(
                    children: [
                      Icon(
                        isSortActive ? Icons.check_rounded : Icons.sort,
                        size: 20,
                        color: _sortHighlighted
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        l10n.sort,
                        style: _sortHighlighted
                            ? TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'view_mode',
                child: Row(
                  children: [
                    ZoomTierIcon(zoomScale: zoomScale, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      isFolderZoomGrid(zoomScale)
                          ? l10n.gridView
                          : l10n.listView,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerRight,
              child: (showQuickActions && hasAnyQuickAction)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onPlayAll != null)
                          FolderNavIconButton(
                            style: style,
                            tooltip: l10n.playAll,
                            icon: Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                              color: hasPlayableSongs
                                  ? style.iconColor
                                  : style.iconColor.withValues(alpha: 0.35),
                              shadows: hasPlayableSongs ? style.shadows : null,
                            ),
                            onPressed: hasPlayableSongs ? onPlayAll : null,
                          ),
                        if (onShufflePlay != null)
                          FolderNavIconButton(
                            style: style,
                            tooltip: l10n.shufflePlay,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              size: 18,
                              color: hasPlayableSongs
                                  ? style.iconColor
                                  : style.iconColor.withValues(alpha: 0.35),
                              shadows: hasPlayableSongs ? style.shadows : null,
                            ),
                            onPressed: hasPlayableSongs ? onShufflePlay : null,
                          ),
                        if (canSearch)
                          FolderNavIconButton(
                            style: style,
                            tooltip: l10n.search,
                            isSelected: isSearching,
                            icon: Icon(
                              Icons.search_rounded,
                              size: 19,
                              color: isSearching
                                  ? Theme.of(context).colorScheme.primary
                                  : style.iconColor,
                              shadows: isSearching ? null : style.shadows,
                            ),
                            onPressed: onSearch,
                          ),
                        Container(
                          width: 1,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: Theme.of(context)
                              .dividerColor
                              .withValues(alpha: 0.2),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          FolderScanSpinner(style: style),
          if (currentMusic != null) ...[
            LocateSongNavButton(
              style: style,
              tooltip: l10n.locateCurrentSong,
              onPressed: () => _handleLocate(ref, context),
            ),
          ],
          FolderZoomNavButton(style: style),
          if (onSortPressed != null)
            FolderNavIconButton(
              style: style,
              tooltip: l10n.sort,
              isSelected: isSortActive,
              icon: Icon(
                isSortActive ? Icons.check_rounded : Icons.sort,
                size: 20,
                color: _sortHighlighted
                    ? Theme.of(context).colorScheme.primary
                    : style.iconColor,
                shadows: _sortHighlighted ? null : style.shadows,
              ),
              onPressed: onSortPressed!,
            ),
          if (onRefresh != null)
            FolderNavIconButton(
              style: style,
              tooltip: l10n.refresh,
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: style.iconColor,
                shadows: style.shadows,
              ),
              onPressed: onRefresh,
            ),
        ],
      );
    }
  }

  String _getParentTitle(AppLocalizations l10n) {
    if (currentFolder != null) {
      if (navigationHistory.isNotEmpty) {
        return navigationHistory.last.name;
      }
      return l10n.scanDirectory;
    }
    return l10n.scanDirectory;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return FolderNavBarScaffold(
      isOverlay: isOverlay,
      scrollProgress: scrollProgress,
      parentTitle: _getParentTitle(l10n),
      onGoBack: onGoBack,
      scrollController: scrollController,
      hideBreadcrumbs: hideBreadcrumbs,
      breadcrumbItemsBuilder: (context, style) =>
          _buildBreadcrumbItems(context, ref, style, l10n),
      actionsBuilder: (context, style) =>
          _buildActions(context, ref, style, l10n),
    );
  }
}
