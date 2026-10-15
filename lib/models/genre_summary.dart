import 'music_file.dart';

/// 流派统计摘要模型
class GenreSummary {
  const GenreSummary({
    required this.name,
    required this.songCount,
    this.representativeArtworkPath,
    this.representativeThumbnailPath,
    required this.songs,
  });

  /// 流派名称
  final String name;

  /// 包含的歌曲总数
  final int songCount;

  /// 代表性歌曲封面路径
  final String? representativeArtworkPath;

  /// 代表性歌曲缩略图路径
  final String? representativeThumbnailPath;

  /// 该流派下的所有歌曲列表
  final List<MusicFile> songs;

  /// 兼容旧属性命名
  List<MusicFile> get sampleSongs => songs;

  /// 唯一标识 Key（忽略首尾空格与大小写）
  String get queryKey => name.trim().toLowerCase();

  /// 总播放时长（毫秒）
  int get totalDurationMillis {
    int sum = 0;
    for (final song in songs) {
      sum += song.durationMillis ?? 0;
    }
    return sum;
  }

  /// 该流派包含的不同专辑数量
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
