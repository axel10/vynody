import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
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
/// 因此扫描入库、缩略图回写引发的连续写入只会产生一次全表重算。
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
    yield LibraryCatalog(kept, isPathAllowed);
  }
});

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

List<GenreSummary> _buildGenreSummaries(List<SongMetadata> songs) {
  final genreMap = <String, List<MusicFile>>{};

  for (final s in songs) {
    final parsedGenres = s.genres;
    if (parsedGenres == null || parsedGenres.isEmpty) continue;

    final musicFile = MusicFile(
      path: s.path,
      name: p.basename(s.path),
      title: s.title,
      artist: s.artist,
      album: s.album,
      artworkPath: s.artworkPath,
      thumbnailPath: s.thumbnailPath,
      durationMillis: s.duration,
      id: s.id,
    );

    for (final g in parsedGenres) {
      final trimmed = g.trim();
      if (trimmed.isNotEmpty) {
        genreMap.putIfAbsent(trimmed, () => []).add(musicFile);
      }
    }
  }

  final list = <GenreSummary>[];
  for (final entry in genreMap.entries) {
    if (entry.value.isEmpty) continue;
    final sampleWithArtwork = entry.value.firstWhere(
      (m) => (m.artworkPath != null && m.artworkPath!.isNotEmpty) ||
             (m.thumbnailPath != null && m.thumbnailPath!.isNotEmpty),
      orElse: () => entry.value.first,
    );

    list.add(
      GenreSummary(
        name: entry.key,
        songCount: entry.value.length,
        representativeArtworkPath: sampleWithArtwork.artworkPath,
        representativeThumbnailPath: sampleWithArtwork.thumbnailPath,
        songs: entry.value,
      ),
    );
  }

  list.sort((a, b) => b.songCount.compareTo(a.songCount));
  return list;
}

List<YearSummary> _buildYearSummaries(List<SongMetadata> songs) {
  final yearMap = <int?, List<MusicFile>>{};

  for (final s in songs) {
    final musicFile = MusicFile(
      path: s.path,
      name: p.basename(s.path),
      title: s.title,
      artist: s.artist,
      album: s.album,
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
