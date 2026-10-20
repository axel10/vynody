import 'package:flutter/foundation.dart';

/// 下载准备的两个阶段。
///
/// [loading] 是「加载曲目」阶段：曲目还没进下载管理，正从服务端一首首取回来；
/// [queueing] 是「加入下载队列」阶段：曲目已在内存里，正逐首算落盘路径并入队。
enum RemoteTrackLoadStage {
  loading,
  queueing,
}

/// 下载准备被用户取消时抛出，用来从拉取/入队的循环里一次性跳出。
///
/// 只是普通的控制流信号，不需要打印堆栈。
class RemoteTrackLoadCancelled implements Exception {
  const RemoteTrackLoadCancelled();

  @override
  String toString() => 'RemoteTrackLoadCancelled';
}

/// 下载准备的进度源。
///
/// 只有一条下载准备流程会同时跑，所以做成单例，让底层拉取/入队逻辑
/// 不必层层透传回调，直接往这里报数，由进度浮层监听展示。
class RemoteTrackLoadProgressNotifier extends ChangeNotifier {
  bool _active = false;
  bool _cancelled = false;
  RemoteTrackLoadStage _stage = RemoteTrackLoadStage.loading;
  int _loaded = 0;
  int _total = 0;

  /// 是否处于一次下载准备流程中。未开始时所有上报都会被忽略，
  /// 避免「播放 / 加入队列」等同样走拉取逻辑的动作误触发进度。
  bool get isActive => _active;

  /// 用户是否在这次流程里点了取消。循环里靠 [throwIfCancelled] 中断。
  bool get isCancelled => _cancelled;
  RemoteTrackLoadStage get stage => _stage;
  int get loaded => _loaded;
  int get total => _total;

  /// 已知总数时返回 0~1 的完成度，未知时返回 null（走不确定进度条）。
  double? get fraction =>
      _total > 0 ? (_loaded / _total).clamp(0.0, 1.0) : null;

  void begin() {
    _active = true;
    _cancelled = false;
    _stage = RemoteTrackLoadStage.loading;
    _loaded = 0;
    _total = 0;
    notifyListeners();
  }

  void end() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  /// 用户点取消。只置标志并通知界面，真正的中断发生在下一个检查点。
  void cancel() {
    if (!_active || _cancelled) return;
    _cancelled = true;
    notifyListeners();
  }

  /// 拉取/入队的每个条目开头调一次，取消后立刻跳出整个流程。
  void throwIfCancelled() {
    if (_cancelled) throw const RemoteTrackLoadCancelled();
  }

  /// 切换阶段。切换时清零已计数，因为两个阶段统计的是不同口径。
  void setStage(RemoteTrackLoadStage stage) {
    if (!_active || _stage == stage) return;
    _stage = stage;
    _loaded = 0;
    notifyListeners();
  }

  void setTotal(int total) {
    if (!_active || _cancelled || total <= 0 || _total == total) return;
    _total = total;
    notifyListeners();
  }

  /// 累加分母。多选多个艺术家/多张专辑时，各自的曲目数要一段段才知道
  /// （艺术家得先拿专辑列表、专辑得先拿 songCount），覆盖式 setTotal 会让
  /// 分母只等于最后一个的分量，这里改成累加。
  void addToTotal(int delta) {
    if (!_active || _cancelled || delta <= 0) return;
    _total += delta;
    notifyListeners();
  }

  void setLoaded(int loaded) {
    if (!_active || _cancelled || loaded == _loaded) return;
    _loaded = loaded;
    notifyListeners();
  }

  void advance([int delta = 1]) => setLoaded(_loaded + delta);
}

/// 全局唯一的下载准备进度源。
final remoteTrackLoadProgress = RemoteTrackLoadProgressNotifier();
