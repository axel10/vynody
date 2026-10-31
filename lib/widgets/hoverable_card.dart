/// 网格卡片的统一悬停反馈：指针进入时轻微放大。
///
/// 实现已随条目脚手架并入 `zoomable_sliver_grid`（与 `ZoomItemCover` 同库），
/// 这里只做转出：全项目必须共用同一个 `HoverableCard`，否则同时 import
/// 本文件与 `folder_layout_utils.dart` 的页面会撞成 ambiguous import。
library;

export 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart'
    show HoverableCard;
