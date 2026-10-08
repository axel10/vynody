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
      String result;
      if (!trimmed.contains('//') &&
          !trimmed.contains('/./') &&
          !trimmed.contains('/../') &&
          !trimmed.startsWith('./') &&
          !trimmed.startsWith('../')) {
        var s = trimmed;
        if (s.length > 1 && s.endsWith('/')) {
          s = s.substring(0, s.length - 1);
        }
        result = s;
      } else {
        var normalized = p.normalize(trimmed);
        if (normalized.length > 1 && normalized.endsWith('/')) {
          normalized = normalized.substring(0, normalized.length - 1);
        }
        result = normalized;
      }
      if ((Platform.isIOS || Platform.isMacOS) && result.startsWith('/private/var/')) {
        result = result.substring('/private'.length);
      }
      return result;
    }
  }

  static String normalizeLyricCacheKey(String? rawKey) {
    if (rawKey == null) return '';
    var key = rawKey.trim();
    if (key.isEmpty) return '';
    if (key.contains('|')) {
      key = key.split('|').first.trim();
    }
    if (key.startsWith('subsonic://') ||
        key.startsWith('webdav://') ||
        key.startsWith('smb://') ||
        key.startsWith('jellyfin://') ||
        key.startsWith('http://') ||
        key.startsWith('https://')) {
      return key;
    }
    return normalizePath(key);
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

  static String? get docDir => _currentIosDocDir;
  static String? get libDir => _currentIosLibDir;

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
    final rawTrimmed = path.trim();
    if (rawTrimmed.startsWith('content://') ||
        rawTrimmed.startsWith('http://') ||
        rawTrimmed.startsWith('https://') ||
        rawTrimmed.startsWith('asset://') ||
        rawTrimmed.startsWith('fd://') ||
        rawTrimmed.contains('://')) {
      return rawTrimmed;
    }
    final trimmed = normalizePath(rawTrimmed);

    final docDir = _currentIosDocDir;
    final libDir = _currentIosLibDir;

    // If already pointing to current app's sandbox, return normalized path
    if (docDir != null && (pathsEqual(docDir, trimmed) || pathContains(docDir, trimmed))) {
      return trimmed;
    }
    if (libDir != null && (pathsEqual(libDir, trimmed) || pathContains(libDir, trimmed))) {
      return trimmed;
    }

    // If the path exists as-is on the filesystem (e.g. valid external folder/file from another app container or iCloud),
    // do not rewrite it to our own sandbox!
    try {
      if (FileSystemEntity.typeSync(trimmed) != FileSystemEntityType.notFound) {
        return trimmed;
      }
    } catch (_) {
      // Ignored if file system permission or check fails
    }

    // 1. Special handling for thumbnails: thumbnails are always located inside libDir/thumbnails
    if (libDir != null && libDir.isNotEmpty) {
      final thumbMatch = RegExp(r'(?:^|/)thumbnails/(.+)$').firstMatch(trimmed);
      if (thumbMatch != null) {
        return p.join(libDir, 'thumbnails', thumbMatch.group(1)!);
      }
    }

    // 2. Container matching: supports iOS device (/var/mobile/Containers/...),
    //    iOS Simulator (.../data/Containers/Data/Application/<UUID>/...),
    //    macOS sandbox (.../Containers/<BundleId>/Data/...),
    //    and File Provider Storage (.../Containers/Shared/AppGroup/<UUID>/File Provider Storage/...).
    //    Greedy .*/ ensures we pick the innermost/last container in case of historical nesting.
    final containerMatch = RegExp(
      r'.*/Containers/(?:Data/Application|Shared/AppGroup|[^/]+)/[^/]+(?:/[^/]+)*(?:/Data)?/(Documents|Library(?:/Application Support)?)(?:/(.*))?$',
    ).firstMatch(trimmed);

    if (containerMatch != null) {
      final type = containerMatch.group(1);
      final subPath = containerMatch.group(2);
      if (type == 'Documents') {
        if (docDir != null && docDir.isNotEmpty) {
          return (subPath == null || subPath.isEmpty)
              ? docDir
              : p.join(docDir, subPath);
        }
      } else {
        if (libDir != null && libDir.isNotEmpty) {
          return (subPath == null || subPath.isEmpty)
              ? libDir
              : p.join(libDir, subPath);
        }
      }
    }

    // 3. Fallback for standalone relative or unscoped Documents paths
    if (docDir != null && docDir.isNotEmpty) {
      final docMatch = RegExp(r'(?:^|/)Documents(?:/(.*))?$').firstMatch(trimmed);
      if (docMatch != null && !trimmed.contains('/Developer/CoreSimulator/')) {
        final subPath = docMatch.group(1);
        return (subPath == null || subPath.isEmpty)
            ? docDir
            : p.join(docDir, subPath);
      }
    }

    return trimmed;
  }

  /// Checks if a path belongs to the current iOS/macOS application sandbox.
  static bool isSandboxInternalPath(String path) {
    if (!Platform.isIOS && !Platform.isMacOS) return false;
    final trimmed = normalizePath(path);
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

  static const Set<String> _windowsProtectedDirectoryNames = {
    r'$recycle.bin',
    'system volume information',
  };

  /// Checks if any segment of [path] (or segments relative to [rootPath])
  /// represents a hidden directory/file (starts with '.') or a system/trash directory.
  static bool isHiddenOrExcludedPath(String path, {String? rootPath}) {
    final lower = path.toLowerCase();
    if (lower.contains('/.trash/') ||
        lower.contains(r'\.trash\') ||
        lower.contains('/.trashes/') ||
        lower.contains(r'\.trashes\') ||
        lower.contains('/.trash-') ||
        lower.contains(r'\.trash-')) {
      return true;
    }

    String relative;
    if (rootPath != null && rootPath.isNotEmpty) {
      try {
        final normalizedRoot = normalizePath(rootPath);
        final normalizedFile = normalizePath(path);
        if (p.isWithin(normalizedRoot, normalizedFile)) {
          relative = p.relative(normalizedFile, from: normalizedRoot);
        } else {
          final rel = p.relative(path, from: rootPath);
          relative = rel.startsWith('..') ? p.basename(path) : rel;
        }
      } catch (_) {
        relative = p.basename(path);
      }
    } else {
      relative = p.basename(path);
    }

    final segments = p.split(relative);
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.' || segment == '..') continue;
      if (segment.startsWith('.')) {
        return true;
      }
      if (Platform.isWindows &&
          _windowsProtectedDirectoryNames.contains(segment.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}

