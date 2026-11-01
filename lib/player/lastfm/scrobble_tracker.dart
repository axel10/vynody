/// 播放过程中的上报信号。
enum ScrobbleSignal {
  /// 什么都不用做。
  none,

  /// 曲目开始（或重播）：可以发 `track.updateNowPlaying`。
  nowPlaying,

  /// 已达到计入播放的门槛：应当入队并尽快上报。
  scrobble,
}

/// Last.fm 上报的阈值状态机。
///
/// 刻意独立于 [AudioService] 既有的 `_hasLoggedCurrentPlayback`：
/// 后者是本地播放统计用的「5 秒或过半」，与 Last.fm 的规则不是一回事，
/// 复用会导致大量误报。
///
/// 规则：
/// - 曲目时长不足 30 秒，不计入播放（Last.fm 官方要求）。
/// - 累计**实际播放时间**达到 `min(时长/2, 4 分钟)` 才计入。
/// - 用累计播放时间而不是当前播放位置，这样暂停、缓冲都不会白算进度；
///   同时拖动进度条跳过去的部分不算听过（delta 突变不计入）。
/// - 同一首歌回拖到开头视为重播，允许再计一次。
class ScrobbleTracker {
  static const Duration minimumTrackDuration = Duration(seconds: 30);
  static const Duration maximumThreshold = Duration(minutes: 4);

  /// 两次位置回调之间允许计入的最大间隔。超过即认为是 seek 造成的跳变。
  static const Duration _maxCountableDelta = Duration(seconds: 3);

  /// 判定「回拖到开头」的位置上限。
  static const Duration _restartPosition = Duration(seconds: 5);

  /// 判定「回拖」需要的最小回退量，避免抖动误判。
  static const Duration _restartRewind = Duration(seconds: 5);

  String? _path;
  Duration _lastPosition = Duration.zero;
  Duration _played = Duration.zero;
  Duration? _trackDuration;
  bool _nowPlayingSent = false;
  bool _scrobbled = false;

  String? get currentPath => _path;

  /// 本曲目是否具备上报资格（时长已知且过短时不具备）。
  bool get isEligible => _path != null && _isEligible();

  /// 本曲目是否已经计入过播放。
  bool get hasScrobbled => _scrobbled;

  void reset() {
    _path = null;
    _lastPosition = Duration.zero;
    _played = Duration.zero;
    _trackDuration = null;
    _nowPlayingSent = false;
    _scrobbled = false;
  }

  /// 每次播放位置更新时调用。返回本次需要触发的动作。
  ///
  /// [duration] 取「标签时长」与「播放器解析时长」中较可靠的那个，未知时传 null。
  ScrobbleSignal update({
    required String path,
    required Duration position,
    required bool isPlaying,
    Duration? duration,
  }) {
    if (_path != path) {
      _path = path;
      _lastPosition = position;
      _played = Duration.zero;
      _scrobbled = false;
      _trackDuration = _normalizeDuration(duration);
      if (!_isEligible()) {
        _nowPlayingSent = false;
        return ScrobbleSignal.none;
      }
      _nowPlayingSent = true;
      return ScrobbleSignal.nowPlaying;
    }

    if (duration != null && duration.inMilliseconds > 0) {
      _trackDuration = duration;
    }

    final rewind = _lastPosition - position;
    final isRestart =
        rewind >= _restartRewind && position < _restartPosition;

    if (isRestart) {
      // 重播：重新累计，允许再计一次。
      _lastPosition = position;
      _played = Duration.zero;
      _scrobbled = false;
      if (!_isEligible()) {
        _nowPlayingSent = false;
        return ScrobbleSignal.none;
      }
      _nowPlayingSent = true;
      return ScrobbleSignal.nowPlaying;
    }

    final delta = position - _lastPosition;
    _lastPosition = position;

    if (!isPlaying) return ScrobbleSignal.none;
    if (_scrobbled) return ScrobbleSignal.none;

    // 只累计「连续前进」的那部分，seek 造成的跳变不计入。
    if (delta > Duration.zero && delta <= _maxCountableDelta) {
      _played += delta;
    }

    if (!_isEligible()) return ScrobbleSignal.none;

    if (_played >= thresholdFor(_trackDuration)) {
      _scrobbled = true;
      return ScrobbleSignal.scrobble;
    }

    return ScrobbleSignal.none;
  }

  /// 是否已经为当前曲目发过 now playing。
  bool get nowPlayingSent => _nowPlayingSent;

  /// 阈值：时长过半，但最多 4 分钟；时长未知时按 4 分钟兜底。
  ///
  /// 现成实现里「过半」依赖时长，而远程曲目经常拿不到时长，
  /// 那样会永远算不出过半 —— 兜底到 4 分钟是唯一安全的做法：
  /// 短于 4 分钟的曲目根本累积不到 4 分钟。
  static Duration thresholdFor(Duration? duration) {
    if (duration == null || duration <= Duration.zero) {
      return maximumThreshold;
    }
    final half = Duration(microseconds: duration.inMicroseconds ~/ 2);
    return half < maximumThreshold ? half : maximumThreshold;
  }

  Duration? _normalizeDuration(Duration? duration) {
    if (duration == null || duration.inMilliseconds <= 0) return null;
    return duration;
  }

  bool _isEligible() {
    final duration = _trackDuration;
    if (duration == null) return true;
    return duration >= minimumTrackDuration;
  }
}
