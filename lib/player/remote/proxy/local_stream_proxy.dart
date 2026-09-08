import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../clients/smb_client.dart';
import '../remote_server_models.dart';
import '../remote_server_storage.dart';

/// Lightweight local HTTP streaming proxy bridging `smb://` to `http://127.0.0.1:<port>/smb/stream`.
///
/// Enables media playback kernels (ExoPlayer, AVFoundation, Rust AudioCore) and TagLib
/// to stream SMB audio and read metadata using standard HTTP Range requests (206 Partial Content).
class LocalStreamProxy {
  static final LocalStreamProxy instance = LocalStreamProxy._();
  LocalStreamProxy._();

  HttpServer? _server;
  int? _port;
  RemoteServerStorage? _storage;

  Future<RemoteServerStorage> _getStorage() async {
    if (_storage != null) return _storage!;
    final prefs = await SharedPreferences.getInstance();
    _storage = RemoteServerStorage(prefs: prefs);
    return _storage!;
  }

  /// Starts the local HTTP proxy if not already running.
  Future<int> ensureStarted() async {
    if (_server != null && _port != null) return _port!;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(
        _handleRequest,
        onError: (err) => debugPrint('[LocalStreamProxy] Server error: $err'),
      );
      debugPrint('[LocalStreamProxy] Started on port $_port');
      return _port!;
    } catch (e) {
      debugPrint('[LocalStreamProxy] Failed to bind: $e');
      rethrow;
    }
  }

  /// Stops the local HTTP proxy server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }

  /// Builds a playable local HTTP streaming URL for a given SMB resource.
  Future<String> buildSmbStreamUrl({
    required String serverId,
    required String share,
    required String relativePath,
  }) async {
    final port = await ensureStarted();
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      path: '/smb/stream',
      queryParameters: {
        'serverId': serverId,
        'share': share,
        'path': relativePath,
      },
    );
    return uri.toString();
  }

  /// Handles incoming HTTP streaming requests.
  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method == 'OPTIONS') {
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Headers', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    if (request.uri.path != '/smb/stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final serverId = request.uri.queryParameters['serverId'];
    final share = request.uri.queryParameters['share'];
    final relativePath = request.uri.queryParameters['path'];

    if (serverId == null || share == null || relativePath == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final storage = await _getStorage();
    final servers = storage.loadServers();
    final server = servers.cast<RemoteServer?>().firstWhere(
          (s) => s?.id == serverId,
          orElse: () => null,
        );

    if (server == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Server not found');
      await request.response.close();
      return;
    }

    final password = await storage.getPassword(serverId) ?? '';
    final smbClient = SmbClient(server: server, password: password);

    try {
      final totalSize = await smbClient.getFileSize(share, relativePath);
      final contentType = _getContentType(relativePath);

      request.response.headers.add('Accept-Ranges', 'bytes');
      request.response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.response.headers.add('Access-Control-Allow-Origin', '*');

      if (request.method == 'HEAD') {
        request.response.headers.set(HttpHeaders.contentLengthHeader, totalSize.toString());
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        // Range: bytes=start-end
        final rangeSpec = rangeHeader.substring(6).trim();
        final parts = rangeSpec.split('-');
        int start = 0;
        int end = totalSize - 1;

        if (parts[0].isNotEmpty) {
          start = int.tryParse(parts[0]) ?? 0;
        }
        if (parts.length > 1 && parts[1].isNotEmpty) {
          end = int.tryParse(parts[1]) ?? (totalSize - 1);
        }

        if (start > end || start >= totalSize) {
          request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalSize');
          await request.response.close();
          return;
        }

        if (end >= totalSize) {
          end = totalSize - 1;
        }

        final length = end - start + 1;
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalSize');
        request.response.headers.set(HttpHeaders.contentLengthHeader, length.toString());

        // For smaller chunks (under 2MB, e.g. TagLib metadata preview), read in one go.
        if (length <= 2 * 1024 * 1024) {
          final data = await smbClient.readFileRange(
            share,
            relativePath,
            offset: start,
            length: length,
          );
          request.response.add(data);
          await request.response.close();
        } else {
          // Stream in chunks using a single persistent handle for maximum throughput
          final pool = await smbClient.getPool(share);
          var cleanPath = relativePath.trim();
          if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);

          await pool.withFile(cleanPath, (file) async {
            const chunkSize = 1024 * 1024; // 1MB chunks
            int currentOffset = start;
            while (currentOffset <= end) {
              final remaining = end - currentOffset + 1;
              final toRead = remaining < chunkSize ? remaining : chunkSize;
              final chunk = await file.read(
                offset: currentOffset,
                length: toRead,
              );
              if (chunk.isEmpty) break;
              try {
                request.response.add(chunk);
                await request.response.flush();
                currentOffset += chunk.length;
              } catch (_) {
                // Client aborted connection (e.g. seek / track skip)
                break;
              }
            }
          }, knownSize: totalSize);
          try {
            await request.response.close();
          } catch (_) {}
        }
      } else {
        // Full file streaming using persistent handle
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentLengthHeader, totalSize.toString());

        final pool = await smbClient.getPool(share);
        var cleanPath = relativePath.trim();
        if (cleanPath.startsWith('/')) cleanPath = cleanPath.substring(1);

        await pool.withFile(cleanPath, (file) async {
          const chunkSize = 1024 * 1024; // 1MB chunks
          int currentOffset = 0;
          while (currentOffset < totalSize) {
            final remaining = totalSize - currentOffset;
            final toRead = remaining < chunkSize ? remaining : chunkSize;
            final chunk = await file.read(
              offset: currentOffset,
              length: toRead,
            );
            if (chunk.isEmpty) break;
            try {
              request.response.add(chunk);
              await request.response.flush();
              currentOffset += chunk.length;
            } catch (_) {
              break;
            }
          }
        }, knownSize: totalSize);
        try {
          await request.response.close();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[LocalStreamProxy] Error serving request: $e');
      try {
        if (!request.response.headers.chunkedTransferEncoding) {
          request.response.statusCode = HttpStatus.internalServerError;
        }
        await request.response.close();
      } catch (_) {}
    }
  }

  String _getContentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return switch (ext) {
      '.mp3' => 'audio/mpeg',
      '.flac' => 'audio/flac',
      '.wav' => 'audio/wav',
      '.m4a' || '.aac' => 'audio/mp4',
      '.ogg' || '.opus' => 'audio/ogg',
      '.ape' => 'audio/x-ape',
      '.wma' => 'audio/x-ms-wma',
      '.webm' => 'audio/webm',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}
