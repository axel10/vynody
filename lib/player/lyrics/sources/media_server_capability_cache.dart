/// 媒体库「能力探测」的进程内缓存。
///
/// 解决的问题：不支持某个歌词接口的服务端（Navidrome 老版本没有
/// `getLyricsBySongId`、Jellyfin 10.9 以下没有 `/Audio/{id}/Lyrics`），
/// 改造前每首歌都要先发一次注定失败的请求再降级。
///
/// 只缓存 [markUnsupported]：网络抖动、认证失败等结论未知的情况一律不记，
/// 避免把「暂时连不上」永久固化成「不支持」。连接测试成功或用户手动刷新时清除。
class MediaServerCapabilityCache {
  MediaServerCapabilityCache._();

  static final MediaServerCapabilityCache instance =
      MediaServerCapabilityCache._();

  /// 能力项标识。
  static const String subsonicLyricsBySongId = 'subsonic.lyricsBySongId';
  static const String jellyfinLyricsEndpoint = 'jellyfin.lyricsEndpoint';

  final Map<String, Set<String>> _unsupported = {};

  bool isUnsupported(String serverId, String capability) {
    if (serverId.isEmpty) return false;
    return _unsupported[serverId]?.contains(capability) ?? false;
  }

  void markUnsupported(String serverId, String capability) {
    if (serverId.isEmpty) return;
    (_unsupported[serverId] ??= <String>{}).add(capability);
  }

  void clear(String serverId) {
    _unsupported.remove(serverId);
  }

  void clearAll() {
    _unsupported.clear();
  }

  /// 仅供测试。
  void debugMarkSupported(String serverId) => clear(serverId);
}
