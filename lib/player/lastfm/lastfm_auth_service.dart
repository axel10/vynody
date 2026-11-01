import 'package:flutter/foundation.dart';

import 'package:vynody/player/lastfm/lastfm_api_client.dart';
import 'package:vynody/utils/secure_storage.dart';

/// 一次待完成的授权：token 用于换取 session，[authorizationUri] 给用户打开。
class LastFmAuthRequest {
  const LastFmAuthRequest({
    required this.token,
    required this.authorizationUri,
  });

  final String token;
  final Uri authorizationUri;
}

/// Last.fm 授权与凭证管理。
///
/// 采用官方桌面端流程（无回跳 scheme）：
///   1. `auth.getToken` 拿一次性 token
///   2. 浏览器打开授权页，用户点「允许」
///   3. 用户回到应用点「已完成授权」，`auth.getSession` 换取持久 session key
///
/// session key 属于凭证，写进 [AppSecureStorage]；用户名字段同样存储，
/// 仅用于界面显示。
class LastFmAuthService {
  LastFmAuthService({
    LastFmApiClient? client,
    AppSecureStorage? storage,
  }) : _client = client ?? LastFmApiClient(),
       _storage = storage ?? appSecureStorage;

  static const String sessionKeyStorageKey = 'lastfm_session_key';
  static const String usernameStorageKey = 'lastfm_username';

  final LastFmApiClient _client;
  final AppSecureStorage _storage;

  /// 热路径（每秒的位置回调）不能每次都走异步读盘，命中后常驻内存。
  LastFmSession? _cachedSession;
  bool _cacheLoaded = false;

  bool get isConfigured => _client.isConfigured;

  /// 已加载的会话（可能为 null，需要先调用 [loadSession]）。
  LastFmSession? get cachedSession => _cachedSession;

  Future<LastFmSession?> loadSession({bool forceReload = false}) async {
    if (_cacheLoaded && !forceReload) return _cachedSession;

    try {
      final key = (await _storage.read(key: sessionKeyStorageKey))?.trim();
      if (key == null || key.isEmpty) {
        _cachedSession = null;
        _cacheLoaded = true;
        return null;
      }
      final username =
          (await _storage.read(key: usernameStorageKey))?.trim() ?? '';
      _cachedSession = LastFmSession(key: key, username: username);
    } catch (error) {
      debugPrint('LastFmAuthService: failed to load session: $error');
      _cachedSession = null;
    }

    _cacheLoaded = true;
    return _cachedSession;
  }

  Future<LastFmAuthRequest> beginAuthorization() async {
    final token = await _client.fetchAuthToken();
    return LastFmAuthRequest(
      token: token,
      authorizationUri: _client.buildAuthorizationUri(token),
    );
  }

  Future<LastFmSession> completeAuthorization(String token) async {
    final session = await _client.fetchSession(token);
    await _storage.write(key: sessionKeyStorageKey, value: session.key);
    if (session.username.isNotEmpty) {
      await _storage.write(key: usernameStorageKey, value: session.username);
    }
    _cachedSession = session;
    _cacheLoaded = true;
    return session;
  }

  Future<void> signOut() async {
    try {
      await _storage.delete(key: sessionKeyStorageKey);
      await _storage.delete(key: usernameStorageKey);
    } catch (error) {
      debugPrint('LastFmAuthService: failed to clear session: $error');
    }
    _cachedSession = null;
    _cacheLoaded = true;
  }

  /// session 被服务端判定失效（error 9）时清掉本地凭证，等用户重新授权。
  Future<void> invalidateSession() => signOut();
}
