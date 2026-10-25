import 'package:flutter/material.dart';
import 'folder_layout_utils.dart';

/// 档位微型指示器图标。
///
/// 替代原先混杂的 Material 图标（如 `density_*` 与 `grid_*`），
/// 统一采用微型矢量几何语言绘制 7 档视图模式（4 档列表 + 3 档网格）：
/// - 极简列表：纯文本行
/// - 紧凑列表：小封面 + 单行条
/// - 标准列表：标准封面 + 双行条
/// - 大图列表：大封面卡片
/// - 小网格：3x3 矩阵
/// - 中网格：2x2 矩阵
/// - 大网格：单列大卡片
class FolderZoomTierIcon extends StatelessWidget {
  const FolderZoomTierIcon({
    super.key,
    this.tier,
    this.zoomScale,
    this.size = 20.0,
    this.color,
    this.shadows,
  }) : assert(
          tier != null || zoomScale != null,
          'Either tier or zoomScale must be provided',
        );

  final FolderZoomTier? tier;
  final double? zoomScale;
  final double size;
  final Color? color;
  final List<Shadow>? shadows;

  FolderZoomTier get effectiveTier =>
      tier ?? getFolderZoomTier(zoomScale ?? 0.0);

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final theme = Theme.of(context);
    final effectiveColor =
        color ?? iconTheme.color ?? theme.colorScheme.onSurface;

    return Semantics(
      label: _tierAccessibilityLabel(effectiveTier),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          size: Size(size, size),
          painter: _FolderZoomTierPainter(
            tier: effectiveTier,
            color: effectiveColor,
            shadows: shadows,
          ),
        ),
      ),
    );
  }

  static String _tierAccessibilityLabel(FolderZoomTier tier) {
    return switch (tier) {
      FolderZoomTier.minimalList => '列表 · 极简',
      FolderZoomTier.compactList => '列表 · 紧凑',
      FolderZoomTier.standardList => '列表 · 标准',
      FolderZoomTier.largeList => '列表 · 大图',
      FolderZoomTier.smallGrid => '网格 · 小',
      FolderZoomTier.mediumGrid => '网格 · 中',
      FolderZoomTier.largeGrid => '网格 · 大',
    };
  }
}

class _FolderZoomTierPainter extends CustomPainter {
  const _FolderZoomTierPainter({
    required this.tier,
    required this.color,
    this.shadows,
  });

  final FolderZoomTier tier;
  final Color color;
  final List<Shadow>? shadows;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24.0, size.height / 24.0);

    final path = _buildTierPath(tier);

    if (shadows != null && shadows!.isNotEmpty) {
      for (final shadow in shadows!) {
        final shadowPaint = shadow.toPaint();
        canvas.save();
        canvas.translate(shadow.offset.dx, shadow.offset.dy);
        canvas.drawPath(path, shadowPaint);
        canvas.restore();
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FolderZoomTierPainter oldDelegate) {
    return oldDelegate.tier != tier ||
        oldDelegate.color != color ||
        oldDelegate.shadows != shadows;
  }
}

Path _buildTierPath(FolderZoomTier tier) {
  final path = Path();
  switch (tier) {
    case FolderZoomTier.minimalList:
      // 4 条水平圆角线（纯文字行列表）
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 4.0, 18.0, 1.8),
        const Radius.circular(0.9),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 8.5, 14.0, 1.8),
        const Radius.circular(0.9),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 13.0, 16.5, 1.8),
        const Radius.circular(0.9),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 17.5, 12.0, 1.8),
        const Radius.circular(0.9),
      ));
      break;

    case FolderZoomTier.compactList:
      // 3 行 [小封面方块 + 文本条]
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 3.5, 4.0, 4.0),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(9.0, 4.5, 12.0, 2.0),
        const Radius.circular(1.0),
      ));

      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 10.0, 4.0, 4.0),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(9.0, 11.0, 9.5, 2.0),
        const Radius.circular(1.0),
      ));

      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 16.5, 4.0, 4.0),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(9.0, 17.5, 11.0, 2.0),
        const Radius.circular(1.0),
      ));
      break;

    case FolderZoomTier.standardList:
      // 2 行 [标准封面方块 + 双行文本条]
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 3.5, 7.0, 7.0),
        const Radius.circular(1.5),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(12.0, 4.5, 9.0, 2.0),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(12.0, 8.0, 6.0, 1.5),
        const Radius.circular(0.75),
      ));

      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 13.5, 7.0, 7.0),
        const Radius.circular(1.5),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(12.0, 14.5, 8.0, 2.0),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(12.0, 18.0, 5.0, 1.5),
        const Radius.circular(0.75),
      ));
      break;

    case FolderZoomTier.largeList:
      // 大图列表卡片：上方大封面+多行信息条，下方露出次项
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 3.0, 9.5, 9.5),
        const Radius.circular(2.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.5, 4.0, 6.5, 2.2),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.5, 7.5, 5.0, 1.8),
        const Radius.circular(0.9),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.5, 10.5, 3.5, 1.5),
        const Radius.circular(0.75),
      ));

      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 15.0, 9.5, 6.0),
        const Radius.circular(1.8),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.5, 16.0, 6.5, 2.2),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(14.5, 19.5, 4.5, 1.5),
        const Radius.circular(0.75),
      ));
      break;

    case FolderZoomTier.smallGrid:
      // 3x3 小方块
      const sSize = 4.6;
      const sStep = 7.2;
      const sStart = 2.5;
      for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 3; c++) {
          path.addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(sStart + c * sStep, sStart + r * sStep, sSize, sSize),
            const Radius.circular(1.2),
          ));
        }
      }
      break;

    case FolderZoomTier.mediumGrid:
      // 2x2 中方块
      const mSize = 8.2;
      const mStep = 10.8;
      const mStart = 2.5;
      for (int r = 0; r < 2; r++) {
        for (int c = 0; c < 2; c++) {
          path.addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(mStart + c * mStep, mStart + r * mStep, mSize, mSize),
            const Radius.circular(2.0),
          ));
        }
      }
      break;

    case FolderZoomTier.largeGrid:
      // 大网格：单个大卡片
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 3.0, 18.0, 13.0),
        const Radius.circular(2.5),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(3.0, 18.0, 11.5, 2.2),
        const Radius.circular(1.0),
      ));
      path.addRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(16.0, 18.0, 5.0, 2.2),
        const Radius.circular(1.0),
      ));
      break;
  }
  return path;
}
