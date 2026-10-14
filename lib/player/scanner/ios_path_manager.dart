import 'dart:io';
import 'package:path/path.dart' as p;

/// Represents the classification of an iOS file/directory path.
enum IosPathKind {
  /// File or folder inside Vynody's own Application Documents container.
  /// (e.g. `/var/mobile/Containers/Data/Application/<Vynody-UUID>/Documents/...`)
  internalDocuments,

  /// File or folder inside Vynody's own Application Library / Application Support container.
  /// (e.g. `/var/mobile/Containers/Data/Application/<Vynody-UUID>/Library/...` or thumbnails)
  internalLibrary,

  /// File or folder in the system File Provider Storage ("On My iPhone" root/shared storage).
  /// (e.g. `/var/mobile/Containers/Shared/AppGroup/<UUID>/File Provider Storage/...`)
  fileProviderStorage,

  /// File or folder in another application's container.
  /// (e.g. `/var/mobile/Containers/Data/Application/<OTHER-UUID>/Documents/...`)
  externalAppContainer,

  /// File or folder outside app containers (e.g. macOS `/Volumes/...` or `/Users/...`).
  externalFilesystem,

  /// Remote URL or virtual scheme (`http://`, `content://`, `asset://`, etc.)
  nonFileUri,
}

/// Centralized manager for handling iOS / macOS sandbox path classification,
/// resolution, and UUID migration.
///
/// Ensures all three iOS storage locations:
/// 1. Vynody own Documents/Library
/// 2. File Provider Storage ("On My iPhone")
/// 3. Other App Documents containers
/// are correctly differentiated without cross-contamination.
class IosPathManager {
  IosPathManager._();

  static String? _currentDocDir;
  static String? _currentLibDir;
  static String? _currentSandboxRoot; // Parent of Documents (i.e. .../Data/Application/<UUID>)

  static final Set<String> _externalRoots = <String>{};
  static final Map<String, String> _resolutionCache = {};
  static const int _maxCacheSize = 10000;

  static final RegExp _iosThumbRegex = RegExp(r'(?:^|/)thumbnails/(.+)$');

  /// Regex matching standard iOS / macOS container patterns:
  /// Group 1: Container root prefix (up to `<UUID>` or `<AppGroup>`)
  /// Group 2: Subfolder type ('Documents' or 'Library')
  /// Group 3: Subpath relative to Documents/Library
  static final RegExp _appContainerRegex = RegExp(
    r'^((?:/private)?/var/mobile/Containers/Data/Application/[^/]+)/(Documents|Library(?:/Application Support)?)(?:/(.*))?$',
  );

  /// Configures the current app's sandbox directories.
  /// Called once during app initialization or whenever root paths change.
  static void configure({
    String? docDir,
    String? libDir,
    Iterable<String>? externalRoots,
  }) {
    _resolutionCache.clear();
    if (docDir != null && docDir.isNotEmpty) {
      _currentDocDir = normalize(docDir);
      _currentSandboxRoot = normalize(p.dirname(_currentDocDir!));
    }
    if (libDir != null && libDir.isNotEmpty) {
      _currentLibDir = normalize(libDir);
    }
    if (externalRoots != null) {
      _externalRoots
        ..clear()
        ..addAll(externalRoots.map(normalize).where((r) => r.isNotEmpty));
    }
  }

  static String? get currentDocDir => _currentDocDir;
  static String? get currentLibDir => _currentLibDir;
  static String? get currentSandboxRoot => _currentSandboxRoot;

  /// Normalizes a path: trims whitespace and resolves standard path segments.
  static String normalize(String path) {
    if (path.isEmpty) return path;
    var trimmed = path.trim();
    if (trimmed.startsWith('file://')) {
      trimmed = Uri.parse(trimmed).toFilePath();
    }
    if (trimmed.contains('://')) {
      return trimmed;
    }
    return p.normalize(trimmed);
  }

  /// Classifies an iOS path into one of [IosPathKind].
  static IosPathKind classify(String rawPath) {
    if (rawPath.isEmpty) return IosPathKind.externalFilesystem;
    if (rawPath.contains('://')) {
      return IosPathKind.nonFileUri;
    }
    final path = normalize(rawPath);

    // 1. File Provider Storage ("On My iPhone")
    // Pattern: .../Containers/Shared/AppGroup/<UUID>/File Provider Storage/...
    if (path.contains('/Containers/Shared/AppGroup/') &&
        path.contains('/File Provider Storage')) {
      return IosPathKind.fileProviderStorage;
    }

    // 2. Thumbnails cache
    if (_iosThumbRegex.hasMatch(path)) {
      return IosPathKind.internalLibrary;
    }

    // 3. Current active sandbox check
    final doc = _currentDocDir;
    final lib = _currentLibDir;
    if (doc != null && (path == doc || path.startsWith('$doc/'))) {
      return IosPathKind.internalDocuments;
    }
    if (lib != null && (path == lib || path.startsWith('$lib/'))) {
      return IosPathKind.internalLibrary;
    }

    // Relative Documents paths
    if (path == 'Documents' || path.startsWith('Documents/')) {
      return IosPathKind.internalDocuments;
    }

    // 4. Standard iOS Application container check
    final match = _appContainerRegex.firstMatch(path);
    if (match != null) {
      final containerRoot = normalize(match.group(1)!);
      final currentRoot = _currentSandboxRoot;

      // If matches current sandbox root, it's internal
      if (currentRoot != null && containerRoot == currentRoot) {
        final type = match.group(2);
        return type == 'Documents'
            ? IosPathKind.internalDocuments
            : IosPathKind.internalLibrary;
      }

      // Check if it's within an explicitly authorized external root
      if (isWithinExternalRoots(path)) {
        return IosPathKind.externalAppContainer;
      }

      // If the path physically exists on disk and is NOT our own sandbox, it's an external app
      try {
        if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
          return IosPathKind.externalAppContainer;
        }
      } on FileSystemException catch (e) {
        // errno = 1 (Operation not permitted) indicates another app container restricted by sandbox
        if (e.osError?.errorCode == 1) {
          return IosPathKind.externalAppContainer;
        }
      } catch (_) {}

      // If it doesn't exist and isn't external, it might be a stale Vynody sandbox from before reinstall
      return IosPathKind.internalDocuments;
    }

    return IosPathKind.externalFilesystem;
  }

  /// Checks if [path] is within any explicitly registered external root directory.
  static bool isWithinExternalRoots(String path) {
    if (path.isEmpty || _externalRoots.isEmpty) return false;
    final norm = normalize(path);
    for (final root in _externalRoots) {
      if (norm == root || norm.startsWith('$root/')) {
        return true;
      }
    }
    return false;
  }

  /// Resolves an iOS / macOS path that may contain a stale Vynody UUID
  /// to the current application container directory.
  ///
  /// Safe against File Provider Storage and other App containers:
  /// - Only [IosPathKind.internalDocuments] and [IosPathKind.internalLibrary] are rewritten.
  /// - [IosPathKind.fileProviderStorage] and [IosPathKind.externalAppContainer] are NEVER touched.
  static String resolveSandboxPath(String path) {
    if (path.isEmpty || (!Platform.isIOS && !Platform.isMacOS)) {
      return path;
    }

    final cached = _resolutionCache[path];
    if (cached != null) return cached;

    final trimmed = normalize(path);

    // Short-circuit non-container paths or remote URLs
    if (trimmed.contains('://')) {
      _putCache(path, trimmed);
      return trimmed;
    }

    final kind = classify(trimmed);

    // Fast-path: Never rewrite File Provider Storage or external containers
    if (kind == IosPathKind.fileProviderStorage ||
        kind == IosPathKind.externalAppContainer ||
        kind == IosPathKind.externalFilesystem ||
        kind == IosPathKind.nonFileUri) {
      _putCache(path, trimmed);
      return trimmed;
    }

    String result = trimmed;
    final docDir = _currentDocDir;
    final libDir = _currentLibDir;

    // 1. Thumbnails resolution
    if (libDir != null && libDir.isNotEmpty) {
      final thumbMatch = _iosThumbRegex.firstMatch(trimmed);
      if (thumbMatch != null) {
        result = p.join(libDir, 'thumbnails', thumbMatch.group(1)!);
        _putCache(path, result);
        return result;
      }
    }

    // 2. Relative Documents resolution
    if (trimmed == 'Documents' || trimmed.startsWith('Documents/')) {
      if (docDir != null && docDir.isNotEmpty) {
        final subPath = trimmed == 'Documents'
            ? ''
            : trimmed.substring('Documents/'.length);
        result = subPath.isEmpty ? docDir : p.join(docDir, subPath);
        _putCache(path, result);
        return result;
      }
    }

    // 3. Stale Vynody Container resolution
    final match = _appContainerRegex.firstMatch(trimmed);
    if (match != null) {
      final type = match.group(2);
      final subPath = match.group(3);

      if (type == 'Documents') {
        if (docDir != null && docDir.isNotEmpty) {
          result = (subPath == null || subPath.isEmpty)
              ? docDir
              : p.join(docDir, subPath);
        }
      } else {
        if (libDir != null && libDir.isNotEmpty) {
          result = (subPath == null || subPath.isEmpty)
              ? libDir
              : p.join(libDir, subPath);
        }
      }
    }

    _putCache(path, result);
    return result;
  }

  static void _putCache(String path, String result) {
    if (_resolutionCache.length > _maxCacheSize) {
      _resolutionCache.clear();
    }
    _resolutionCache[path] = result;
  }
}
