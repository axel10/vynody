import 'package:flutter/material.dart';

/// 应用的中性色（surface 体系）。
///
/// 用户的主题色只应决定 primary。若把主题色当种子交给 `ColorScheme.fromSeed`，
/// 它会把种子色混进整套中性色里：默认初音绿 `#39C5BB` 下，亮色 surface 是
/// `#F4FBF9`（偏青绿而非纯白），`surfaceContainerHighest` 是 `#DDE4E2`
/// （白底上的卡片泛灰绿），暗色卡片 `#2F3635` 同样偏青。
///
/// 这里把中性色钉成固定灰阶：亮色纯白底、暗色 `#0C0C0C` 近黑底，
/// 种子色只留在 primary / secondary 上。
@immutable
class AppSurfacePalette {
  const AppSurfacePalette({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
  });

  /// 页面底色（Scaffold）。
  final Color surface;
  final Color surfaceDim;
  final Color surfaceBright;

  /// 各类容器层级，从最浅（页面之上浮起的卡片）到最深。
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;

  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;

  /// 暗色底：`#0C0C0C`，接近纯黑的深灰。
  ///
  /// 底色压到这么低之后，容器层级只能往上叠：lowest 与页面底同色，
  /// 往上每档 +6~+8，保证相邻层级在近黑背景上肉眼可辨。
  static const AppSurfacePalette dark = AppSurfacePalette(
    surface: Color(0xFF0C0C0C),
    surfaceDim: Color(0xFF080808),
    surfaceBright: Color(0xFF313131),
    surfaceContainerLowest: Color(0xFF0C0C0C),
    surfaceContainerLow: Color(0xFF141414),
    surfaceContainer: Color(0xFF1A1A1A),
    surfaceContainerHigh: Color(0xFF212121),
    surfaceContainerHighest: Color(0xFF282828),
    onSurface: Color(0xFFE9E9E9),
    onSurfaceVariant: Color(0xFF9E9EA3),
    outline: Color(0xFF7A7A7E),
    outlineVariant: Color(0xFF2E2E31),
  );

  /// 亮色底：纯白 `#FFFFFF`。
  static const AppSurfacePalette light = AppSurfacePalette(
    surface: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFDCDCDE),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F8),
    surfaceContainer: Color(0xFFF1F1F3),
    surfaceContainerHigh: Color(0xFFEAEAEC),
    surfaceContainerHighest: Color(0xFFE2E2E5),
    onSurface: Color(0xFF1C1C1E),
    onSurfaceVariant: Color(0xFF6E6E73),
    outline: Color(0xFF8E8E93),
    outlineVariant: Color(0xFFE4E4E8),
  );

  static AppSurfacePalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 把本套中性色覆盖到 [scheme] 上，返回新的 scheme。
  ///
  /// `surfaceTint` 置透明，否则 M3 组件在 elevation > 0 时仍会叠一层种子色调，
  /// 导致钉死的色值又被染回偏色。
  ColorScheme applyTo(ColorScheme scheme) {
    return scheme.copyWith(
      surface: surface,
      surfaceDim: surfaceDim,
      surfaceBright: surfaceBright,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      surfaceTint: Colors.transparent,
    );
  }

  /// 对话框 / 浮层的底色：亮色用纯白，暗色比页面底色亮一档，
  /// 保证弹层浮在暗色底之上时仍有层级感。
  static Color elevatedSurface(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? scheme.surfaceContainer
      : scheme.surface;
}
