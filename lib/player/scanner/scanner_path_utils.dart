import 'dart:io';

import 'package:path/path.dart' as p;

class ScannerPathUtils {
  static bool isLikelyPackagedWindowsApp() {
    if (!Platform.isWindows) return false;
    try {
      final executablePath = Platform.resolvedExecutable.replaceAll('/', r'\');
      return executablePath.toLowerCase().contains(r'\windowsapps\');
    } catch (_) {
      return false;
    }
  }

  static String normalizePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return trimmed;

    if (Platform.isWindows) {
      if (!trimmed.contains('/') &&
          !trimmed.contains(r'\.\') &&
          !trimmed.contains(r'\..\') &&
          !trimmed.startsWith(r'.\') &&
          !trimmed.startsWith(r'..\')) {
        var s = trimmed;
        if (s.length > 3 && s.endsWith(r'\')) {
          s = s.substring(0, s.length - 1);
        }
        return s;
      }
      var normalized = p.normalize(trimmed).replaceAll('/', r'\');
      if (normalized.length > 3 && normalized.endsWith(r'\')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    } else {
      if (!trimmed.contains('//') &&
          !trimmed.contains('/./') &&
          !trimmed.contains('/../') &&
          !trimmed.startsWith('./') &&
          !trimmed.startsWith('../')) {
        var s = trimmed;
        if (s.length > 1 && s.endsWith('/')) {
          s = s.substring(0, s.length - 1);
        }
        return s;
      }
      var normalized = p.normalize(trimmed);
      if (normalized.length > 1 && normalized.endsWith('/')) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
      return normalized;
    }
  }

  static String pathLookupKey(String path) {
    final normalized = normalizePath(path);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static List<String> normalizeDeclaredRootPaths(Iterable<String> paths) {
    final normalizedPaths = paths
        .map(normalizePath)
        .where((path) => path.isNotEmpty)
        .toList();

    final result = <String>[];
    for (final path in normalizedPaths) {
      if (result.any((existing) => pathsEqual(existing, path))) {
        continue;
      }
      result.add(path);
    }

    return result;
  }

  static List<String> computeScanRoots(Iterable<String> paths) {
    final normalizedPaths = normalizeDeclaredRootPaths(paths);
    normalizedPaths.sort((a, b) => a.length.compareTo(b.length));

    final result = <String>[];
    for (final path in normalizedPaths) {
      if (result.any((existing) => pathContains(existing, path))) {
        continue;
      }
      result.add(path);
    }

    return result;
  }

  static bool pathsEqual(String left, String right) {
    if (identical(left, right) || left == right) return true;
    if (Platform.isWindows &&
        left.length == right.length &&
        left.toLowerCase() == right.toLowerCase()) {
      return true;
    }
    final normalizedLeft = normalizePath(left);
    final normalizedRight = normalizePath(right);
    if (Platform.isWindows) {
      return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    }
    return normalizedLeft == normalizedRight;
  }

  static bool pathContains(String parent, String child) {
    final normalizedParent = normalizePath(parent);
    final normalizedChild = normalizePath(child);

    if (pathsEqual(normalizedParent, normalizedChild)) {
      return true;
    }

    if (Platform.isWindows) {
      return p.isWithin(
        normalizedParent.toLowerCase(),
        normalizedChild.toLowerCase(),
      );
    }

    return p.isWithin(normalizedParent, normalizedChild);
  }

  static String displayNameForPath(String path) {
    final normalizedPath = normalizePath(path);
    final basename = p.basename(normalizedPath);
    if (basename.isNotEmpty) return basename;

    if (Platform.isWindows) {
      var drive = p.rootPrefix(normalizedPath);
      if (drive.endsWith(r'\') || drive.endsWith('/')) {
        drive = drive.substring(0, drive.length - 1);
      }
      if (drive.isNotEmpty) return drive;
    }

    return normalizedPath;
  }

  static String cleanDisplayPath(String path) {
    var cleaned = normalizePath(path);
    if (Platform.isIOS) {
      // Clean AppGroup path: /private/var/mobile/Containers/Shared/AppGroup/UUID/ -> AppGroup/
      cleaned = cleaned.replaceFirst(
        RegExp(r'^/(private/)?var/mobile/Containers/Shared/AppGroup/[^/]+/'),
        'AppGroup/',
      );
      // Clean Application Documents path: /private/var/mobile/Containers/Data/Application/UUID/Documents/ -> Documents/
      cleaned = cleaned.replaceFirst(
        RegExp(r'^/(private/)?var/mobile/Containers/Data/Application/[^/]+/Documents/'),
        'Documents/',
      );
      // Clean Application Library path: /private/var/mobile/Containers/Data/Application/UUID/Library/ -> Library/
      cleaned = cleaned.replaceFirst(
        RegExp(r'^/(private/)?var/mobile/Containers/Data/Application/[^/]+/Library/'),
        'Library/',
      );
      // Clean general Containers path: /private/var/mobile/Containers/Type/UUID/ -> Container/
      cleaned = cleaned.replaceFirst(
        RegExp(r'^/(private/)?var/mobile/Containers/[^/]+/[^/]+/'),
        'Container/',
      );
    }
    return cleaned;
  }

  static String? _currentIosDocDir;
  static String? _currentIosLibDir;

  static void setIosSandboxDirs({String? docDir, String? libDir}) {
    if (docDir != null && docDir.isNotEmpty) {
      _currentIosDocDir = normalizePath(docDir);
    }
    if (libDir != null && libDir.isNotEmpty) {
      _currentIosLibDir = normalizePath(libDir);
    }
  }

  /// Resolves an iOS / macOS sandbox path that may contain a stale container UUID
  /// to the current application container directory.
  static String resolveIosSandboxPath(String path) {
    if (path.isEmpty || (!Platform.isIOS && !Platform.isMacOS)) {
      return path;
    }
    final trimmed = path.trim();
    if (trimmed.startsWith('content://') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('asset://') ||
        trimmed.startsWith('fd://')) {
      return trimmed;
    }

    // If file or directory directly exists as-is, no need to transform
    if (File(trimmed).existsSync() || Directory(trimmed).existsSync()) {
      return trimmed;
    }

    final docDir = _currentIosDocDir;
    final libDir = _currentIosLibDir;

    // 1. Documents container matching (supports /var/mobile, /private/var/mobile, and Simulator)
    if (docDir != null && docDir.isNotEmpty) {
      final docMatch = RegExp(
        r'(?:^|/)(?:private/)?var/mobile/Containers/Data/Application/[^/]+/Documents(?:/(.*))?$',
      ).firstMatch(trimmed) ?? RegExp(
        r'/Containers/Data/Application/[^/]+/Documents(?:/(.*))?$',
      ).firstMatch(trimmed);

      if (docMatch != null) {
        final subPath = docMatch.group(1);
        final resolved = (subPath == null || subPath.isEmpty)
            ? docDir
            : p.join(docDir, subPath);
        if (File(resolved).existsSync() ||
            Directory(resolved).existsSync() ||
            (!File(trimmed).existsSync() && !Directory(trimmed).existsSync())) {
          return resolved;
        }
      }
    }

    // 2. Library / Application Support container matching
    if (libDir != null && libDir.isNotEmpty) {
      final libMatch = RegExp(
        r'(?:^|/)(?:private/)?var/mobile/Containers/Data/Application/[^/]+/Library/(?:Application Support/)?(?:/(.*))?$',
      ).firstMatch(trimmed) ?? RegExp(
        r'/Containers/Data/Application/[^/]+/Library/(?:Application Support/)?(?:/(.*))?$',
      ).firstMatch(trimmed);

      if (libMatch != null) {
        final subPath = libMatch.group(1);
        final resolved = (subPath == null || subPath.isEmpty)
            ? libDir
            : p.join(libDir, subPath);
        if (File(resolved).existsSync() ||
            Directory(resolved).existsSync() ||
            (!File(trimmed).existsSync() && !Directory(trimmed).existsSync())) {
          return resolved;
        }
      }
    }

    return trimmed;
  }

  /// Checks if a path belongs to the iOS/macOS application sandbox.
  static bool isSandboxInternalPath(String path) {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    final trimmed = normalizePath(path);
    if (trimmed.contains('/Containers/Data/Application/')) {
      return true;
    }
    if (_currentIosDocDir != null &&
        (pathsEqual(_currentIosDocDir!, trimmed) ||
            pathContains(_currentIosDocDir!, trimmed))) {
      return true;
    }
    if (_currentIosLibDir != null &&
        (pathsEqual(_currentIosLibDir!, trimmed) ||
            pathContains(_currentIosLibDir!, trimmed))) {
      return true;
    }
    return false;
  }
}

