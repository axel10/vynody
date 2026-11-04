import 'package:flutter/material.dart';

/// 媒体库二级页页头（`LibraryCategoryHeader`、`LibraryLargeTitle`、
/// `LibraryInsightList` 自带页头）内所有图标按钮尺寸的**唯一入口**。
///
/// 此前返回键与右侧动作按钮各自 new `IconButton`、各自设 `constraints` 与
/// `visualDensity`，同一个 Row 里于是出现 28×28（返回）与 48×48（播放全部）
/// 的错位：返回图标还大 4px，按钮盒却小一圈，视觉上像被缩了一档。
///
/// 之后所有尺寸调整只改本类，不要再往调用点写死数值；新增页头动作按钮一律
/// 走 [libraryToolbarIconButton]。
abstract final class LibraryToolbarMetrics {
  /// 按钮盒边长，同时也是最小命中区。
  ///
  /// 返回键必须与右侧动作按钮同高，否则同一行会出现肉眼可见的高低差。
  static const double buttonSize = 40.0;

  /// 常规动作图标尺寸（播放全部、随机、排序、来源筛选、缩放…）。
  static const double iconSize = 24.0;

  /// 返回箭头图标尺寸。
  ///
  /// `chevron_left_rounded` 是细笔画折线，与 24 的实心 `play_arrow_rounded`
  /// 并排时视觉重量明显偏轻，故比常规图标放大 4px 作补偿；按钮盒仍按
  /// [buttonSize] 走，不再用 `VisualDensity.compact` 把命中区吃掉。
  static const double backIconSize = 28.0;

  /// 返回键与标题之间的横向间距。
  ///
  /// 按钮盒回到 48 之后自带足够留白，这里的间距只负责贴住大标题，4 已足够。
  static const double backTitleSpacing = 4.0;
}

/// 按 [LibraryToolbarMetrics] 生成统一的页头动作按钮。
///
/// [wrapIcon] 用于给图标套外壳（例如来源筛选的 `Badge`），外壳内部的图标
/// 仍由本函数按 [LibraryToolbarMetrics.iconSize] 定尺寸，不要在外面再写一次。
IconButton libraryToolbarIconButton({
  Key? key,
  required IconData icon,
  String? tooltip,
  VoidCallback? onPressed,
  double iconSize = LibraryToolbarMetrics.iconSize,
  Color? color,
  Widget Function(Widget icon)? wrapIcon,
}) {
  Widget iconWidget = Icon(icon, size: iconSize, color: color);
  if (wrapIcon != null) {
    iconWidget = wrapIcon(iconWidget);
  }
  return IconButton(
    key: key,
    tooltip: tooltip,
    onPressed: onPressed,
    padding: EdgeInsets.zero,
    // 显式钉住 standard，避免主题级 visualDensity 把按钮盒再吃掉一档。
    visualDensity: VisualDensity.standard,
    constraints: const BoxConstraints(
      minWidth: LibraryToolbarMetrics.buttonSize,
      minHeight: LibraryToolbarMetrics.buttonSize,
    ),
    icon: iconWidget,
  );
}
