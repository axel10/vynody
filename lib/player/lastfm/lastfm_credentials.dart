/// Last.fm 应用凭据。
///
/// [apiKey] 本身是公开信息 —— 它会原样出现在浏览器授权页的 URL 里，
/// 因此可以安全入库。
///
/// [sharedSecret] 绝不能进仓库：构建时通过
/// `--dart-define=LASTFM_SECRET=...` 注入（CI 使用 repository secret，
/// 本地打包时从环境变量读取）。未注入时 [isConfigured] 为 false，
/// 整个上报链路静默禁用 —— 这也让 `flutter run` 调试构建不会
/// 往真实账号写入测试记录。
class LastFmCredentials {
  const LastFmCredentials._();

  static const String apiKey = '4229adebc2bbb491a5ce62060b9298f0';

  static const String _sharedSecret = String.fromEnvironment('LASTFM_SECRET');

  /// 构建期注入的共享密钥；未注入时为 null。
  static String? get sharedSecret =>
      _sharedSecret.trim().isEmpty ? null : _sharedSecret.trim();

  /// 当前构建是否具备完整凭据。
  static bool get isConfigured => apiKey.isNotEmpty && sharedSecret != null;
}
