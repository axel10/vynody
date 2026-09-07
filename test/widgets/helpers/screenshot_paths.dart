import 'dart:io';
import 'package:flutter/services.dart';

/// Centralized configuration and path generator for screenshot test outputs.
class ScreenshotPaths {
  /// Root directory for all generated screenshots and store posters.
  static String baseDir = 'screenshots';

  /// Generates a relative path for a raw device/window screenshot.
  /// Example: ScreenshotPaths.raw('ios_screen_01_playback.png', lang: 'zh') -> 'raw/zh/ios_screen_01_playback.png'
  static String raw(String filename, {String lang = 'zh'}) => 'raw/$lang/$filename';

  /// Generates a relative path for a finished store poster screenshot.
  /// Example: ScreenshotPaths.store('ios_store_01_playback.png', lang: 'zh') -> 'store/zh/ios_store_01_playback.png'
  static String store(String filename, {String lang = 'zh'}) => 'store/$lang/$filename';

  /// Resolves relative or absolute path against [baseDir] and returns a [File].
  static File resolve(String pathOrFilename) {
    if (pathOrFilename.contains('/Volumes/Untitled/projects/vibe_flow/screenshots/')) {
      pathOrFilename = pathOrFilename.replaceFirst(
        '/Volumes/Untitled/projects/vibe_flow/screenshots/',
        '',
      );
    }
    if (pathOrFilename.startsWith('/') ||
        pathOrFilename.contains(':\\') ||
        pathOrFilename.startsWith('\\')) {
      return File(pathOrFilename);
    }
    return File('$baseDir/$pathOrFilename');
  }

  /// Resolves cover file path, falling back to local `test_covers/` directory if needed.
  static Uint8List? resolveCoverBytes(String path) {
    var file = File(path);
    if (!file.existsSync()) {
      final fileName = path.split(RegExp(r'[\\/]')).last;
      final local = File('test_covers/$fileName');
      if (local.existsSync()) {
        file = local;
      }
    }
    if (file.existsSync()) {
      return Uint8List.fromList(file.readAsBytesSync());
    }
    return null;
  }

  /// Dynamically finds MaterialIcons font across platforms (Windows, macOS, Linux).
  static File? findMaterialIconsFont() {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null && flutterRoot.isNotEmpty) {
      final f = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (f.existsSync()) return f;
    }

    final candidates = [
      'D:/flutter/3.44.9/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      '/Users/axel10/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f;
    }

    try {
      final res = Process.runSync(Platform.isWindows ? 'where.exe' : 'which', ['flutter']);
      if (res.exitCode == 0) {
        final line = (res.stdout as String)
            .split(RegExp(r'[\r\n]+'))
            .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        if (line.isNotEmpty) {
          final binDir = File(line.trim()).parent;
          final f = File('${binDir.path}/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
          if (f.existsSync()) return f;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Finds unicode / CJK fonts across Windows, macOS, and Linux.
  static List<File> findUnicodeFontFiles() {
    final candidates = [
      'C:\\Windows\\Fonts\\msyh.ttc',
      'C:\\Windows\\Fonts\\msyh.ttf',
      'C:\\Windows\\Fonts\\segoeui.ttf',
      'C:\\Windows\\Fonts\\arial.ttf',
      '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
    ];
    final files = <File>[];
    for (final p in candidates) {
      final f = File(p);
      if (f.existsSync()) {
        files.add(f);
      }
    }
    return files;
  }

  /// Cross-platform test font loader.
  static Future<void> loadCrossPlatformTestFonts() async {
    final iconFontFile = findMaterialIconsFont();
    if (iconFontFile != null && iconFontFile.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons');
      iconLoader.addFont(
        Future.value(ByteData.sublistView(iconFontFile.readAsBytesSync())),
      );
      await iconLoader.load();
    }

    final unicodeFonts = findUnicodeFontFiles();
    for (final fontFile in unicodeFonts) {
      try {
        final bytes = fontFile.readAsBytesSync();
        for (final family in [
          'Roboto',
          'Arial Unicode MS',
          '.SF UI Text',
          '.SF UI Display',
          'PingFang SC',
          'Segoe UI',
          'Microsoft YaHei UI',
          'Microsoft YaHei',
          'Heiti SC',
          'sans-serif',
          '',
        ]) {
          final loader = FontLoader(family);
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
          await loader.load();
        }
        break;
      } catch (_) {}
    }
  }
}
