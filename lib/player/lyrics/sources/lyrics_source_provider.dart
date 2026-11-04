import 'package:dio/dio.dart';

import 'package:vynody/player/lyrics/lyrics_service.dart';

/// 歌词来源提供者。
///
/// 每个实现只负责一件事：判断自己是否适用于当前曲目（[handles]），
/// 适用时返回一条可直接展示的结果（[load]）。
///
/// 顺序不由实现类决定 —— 由 `LyricsResolver` 持有的有序列表决定。
/// 实现内部禁止出现「换下一个来源」这类跨来源判断。
abstract class LyricsSourceProvider {
  /// 稳定标识，仅用于日志与调试。
  String get id;

  /// 是否适用于该曲目。
  ///
  /// 只做本地文件 / 远程 URI / 服务端类型这类**无副作用**判定，不得发起请求。
  /// 需要网络才能确定的能力（例如服务端是否支持某个接口），放到 [load] 内部处理。
  bool handles(LyricsQuery query);

  /// 取一条歌词结果；未命中返回 null。
  ///
  /// [saveToDb] 为 false 时只读不落库，供「换源」候选探测复用同一份读取逻辑。
  Future<LyricSelectionResult?> load(
    LyricsQuery query, {
    bool saveToDb = true,
    CancelToken? cancelToken,
  });
}
