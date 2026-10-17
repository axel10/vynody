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

/// 按封面图去重：同一张封面只保留一个流派。
///
/// 封面资源键是多对一映射（`Rap` / `Trap` / `Drill` 都落到 `hip-hop`），这些流派
/// 在库里各自成组时，纯封面的展示位会连着排出多张一模一样的图，观感等同于渲染
/// bug；未命中任何规则的流派共用兜底图（`music.webp`），同样只该出现一次。
///
/// 每组取 [GenreSummary.songCount] 最大的一项作代表（最能代表这张封面），
/// 并沿用该封面首次出现的位置，避免打乱调用方既有的排序。
///
/// 唯一例外是兜底封面（[GenreSummary.usesFallbackCover]）：它不代表任何具体流派，
/// 夹在中间会显得突兀，因此固定排在最后。
List<GenreSummary> dedupeGenresByCoverArt(Iterable<GenreSummary> genres) {
  final indexByCover = <String, int>{};
  final result = <GenreSummary>[];
  for (final genre in genres) {
    final cover = genre.imageAssetPath;
    final index = indexByCover[cover];
    if (index == null) {
      indexByCover[cover] = result.length;
      result.add(genre);
    } else if (genre.songCount > result[index].songCount) {
      result[index] = genre;
    }
  }

  final fallback = result.where((g) => g.usesFallbackCover).toList();
  if (fallback.isEmpty) return result;
  result.removeWhere((g) => g.usesFallbackCover);
  return result..addAll(fallback);
}
