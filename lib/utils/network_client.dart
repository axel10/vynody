import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:proxy_getter/proxy_getter.dart';

export 'package:dio/dio.dart'
    show Response, Options, DioException, CancelToken, ProgressCallback;

/// 全局共享的网络请求封装。
///
/// 所有业务网络请求都应通过这个单例发起，方便统一加拦截器、日志、鉴权和重试逻辑。
class NetworkClient {
  NetworkClient._internal()
    : _dio = Dio(
        BaseOptions(
          // 不设置默认超时，让具体业务按需决定，避免长耗时的 AI 请求被全局 15 秒限制误杀。
          connectTimeout: null,
          receiveTimeout: null,
          sendTimeout: null,
          headers: const {
            'Accept': 'application/json',
            'User-Agent': 'VibeFlow/1.0 (zgmf300@outlook.com)',
          },
        ),
      ) {
    _dio.httpClientAdapter = _SystemProxyHttpClientAdapter();

    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            debugPrint('Network Request: [${options.method}] ${options.uri}');
            return handler.next(options);
          },
        ),
      );
    }
  }

  static final NetworkClient instance = NetworkClient._internal();

  final Dio _dio;

  /// 提供对底层 Dio 实例的直接访问，用于需要特殊处理的场景。
  Dio get dio => _dio;

  /// 向全局 Dio 添加单个拦截器。
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// 向全局 Dio 批量添加拦截器。
  void addInterceptors(Iterable<Interceptor> interceptors) {
    _dio.interceptors.addAll(interceptors);
  }

  /// 发起 GET 请求
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    return _dio.get<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 发起 POST 请求
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 发起 PUT 请求
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    void Function(int, int)? onSendProgress,
    void Function(int, int)? onReceiveProgress,
  }) async {
    return _dio.put<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );
  }

  /// 发起 DELETE 请求
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.delete<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// 通用的下载方法
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    return _dio.download(
      urlPath,
      savePath,
      onReceiveProgress: onReceiveProgress,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      deleteOnError: deleteOnError,
      lengthHeader: lengthHeader,
      data: data,
      options: options,
    );
  }
}

class _SystemProxyHttpClientAdapter implements HttpClientAdapter {
  _SystemProxyHttpClientAdapter();

  final Map<String, String> _proxyCache = {};
  final Map<String, Future<String>> _proxyLookupsInFlight = {};
  Future<SystemProxy>? _systemProxyFuture;
  bool _closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError(
        "Can't establish connection after the adapter was closed.",
      );
    }

    final httpClient = HttpClient()..idleTimeout = const Duration(seconds: 3);
    final proxyRule = await _resolveProxyRule(options.uri);
    httpClient.findProxy = (uri) => proxyRule;

    final connectionTimeout = options.connectTimeout;
    if (connectionTimeout != null && connectionTimeout > Duration.zero) {
      httpClient.connectionTimeout = connectionTimeout;
    } else {
      httpClient.connectionTimeout = null;
    }

    try {
      final reqFuture = httpClient.openUrl(options.method, options.uri);
      late HttpClientRequest request;
      if (connectionTimeout != null && connectionTimeout > Duration.zero) {
        request = await reqFuture.timeout(
          connectionTimeout,
          onTimeout: () {
            throw DioException.connectionTimeout(
              requestOptions: options,
              timeout: connectionTimeout,
            );
          },
        );
      } else {
        request = await reqFuture;
      }

      final requestWR = WeakReference<HttpClientRequest>(request);
      cancelFuture?.whenComplete(() {
        requestWR.target?.abort();
      });

      options.headers.forEach((key, value) {
        if (value != null) {
          request.headers.set(
            key,
            value,
            preserveHeaderCase: options.preserveHeaderCase,
          );
        }
      });

      request.followRedirects = options.followRedirects;
      request.maxRedirects = options.maxRedirects;
      request.persistentConnection = options.persistentConnection;

      if (requestStream != null) {
        Future<dynamic> future = request.addStream(requestStream);
        final sendTimeout = options.sendTimeout;
        if (sendTimeout != null && sendTimeout > Duration.zero) {
          future = future.timeout(
            sendTimeout,
            onTimeout: () {
              request.abort();
              throw DioException.sendTimeout(
                timeout: sendTimeout,
                requestOptions: options,
              );
            },
          );
        }
        await future;
      }

      Future<HttpClientResponse> future = request.close();
      final receiveTimeout = options.receiveTimeout ?? Duration.zero;
      if (receiveTimeout > Duration.zero) {
        future = future.timeout(
          receiveTimeout,
          onTimeout: () {
            request.abort();
            throw DioException.receiveTimeout(
              timeout: receiveTimeout,
              requestOptions: options,
            );
          },
        );
      }
      final responseStream = await future;

      if (responseStream.redirects.isNotEmpty) {
        debugPrint(
          '[NetworkClient] redirect: ${options.uri} -> ${responseStream.redirects.last.location}',
        );
      }

      final headers = <String, List<String>>{};
      responseStream.headers.forEach((key, values) {
        headers[key] = values;
      });

      String? httpVersion;
      try {
        httpVersion = (responseStream.headers as dynamic).protocolVersion;
      } catch (_) {}

      final responseBody = ResponseBody(
        responseStream.cast(),
        responseStream.statusCode,
        headers: headers,
        isRedirect:
            responseStream.isRedirect || responseStream.redirects.isNotEmpty,
        redirects: responseStream.redirects
            .map((e) => RedirectRecord(e.statusCode, e.method, e.location))
            .toList(),
        statusMessage: responseStream.reasonPhrase,
        onClose: () => httpClient.close(force: false),
      );
      if (httpVersion != null) {
        responseBody.extra[HttpClientAdapter.extraKeyHttpVersion] ??=
            httpVersion;
      }

      return responseBody;
    } on SocketException catch (e) {
      httpClient.close(force: true);
      if (e.message.contains('timed out')) {
        final Duration effectiveTimeout;
        if (connectionTimeout != null && connectionTimeout > Duration.zero) {
          effectiveTimeout = connectionTimeout;
        } else if (httpClient.connectionTimeout != null &&
            httpClient.connectionTimeout! > Duration.zero) {
          effectiveTimeout = httpClient.connectionTimeout!;
        } else {
          effectiveTimeout = Duration.zero;
        }
        throw DioException.connectionTimeout(
          requestOptions: options,
          timeout: effectiveTimeout,
          error: e,
        );
      }
      throw DioException.connectionError(
        requestOptions: options,
        reason: e.message,
        error: e,
      );
    } catch (_) {
      httpClient.close(force: true);
      rethrow;
    }
  }

  @override
  void close({bool force = false}) {
    _closed = true;
  }

  Future<String> _resolveProxyRule(Uri uri) async {
    final cacheKey = uri.toString();
    final cached = _proxyCache[cacheKey];
    if (cached != null) return cached;

    final inFlight = _proxyLookupsInFlight[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _detectProxyRule(uri).whenComplete(() {
      _proxyLookupsInFlight.remove(cacheKey);
    });
    _proxyLookupsInFlight[cacheKey] = future;

    final rule = await future;
    _proxyCache[cacheKey] = rule;
    return rule;
  }

  Future<String> _detectProxyRule(Uri uri) async {
    try {
      if (_supportsSystemProxyPlugin) {
        final proxy = await _loadSystemProxy();
        if (proxy != null) {
          if (!proxy.enable || proxy.host.trim().isEmpty || proxy.port <= 0) {
            return 'DIRECT';
          }

          if (_isBypassed(uri, proxy.bypass)) {
            return 'DIRECT';
          }

          final proxyAddress = _normalizeProxyAddress(
            '${proxy.host}:${proxy.port}',
          );
          if (proxyAddress.isNotEmpty) {
            return 'PROXY $proxyAddress; DIRECT';
          }
        }
      }
    } catch (e) {
      debugPrint('[NetworkClient] system proxy detect failed for $uri: $e');
    }

    return HttpClient.findProxyFromEnvironment(uri);
  }

  bool get _supportsSystemProxyPlugin {
    return Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isLinux;
  }

  Future<SystemProxy?> _loadSystemProxy() async {
    _systemProxyFuture ??= getSystemProxy();
    try {
      return await _systemProxyFuture;
    } catch (e) {
      _systemProxyFuture = null;
      debugPrint('[NetworkClient] failed to load system proxy: $e');
      return null;
    }
  }

  bool _isBypassed(Uri uri, String bypassList) {
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || bypassList.trim().isEmpty) return false;

    final entries = bypassList
        .split(RegExp(r'[;,|]'))
        .map((entry) {
          return entry.trim().toLowerCase();
        })
        .where((entry) => entry.isNotEmpty);

    for (final entry in entries) {
      if (entry == '<local>' && !host.contains('.')) {
        return true;
      }
      if (_matchesBypassPattern(host, entry)) {
        return true;
      }
    }

    return false;
  }

  bool _matchesBypassPattern(String host, String pattern) {
    if (pattern == '*') return true;

    if (pattern.startsWith('*.')) {
      final suffix = pattern.substring(2);
      return host == suffix || host.endsWith('.$suffix');
    }

    if (pattern.startsWith('.')) {
      final suffix = pattern.substring(1);
      return host == suffix || host.endsWith('.$suffix');
    }

    if (!pattern.contains('*')) {
      return host == pattern;
    }

    final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
    return RegExp('^$escaped\$').hasMatch(host);
  }

  String _normalizeProxyAddress(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';

    final parsed = Uri.tryParse(text);
    if (parsed != null && parsed.scheme.isNotEmpty && parsed.host.isNotEmpty) {
      final port = parsed.hasPort ? parsed.port : null;
      return port == null ? parsed.host : '${parsed.host}:$port';
    }

    text = text.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
    text = text.replaceFirst(RegExp(r'^PROXY\s+', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^SOCKS\s+', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'/$'), '');
    return text;
  }
}
