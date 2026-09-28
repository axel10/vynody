import 'dart:convert';
import 'package:dart_webdav/dart_webdav.dart' as dw;
import 'package:dio/dio.dart';
import '../remote_server_models.dart';

// Re-export WebDavFile and WebDavException so callers don't need direct package imports
export 'package:dart_webdav/dart_webdav.dart'
    show WebDavFile, WebDavException, WebDavConnectionResult;

/// Common client interface for hierarchical remote file systems (WebDAV, SMB, etc.).
abstract class RemoteDirectoryClient {
  Future<List<dw.WebDavFile>> listFiles(String path);
}

/// Vynody WebDAV client powered by the robust `dart_webdav` engine.
class WebDavClient implements RemoteDirectoryClient {
  final RemoteServer server;
  final String password;
  final dw.WebDavClient _inner;

  WebDavClient({
    required this.server,
    required this.password,
    Dio? customDio,
  }) : _inner = dw.WebDavClient.basic(
          baseUrl: server.url,
          username: server.username,
          password: password,
          options: dw.WebDavClientOptions(
            ignoreSsl: server.ignoreSsl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
            userAgent: 'Vynody/1.19.0',
          ),
          customDio: customDio,
        );

  /// Access the underlying high-performance [dw.WebDavClient] directly for streaming or advanced operations.
  dw.WebDavClient get inner => _inner;

  String get baseUrl => _inner.baseUrl;

  String get basicAuthHeader {
    final credentials = '${server.username}:$password';
    return 'Basic ${base64Encode(utf8.encode(credentials))}';
  }

  Map<String, String> get authHeaders => _inner.authHeaders;

  /// Safely encodes a relative or absolute URL path segment-by-segment.
  /// Converts `#` to `%23`, `+` to `%2B`, spaces to `%20`, brackets, etc.
  /// Idempotent (does not double-encode already percent-encoded strings).
  static String safeEncodePath(String path) => dw.SafeUrlEncoder.encodePath(path);

  /// Normalizes and encodes a full URL safely.
  static String safeEncodeUrl(String url) => dw.SafeUrlEncoder.encodeUrl(url);

  /// Builds a playable stream URL with inline authentication credentials.
  String buildStreamUrl(String relativePath) =>
      _inner.buildStreamUrl(relativePath);

  /// Builds a fully-qualified, safe percent-encoded URL for the given relative path.
  String buildFullUrl(String relativePath, {bool includeAuth = false}) =>
      _inner.buildFullUrl(relativePath, includeAuth: includeAuth);

  /// Tests WebDAV connection with auto-detection fallback.
  Future<ConnectionTestResult> testConnection() async {
    final result = await _inner.testConnection(explicitPath: server.customPath);
    if (result.success) {
      return ConnectionTestResult.success(
        message: result.message,
        serverVersion: result.serverVersion,
        detectedCustomPath: result.detectedCustomPath,
      );
    } else {
      return ConnectionTestResult.failure(result.message);
    }
  }

  /// Lists files and directories inside the given path using PROPFIND (Depth: 1).
  @override
  Future<List<dw.WebDavFile>> listFiles(String path) async {
    try {
      return await _inner.listFiles(path);
    } on dw.WebDavException catch (e) {
      // If root path was requested and returned 405/404, fallback to /dav
      if (path == '/' && (e.statusCode == 405 || e.statusCode == 404)) {
        try {
          return await _inner.listFiles('/dav');
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Parses PROPFIND Multi-Status XML response into a list of [WebDavFile].
  static List<dw.WebDavFile> parsePropfindXml(String xmlString, {String? requestPath}) =>
      dw.PropFindXmlParser.parseFiles(xmlString, requestPath: requestPath);

  /// Downloads text content of a file (e.g. .lrc lyrics file).
  Future<String?> getFileContent(String relativeOrFullPath) async {
    try {
      return await _inner.getText(relativeOrFullPath);
    } catch (_) {
      return null;
    }
  }
}
