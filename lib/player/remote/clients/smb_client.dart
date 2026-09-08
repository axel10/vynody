import 'dart:io';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../remote_server_models.dart';

/// Representation of a file or folder in an SMB share.
class SmbFile {
  final String share;
  final String path;
  final String name;
  final bool isDirectory;
  final int contentLength;
  final DateTime? lastModified;

  const SmbFile({
    required this.share,
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.contentLength,
    this.lastModified,
  });

  bool get isAudio {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    return const {
      '.mp3',
      '.flac',
      '.wav',
      '.m4a',
      '.aac',
      '.ogg',
      '.opus',
      '.ape',
      '.wma',
      '.dsf',
      '.dff',
      '.alac',
      '.webm',
      '.aif',
      '.aiff',
      '.caf',
      '.m4b',
      '.m4p',
      '.mid',
      '.midi',
    }.contains(ext);
  }

  bool get isImage {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp'}.contains(ext);
  }

  bool get isLyric {
    if (isDirectory) return false;
    final ext = p.extension(name).toLowerCase();
    return ext == '.lrc';
  }
}

/// Client helper for interacting with SMB servers using `dart_smb2`.
class SmbClient {
  final RemoteServer server;
  final String password;

  // Cached pool per share to reuse TCP connections.
  static final Map<String, Smb2Pool> _poolCache = {};

  SmbClient({
    required this.server,
    required this.password,
  });

  /// Extracts host and optional port from the server url.
  String get host {
    var raw = server.url.trim();
    if (raw.startsWith('smb://')) {
      raw = raw.substring(6);
    }
    final slashIdx = raw.indexOf('/');
    if (slashIdx >= 0) {
      raw = raw.substring(0, slashIdx);
    }
    final colonIdx = raw.indexOf(':');
    if (colonIdx >= 0) {
      return raw.substring(0, colonIdx);
    }
    return raw;
  }

  /// Default share name specified in customPath, if any.
  String? get defaultShare {
    final custom = server.customPath?.trim();
    if (custom == null || custom.isEmpty) return null;
    var clean = custom.startsWith('/') ? custom.substring(1) : custom;
    final slashIdx = clean.indexOf('/');
    if (slashIdx >= 0) {
      return clean.substring(0, slashIdx);
    }
    return clean.isNotEmpty ? clean : null;
  }

  /// Cache key for pooling workers by server and share.
  String _poolKey(String share) => '${server.id}:$share';

  /// Obtains a pooled worker for a given share.
  Future<Smb2Pool> getPool(String share) async {
    final key = _poolKey(share);
    final existing = _poolCache[key];
    if (existing != null) {
      try {
        await existing.echo();
        return existing;
      } catch (_) {
        _poolCache.remove(key);
        try {
          await existing.disconnect();
        } catch (_) {}
      }
    }

    final pool = await Smb2Pool.connect(
      host: host,
      share: share,
      user: server.username.isNotEmpty ? server.username : null,
      password: password.isNotEmpty ? password : null,
      domain: server.domain,
      workers: 2,
      timeoutSeconds: 15,
    );
    _poolCache[key] = pool;
    return pool;
  }

  /// Evicts and closes any open pool for this server.
  static Future<void> closeServerPools(String serverId) async {
    final keysToRemove = _poolCache.keys
        .where((k) => k.startsWith('$serverId:'))
        .toList();
    for (final k in keysToRemove) {
      final pool = _poolCache.remove(k);
      try {
        await pool?.disconnect();
      } catch (_) {}
    }
  }

  /// Tests connection to server and lists available shares.
  Future<ConnectionTestResult> testConnection() async {
    try {
      final shares = await listShares();
      if (shares.isEmpty) {
        return const ConnectionTestResult.success(
          message: 'Connected successfully, but no shared folders were found.',
          availableShares: [],
        );
      }

      final shareNames = shares
          .where((s) => !s.name.endsWith(r'$')) // Filter out admin shares like IPC$, C$, ADMIN$
          .map((s) => s.name)
          .toList();

      return ConnectionTestResult.success(
        message: 'Successfully connected! Found ${shareNames.length} shared folder(s).',
        availableShares: shareNames,
      );
    } catch (e) {
      debugPrint('[SmbClient] testConnection error: $e');
      return ConnectionTestResult.failure('Failed to connect to SMB server: $e');
    }
  }

  /// Lists all accessible shares on the server.
  Future<List<Smb2ShareInfo>> listShares() async {
    return await Smb2Pool.listSharesOn(
      host: host,
      user: server.username.isNotEmpty ? server.username : null,
      password: password.isNotEmpty ? password : null,
      domain: server.domain,
      timeoutSeconds: 10,
    );
  }

  /// Lists files and folders in a given share and directory path.
  Future<List<SmbFile>> listFiles(String share, String relativePath) async {
    final pool = await getPool(share);
    var cleanPath = relativePath.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    if (cleanPath.endsWith('/')) cleanPath = cleanPath.substring(0, cleanPath.length - 1);

    final entries = await pool.listDirectory(cleanPath);
    final results = <SmbFile>[];

    for (final entry in entries) {
      if (entry.name == '.' || entry.name == '..') continue;

      final entryPath = cleanPath.isEmpty ? entry.name : '$cleanPath/${entry.name}';
      results.add(SmbFile(
        share: share,
        path: entryPath,
        name: entry.name,
        isDirectory: entry.isDirectory,
        contentLength: entry.stat.size,
        lastModified: entry.stat.modified,
      ));
    }

    // Sort: directories first, then alphabetical
    results.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return results;
  }

  /// Reads a byte range from an SMB file.
  Future<Uint8List> readFileRange(
    String share,
    String relativePath, {
    int offset = 0,
    required int length,
  }) async {
    final pool = await getPool(share);
    var cleanPath = relativePath.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    return await pool.readFileRange(cleanPath, offset: offset, length: length);
  }

  /// Streams chunks of a file.
  Stream<Uint8List> streamFile(
    String share,
    String relativePath, {
    int chunkSize = 256 * 1024,
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
  }) async* {
    final pool = await getPool(share);
    var cleanPath = relativePath.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);

    yield* pool.streamFile(
      cleanPath,
      chunkSize: chunkSize,
      onProgress: onProgress,
      isCanceled: isCanceled,
    );
  }

  /// Downloads a remote file to a local destination.
  Future<int> downloadToFile(
    String share,
    String relativePath,
    File destFile, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    final pool = await getPool(share);
    var cleanPath = relativePath.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);

    return await pool.downloadToFile(
      cleanPath,
      destFile,
      onProgress: onProgress,
      isCanceled: isCanceled,
    );
  }

  /// Gets the size of a remote file.
  Future<int> getFileSize(String share, String relativePath) async {
    final pool = await getPool(share);
    var cleanPath = relativePath.trim();
    if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);
    return await pool.fileSize(cleanPath);
  }
}
