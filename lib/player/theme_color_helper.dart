import 'dart:convert';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator_master/palette_generator_master.dart'
    as palette_master;
import 'package:image/image.dart' as img;

class _ThemeBucketStat {
  int count = 0;
  int sumRed = 0;
  int sumGreen = 0;
  int sumBlue = 0;

  void addColor(Color color, int weight) {
    final argb = color.toARGB32();
    count += weight;
    sumRed += ((argb >> 16) & 0xFF) * weight;
    sumGreen += ((argb >> 8) & 0xFF) * weight;
    sumBlue += (argb & 0xFF) * weight;
  }

  Color toColor() {
    if (count <= 0) {
      return Colors.transparent;
    }

    return Color.fromARGB(
      0xFF,
      (sumRed / count).round().clamp(0, 255).toInt(),
      (sumGreen / count).round().clamp(0, 255).toInt(),
      (sumBlue / count).round().clamp(0, 255).toInt(),
    );
  }
}

class _ThemeColorCandidate {
  _ThemeColorCandidate(this.color, this.count)
    : hsl = HSLColor.fromColor(color);

  final Color color;
  final int count;
  final HSLColor hsl;

  double get saturation => hsl.saturation;
  double get lightness => hsl.lightness;
}

@pragma('vm:entry-point')
Future<Map<String, int>> _generateThemeColorMapTask(
  Map<String, dynamic> args,
) async {
  final bytes = args['bytes'] as Uint8List?;
  final path = args['path'] as String?;
  final squareCrop = args['squareCrop'] as bool? ?? false;

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

    final workingImage = squareCrop
        ? _cropSquare(image)
        : _resizeForSampling(image);
    return _buildThemeColorMap(workingImage);
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
        _generateThemeColorMapTask,
        <String, dynamic>{'bytes': bytes, 'path': path, 'squareCrop': false},
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

img.Image _resizeForSampling(img.Image image) {
  if (image.width <= 0 || image.height <= 0) {
    return image;
  }

  if (image.width >= image.height) {
    return img.copyResize(
      image,
      width: generatedArtworkThumbnailSize,
      interpolation: img.Interpolation.average,
    );
  }

  return img.copyResize(
    image,
    height: generatedArtworkThumbnailSize,
    interpolation: img.Interpolation.average,
  );
}

img.Image _cropSquare(img.Image image) {
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

  return img.copyResize(
    square,
    width: generatedArtworkThumbnailSize,
    height: generatedArtworkThumbnailSize,
    interpolation: img.Interpolation.average,
  );
}

Map<String, int> _buildThemeColorMap(img.Image image) {
  if (image.width <= 0 || image.height <= 0) {
    return const {};
  }

  final buckets = <int, _ThemeBucketStat>{};
  final stepX = (image.width / 48).ceil().clamp(1, 8).toInt();
  final stepY = (image.height / 48).ceil().clamp(1, 8).toInt();

  for (var y = 0; y < image.height; y += stepY) {
    for (var x = 0; x < image.width; x += stepX) {
      final pixel = image.getPixel(x, y);
      final alpha = pixel.a.toInt();
      if (alpha < 24) {
        continue;
      }

      final color = Color.fromARGB(
        alpha,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
      final key = _quantizeColorKey(color);
      final bucket = buckets.putIfAbsent(key, _ThemeBucketStat.new);
      final weight = alpha < 24 ? 24 : alpha;
      bucket.addColor(color, weight);
    }
  }

  if (buckets.isEmpty) {
    return const {};
  }

  final candidates = buckets.values
      .map((bucket) => _ThemeColorCandidate(bucket.toColor(), bucket.count))
      .where((candidate) => candidate.color.a > 0)
      .toList(growable: false);

  if (candidates.isEmpty) {
    return const {};
  }

  _ThemeColorCandidate pickDominant() {
    return candidates.reduce(
      (best, candidate) => candidate.count > best.count ? candidate : best,
    );
  }

  _ThemeColorCandidate pickVibrant() {
    final saturated = candidates
        .where((candidate) => candidate.saturation >= 0.35)
        .toList(growable: false);
    if (saturated.isEmpty) return pickDominant();

    return saturated.reduce((best, candidate) {
      final bestScore =
          best.count * (0.35 + best.saturation) * (0.45 + best.lightness);
      final candidateScore =
          candidate.count *
          (0.35 + candidate.saturation) *
          (0.45 + candidate.lightness);
      return candidateScore > bestScore ? candidate : best;
    });
  }

  _ThemeColorCandidate pickMuted() {
    final muted = candidates
        .where((candidate) => candidate.saturation <= 0.55)
        .toList(growable: false);
    if (muted.isEmpty) return pickDominant();

    return muted.reduce((best, candidate) {
      final bestScore =
          best.count *
          (1.2 - best.saturation) *
          (1.1 - (best.lightness - 0.5).abs());
      final candidateScore =
          candidate.count *
          (1.2 - candidate.saturation) *
          (1.1 - (candidate.lightness - 0.5).abs());
      return candidateScore > bestScore ? candidate : best;
    });
  }

  Color lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color darken(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  final dominant = pickDominant().color;
  final vibrant = pickVibrant().color;
  final muted = pickMuted().color;

  final lightVibrant =
      candidates
          .where((candidate) => candidate.saturation >= 0.35)
          .fold<_ThemeColorCandidate?>(null, (best, candidate) {
            if (best == null || candidate.lightness > best.lightness) {
              return candidate;
            }
            return best;
          })
          ?.color ??
      lighten(vibrant, 0.18);

  final darkVibrant =
      candidates
          .where((candidate) => candidate.saturation >= 0.35)
          .fold<_ThemeColorCandidate?>(null, (best, candidate) {
            if (best == null || candidate.lightness < best.lightness) {
              return candidate;
            }
            return best;
          })
          ?.color ??
      darken(vibrant, 0.18);

  final lightMuted =
      candidates
          .where((candidate) => candidate.saturation <= 0.55)
          .fold<_ThemeColorCandidate?>(null, (best, candidate) {
            if (best == null || candidate.lightness > best.lightness) {
              return candidate;
            }
            return best;
          })
          ?.color ??
      lighten(muted, 0.18);

  final darkMuted =
      candidates
          .where((candidate) => candidate.saturation <= 0.55)
          .fold<_ThemeColorCandidate?>(null, (best, candidate) {
            if (best == null || candidate.lightness < best.lightness) {
              return candidate;
            }
            return best;
          })
          ?.color ??
      darken(muted, 0.18);

  return {
    'dominant': dominant.toARGB32(),
    'vibrant': vibrant.toARGB32(),
    'lightVibrant': lightVibrant.toARGB32(),
    'darkVibrant': darkVibrant.toARGB32(),
    'muted': muted.toARGB32(),
    'lightMuted': lightMuted.toARGB32(),
    'darkMuted': darkMuted.toARGB32(),
  };
}

int _quantizeColorKey(Color color) {
  final argb = color.toARGB32();
  final red = (argb >> 16) & 0xFF;
  final green = (argb >> 8) & 0xFF;
  final blue = argb & 0xFF;
  return (red << 8) | (green << 4) | blue;
}
