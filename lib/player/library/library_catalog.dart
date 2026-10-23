import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/genre_naming.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/artist_library.dart';
import 'package:vynody/player/library/library_source_filter.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/stream_utils.dart';

/// 曲库快照：songs 表在一次节流窗口内只查询一次、只反序列化一次，
/// 专辑 / 艺术家 / 流派 / 年份等聚合视图共享同一份数据。
///
/// 聚合字段全部是 `late final`，按需惰性求值：
/// 只有被实际读取的视图才会计算，未读取的视图不产生任何开销。
/// 这保证「只打开年份页」时不会顺带算出专辑与艺术家。
class LibraryCatalog {
  LibraryCatalog(this.songs, this.isPathAllowed);

  /// 已排除 external 来源与已删除记录的歌曲（未做活动根目录 / 来源过滤）。
  final List<SongMetadata> songs;

  /// 活动根目录与来源过滤的可调用包装，见 [libraryCatalogProvider]。
  final bool Function(String path) isPathAllowed;

  /// 应用了活动根目录 / 来源过滤后的歌曲，供各列表视图使用。
  late final List<SongMetadata> visibleSongs = songs
      .where((song) => isPathAllowed(song.path))
      .toList(growable: false);

  late final List<AlbumSummary> albums = buildAlbumSummaries(visibleSongs);

  late final List<GenreSummary> genres = _buildGenreSummaries(visibleSongs);

  late final List<YearSummary> years = _buildYearSummaries(visibleSongs);

  /// 艺术家聚合需要额外查询两张缓存表，因此是异步的；
  /// `late final` 会把 Future 缓存住，重复读取不会重复查库。
  late final Future<List<ArtistSummary>> artists =
      ArtistLibraryRepository().buildSummariesFor(visibleSongs);
}

/// 全应用唯一的 songs 表订阅点。
///
/// 所有曲库派生视图（专辑 / 艺术家 / 流派 / 年份 / 已评分 / 拾光机）都从这里取值，
/// 因此扫描入库引发的连续写入只会产生一次全表重算。
///
/// 另外，写入若只改了展示字段（典型是缩略图回填写 `thumbnailPath`），结构签名
/// 不变，本 Provider 不会产出新快照 —— 下游的聚合与排序完全不会被惊动。
final libraryCatalogProvider = StreamProvider<LibraryCatalog>((ref) async* {
  final db = MetadataDatabase();
  final isReady = ref.watch(scannerServiceProvider.select((s) => s.isReady));
  final rootPathsKey = ref.watch(
    scannerServiceProvider.select((s) => s.rootPaths.join('|')),
  );
  final hasSystemMedia = ref.watch(
    scannerServiceProvider.select((s) => s.systemMediaFolder != null),
  );
  final remoteRootsKey = ref.watch(
    scannerServiceProvider
        .select((s) => s.remoteRoots.map((r) => r.virtualUri).join('|')),
  );
  final sourceFilter = ref.watch(librarySourceFilterProvider);
  final scanner = ref.read(scannerServiceProvider);
  final shouldFilter =
      isReady &&
      (rootPathsKey.isNotEmpty ||
          hasSystemMedia ||
          remoteRootsKey.isNotEmpty);

  bool isPathAllowed(String path) {
    if (shouldFilter && !scanner.isPathInActiveRoots(path)) return false;
    return sourceFilter.matchesSongPath(path);
  }

  List<SongMetadata>? lastKept;

  await for (final songs in db
      .watchAllSongMetadata()
      .throttleLeadingAndTrailing(const Duration(seconds: 1))) {
    final kept = <SongMetadata>[];
    for (final song in songs) {
      if (song.deletedAt != null) continue;
      final flags = song.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;
      kept.add(song);
    }
    // 表级监听无法区分「哪一列变了」，而缩略图回填每补一张封面都会写一次库。
    // 若每次写入都产出新快照，一张封面就会触发：全量 buildAlbumSummaries
    // （每首歌 new 一个 MusicFile）+ 全量重排（comparator 里反复 toLowerCase）
    // + 整棵 SliverGrid 重建。所以这里对「结构」做等价判断，结构没变就沿用
    // 上一份快照，让纯展示字段的写入不再穿透到列表层。
    if (lastKept != null && libraryStructureEquals(lastKept, kept)) {
      continue;
    }
    lastKept = kept;
    yield LibraryCatalog(kept, isPathAllowed);
  }
});

/// 判断两份曲库快照的「结构」是否等价 —— 即所有会影响派生列表内容与顺序的字段。
///
/// 有意排除的字段：
/// - `thumbnailPath`：缩略图回填的写入点。它只影响封面显示，而封面组件本身
///   会走 artwork_resolver 解析（命中内存缓存，不会再起 isolate），因此列表
///   不需要因它重算。
/// - `themeColorsBlob` / `waveformBlob`：后台分析写入的展示数据，且每次查询
///   都会生成新的 Uint8List 实例（identity hashCode），参与比较会让本函数
///   恒为 false，反而把节流效果抹掉。
///
/// 新增「会影响列表内容」的字段时请同步补充 [_sameSongStructure]，否则该字段
/// 的变更要等到下一次结构变化才会反映到界面上。
///
/// 暴露为公开函数是为了让测试能直接覆盖「哪些字段算结构」这条规则。
bool libraryStructureEquals(
  List<SongMetadata> previous,
  List<SongMetadata> next,
) {
  if (identical(previous, next)) return true;
  if (previous.length != next.length) return false;
  for (var i = 0; i < previous.length; i++) {
    if (!_sameSongStructure(previous[i], next[i])) return false;
  }
  return true;
}

bool _sameSongStructure(SongMetadata a, SongMetadata b) {
  if (identical(a, b)) return true;
  return a.path == b.path &&
      a.title == b.title &&
      a.album == b.album &&
      a.artist == b.artist &&
      a.albumArtist == b.albumArtist &&
      a.trackNumber == b.trackNumber &&
      a.duration == b.duration &&
      a.year == b.year &&
      a.lastModifiedTime == b.lastModifiedTime &&
      a.createdAt == b.createdAt &&
      a.deletedAt == b.deletedAt &&
      a.sourceFlags == b.sourceFlags &&
      a.isAppModified == b.isAppModified &&
      a.id == b.id &&
      a.mediaId == b.mediaId &&
      a.fileRating == b.fileRating &&
      a.artworkPath == b.artworkPath &&
      a.artworkWidth == b.artworkWidth &&
      a.artworkHeight == b.artworkHeight &&
      a.hasArtwork == b.hasArtwork &&
      a.bitrate == b.bitrate &&
      a.sampleRate == b.sampleRate &&
      a.channels == b.channels &&
      a.bitDepth == b.bitDepth &&
      a.format == b.format &&
      a.codec == b.codec &&
      _sameStringList(a.genres, b.genres);
}

/// 逐项比较流派列表。`List` 的 hashCode 是 identity 的，而每次查库都会
/// 重新反序列化出一个新 List，所以不能用 `==` 或 hashCode 判等。
bool _sameStringList(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 把 catalog 快照包装成 [Stream]，让派生 provider 保持原有的
/// `StreamProvider<...>` 类型与 `overrideWith` 签名不变。
///
/// [select] 允许返回 [FutureOr]，以支持需要额外查询缓存表的艺术家聚合。
/// catalog 尚未就绪时返回空流（下游维持 loading），出错时把错误原样透传。
Stream<T> catalogDerived<T>(
  Ref ref,
  FutureOr<T> Function(LibraryCatalog catalog) select,
) {
  return ref
      .watch(libraryCatalogProvider)
      .when(
        data: (catalog) {
          final value = select(catalog);
          return value is Future<T>
              ? Stream<T>.fromFuture(value)
              : Stream<T>.value(value);
        },
        loading: () => Stream<T>.empty(),
        error: (error, stackTrace) => Stream<T>.error(error, stackTrace),
      );
}

/// 按归一化键聚合流派。
///
/// 标签里的流派是自由文本，`Rock` / `rock` / `ROCK` 会被 [normalizeGenreKey]
/// 归到同一个键，避免同一流派在库里裂成好几份；组内挑出现次数最多的原始
/// 写法作为展示名，并对全小写英文做首字母美化。
///
/// 同一首歌可能带多个指向同一流派的标签（如 `Rock` + `rock`），因此歌曲按
/// 路径去重，否则 songCount 会虚高。
List<GenreSummary> _buildGenreSummaries(List<SongMetadata> songs) {
  final groups = <String, _GenreGroup>{};

  for (final s in songs) {
    final parsedGenres = s.genres;
    if (parsedGenres == null || parsedGenres.isEmpty) continue;

    // 同一首歌的多个流派标签共用同一个 MusicFile，避免重复构造
    MusicFile? musicFile;
    for (final g in parsedGenres) {
      final key = normalizeGenreKey(g);
      if (key.isEmpty) continue;

      final file = musicFile ??= MusicFile(
        path: s.path,
        name: p.basename(s.path),
        title: s.title,
        artist: s.artist,
        albumArtist: s.albumArtist,
        album: s.album,
        trackNumber: s.trackNumber,
        artworkPath: s.artworkPath,
        thumbnailPath: s.thumbnailPath,
        durationMillis: s.duration,
        id: s.id,
      );

      groups
          .putIfAbsent(key, () => _GenreGroup())
          .addSong(file, rawName: g);
    }
  }

  final list = <GenreSummary>[];
  for (final group in groups.values) {
    final groupSongs = group.songs;
    if (groupSongs.isEmpty) continue;

    final sampleWithArtwork = groupSongs.firstWhere(
      (m) =>
          (m.artworkPath != null && m.artworkPath!.isNotEmpty) ||
          (m.thumbnailPath != null && m.thumbnailPath!.isNotEmpty),
      orElse: () => groupSongs.first,
    );

    list.add(
      GenreSummary(
        name: group.displayName,
        songCount: groupSongs.length,
        representativeArtworkPath: sampleWithArtwork.artworkPath,
        representativeThumbnailPath: sampleWithArtwork.thumbnailPath,
        songs: groupSongs,
      ),
    );
  }

  list.sort((a, b) {
    final byCount = b.songCount.compareTo(a.songCount);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return list;
}

/// 归一化流派的聚合暂存：按路径去重歌曲，并统计各种原始写法的出现次数。
class _GenreGroup {
  final Map<String, MusicFile> _songsByPath = <String, MusicFile>{};
  final Map<String, int> _rawNameCounts = <String, int>{};

  void addSong(MusicFile song, {required String rawName}) {
    _songsByPath.putIfAbsent(song.path, () => song);
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return;
    _rawNameCounts.update(trimmed, (v) => v + 1, ifAbsent: () => 1);
  }

  List<MusicFile> get songs => _songsByPath.values.toList(growable: false);

  /// 组内出现次数最多的原始写法作为展示名；平手时取先出现的那个。
  String get displayName {
    String? best;
    var bestCount = 0;
    for (final entry in _rawNameCounts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return pickGenreDisplayName(best ?? '');
  }
}

List<YearSummary> _buildYearSummaries(List<SongMetadata> songs) {
  final yearMap = <int?, List<MusicFile>>{};

  for (final s in songs) {
    final musicFile = MusicFile(
      path: s.path,
      name: p.basename(s.path),
      title: s.title,
      artist: s.artist,
      albumArtist: s.albumArtist,
      album: s.album,
      trackNumber: s.trackNumber,
      artworkPath: s.artworkPath,
      thumbnailPath: s.thumbnailPath,
      durationMillis: s.duration,
      id: s.id,
      year: s.year,
      genres: s.genres,
    );

    yearMap.putIfAbsent(s.year, () => []).add(musicFile);
  }

  final list = <YearSummary>[];
  for (final entry in yearMap.entries) {
    if (entry.value.isEmpty) continue;
    final sampleWithArtwork = entry.value.firstWhere(
      (m) =>
          (m.artworkPath != null && m.artworkPath!.isNotEmpty) ||
          (m.thumbnailPath != null && m.thumbnailPath!.isNotEmpty),
      orElse: () => entry.value.first,
    );

    list.add(
      YearSummary(
        year: entry.key,
        songCount: entry.value.length,
        representativeArtworkPath: sampleWithArtwork.artworkPath,
        representativeThumbnailPath: sampleWithArtwork.thumbnailPath,
        songs: entry.value,
      ),
    );
  }

  list.sort((a, b) {
    // 未知年份分组固定沉底，其余按年份由新到旧
    if (a.year == null && b.year == null) return 0;
    if (a.year == null) return 1;
    if (b.year == null) return -1;
    return b.year!.compareTo(a.year!);
  });
  return list;
}
