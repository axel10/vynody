import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/utils/app_orientation_manager.dart';

/// 多选面板中的单个操作动作项。
class SelectionActionItem {
  final IconData icon;
  final String label;

  /// 宽度受限时的短标签（例如「添加到播放列表」简写为「播放列表」）。
  final String? shortLabel;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final bool isDestructive;

  const SelectionActionItem({
    required this.icon,
    required this.label,
    this.shortLabel,
    required this.onPressed,
    this.iconColor,
    this.isDestructive = false,
  });

  bool get isEnabled => onPressed != null;
}

/// 通用多选浮动操作面板。
///
/// 具备标准视觉外壳（居中浮动卡片、圆角、阴影、安全区适配、横竖屏自适应约束），
/// 头部包含标题（或已选数量统计）与关闭按钮；内容区接收一组 [SelectionActionItem]
/// 并以网格流式排布，多于 2 行时自动支持滚动。
class GenericSelectionPanel extends StatefulWidget {
  const GenericSelectionPanel({
    super.key,
    required this.title,
    required this.onCancel,
    required this.actions,
    this.columns,
  });

  /// 面板顶部标题（通常显示已选数量，如「已选 3 首」或「多选 · 1 / 5」）。
  final String title;

  /// 取消/退出多选的回调。
  final VoidCallback onCancel;

  /// 操作按钮列表。
  final List<SelectionActionItem> actions;

  /// 每行显示的列数。不传时默认按 4 列网格排布，不足 4 列时末尾留空。
  final int? columns;

  @override
  State<GenericSelectionPanel> createState() => _GenericSelectionPanelState();
}

class _GenericSelectionPanelState extends State<GenericSelectionPanel> {
  final ScrollController _scrollController = ScrollController();

  static const double _singleRowHeight = 58.0;
  static const double _rowSpacing = 8.0;
  static const double _maxVisibleRows = 2.0;
  static const double _maxActionAreaHeight =
      (_singleRowHeight * _maxVisibleRows) +
      (_rowSpacing * (_maxVisibleRows - 1));

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isTablet = MediaQuery.sizeOf(context).shortestSide >=
        AppOrientationManager.tabletShortestSideBreakpoint;
    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;

    final isPhonePortrait = !isLandscape && !isTablet && !isDesktop;
    final double maxPanelWidth = isPhonePortrait ? 372.0 : 620.0;

    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    final double safeBottom;
    if (isTablet) {
      safeBottom = bottomPadding > 0 ? (bottomPadding + 8.0) : 28.0;
    } else if (isIOS) {
      safeBottom = bottomPadding > 0
          ? (bottomPadding - 14.0).clamp(12.0, double.infinity)
          : 12.0;
    } else {
      safeBottom = bottomPadding > 0 ? bottomPadding : 12.0;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final double effectivePanelWidth =
            (parentWidth - 32.0).clamp(0.0, maxPanelWidth);
        // 卡片内部横向可用宽度（减去左右 padding 14 + 8 = 22）
        final double contentWidth = effectivePanelWidth - 22.0;

        // 手机竖屏固定 4 列；宽屏（横屏/平板/桌面）且内容宽度充足时显示 5 列
        final bool canFitFive = !isPhonePortrait && contentWidth >= 400.0;
        final int columnCount = widget.columns ??
            ((canFitFive && widget.actions.length >= 5) ? 5 : 4);
        final double colSpacing = columnCount >= 5 ? 6.0 : 8.0;

        final actionRows = <Widget>[];
        for (var i = 0; i < widget.actions.length; i += columnCount) {
          final chunk = widget.actions.sublist(
            i,
            i + columnCount > widget.actions.length
                ? widget.actions.length
                : i + columnCount,
          );

          final rowChildren = <Widget>[];
          for (var col = 0; col < columnCount; col++) {
            if (col > 0) {
              rowChildren.add(SizedBox(width: colSpacing));
            }
            if (col < chunk.length) {
              rowChildren.add(
                Expanded(
                  child: _buildActionButton(context, chunk[col]),
                ),
              );
            } else {
              rowChildren.add(const Expanded(child: SizedBox.shrink()));
            }
          }

          actionRows.add(Row(children: rowChildren));
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, safeBottom),
          child: SafeArea(
            top: false,
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxPanelWidth),
                child: Material(
                  elevation: 16,
                  color: theme.colorScheme.surface,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(24),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 8, 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row
                        Row(
                          children: [
                            const SizedBox(width: 6),
                            Text(
                              widget.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(6),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: widget.onCancel,
                              tooltip: l10n.cancel,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: _maxActionAreaHeight,
                          ),
                          child: Scrollbar(
                            controller: _scrollController,
                            thumbVisibility: actionRows.length > 2,
                            child: SingleChildScrollView(
                              controller: _scrollController,
                              physics: actionRows.length > 2
                                  ? const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    )
                                  : const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.only(
                                right: actionRows.length > 2 ? 6.0 : 0.0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < actionRows.length; i++) ...[
                                    if (i > 0) const SizedBox(height: _rowSpacing),
                                    actionRows[i],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton(BuildContext context, SelectionActionItem action) {
    final theme = Theme.of(context);
    final isEnabled = action.isEnabled;
    final effectiveIconColor = action.iconColor ??
        (action.isDestructive
            ? theme.colorScheme.error
            : theme.colorScheme.onSurface);

    return SizedBox(
      height: _singleRowHeight,
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.38,
        child: LayoutBuilder(
          builder: (context, constraints) {
            String label = action.label;
            if (action.shortLabel != null && constraints.maxWidth > 0) {
              final textScaler = MediaQuery.textScalerOf(context);
              const textStyle = TextStyle(fontSize: 12);
              final painter = TextPainter(
                text: TextSpan(text: action.label, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: textScaler,
                maxLines: 1,
              )..layout();

              // TextButton 内部 padding 为 horizontal: 4 (合计 8)，外加 2 像素缓冲
              if (painter.width > constraints.maxWidth - 10.0) {
                label = action.shortLabel!;
              }
            }

            return TextButton(
              onPressed: action.onPressed,
              style: TextButton.styleFrom(
                foregroundColor: action.isDestructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(action.icon, size: 22, color: effectiveIconColor),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
