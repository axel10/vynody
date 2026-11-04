/// 媒体库歌词请求的四种结论。
///
/// 改造前两家客户端都只返回 `String?`，异常一律 `catch (_) {}` 吞掉，
/// 上层无法区分「服务端没有歌词」「服务端不支持这个接口」「这次请求失败了」。
/// 后果是弱网失败被当成「没有」，静默降级到在线库，日志里也看不出原因。
enum MediaServerLyricsStatus {
  /// 拿到非空歌词。
  hit,

  /// 服务端明确表示没有（404 语义 / 错误码 70 / 空内容）。
  absent,

  /// 服务端不支持该接口（未知方法 / 版本过低）。可记入能力缓存。
  unsupported,

  /// 网络、认证或解析失败，结论未知。**不得**记入能力缓存。
  failed,
}

class MediaServerLyricsResult {
  const MediaServerLyricsResult.hit(
    this.text, {
    this.variant = '',
    this.synced = false,
  }) : status = MediaServerLyricsStatus.hit,
       diagnostic = null;

  const MediaServerLyricsResult.miss(
    this.status, {
    this.diagnostic,
  }) : assert(status != MediaServerLyricsStatus.hit, '命中请用 hit 构造'),
       text = null,
       variant = '',
       synced = false;

  final MediaServerLyricsStatus status;

  /// 仅 [MediaServerLyricsStatus.hit] 时非空。
  final String? text;

  /// 命中的具体路径，如 `structured-synced` / `legacy` / `jellyfin-lines`。
  final String variant;

  /// 歌词是否带时间轴。
  final bool synced;

  /// 错误码或 HTTP 状态，仅用于日志与排查。
  final String? diagnostic;

  bool get isHit => status == MediaServerLyricsStatus.hit;

  @override
  String toString() =>
      'MediaServerLyricsResult(${status.name}'
      '${variant.isEmpty ? '' : ' $variant'}'
      '${diagnostic == null ? '' : ' $diagnostic'})';
}
