import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'folder_layout_utils.dart';
import 'folder_zoom_tier_icon.dart';

/// 使用方通常同时需要弹窗与记忆域枚举、档位微型指示器，这里一并导出。
export 'package:vynody/player/settings/settings_service.dart'
    show LibraryZoomScope;
export 'folder_zoom_tier_icon.dart';

/// 视图片档位弹窗 / 按钮的共享实现。
///
/// 目录页、专辑页、专辑详情页共用同一套七档体系，只是各自记忆在不同的
/// [LibraryZoomScope] 里。凡是"按档位缩放条目"的页面都从这里取控件，
/// 不要再各自抄一份弹窗。
/// 早于本文件时该弹窗是 `folder_header_nav_bar.dart` 里的私有实现，
/// 那里现在只是转调。

/// 档位对应的备用图标（若无法使用 [FolderZoomTierIcon] 控件时降级使用）。
IconData getFolderZoomTierIcon(double zoomScale) {
  return switch (getFolderZoomTier(zoomScale)) {
    FolderZoomTier.minimalList => Icons.view_headline_rounded,
    FolderZoomTier.compactList => Icons.view_list_rounded,
    FolderZoomTier.standardList => Icons.table_rows_rounded,
    FolderZoomTier.largeList => Icons.view_agenda_rounded,
    FolderZoomTier.smallGrid => Icons.grid_on_rounded,
    FolderZoomTier.mediumGrid => Icons.grid_view_rounded,
    FolderZoomTier.largeGrid => Icons.view_module_rounded,
  };
}

/// 档位的本地化短名（列表四档 + 网格三档）。
String _tierLabel(AppLocalizations l10n, FolderZoomTier tier) {
  return switch (tier) {
    FolderZoomTier.minimalList => '极简',
    FolderZoomTier.compactList => '紧凑',
    FolderZoomTier.standardList => '标准',
    FolderZoomTier.largeList => '大图',
    FolderZoomTier.smallGrid => '小',
    FolderZoomTier.mediumGrid => '中',
    FolderZoomTier.largeGrid => '大',
  };
}

/// 在 [anchorContext] 所在控件下方弹出档位调节卡片。
///
/// [scope] 决定读写哪一份档位记忆；卡片本身只认档位值，不认页面。
Future<void> showLibraryZoomPopover(
  BuildContext anchorContext, {
  required LibraryZoomScope scope,
}) async {
  final renderBox = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.maybeOf(anchorContext)?.context.findRenderObject() as RenderBox?;

  double topOffset = MediaQuery.paddingOf(anchorContext).top + 56.0;
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
            child: LibraryZoomPopoverCard(scope: scope),
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

/// 滑杆 + 七档预设按钮的档位调节卡片。
class LibraryZoomPopoverCard extends ConsumerWidget {
  const LibraryZoomPopoverCard({super.key, required this.scope});

  final LibraryZoomScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.zoomScaleFor(scope)),
    );
    final settings = ref.read(settingsServiceProvider);
    final tier = getFolderZoomTier(zoomScale);
    final isListOnly = scope == LibraryZoomScope.queue;
    final isGrid = !isListOnly && isFolderZoomGrid(zoomScale);

    final modeLabel = isGrid ? l10n.gridView : l10n.listView;
    final tierName = _tierLabel(l10n, tier);

    final maxScale = isListOnly ? kFolderZoomTierLargeList : 1.0;
    final divisions = isListOnly ? 3 : (kFolderZoomTierValues.length - 1);

    void setScale(double value) => settings.setZoomScale(scope, value);

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: AppBlur.mediumFilter,
          child: Container(
            width: 292,
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
                    FolderZoomTierIcon(
                      zoomScale: zoomScale,
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
                          ? () => setScale(stepFolderZoomScale(zoomScale, -1))
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
                          value: snapFolderZoomScale(zoomScale)
                              .clamp(0.0, maxScale),
                          min: 0.0,
                          max: maxScale,
                          divisions: divisions,
                          onChanged: (val) =>
                              setScale(snapFolderZoomScale(val)),
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
                      onPressed: zoomScale < (maxScale - 0.001)
                          ? () => setScale(stepFolderZoomScale(zoomScale, 1))
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.minimalList,
                      tooltip: '${l10n.listView} · 极简',
                      isSelected: tier == FolderZoomTier.minimalList,
                      horizontalPadding: isListOnly ? 16 : 9,
                      onTap: () => setScale(kFolderZoomTierMinimalList),
                    ),
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.compactList,
                      tooltip: '${l10n.listView} · 紧凑',
                      isSelected: tier == FolderZoomTier.compactList,
                      horizontalPadding: isListOnly ? 16 : 9,
                      onTap: () => setScale(kFolderZoomTierCompactList),
                    ),
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.standardList,
                      tooltip: '${l10n.listView} · 标准',
                      isSelected: tier == FolderZoomTier.standardList,
                      horizontalPadding: isListOnly ? 16 : 9,
                      onTap: () => setScale(kFolderZoomTierStandardList),
                    ),
                    _ZoomTierPresetButton(
                      tier: FolderZoomTier.largeList,
                      tooltip: '${l10n.listView} · 大图',
                      isSelected: tier == FolderZoomTier.largeList,
                      horizontalPadding: isListOnly ? 16 : 9,
                      onTap: () => setScale(kFolderZoomTierLargeList),
                    ),
                    if (!isListOnly) ...[
                      Container(
                        width: 1,
                        height: 18,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                      _ZoomTierPresetButton(
                        tier: FolderZoomTier.smallGrid,
                        tooltip: '${l10n.gridView} · 小',
                        isSelected: tier == FolderZoomTier.smallGrid,
                        onTap: () => setScale(kFolderZoomTierSmallGrid),
                      ),
                      _ZoomTierPresetButton(
                        tier: FolderZoomTier.mediumGrid,
                        tooltip: '${l10n.gridView} · 中',
                        isSelected: tier == FolderZoomTier.mediumGrid,
                        onTap: () => setScale(kFolderZoomTierMediumGrid),
                      ),
                      _ZoomTierPresetButton(
                        tier: FolderZoomTier.largeGrid,
                        tooltip: '${l10n.gridView} · 大',
                        isSelected: tier == FolderZoomTier.largeGrid,
                        onTap: () => setScale(kFolderZoomTierLargeGrid),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.mouse_rounded,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.75),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ctrl + 滚轮，或双指捏合，可逐档调节',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.75),
                        ),
                      ),
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
    required this.tier,
    required this.isSelected,
    required this.onTap,
    this.tooltip,
    this.horizontalPadding = 9.0,
  });

  final FolderZoomTier tier;
  final bool isSelected;
  final VoidCallback onTap;
  final String? tooltip;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 6),
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
        child: FolderZoomTierIcon(
          tier: tier,
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

/// 通用档位按钮：工具栏与顶栏都能直接放。
///
/// 图标随档位实时变化，点击在自身下方弹出 [LibraryZoomPopoverCard]。
class LibraryZoomButton extends ConsumerWidget {
  const LibraryZoomButton({
    super.key,
    required this.scope,
    this.iconSize = 24.0,
    this.color,
    this.visualDensity,
  });

  final LibraryZoomScope scope;
  final double iconSize;
  final Color? color;
  final VisualDensity? visualDensity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.zoomScaleFor(scope)),
    );

    final isListOnly = scope == LibraryZoomScope.queue;
    final tooltipText = isListOnly
        ? l10n.listView
        : (isFolderZoomGrid(zoomScale) ? l10n.gridView : l10n.listView);

    return Builder(
      builder: (btnContext) {
        return IconButton(
          tooltip: tooltipText,
          visualDensity: visualDensity,
          onPressed: () => showLibraryZoomPopover(btnContext, scope: scope),
          icon: FolderZoomTierIcon(
            zoomScale: zoomScale,
            size: iconSize,
            color: color,
          ),
        );
      },
    );
  }
}
