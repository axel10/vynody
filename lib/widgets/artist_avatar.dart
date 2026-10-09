import 'dart:io';

import 'package:flutter/material.dart';

/// Apple Music 风格的艺术家麦克风矢量图标
class ArtistMicIcon extends StatelessWidget {
  const ArtistMicIcon({
    super.key,
    this.size = 24.0,
    this.color,
  });

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final effectiveSize = size ?? iconTheme.size ?? 24.0;
    final effectiveColor =
        color ?? iconTheme.color ?? Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      width: effectiveSize,
      height: effectiveSize,
      child: CustomPaint(
        size: Size(effectiveSize, effectiveSize),
        painter: _ArtistMicPainter(color: effectiveColor),
      ),
    );
  }
}

class _ArtistMicPainter extends CustomPainter {
  const _ArtistMicPainter({required this.color});

  final Color color;

  static final Path _cachedPath = _createPath();

  static Path _createPath() {
    final path = Path()..fillType = PathFillType.evenOdd;

    // Subpath 1: 话筒立架与外夹 (Stand & Clamp)
    path.moveTo(6.4936, 13.1841);
    path.cubicTo(6.8174, 13.1841, 7.0713, 12.9302, 7.0713, 12.6128);
    path.lineTo(7.0713, 7.9029);
    path.lineTo(8.9692, 6.1509);
    path.cubicTo(9.6929, 6.2461, 10.4546, 5.9478, 11.1211, 5.2813);
    path.lineTo(7.6299, 1.7837);
    path.cubicTo(6.9570, 2.4502, 6.6777, 3.1992, 6.7793, 3.9292);
    path.lineTo(0.8760, 10.2832);
    path.cubicTo(0.6348, 10.5435, 0.5967, 10.9053, 0.8950, 11.2036);
    path.lineTo(0.0825, 12.2510);
    path.cubicTo(0.0063, 12.3526, 0.0000, 12.4986, 0.1143, 12.6128);
    path.lineTo(0.2983, 12.8032);
    path.cubicTo(0.4063, 12.9111, 0.5522, 12.9175, 0.6665, 12.8286);
    path.lineTo(1.7139, 12.0098);
    path.cubicTo(1.9995, 12.3081, 2.3677, 12.2700, 2.6216, 12.0288);
    path.lineTo(5.9160, 8.9820);
    path.lineTo(5.9160, 12.6128);
    path.cubicTo(5.9160, 12.9302, 6.1699, 13.1841, 6.4936, 13.1841);
    path.close();

    // Subpath 2: 话筒主体手柄 (Microphone Body)
    path.moveTo(1.5298, 10.8037);
    path.lineTo(7.1284, 4.8623);
    path.cubicTo(7.2363, 5.0464, 7.3633, 5.2178, 7.5220, 5.3892);
    path.cubicTo(7.6743, 5.5479, 7.8520, 5.6939, 8.0171, 5.7954);
    path.lineTo(2.1138, 11.3877);
    path.close();

    // Subpath 3: 话筒网罩圆头 (Microphone Capsule)
    path.moveTo(8.2646, 1.1426);
    path.lineTo(11.7622, 4.6402);
    path.cubicTo(12.8794, 3.5357, 12.9238, 2.1201, 11.8511, 1.0537);
    path.cubicTo(10.7847, 0.0000, 9.3818, 0.0254, 8.2646, 1.1426);
    path.close();

    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    const origWidth = 12.923817;
    const origHeight = 13.184098;

    final scale = (size.width / origWidth < size.height / origHeight)
        ? size.width / origWidth
        : size.height / origHeight;
    final dx = (size.width - origWidth * scale) / 2;
    final dy = (size.height - origHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);
    canvas.drawPath(_cachedPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ArtistMicPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Apple Music 风格的艺术家圆形头像，支持本地文件/网络图片并自动降级为矢量麦克风
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.diameter,
    this.imagePath,
    this.imageUrl,
    this.backgroundColor,
    this.iconColor,
  });

  final double diameter;
  final String? imagePath;
  final String? imageUrl;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final validPath = imagePath != null &&
        imagePath!.trim().isNotEmpty &&
        File(imagePath!).existsSync();

    if (validPath) {
      return ClipOval(
        child: Image.file(
          File(imagePath!),
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildPlaceholder(context),
        ),
      );
    }

    if (imageUrl != null && imageUrl!.trim().isNotEmpty) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          width: diameter,
          height: diameter,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildPlaceholder(context),
        ),
      );
    }

    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBgColor = backgroundColor ??
        (isDark
            ? theme.colorScheme.surfaceContainerHighest
            : const Color(0xFF8E959E));
    final effectiveIconColor = iconColor ??
        (isDark ? theme.colorScheme.onSurfaceVariant : Colors.white);

    return SizedBox(
      width: diameter,
      height: diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: effectiveBgColor,
        ),
        child: Center(
          child: ArtistMicIcon(
            size: diameter * 0.54,
            color: effectiveIconColor,
          ),
        ),
      ),
    );
  }
}
