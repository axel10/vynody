import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'package:vynody/utils/song_locator_helper.dart';
import 'folder_layout_utils.dart';
import 'folder_nav_bar_scaffold.dart';
import 'folder_scan_widgets.dart';
import 'locate_song_button.dart';
export 'folder_nav_bar_scaffold.dart';

/// Returns the icon corresponding to the current [zoomScale] tier.
IconData getFolderZoomTierIcon(double zoomScale) {
  return switch (getFolderZoomTier(zoomScale)) {
    FolderZoomTier.compactList => Icons.density_small_rounded,
    FolderZoomTier.standardList => Icons.density_medium_rounded,
    FolderZoomTier.largeList => Icons.density_large_rounded,
    FolderZoomTier.smallGrid => Icons.grid_on_rounded,
    FolderZoomTier.mediumGrid => Icons.grid_view_rounded,
    FolderZoomTier.largeGrid => Icons.view_module_rounded,
  };
}

/// Shows a floating popover below the top navigation bar with a live zoom slider
/// and discrete tier presets.
Future<void> showFolderZoomPopover(BuildContext anchorContext) async {
  final renderBox = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.maybeOf(anchorContext)?.context.findRenderObject() as RenderBox?;

  double topOffset = FolderNavBarScaffold.getBarHeight(anchorContext) + 6.0;
  double rightOffset = 16.0;

  if (renderBox != null && overlay != null && renderBox.hasSize) {
    final globalPos = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
    topOffset = globalPos.dy + renderBox.size.height + 6.0;
    final calculatedRight =
        overlay.size.width - (globalPos.dx + renderBox.size.width);
    rightOffset = calculatedRight.clamp(12.0, overlay.size.width - 280.0);
  }

  await showGeneralDialog<void>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(anchorContext).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned(
            top: topOffset,
            right: rightOffset,
            child: _FolderZoomPopoverCard(),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

class _FolderZoomPopoverCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;
    final tier = getFolderZoomTier(zoomScale);
    final isGrid = isFolderZoomGrid(zoomScale);

    final modeLabel = isGrid ? l10n.gridView : l10n.listView;
    final tierName = switch (tier) {
      FolderZoomTier.compactList => '紧凑',
      FolderZoomTier.standardList => '标准',
      FolderZoomTier.largeList => '大图',
      FolderZoomTier.smallGrid => '小',
      FolderZoomTier.mediumGrid => '中',
      FolderZoomTier.largeGrid => '大',
    };

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: AppBlur.mediumFilter,
          child: Container(
            width: 276,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh
                  .withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      getFolderZoomTierIcon(zoomScale),
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        modeLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tierName,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.remove_rounded, size: 18),
                      onPressed: zoomScale > 0.001
                          ? () {
                              settings.folderZoomScale =
                                  stepFolderZoomScale(zoomScale, -1);
                            }
                          : null,
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 14,
                          ),
                        ),
                        child: Slider(
                          value: snapFolderZoomScale(zoomScale),
                          min: 0.0,
                          max: 1.0,
                          divisions: 5,
                          onChanged: (val) {
                            settings.folderZoomScale = snapFolderZoomScale(val);
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: zoomScale < 0.999
                          ? () {
                              settings.folderZoomScale =
                                  stepFolderZoomScale(zoomScale, 1);
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ZoomTierPresetButton(
                      icon: Icons.density_small_rounded,
                      tooltip: '${l10n.listView} · 紧凑',
                      isSelected: tier == FolderZoomTier.compactList,
                      onTap: () => settings.folderZoomScale =
                          kFolderZoomTierCompactList,
                    ),
                    _ZoomTierPresetButton(
                      icon: Icons.density_medium_rounded,
                      tooltip: '${l10n.listView} · 标准',
                      isSelected: tier == FolderZoomTier.standardList,
                      onTap: () => settings.folderZoomScale =
                          kFolderZoomTierStandardList,
                    ),
                    _ZoomTierPresetButton(
                      icon: Icons.density_large_rounded,
                      tooltip: '${l10n.listView} · 大图',
                      isSelected: tier == FolderZoomTier.largeList,
                      onTap: () => settings.folderZoomScale =
                          kFolderZoomTierLargeList,
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                    _ZoomTierPresetButton(
                      icon: Icons.grid_on_rounded,
                      tooltip: '${l10n.gridView} · 小',
                      isSelected: tier == FolderZoomTier.smallGrid,
                      onTap: () => settings.folderZoomScale =
                          kFolderZoomTierSmallGrid,
                    ),
                    _ZoomTierPresetButton(
                      icon: Icons.grid_view_rounded,
                      tooltip: '${l10n.gridView} · 中',
                      isSelected: tier == FolderZoomTier.mediumGrid,
                      onTap: () => settings.folderZoomScale =
                          kFolderZoomTierMediumGrid,
                    ),
                    _ZoomTierPresetButton(
                      icon: Icons.view_module_rounded,
                      tooltip: '${l10n.gridView} · 大',
                      isSelected: tier == FolderZoomTier.largeGrid,
                      onTap: () => settings.folderZoomScale =
                          kFolderZoomTierLargeGrid,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomTierPresetButton extends StatelessWidget {
  const _ZoomTierPresetButton({
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

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
          icon: Icon(
            getFolderZoomTierIcon(zoomScale),
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
    required this.onSortPressed,
    this.isSortActive = false,
    this.isSortHighlighted = false,
    this.onClearAllSelection,
    this.scrollController,
    this.onRefresh,
  });

  final bool isOverlay;
  final ValueListenable<double> scrollProgress;
  final MusicFolder? currentFolder;
  final List<MusicFolder> navigationHistory;
  final VoidCallback? onGoBack;
  final VoidCallback? onLocateCurrentSong;
  final VoidCallback onSortPressed;

  /// 排序按钮处于「进行中的模式」（根目录拖拽排序）：图标换成对勾，带底色
  final bool isSortActive;

  /// 当前目录有独立排序覆盖：只给图标着色，不加底色
  final bool isSortHighlighted;
  final VoidCallback? onClearAllSelection;
  final ScrollController? scrollController;
  final VoidCallback? onRefresh;

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

    if (style.isPortrait) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FolderScanSpinner(style: style),
          FolderZoomNavButton(style: style),
          FolderNavActionMenu<String>(
            style: style,
            onSelected: (value) {
              if (value == 'locate') {
                _handleLocate(ref, context);
              } else if (value == 'refresh') {
                onRefresh?.call();
              } else if (value == 'sort') {
                onSortPressed();
              } else if (value == 'view_mode') {
                showFolderZoomPopover(context);
              }
            },
            itemBuilder: (context) => [
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
                    Icon(getFolderZoomTierIcon(zoomScale), size: 20),
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
          FolderScanSpinner(style: style),
          if (currentMusic != null) ...[
            LocateSongNavButton(
              style: style,
              tooltip: l10n.locateCurrentSong,
              onPressed: () => _handleLocate(ref, context),
            ),
          ],
          FolderZoomNavButton(style: style),
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
            onPressed: onSortPressed,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return FolderNavBarScaffold(
      isOverlay: isOverlay,
      scrollProgress: scrollProgress,
      onGoBack: onGoBack,
      scrollController: scrollController,
      breadcrumbItemsBuilder: (context, style) =>
          _buildBreadcrumbItems(context, ref, style, l10n),
      actionsBuilder: (context, style) =>
          _buildActions(context, ref, style, l10n),
    );
  }
}
