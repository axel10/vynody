import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:proxy_getter/proxy_getter.dart';

/// 代理配置模式
enum AppProxyMode {
  system,
  direct,
  custom;

  static AppProxyMode fromString(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'direct' => AppProxyMode.direct,
      'custom' => AppProxyMode.custom,
      _ => AppProxyMode.system,
    };
  }

  String get id => name;
}

/// 全局网络代理统一管理器
///
/// 统一管理应用内所有 HTTP/HTTPS 网络请求（包括音频流媒体、封面、AI 歌词、元数据服务）的代理策略。
class AppProxyManager {
  AppProxyManager._();

  static final AppProxyManager instance = AppProxyManager._();

  AppProxyMode _mode = AppProxyMode.system;
  String _customHost = '127.0.0.1';
  int _customPort = 7890;
  String _customBypass = 'localhost, 127.0.0.1, <local>';

  SystemProxy? _cachedSystemProxy;
  DateTime? _systemProxyCachedAt;
  final Map<String, String> _ruleCache = {};
  final Map<String, Future<String>> _inFlightLookups = {};

  /// 系统代理结果缓存有效期。到期后重新读取，外部代理工具开/关系统代理才能在
  /// 不重启 App、不改应用内设置的情况下被感知。
  static const Duration systemProxyCacheTtl = Duration(seconds: 30);

  /// 系统代理读取入口，生产环境走 proxy_getter 插件；单元测试可注入替身。
  Future<SystemProxy> Function() _systemProxyLoader = getSystemProxy;

  VoidCallback? onProxyChanged;

  AppProxyMode get mode => _mode;
  String get customHost => _customHost;
  int get customPort => _customPort;
  String get customBypass => _customBypass;
  SystemProxy? get cachedSystemProxy => _cachedSystemProxy;

  /// 注入系统代理读取实现（仅测试）
  @visibleForTesting
  set systemProxyLoaderOverride(Future<SystemProxy> Function()? loader) {
    _systemProxyLoader = loader ?? getSystemProxy;
  }

  /// 读取/回拨系统代理缓存的写入时间（仅测试），用于模拟缓存过期。
  @visibleForTesting
  DateTime? get systemProxyCachedAtForTest => _systemProxyCachedAt;

  @visibleForTesting
  set systemProxyCachedAtForTest(DateTime? value) => _systemProxyCachedAt = value;

  /// 更新代理设置并清空现有代理规则缓存
  void updateSettings({
    required AppProxyMode mode,
    String? customHost,
    int? customPort,
    String? customBypass,
  }) {
    bool changed = false;
    if (_mode != mode) {
      _mode = mode;
      changed = true;
    }
    if (customHost != null && _customHost != customHost.trim()) {
      _customHost = customHost.trim();
      changed = true;
    }
    if (customPort != null && _customPort != customPort) {
      _customPort = customPort;
      changed = true;
    }
    if (customBypass != null && _customBypass != customBypass.trim()) {
      _customBypass = customBypass.trim();
      changed = true;
    }

    if (changed) {
      clearCache();
      if (_mode == AppProxyMode.system) {
        unawaited(refreshSystemProxy());
      }
      onProxyChanged?.call();
      debugPrint(
        '[AppProxyManager] Proxy updated: mode=$_mode, custom=$_customHost:$_customPort',
      );
    }
  }

  /// 清空代理缓存
  void clearCache() {
    _ruleCache.clear();
    _inFlightLookups.clear();
    _cachedSystemProxy = null;
    _systemProxyCachedAt = null;
  }

  /// 异步刷新系统代理信息
  Future<SystemProxy?> refreshSystemProxy() {
    if (!_supportsSystemProxyPlugin) return Future.value(null);
    return _pendingSystemProxyRefresh ??= _performSystemProxyRefresh();
  }

  Future<SystemProxy?>? _pendingSystemProxyRefresh;

  Future<SystemProxy?> _performSystemProxyRefresh() async {
    try {
      final proxy = await _systemProxyLoader();
      _cachedSystemProxy = proxy;
      _systemProxyCachedAt = DateTime.now();
      return proxy;
    } catch (e) {
      // 读取失败不写入缓存，下一次解析会重试，避免一次瞬时失败被永久固化为 DIRECT。
      debugPrint('[AppProxyManager] Failed to load system proxy: $e');
      return null;
    } finally {
      _pendingSystemProxyRefresh = null;
    }
  }

  /// 确保系统代理结果可用：缓存缺失或超过 [systemProxyCacheTtl] 时重新读取。
  Future<void> _ensureSystemProxyFresh() async {
    if (!_supportsSystemProxyPlugin) return;
    final cachedAt = _systemProxyCachedAt;
    final hasFreshCache =
        _cachedSystemProxy != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < systemProxyCacheTtl;
    if (hasFreshCache) return;
    await refreshSystemProxy();
  }

  /// 同步解析 PAC 代理规则（供 Dart [HttpOverrides] 与 [HttpClient.findProxy] 即时调用）
  String resolveProxyRuleSync(Uri uri) {
    switch (_mode) {
      case AppProxyMode.direct:
        return 'DIRECT';

      case AppProxyMode.custom:
        final cleanHost = normalizeHost(_customHost);
        if (cleanHost.isEmpty || _customPort <= 0) {
          return 'DIRECT';
        }
        if (isBypassed(uri, _customBypass)) {
          return 'DIRECT';
        }
        return 'PROXY $cleanHost:$_customPort; DIRECT';

      case AppProxyMode.system:
        final sysProxy = _cachedSystemProxy;
        if (sysProxy != null) {
          final cleanHost = normalizeHost(sysProxy.host);
          if (!sysProxy.enable ||
              cleanHost.isEmpty ||
              sysProxy.port <= 0) {
            return 'DIRECT';
          }
          if (isBypassed(uri, sysProxy.bypass)) {
            return 'DIRECT';
          }
          return 'PROXY $cleanHost:${sysProxy.port}; DIRECT';
        }
        final envProxy = Platform.environment['https_proxy'] ??
            Platform.environment['http_proxy'] ??
            Platform.environment['ALL_PROXY'];
        if (envProxy != null && envProxy.isNotEmpty) {
          final parsedAddress = normalizeProxyAddress(envProxy);
          if (parsedAddress.isNotEmpty) {
            return 'PROXY $parsedAddress; DIRECT';
          }
        }
        return 'DIRECT';
    }
  }

  /// 异步解析 PAC 代理规则（带缓存，供 [NetworkClient] 使用）
  Future<String> resolveProxyRule(Uri uri) async {
    final cacheKey = uri.toString();
    final cached = _ruleCache[cacheKey];
    if (cached != null) return cached;

    final inFlight = _inFlightLookups[cacheKey];
    if (inFlight != null) return inFlight;

    final future = _detectProxyRule(uri).whenComplete(() {
      _inFlightLookups.remove(cacheKey);
    });
    _inFlightLookups[cacheKey] = future;

    final rule = await future;
    _ruleCache[cacheKey] = rule;
    return rule;
  }

  Future<String> _detectProxyRule(Uri uri) async {
    if (_mode == AppProxyMode.system) {
      await _ensureSystemProxyFresh();
    }
    return resolveProxyRuleSync(uri);
  }

  /// 检查给定 [uri] 是否在绕过名单 [bypassList] 中
  bool isBypassed(Uri uri, String bypassList) {
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty || bypassList.trim().isEmpty) return false;

    final entries = bypassList
        .split(RegExp(r'[;,|]'))
        .map((entry) => entry.trim().toLowerCase())
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

  /// 标准化主机名/IP（去除 http://、路径、端口等）
  String normalizeHost(String host) {
    var text = host.trim();
    if (text.isEmpty) return '';

    final parsed = Uri.tryParse(text);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.host;
    }

    text = text.replaceFirst(RegExp(r'^[a-zA-Z]+://'), '');
    text = text.replaceFirst(RegExp(r'^PROXY\s+', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'^SOCKS\s+', caseSensitive: false), '');
    final slashIdx = text.indexOf('/');
    if (slashIdx >= 0) {
      text = text.substring(0, slashIdx);
    }
    final colonIdx = text.indexOf(':');
    if (colonIdx >= 0) {
      text = text.substring(0, colonIdx);
    }
    return text.trim();
  }

  /// 标准化代理地址字符串（去除 http://、末尾斜杠等前缀）
  String normalizeProxyAddress(String value) {
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

  /// 测试指定 Host 和 Port 的 TCP 代理连通性
  Future<bool> testProxyConnection(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final cleanHost = normalizeProxyAddress(host).split(':').first;
    if (cleanHost.isEmpty || port <= 0 || port > 65535) {
      return false;
    }
    try {
      final socket = await Socket.connect(cleanHost, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _supportsSystemProxyPlugin {
    return Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isLinux;
  }
}
