import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/utils/blur_constants.dart';
import 'folder_layout_utils.dart';

/// 使用方通常同时需要弹窗与记忆域枚举、档位微型指示器，这里一并导出。
export 'package:vynody/player/settings/settings_service.dart'
    show LibraryZoomScope;

/// 视图片档位弹窗 / 按钮的共享实现。
///
/// 目录页、专辑页、专辑详情页共用同一套七档体系，只是各自记忆在不同的
/// [LibraryZoomScope] 里。凡是"按档位缩放条目"的页面都从这里取控件，
/// 不要再各自抄一份弹窗。
/// 早于本文件时该弹窗是 `folder_header_nav_bar.dart` 里的私有实现，
/// 那里现在只是转调。

/// 档位对应的备用图标（若无法使用 [ZoomTierIcon] 控件时降级使用）。
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

/// 视图模式图标：混合视图时展示拼贴图标，其余情况展示七档 [ZoomTierIcon]。
class LibraryZoomModeIcon extends StatelessWidget {
  const LibraryZoomModeIcon({
    super.key,
    required this.zoomScale,
    this.isHybrid = false,
    this.size = 20.0,
    this.color,
    this.shadows,
  });

  final double zoomScale;
  final bool isHybrid;
  final double size;
  final Color? color;
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    if (isHybrid) {
      return Icon(
        Icons.view_quilt_rounded,
        size: size,
        color: color,
        shadows: shadows,
      );
    }
    return ZoomTierIcon(
      zoomScale: zoomScale,
      size: size,
      color: color,
      shadows: shadows,
    );
  }
}

/// 视图模式展示文案：混合视图 / 网格视图 / 列表视图。
String libraryZoomModeLabel(
  AppLocalizations l10n,
  double zoomScale, {
  bool isHybrid = false,
}) {
  if (isHybrid) return l10n.hybridView;
  return isFolderZoomGrid(zoomScale) ? l10n.gridView : l10n.listView;
}

/// 档位的本地化短名（列表四档 + 网格三档）。
String _tierLabel(AppLocalizations l10n, FolderZoomTier tier) {
  return switch (tier) {
    FolderZoomTier.minimalList => l10n.zoomTierMinimal,
    FolderZoomTier.compactList => l10n.zoomTierCompact,
    FolderZoomTier.standardList => l10n.zoomTierStandard,
    FolderZoomTier.largeList => l10n.zoomTierLargeList,
    FolderZoomTier.smallGrid => l10n.zoomTierSmallGrid,
    FolderZoomTier.mediumGrid => l10n.zoomTierMediumGrid,
    FolderZoomTier.largeGrid => l10n.zoomTierLargeGrid,
  };
}

/// 预设按钮的悬浮文案：「列表视图 · 标准」这种。
String _tierTooltip(AppLocalizations l10n, double tierValue) {
  final tier = getFolderZoomTier(tierValue);
  final mode = tier.isGrid ? l10n.gridView : l10n.listView;
  return '$mode · ${_tierLabel(l10n, tier)}';
}

/// 预设按钮之间那条竖线只画在「列表段 / 网格段」交界处。
///
/// 只允许一种形态的记忆域（队列只有列表、专辑只有网格）里两段不可能同时存在，
/// 因此不画线，按钮自然均分整行。
bool _needsTierDividerBefore(double tierValue, List<double> allowedTiers) =>
    tierValue == kFolderZoomTierSmallGrid &&
    allowedTiers.any((tier) => tier < kFolderZoomTierSmallGrid);

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
    final isHybrid = ref.watch(
      settingsServiceProvider.select((s) => s.isHybridViewFor(scope)),
    );
    final settings = ref.read(settingsServiceProvider);
    final tier = getFolderZoomTier(zoomScale);

    final modeLabel = libraryZoomModeLabel(l10n, zoomScale, isHybrid: isHybrid);
    final tierName = _tierLabel(l10n, tier);
    final supportsHybrid = scope == LibraryZoomScope.folder;

    // 可用档位由记忆域决定（队列只有列表四档、专辑只有网格三档），
    // 滑杆区间、刻度数与预设按钮全部从这一份派生，不再各自判断 scope。
    final allowedTiers = scope.allowedZoomTiers;
    final minScale = scope.minZoomTier;
    final maxScale = scope.maxZoomTier;
    final divisions = allowedTiers.length > 1 ? allowedTiers.length - 1 : 1;
    final compactPresets = allowedTiers.length > 4;

    void setScale(double value) => settings.setZoomScale(scope, value);

    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AppBackdropFilter(
          filter: AppBlur.mediumFilter,
          child: Container(
            width: 292,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppBlur.dialogSurface(
                context,
                isBlurEnabled: ref.watch(isBlurEffectEnabledProvider),
              ),
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
                    LibraryZoomModeIcon(
                      zoomScale: zoomScale,
                      isHybrid: isHybrid,
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
                    if (!isHybrid)
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
                IgnorePointer(
                  ignoring: isHybrid,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 160),
                    opacity: isHybrid ? 0.42 : 1.0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                              onPressed: !isHybrid && zoomScale > minScale + 0.001
                                  ? () => setScale(
                                      stepFolderZoomScale(zoomScale, -1))
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
                                  value: zoomScale.clamp(minScale, maxScale),
                                  min: minScale,
                                  max: maxScale,
                                  divisions: divisions,
                                  onChanged: isHybrid
                                      ? null
                                      : (val) =>
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
                              onPressed: !isHybrid && zoomScale < (maxScale - 0.001)
                                  ? () => setScale(
                                      stepFolderZoomScale(zoomScale, 1))
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final tierValue in allowedTiers) ...[
                              if (_needsTierDividerBefore(
                                  tierValue, allowedTiers))
                                Container(
                                  width: 1,
                                  height: 18,
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 2),
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              _ZoomTierPresetButton(
                                tier: getFolderZoomTier(tierValue),
                                tooltip: _tierTooltip(l10n, tierValue),
                                isSelected: !isHybrid &&
                                    tier == getFolderZoomTier(tierValue),
                                horizontalPadding: compactPresets ? 9 : 16,
                                onTap: () => setScale(tierValue),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (supportsHybrid) ...[
                  const SizedBox(height: 8),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 6),
                  _HybridViewToggleRow(
                    label: l10n.hybridView,
                    value: isHybrid,
                    onChanged: (val) => settings.setHybridViewFor(scope, val),
                  ),
                ],
                if (!isHybrid) ...[
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
                          l10n.zoomTierShortcutHint(zoomModifierKeyLabel),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
        child: ZoomTierIcon(
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

class _HybridViewToggleRow extends StatelessWidget {
  const _HybridViewToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.view_quilt_rounded,
              size: 16,
              color: value
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                  color: value
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (checked) => onChanged(checked ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
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
    this.buttonSize,
  });

  final LibraryZoomScope scope;
  final double iconSize;
  final Color? color;
  final VisualDensity? visualDensity;

  /// 统一顶部动作行传入 [LibraryToolbarMetrics.buttonSize]，让档位按钮与同行的
  /// 播放 / 排序按钮一样高（默认 null 时沿用 IconButton 原生 48，保持其它页原样）。
  final double? buttonSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final zoomScale = ref.watch(
      settingsServiceProvider.select((s) => s.zoomScaleFor(scope)),
    );
    final isHybrid = ref.watch(
      settingsServiceProvider.select((s) => s.isHybridViewFor(scope)),
    );

    final tooltipText = libraryZoomModeLabel(
      l10n,
      zoomScale,
      isHybrid: isHybrid,
    );

    return Builder(
      builder: (btnContext) {
        return IconButton(
          tooltip: tooltipText,
          visualDensity: visualDensity,
          padding: buttonSize == null ? null : EdgeInsets.zero,
          constraints: buttonSize == null
              ? null
              : BoxConstraints(
                  minWidth: buttonSize!,
                  minHeight: buttonSize!,
                ),
          onPressed: () => showLibraryZoomPopover(btnContext, scope: scope),
          icon: LibraryZoomModeIcon(
            zoomScale: zoomScale,
            isHybrid: isHybrid,
            size: iconSize,
            color: color,
          ),
        );
      },
    );
  }
}
