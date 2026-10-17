import 'package:flutter/material.dart';

/// 图标底色配色（对齐 macOS 系统设置的观感）。
///
/// 与 Material 那套高饱和调色板（`#EF4444` / `#F59E0B` / `#8B5CF6`）相比，
/// 这里把饱和度整体压下来、明度收敛到中间调，并让每个色只有很小的明度落差，
/// 因此并排出现时不会有明显的双色渐变，也不会互相抢眼。
///
/// 只用于「带图标的圆角色块」这一种组件：设置页入口、媒体库首页快捷入口。
abstract final class AppIconPalette {
  /// 蓝（网络 / 显示 / 相册）
  static const List<Color> blue = [Color(0xFF4A85D6), Color(0xFF3B72C4)];

  /// 绿（能耗 / 最近添加 / 转码）
  static const List<Color> green = [Color(0xFF5FA960), Color(0xFF4E9250)];

  /// 红（通知 / 高频播放）
  static const List<Color> red = [Color(0xFFCF6A6E), Color(0xFFB9575C)];

  /// 琥珀金（标签 / 评分）
  static const List<Color> amber = [Color(0xFFC69B55), Color(0xFFB08542)];

  /// 靛蓝（播放列表 / 快捷键）
  static const List<Color> indigo = [Color(0xFF6E7CC4), Color(0xFF5B69B0)];

  /// 紫（流派 / 歌词）
  static const List<Color> violet = [Color(0xFF8471C4), Color(0xFF6F5CAE)];

  /// 青（最近播放 / 声学指纹）
  static const List<Color> teal = [Color(0xFF4E9BAE), Color(0xFF3F8698)];

  /// 橙（艺术家 / 存储）
  static const List<Color> orange = [Color(0xFFC8825C), Color(0xFFB16E4A)];

  /// 玫红（音频 / 声音）
  static const List<Color> rose = [Color(0xFFCB7287), Color(0xFFB35E73)];

  /// 天蓝（年份 / 窗口）
  static const List<Color> sky = [Color(0xFF5896B8), Color(0xFF47839F)];

  /// 中性灰（通用设置）
  static const List<Color> gray = [Color(0xFF8C9099), Color(0xFF797D86)];

  /// 深板岩（关于 / 年份这类不需要强调的入口）
  static const List<Color> slate = [Color(0xFF6C7480), Color(0xFF5A626D)];

  /// 图标色块统一投影。
  ///
  /// macOS 不使用彩色光晕，这里只留一层极淡的落影交代厚度，
  /// 避免色块浮在卡片上时显得发飘。
  static List<BoxShadow> shadowOf(List<Color> gradient) {
    return [
      BoxShadow(
        color: gradient.first.withValues(alpha: 0.16),
        blurRadius: 5,
        offset: const Offset(0, 1),
      ),
    ];
  }
}
