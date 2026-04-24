import 'dart:convert';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart' as palette_legacy;
import 'package:palette_generator_master/palette_generator_master.dart'
    as palette_master;
import 'package:image/image.dart' as img;

@pragma('vm:entry-point')
Future<Map<String, int>> _generatePaletteColorMapTask(
  Map<String, dynamic> args,
) async {
  final bytes = args['bytes'] as Uint8List?;
  final path = args['path'] as String?;

  try {
    img.Image? image;
    if (bytes != null && bytes.isNotEmpty) {
      image = img.decodeImage(bytes);
    } else if (path != null && path.isNotEmpty) {
      final fileBytes = File(path).readAsBytesSync();
      image = img.decodeImage(fileBytes);
    }

    if (image == null) {
      return const {};
    }

    final resized = image.width >= image.height
        ? img.copyResize(
            image,
            width: generatedArtworkThumbnailSize,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: generatedArtworkThumbnailSize,
            interpolation: img.Interpolation.average,
          );

    final rgbaBytes = resized.getBytes(order: img.ChannelOrder.rgba);
    final palette = await palette_legacy.PaletteGenerator.fromByteData(
      palette_legacy.EncodedImage(
        ByteData.sublistView(rgbaBytes),
        width: resized.width,
        height: resized.height,
      ),
      maximumColorCount: 20,
    );
    final Map<String, int> colors = {};
    if (palette.dominantColor != null) {
      colors['dominant'] = palette.dominantColor!.color.toARGB32();
    }
    if (palette.vibrantColor != null) {
      colors['vibrant'] = palette.vibrantColor!.color.toARGB32();
    }
    if (palette.lightVibrantColor != null) {
      colors['lightVibrant'] = palette.lightVibrantColor!.color.toARGB32();
    }
    if (palette.darkVibrantColor != null) {
      colors['darkVibrant'] = palette.darkVibrantColor!.color.toARGB32();
    }
    if (palette.mutedColor != null) {
      colors['muted'] = palette.mutedColor!.color.toARGB32();
    }
    if (palette.lightMutedColor != null) {
      colors['lightMuted'] = palette.lightMutedColor!.color.toARGB32();
    }
    if (palette.darkMutedColor != null) {
      colors['darkMuted'] = palette.darkMutedColor!.color.toARGB32();
    }
    return colors;
  } catch (_) {
    return const {};
  }
}

@pragma('vm:entry-point')
Future<Map<String, int>> _generatePaletteMasterColorMapTask(
  Map<String, dynamic> args,
) async {
  final bytes = args['bytes'] as Uint8List?;
  final path = args['path'] as String?;

  try {
    img.Image? image;
    if (bytes != null && bytes.isNotEmpty) {
      image = img.decodeImage(bytes);
    } else if (path != null && path.isNotEmpty) {
      final fileBytes = File(path).readAsBytesSync();
      image = img.decodeImage(fileBytes);
    }

    if (image == null) {
      return const {};
    }

    final cropSize = image.width < image.height ? image.width : image.height;
    final offsetX = (image.width - cropSize) ~/ 2;
    final offsetY = (image.height - cropSize) ~/ 2;
    final square = img.copyCrop(
      image,
      x: offsetX,
      y: offsetY,
      width: cropSize,
      height: cropSize,
    );

    final resized = img.copyResize(
      square,
      width: generatedArtworkThumbnailSize,
      height: generatedArtworkThumbnailSize,
      interpolation: img.Interpolation.average,
    );

    final rgbaBytes = resized.getBytes(order: img.ChannelOrder.rgba);
    final palette = await palette_master.PaletteGeneratorMaster.fromByteData(
      palette_master.EncodedImageMaster(
        ByteData.sublistView(rgbaBytes),
        width: resized.width,
        height: resized.height,
        name: path,
      ),
      maximumColorCount: 20,
    );

    final Map<String, int> colors = {};
    if (palette.dominantColor != null) {
      colors['dominant'] = palette.dominantColor!.color.toARGB32();
    }
    if (palette.vibrantColor != null) {
      colors['vibrant'] = palette.vibrantColor!.color.toARGB32();
    }
    if (palette.lightVibrantColor != null) {
      colors['lightVibrant'] = palette.lightVibrantColor!.color.toARGB32();
    }
    if (palette.darkVibrantColor != null) {
      colors['darkVibrant'] = palette.darkVibrantColor!.color.toARGB32();
    }
    if (palette.mutedColor != null) {
      colors['muted'] = palette.mutedColor!.color.toARGB32();
    }
    if (palette.lightMutedColor != null) {
      colors['lightMuted'] = palette.lightMutedColor!.color.toARGB32();
    }
    if (palette.darkMutedColor != null) {
      colors['darkMuted'] = palette.darkMutedColor!.color.toARGB32();
    }
    return colors;
  } catch (_) {
    return const {};
  }
}

class ThemeColorHelper {

  static Uint8List paletteToBlob(palette_legacy.PaletteGenerator palette) {
    return colorsMapToBlob({
      if (palette.dominantColor != null)
        'dominant': palette.dominantColor!.color,
      if (palette.vibrantColor != null) 'vibrant': palette.vibrantColor!.color,
      if (palette.lightVibrantColor != null)
        'lightVibrant': palette.lightVibrantColor!.color,
      if (palette.darkVibrantColor != null)
        'darkVibrant': palette.darkVibrantColor!.color,
      if (palette.mutedColor != null) 'muted': palette.mutedColor!.color,
      if (palette.lightMutedColor != null)
        'lightMuted': palette.lightMutedColor!.color,
      if (palette.darkMutedColor != null)
        'darkMuted': palette.darkMutedColor!.color,
    });
  }

  static Uint8List colorsMapToBlob(Map<String, Color> colorsMap) {
    final colors = <String, int>{};
    for (final entry in colorsMap.entries) {
      colors[entry.key] = entry.value.toARGB32();
    }
    final jsonStr = jsonEncode(colors);
    return Uint8List.fromList(utf8.encode(jsonStr));
  }

  static Map<String, Color> blobToColors(Uint8List blob) {
    try {
      final jsonStr = utf8.decode(blob);
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      final Map<String, Color> colors = {};

      decoded.forEach((key, value) {
        if (value is int) {
          colors[key] = Color(value);
        }
      });
      return colors;
    } catch (e) {
      return {};
    }
  }

  static Uint8List paletteMasterToBlob(
    palette_master.PaletteGeneratorMaster palette,
  ) {
    return colorsMapToBlob({
      if (palette.dominantColor != null)
        'dominant': palette.dominantColor!.color,
      if (palette.vibrantColor != null) 'vibrant': palette.vibrantColor!.color,
      if (palette.lightVibrantColor != null)
        'lightVibrant': palette.lightVibrantColor!.color,
      if (palette.darkVibrantColor != null)
        'darkVibrant': palette.darkVibrantColor!.color,
      if (palette.mutedColor != null) 'muted': palette.mutedColor!.color,
      if (palette.lightMutedColor != null)
        'lightMuted': palette.lightMutedColor!.color,
      if (palette.darkMutedColor != null)
        'darkMuted': palette.darkMutedColor!.color,
    });
  }

  static Color? resolveMeshColor(
    Map<String, Color> colorsMap,
    List<String> keys, {
    Color? fallback,
  }) {
    for (final key in keys) {
      final color = colorsMap[key];
      if (color != null) return color;
    }
    return fallback;
  }

  static List<Color> resolveMeshColors(
    Map<String, Color> themeColors, {
    Color? dynamicStartColor,
    Color? dynamicEndColor,
  }) {
    final color1 = resolveMeshColor(themeColors, const [
      'dominant',
      'vibrant',
    ], fallback: dynamicStartColor ?? Colors.white)!;
    final color2 = resolveMeshColor(themeColors, const [
      'vibrant',
      'muted',
    ], fallback: dynamicEndColor ?? Colors.black)!;
    final color3 = resolveMeshColor(themeColors, const [
      'lightVibrant',
      'muted',
    ], fallback: Colors.black)!;
    final color4 = resolveMeshColor(themeColors, const [
      'darkVibrant',
      'darkMuted',
    ], fallback: Colors.black)!;

    return [color1, color2, color3, color4];
  }

  static double hueDistance(Color a, Color b) {
    final hueA = HSVColor.fromColor(a).hue;
    final hueB = HSVColor.fromColor(b).hue;
    final diff = (hueA - hueB).abs();
    return diff > 180.0 ? 360.0 - diff : diff;
  }

  static double hueSpread(Color color1, List<Color> otherColors) {
    var total = 0.0;
    for (final color in otherColors) {
      total += hueDistance(color1, color);
    }
    return total;
  }
  static const double defaultHueSpreadThreshold = 210.0;
  static bool shouldRebuildPalette(
    List<Color> colors, {
    double threshold = defaultHueSpreadThreshold,
  }) {
    if (colors.length < 4) return false;
    final spread = hueSpread(colors.first, colors.sublist(1));
    return spread > threshold;
  }

  static Future<CustomPalette> generatePaletteMaster({
    Uint8List? bytes,
    String? path,
  }) async {
    if ((bytes == null || bytes.isEmpty) && (path == null || path.isEmpty)) {
      return CustomPalette(
        startColor: Colors.blue,
        endColor: Colors.deepPurple,
        colorsMap: {
          'dominant': Colors.blue,
          'vibrant': Colors.deepPurple,
          'muted': Colors.indigo,
        },
      );
    }

    try {
      final colorMap = await compute(
        _generatePaletteMasterColorMapTask,
        <String, dynamic>{'bytes': bytes, 'path': path},
      );

      Color? colorOf(String key) {
        final value = colorMap[key];
        return value == null ? null : Color(value);
      }

      final dominant = colorOf('dominant') ?? Colors.blue;
      final vibrant = colorOf('vibrant') ?? Colors.deepPurple;
      final muted = colorOf('muted') ?? Colors.indigo;

      return CustomPalette(
        startColor: dominant,
        endColor: (colorOf('vibrant')?.withValues(alpha: 0.8)) ?? muted,
        colorsMap: {
          'dominant': dominant,
          'vibrant': vibrant,
          'muted': muted,
          'lightVibrant': colorOf('lightVibrant') ?? dominant,
          'darkVibrant': colorOf('darkVibrant') ?? dominant,
          'lightMuted': colorOf('lightMuted') ?? muted,
          'darkMuted': colorOf('darkMuted') ?? muted,
        },
      );
    } catch (e) {
      debugPrint('Error generating master palette: $e');
      return CustomPalette(
        startColor: Colors.blue,
        endColor: Colors.deepPurple,
        colorsMap: {
          'dominant': Colors.blue,
          'vibrant': Colors.deepPurple,
          'muted': Colors.indigo,
        },
      );
    }
  }

  static Future<CustomPalette> generatePalette({
    Uint8List? bytes,
    String? path,
  }) async {
    if ((bytes == null || bytes.isEmpty) && (path == null || path.isEmpty)) {
      return CustomPalette(
        startColor: Colors.blue,
        endColor: Colors.deepPurple,
        colorsMap: {
          'dominant': Colors.blue,
          'vibrant': Colors.deepPurple,
          'muted': Colors.indigo,
        },
      );
    }

    try {
      final colorMap = await compute(
        _generatePaletteColorMapTask,
        <String, dynamic>{'bytes': bytes, 'path': path},
      );

      Color? colorOf(String key) {
        final value = colorMap[key];
        return value == null ? null : Color(value);
      }

      final dominant = colorOf('dominant') ?? Colors.blue;
      final vibrant = colorOf('vibrant') ?? Colors.deepPurple;
      final muted = colorOf('muted') ?? Colors.indigo;

      return CustomPalette(
        startColor: dominant,
        endColor: (colorOf('vibrant')?.withValues(alpha: 0.8)) ?? muted,
        colorsMap: {
          'dominant': dominant,
          'vibrant': vibrant,
          'muted': muted,
          'lightVibrant': colorOf('lightVibrant') ?? dominant,
          'darkVibrant': colorOf('darkVibrant') ?? dominant,
          'lightMuted': colorOf('lightMuted') ?? muted,
          'darkMuted': colorOf('darkMuted') ?? muted,
        },
      );
    } catch (e) {
      debugPrint('Error generating palette: $e');
      return CustomPalette(
        startColor: Colors.blue,
        endColor: Colors.deepPurple,
        colorsMap: {
          'dominant': Colors.blue,
          'vibrant': Colors.deepPurple,
          'muted': Colors.indigo,
        },
      );
    }
  }
}

class CustomPalette {
  final Color startColor;
  final Color endColor;
  final Map<String, Color> colorsMap;

  CustomPalette({
    required this.startColor,
    required this.endColor,
    required this.colorsMap,
  });
}
