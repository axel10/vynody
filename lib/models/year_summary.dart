import 'music_file.dart';

/// 发行年份统计摘要模型
///
/// 与 [GenreSummary] 结构保持一致，便于复用流派页的主从列表与详情页设计。
/// [year] 为 null 时表示「未知年份」分组。
class YearSummary {
  const YearSummary({
    required this.year,
    required this.songCount,
    this.representativeArtworkPath,
    this.representativeThumbnailPath,
    required this.songs,
  });

  /// 发行年份；null 表示该分组为「未知年份」
  final int? year;

  /// 该年份下的歌曲总数
  final int songCount;

  /// 代表性歌曲封面路径
  final String? representativeArtworkPath;

  /// 代表性歌曲缩略图路径
  final String? representativeThumbnailPath;

  /// 该年份下的所有歌曲列表
  final List<MusicFile> songs;

  /// 是否为「未知年份」分组
  bool get isUnknownYear => year == null;

  /// 未知年份分组的稳定标识
  static const String unknownYearKey = '__unknown_year__';

  /// 唯一标识 Key
  String get queryKey => year?.toString() ?? unknownYearKey;

  /// 用于展示的年份文本；未知年份时回退到调用方提供的本地化文案
  String labelWith(String unknownYearLabel) =>
      year?.toString() ?? unknownYearLabel;

  /// 总播放时长（毫秒）
  int get totalDurationMillis {
    int sum = 0;
    for (final song in songs) {
      sum += song.durationMillis ?? 0;
    }
    return sum;
  }

  /// 该年份包含的不同专辑数量
  int get albumCount {
    final albums = <String>{};
    for (final song in songs) {
      final alb = song.album?.trim();
      if (alb != null && alb.isNotEmpty) {
        albums.add(alb.toLowerCase());
      }
    }
    return albums.length;
  }
}
