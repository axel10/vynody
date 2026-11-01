import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:vynody/player/lastfm/lastfm_credentials.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_entry.dart';
import 'package:vynody/utils/network_client.dart';

const String _lastFmEndpoint = 'https://ws.audioscrobbler.com/2.0/';

/// Last.fm 返回的业务错误。
///
/// 错误码语义见 https://www.last.fm/api/errorcodes，这里按「能不能重试」
/// 归成三类，调用方据此决定是保留队列、丢弃还是要求重新授权。
class LastFmApiException implements Exception {
  const LastFmApiException({
    required this.code,
    required this.message,
    this.httpStatus,
  });

  /// -1 表示网络层失败（没有拿到 Last.fm 的业务错误码）。
  final int code;
  final String message;
  final int? httpStatus;

  /// session key 失效，需要重新授权。
  bool get isSessionInvalid => code == 9;

  /// 临时性故障：过一会儿重试还有机会成功，队列必须保留。
  bool get isRetryable =>
      code == -1 || code == 8 || code == 11 || code == 16 || code == 29;

  /// 重试也不会成功的错误（参数错误、无权限、key 被吊销等），
  /// 继续留在队列里只会无限堆积。
  bool get isFatal => !isRetryable && !isSessionInvalid;

  @override
  String toString() => 'LastFmApiException($code): $message';
}

/// 授权成功后拿到的会话。
class LastFmSession {
  const LastFmSession({required this.key, required this.username});

  final String key;
  final String username;

  bool get isValid => key.isNotEmpty;
}

/// `track.scrobble` 的应答统计。
class LastFmScrobbleAck {
  const LastFmScrobbleAck({required this.accepted, required this.ignored});

  final int accepted;
  final int ignored;

  @override
  String toString() => 'accepted=$accepted ignored=$ignored';
}

/// 计算 Last.fm 方法签名。
///
/// 规则：除 `format` / `callback` / `api_sig` 外的所有参数，按 key 升序
/// 直接拼接 `key + value`（中间不加分隔符），末尾接上 shared secret，
/// 取小写 md5。参数值必须是**未经 URL 编码**的原始值。
@visibleForTesting
String signLastFmParams(Map<String, String> params, String sharedSecret) {
  final keys = params.keys
      .where((key) => key != 'format' && key != 'callback' && key != 'api_sig')
      .toList()
    ..sort();
  final buffer = StringBuffer();
  for (final key in keys) {
    buffer
      ..write(key)
      ..write(params[key]);
  }
  buffer.write(sharedSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString();
}

/// Last.fm Web API 客户端。
///
/// 只覆盖上报所需的方法：授权流程 + now playing + scrobble。
class LastFmApiClient {
  LastFmApiClient({
    NetworkClient? client,
    String? sharedSecret,
  }) : _client = client ?? NetworkClient.instance,
       _sharedSecret = sharedSecret ?? LastFmCredentials.sharedSecret;

  final NetworkClient _client;
  final String? _sharedSecret;

  bool get isConfigured =>
      LastFmCredentials.apiKey.isNotEmpty && (_sharedSecret?.isNotEmpty ?? false);

  /// `auth.getToken`：申请一次性 token，用于拼出浏览器授权地址。
  Future<String> fetchAuthToken() async {
    final json = await _call('auth.getToken');
    final token = (json['token'] as String?)?.trim() ?? '';
    if (token.isEmpty) {
      throw const LastFmApiException(
        code: -1,
        message: 'auth.getToken returned an empty token',
      );
    }
    return token;
  }

  /// 拼接浏览器授权页地址。
  Uri buildAuthorizationUri(String token) {
    return Uri.https('www.last.fm', '/api/auth/', <String, String>{
      'api_key': LastFmCredentials.apiKey,
      'token': token,
    });
  }

  /// `auth.getSession`：用户授权后，用 token 换持久 session key。
  Future<LastFmSession> fetchSession(String token) async {
    final json = await _call('auth.getSession', params: {'token': token});
    final session = json['session'];
    if (session is! Map) {
      throw const LastFmApiException(
        code: -1,
        message: 'auth.getSession returned no session',
      );
    }
    final key = (session['key'] as String?)?.trim() ?? '';
    final username = (session['name'] as String?)?.trim() ?? '';
    if (key.isEmpty) {
      throw const LastFmApiException(
        code: -1,
        message: 'auth.getSession returned an empty session key',
      );
    }
    return LastFmSession(key: key, username: username);
  }

  /// `track.updateNowPlaying`：尽力而为，失败不影响播放。
  Future<void> updateNowPlaying({
    required String sessionKey,
    required LastFmScrobbleEntry entry,
  }) async {
    await _call(
      'track.updateNowPlaying',
      params: entry.toNowPlayingParams(),
      sessionKey: sessionKey,
    );
  }

  /// `track.scrobble`：单次最多 50 条，超出需分批。
  Future<LastFmScrobbleAck> scrobble({
    required String sessionKey,
    required List<LastFmScrobbleEntry> entries,
  }) async {
    if (entries.isEmpty) {
      return const LastFmScrobbleAck(accepted: 0, ignored: 0);
    }
    if (entries.length > 50) {
      throw const LastFmApiException(
        code: -1,
        message: 'track.scrobble accepts at most 50 entries per request',
      );
    }

    final params = <String, String>{};
    for (var i = 0; i < entries.length; i++) {
      params.addAll(entries[i].toScrobbleParams(i));
    }

    final json = await _call(
      'track.scrobble',
      params: params,
      sessionKey: sessionKey,
    );

    final attributes = _extractScrobbleAttributes(json);
    return LastFmScrobbleAck(
      accepted: _readInt(attributes?['accepted']) ?? entries.length,
      ignored: _readInt(attributes?['ignored']) ?? 0,
    );
  }

  Map<String, dynamic>? _extractScrobbleAttributes(Map<String, dynamic> json) {
    final scrobbles = json['scrobbles'];
    if (scrobbles is! Map) return null;
    final attributes = scrobbles['@attr'];
    if (attributes is Map) {
      return attributes.map((key, value) => MapEntry('$key', value));
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<Map<String, dynamic>> _call(
    String method, {
    Map<String, String> params = const <String, String>{},
    String? sessionKey,
  }) async {
    final secret = _sharedSecret;
    if (!isConfigured || secret == null) {
      throw const LastFmApiException(
        code: -1,
        message: 'Last.fm credentials are not configured in this build',
      );
    }

    final payload = <String, String>{
      'method': method,
      'api_key': LastFmCredentials.apiKey,
    };
    if (sessionKey != null && sessionKey.isNotEmpty) {
      payload['sk'] = sessionKey;
    }
    for (final entry in params.entries) {
      if (entry.value.isEmpty) continue;
      payload[entry.key] = entry.value;
    }
    payload['api_sig'] = signLastFmParams(payload, secret);
    // format 不参与签名，因此必须放在签名之后。
    payload['format'] = 'json';

    Response<dynamic> response;
    try {
      response = await _client.post<dynamic>(
        _lastFmEndpoint,
        data: payload,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          // Last.fm 的业务错误走 400/403，需要读 body 里的 error 码，
          // 不能让 dio 先把异常抛掉。
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (error) {
      throw LastFmApiException(
        code: -1,
        message: error.message ?? error.type.name,
        httpStatus: error.response?.statusCode,
      );
    }

    final json = _decodeBody(response.data);
    final errorCode = _readInt(json['error']);
    if (errorCode != null) {
      throw LastFmApiException(
        code: errorCode,
        message: (json['message'] as String?)?.trim() ?? '',
        httpStatus: response.statusCode,
      );
    }

    if (response.statusCode != null && response.statusCode! >= 400) {
      throw LastFmApiException(
        code: -1,
        message: 'HTTP ${response.statusCode}',
        httpStatus: response.statusCode,
      );
    }

    return json;
  }

  Map<String, dynamic> _decodeBody(Object? data) {
    if (data is Map) {
      return data.map((key, value) => MapEntry('$key', value));
    }
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry('$key', value));
        }
      } on FormatException {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }
}
