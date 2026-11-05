import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 跨设备同步的数据种类。
enum LanSyncKind { lyrics, playlists }

/// [incoming] = 本机接收并落地；[outgoing] = 本机把数据交给对方。
enum LanSyncDirection { incoming, outgoing }

/// 一次跨设备传输的落地结果。
///
/// 发起方与被动方共用同一条通知链路：此前只有歌单在被动方有提示，
/// 歌词导入完是静默的；导出方向（被拉取那台）两侧都没有提示。
class LanSyncReceipt {
  final LanSyncKind kind;
  final LanSyncDirection direction;

  /// 载体数量：歌单同步是歌单个数，歌词同步不适用（保持 0）。
  final int containers;
  final int added;
  final int updated;
  final int skipped;
  final int missing;

  /// 命中了多首本地歌、无法收敛到唯一的条目数（同名不同版本 / 重复目录）。
  final int ambiguous;

  /// 明细样本（最多 [maxSamples] 条），供结果卡片展开。
  ///
  /// 只带名字不带完整条目：结果卡片是给人看的，不是给程序消费的；
  /// 整库级别的未匹配清单会撑爆 UI，也不会有人真的逐条去补。
  final List<String> missingSamples;
  final List<String> ambiguousSamples;

  final Duration elapsed;
  final String? deviceName;

  static const int maxSamples = 20;

  const LanSyncReceipt({
    required this.kind,
    required this.direction,
    this.containers = 0,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.missing = 0,
    this.ambiguous = 0,
    this.missingSamples = const [],
    this.ambiguousSamples = const [],
    this.elapsed = Duration.zero,
    this.deviceName,
  });

  /// 有没有值得展开看的明细。没有的话结果卡片只是「新增 3 首」这种一句话。
  bool get hasDetails => missing > 0 || ambiguous > 0;

  /// 明细总数，用于 SnackBar 上提示「查看详情」。
  int get detailCount => missing + ambiguous;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'direction': direction.name,
    'containers': containers,
    'added': added,
    'updated': updated,
    'skipped': skipped,
    'missing': missing,
    'ambiguous': ambiguous,
    'missingSamples': missingSamples,
    'ambiguousSamples': ambiguousSamples,
    'elapsedMs': elapsed.inMilliseconds,
    if (deviceName != null) 'deviceName': deviceName,
    'finishedAtMs': DateTime.now().millisecondsSinceEpoch,
  };

  /// 从持久化的 JSON 还原（「最近一次同步」回看用）。
  static LanSyncReceipt? fromJson(Map<String, dynamic> json) {
    final kind = LanSyncKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    final direction = LanSyncDirection.values
        .where((value) => value.name == json['direction'])
        .firstOrNull;
    if (kind == null || direction == null) return null;

    List<String> samples(Object? raw) => raw is List
        ? raw.whereType<String>().toList(growable: false)
        : const [];

    int intOr(Object? raw, int fallback) => raw is int ? raw : fallback;

    return LanSyncReceipt(
      kind: kind,
      direction: direction,
      containers: intOr(json['containers'], 0),
      added: intOr(json['added'], 0),
      updated: intOr(json['updated'], 0),
      skipped: intOr(json['skipped'], 0),
      missing: intOr(json['missing'], 0),
      ambiguous: intOr(json['ambiguous'], 0),
      missingSamples: samples(json['missingSamples']),
      ambiguousSamples: samples(json['ambiguousSamples']),
      elapsed: Duration(milliseconds: intOr(json['elapsedMs'], 0)),
      deviceName: json['deviceName'] as String?,
    );
  }
}

class LanSyncReceiptNotifier extends Notifier<LanSyncReceipt?> {
  @override
  LanSyncReceipt? build() => null;

  void notify(LanSyncReceipt receipt) => state = receipt;
  void clear() => state = null;
}

final lanSyncReceiptProvider =
    NotifierProvider<LanSyncReceiptNotifier, LanSyncReceipt?>(
      LanSyncReceiptNotifier.new,
    );

/// 一次同步在本地算出来的结果。
///
/// 取代原来那种 `Map<String, int>`：统计口径散在三个调用点里各自解释
/// `overwritten` / `imported_songs` 的含义，加一个字段（比如 `ambiguous`）
/// 就得同时改 4 处 map 键名，而且拼错键名不会有任何编译期报错。
class LanSyncOutcome {
  /// 载体数量：歌单同步是歌单个数。
  final int containers;

  /// 远端条目中在本机找到对应歌曲的条数（按条目计，不按命中歌曲数）。
  final int matched;
  final int added;
  final int updated;
  final int skipped;

  /// 完全没找到本地对应歌曲的条目数。
  final int missing;

  /// 找到多首、无法收敛到唯一的条目数。
  final int ambiguous;

  final List<String> missingSamples;
  final List<String> ambiguousSamples;

  const LanSyncOutcome({
    this.containers = 0,
    this.matched = 0,
    this.added = 0,
    this.updated = 0,
    this.skipped = 0,
    this.missing = 0,
    this.ambiguous = 0,
    this.missingSamples = const [],
    this.ambiguousSamples = const [],
  });

  LanSyncReceipt toReceipt({
    required LanSyncKind kind,
    required LanSyncDirection direction,
    String? deviceName,
    Duration elapsed = Duration.zero,
  }) {
    return LanSyncReceipt(
      kind: kind,
      direction: direction,
      containers: containers,
      added: added,
      updated: updated,
      skipped: skipped,
      missing: missing,
      ambiguous: ambiguous,
      missingSamples: missingSamples,
      ambiguousSamples: ambiguousSamples,
      elapsed: elapsed,
      deviceName: deviceName,
    );
  }
}

/// 同一台设备上已经有一个同步任务在跑。
///
/// 旧实现没有任何互斥：用户等不及再点一次就会并发发两份，第二份多半把第一份
/// 的结果覆盖掉，但两边的回执和进度都会各弹一遍，看起来像「同步了两次」。
class LanSyncBusyException implements Exception {
  const LanSyncBusyException(this.kind);
  final LanSyncKind kind;

  @override
  String toString() => 'LanSyncBusyException(${kind.name})';
}

/// 用户点了进度对话框上的「取消」。
///
/// 不是错误：调用方要把它和失败区分开，否则取消也会弹「同步失败」。
class LanSyncCancelledException implements Exception {
  const LanSyncCancelledException();

  @override
  String toString() => 'LanSyncCancelledException';
}
