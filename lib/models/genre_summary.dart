import 'genre_naming.dart';
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

  /// 唯一标识 Key（忽略大小写、标点与连接符差异）。
  ///
  /// 与 [normalizeGenreKey] 同源：`R&B` 与 `R and B` 会得到同一个 Key，
  /// 因此可以安全地用于选中态比较、多选集合等场景。
  String get queryKey => normalizeGenreKey(name);

  /// 流派展示图（`assets/images/genre/webp/*.webp`）。
  ///
  /// 未命中任何流派规则时回落到 `default.webp`，因此永远非空。
  String get imageAssetPath =>
      'assets/images/genre/webp/${genreImageAssetKey(name)}.webp';

  /// 流派图标（`assets/icons/genre/*.svg`）。
  ///
  /// 兜底流派没有专属图标，返回 `null`，调用方需自行跳过渲染。
  String? get iconAssetPath {
    final key = genreIconAssetKey(name);
    return key == null ? null : 'assets/icons/genre/$key.svg';
  }

  /// 是否使用兜底封面：未命中任何流派规则，与所有其他未识别流派共用 `music.webp`。
  bool get usesFallbackCover =>
      genreImageAssetKey(name) == kFallbackGenreAssetKey;

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
