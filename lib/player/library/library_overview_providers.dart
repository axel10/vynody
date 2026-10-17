import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/library_catalog.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/widgets/section_type_toggle.dart';

/// 拾光机 / 重温旧爱：推荐专辑条目
class TimeMachineAlbumEntry {
  const TimeMachineAlbumEntry({
    required this.album,
    required this.artist,
    this.artworkPath,
    this.thumbnailPath,
    required this.songs,
    this.totalPlayCount = 0,
    this.maxRating = 0,
    this.lastPlayedAt,
    this.latestAddedAt,
  });

  final String album;
  final String artist;
  final String? artworkPath;
  final String? thumbnailPath;
  final List<MusicFile> songs;
  final int totalPlayCount;
  final int maxRating;
  final int? lastPlayedAt;

  /// 专辑内最新一首歌的入库时间，仅「最近添加」专辑视图使用。
  final int? latestAddedAt;
}

/// 流派列表 Provider：仅返回包含有效歌曲的流派，并按歌曲数量从多到少排序。
/// 聚合数据来自 [libraryCatalogProvider]，自身不再订阅 songs 表。
final genreLibraryProvider = StreamProvider<List<GenreSummary>>(
  (ref) => catalogDerived(ref, (catalog) => catalog.genres),
);

/// 发行年份列表 Provider：
/// 按音频元数据中的发行年份聚合歌曲，年份由新到旧排列；
/// 未提取到年份的歌曲统一归入「未知年份」分组并固定排在列表末尾。
/// 聚合数据来自 [libraryCatalogProvider]，自身不再订阅 songs 表。
final yearLibraryProvider = StreamProvider<List<YearSummary>>(
  (ref) => catalogDerived(ref, (catalog) => catalog.years),
);

/// 全部已打分歌曲 Provider（用于二级页已评分曲目列表）。
///
/// 歌曲来源为曲库快照；只有评分数据变化时才会重新计算，
/// 不会再因为一次打分而重扫 songs 表。
final allRatedSongsProvider = StreamProvider<List<LibraryInsightSongEntry>>((ref) {
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  if (allRatings.isEmpty) {
    return Stream.value(const <LibraryInsightSongEntry>[]);
  }

  return catalogDerived(ref, (catalog) {
    final list = <LibraryInsightSongEntry>[];

    for (final s in catalog.songs) {
      final normalizedPath = s.path.replaceAll('\\', '/');
      final rating = allRatings[normalizedPath] ??
          allRatings[s.path] ??
          ratingService.getRating(s.path);
      if (rating <= 0) continue;

      list.add(
        LibraryInsightSongEntry(
          song: MusicFile(
            path: s.path,
            name: p.basename(s.path),
            title: s.title,
            artist: s.artist,
            album: s.album,
            artworkPath: s.artworkPath,
            thumbnailPath: s.thumbnailPath,
            durationMillis: s.duration,
            id: s.id,
          ),
          playCount: rating,
          createdAt: s.createdAt,
        ),
      );
    }

    list.sort((a, b) {
      final rCompare = b.playCount.compareTo(a.playCount);
      if (rCompare != 0) return rCompare;
      return (b.createdAt ?? 0).compareTo(a.createdAt ?? 0);
    });

    return list;
  });
});

/// 拾光机 / 重温旧爱专辑 Provider：
/// 满足历史高频播放（playCount >= 2）或主动打分（rating >= 4），且在近 30 天内未曾播放的专辑
final timeMachineAlbumsProvider = StreamProvider<List<TimeMachineAlbumEntry>>((ref) {
  final mostPlayedAsync = ref.watch(mostPlayedSongsProvider(LibraryTimeRange.allTime));
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final thirtyDaysAgoMillis = nowMillis - const Duration(days: 30).inMilliseconds;

  final insightMap = <String, LibraryInsightSongEntry>{};
  for (final item in mostPlayedAsync.value ?? const <LibraryInsightSongEntry>[]) {
    insightMap[item.song.path.replaceAll('\\', '/')] = item;
  }

  return catalogDerived(ref, (catalog) {
    final albumGroups = <String, List<(SongMetadata, int playCount, int rating, int? lastPlayed)>>{};

    for (final s in catalog.songs) {
      final normalizedPath = s.path.replaceAll('\\', '/');
      final insight = insightMap[normalizedPath];
      final playCount = insight?.playCount ?? 0;
      final lastPlayedAt = insight?.lastPlayedAt;
      final rating = allRatings[normalizedPath] ?? allRatings[s.path] ?? 0;

      if (lastPlayedAt != null && lastPlayedAt > thirtyDaysAgoMillis) {
        continue;
      }

      if (playCount < 2 && rating < 4) {
        continue;
      }

      final albumKey = '${s.album}|${s.artist}';
      albumGroups.putIfAbsent(albumKey, () => []).add((s, playCount, rating, lastPlayedAt));
    }

    final results = <TimeMachineAlbumEntry>[];

    for (final entry in albumGroups.entries) {
      final items = entry.value;
      if (items.isEmpty) continue;

      final first = items.first.$1;
      final albumName = first.album.trim().isNotEmpty
          ? first.album.trim()
          : 'Unknown Album';
      final artistName = first.artist.trim().isNotEmpty
          ? first.artist.trim()
          : 'Unknown Artist';

      int totalPlays = 0;
      int maxRating = 0;
      int? latestPlayed;

      final musicFiles = <MusicFile>[];
      String? artworkPath;
      String? thumbnailPath;

      for (final item in items) {
        final s = item.$1;
        totalPlays += item.$2;
        if (item.$3 > maxRating) maxRating = item.$3;
        if (item.$4 != null) {
          if (latestPlayed == null || item.$4! > latestPlayed) {
            latestPlayed = item.$4;
          }
        }
        if (artworkPath == null && s.artworkPath != null && s.artworkPath!.isNotEmpty) {
          artworkPath = s.artworkPath;
          thumbnailPath = s.thumbnailPath;
        }

        musicFiles.add(
          MusicFile(
            path: s.path,
            name: p.basename(s.path),
            title: s.title,
            artist: s.artist,
            album: s.album,
            artworkPath: s.artworkPath,
            thumbnailPath: s.thumbnailPath,
            durationMillis: s.duration,
            id: s.id,
          ),
        );
      }

      results.add(
        TimeMachineAlbumEntry(
          album: albumName,
          artist: artistName,
          artworkPath: artworkPath ?? items.first.$1.artworkPath,
          thumbnailPath: thumbnailPath ?? items.first.$1.thumbnailPath,
          songs: musicFiles,
          totalPlayCount: totalPlays,
          maxRating: maxRating,
          lastPlayedAt: latestPlayed,
        ),
      );
    }

    results.sort((a, b) {
      final scoreA = a.totalPlayCount + (a.maxRating * 3);
      final scoreB = b.totalPlayCount + (b.maxRating * 3);
      return scoreB.compareTo(scoreA);
    });

    return results.take(12).toList();
  });
});

/// 最多播放专辑 Provider（按时间跨度统计）：
final mostPlayedAlbumsProvider =
    Provider.family<AsyncValue<List<TimeMachineAlbumEntry>>, LibraryTimeRange>((ref, range) {
  final mostPlayedAsync = ref.watch(mostPlayedSongsProvider(range));
  final albumsAsync = ref.watch(albumLibraryProvider);

  if (mostPlayedAsync.isLoading || albumsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (mostPlayedAsync.hasError) {
    return AsyncValue.error(mostPlayedAsync.error!, mostPlayedAsync.stackTrace!);
  }
  if (albumsAsync.hasError) {
    return AsyncValue.error(albumsAsync.error!, albumsAsync.stackTrace!);
  }

  final songs = mostPlayedAsync.value ?? const [];
  if (songs.isEmpty) {
    return const AsyncValue.data([]);
  }

  final playCounts = <String, int>{};
  final lastPlayedMap = <String, int>{};
  for (final s in songs) {
    final normalized = s.song.path.replaceAll('\\', '/');
    playCounts[normalized] = s.playCount;
    playCounts[s.song.path] = s.playCount;
    if (s.lastPlayedAt != null) {
      final existing = lastPlayedMap[normalized];
      if (existing == null || s.lastPlayedAt! > existing) {
        lastPlayedMap[normalized] = s.lastPlayedAt!;
        lastPlayedMap[s.song.path] = s.lastPlayedAt!;
      }
    }
  }

  final allAlbums = albumsAsync.value ?? const [];
  final albumList = <TimeMachineAlbumEntry>[];

  for (final album in allAlbums) {
    int total = 0;
    int? maxLastPlayed;
    for (final song in album.songs) {
      final normalized = song.path.replaceAll('\\', '/');
      final c = playCounts[normalized] ?? playCounts[song.path] ?? 0;
      total += c;
      final lp = lastPlayedMap[normalized] ?? lastPlayedMap[song.path];
      if (lp != null && (maxLastPlayed == null || lp > maxLastPlayed)) {
        maxLastPlayed = lp;
      }
    }
    if (total > 0) {
      albumList.add(
        TimeMachineAlbumEntry(
          album: album.title,
          artist: album.artist,
          artworkPath: album.representativeSong.artworkPath,
          thumbnailPath: album.representativeSong.thumbnailPath,
          songs: album.songs,
          totalPlayCount: total,
          maxRating: 0,
          lastPlayedAt: maxLastPlayed,
        ),
      );
    }
  }

  albumList.sort((a, b) => b.totalPlayCount.compareTo(a.totalPlayCount));
  return AsyncValue.data(albumList);
});

/// 本周常听专辑 Provider：
/// 基于本周播放记录和专辑库统计近 7 天播放次数最多的专辑
final thisWeekTopAlbumsProvider = Provider<AsyncValue<List<TimeMachineAlbumEntry>>>((ref) {
  final fullListAsync = ref.watch(mostPlayedAlbumsProvider(LibraryTimeRange.last7Days));
  return fullListAsync.whenData((list) => list.take(12).toList());
});

/// 二级洞察页（最近播放 / 最多播放 / 最近添加）共用的筛选状态：
/// [type] 决定展示单曲还是专辑，[range] 决定统计的时间跨度。
class LibraryInsightFilterState {
  const LibraryInsightFilterState({
    this.type = SectionItemType.songs,
    this.range = LibraryTimeRange.allTime,
  });

  final SectionItemType type;
  final LibraryTimeRange range;

  /// 是否为页面的初始状态（歌曲 + 全部时间）。
  /// 用于让 [LibraryInsightFilterNotifier.reset] 幂等，避免无意义地触发通知。
  bool get isDefault =>
      type == SectionItemType.songs && range == LibraryTimeRange.allTime;

  LibraryInsightFilterState copyWith({
    SectionItemType? type,
    LibraryTimeRange? range,
  }) {
    return LibraryInsightFilterState(
      type: type ?? this.type,
      range: range ?? this.range,
    );
  }
}

class LibraryInsightFilterNotifier extends Notifier<LibraryInsightFilterState> {
  @override
  LibraryInsightFilterState build() => const LibraryInsightFilterState();

  void setType(SectionItemType type) {
    if (state.type != type) {
      state = state.copyWith(type: type);
    }
  }

  void setRange(LibraryTimeRange range) {
    if (state.range != range) {
      state = state.copyWith(range: range);
    }
  }

  void setBoth({
    required SectionItemType type,
    required LibraryTimeRange range,
  }) {
    if (state.type != type || state.range != range) {
      state = LibraryInsightFilterState(type: type, range: range);
    }
  }

  /// 复位为「歌曲 + 全部时间」。
  ///
  /// 已处于初始状态时直接返回：宿主页销毁阶段会调用它，此时若仍发出通知，
  /// 会去 markNeedsBuild 一批已经在拆卸中的元素。
  /// 容器已销毁（热重启、登出等）时静默跳过，避免 unmounted ref 异常。
  void reset() {
    if (!ref.mounted) return;
    if (state.isDefault) return;
    state = const LibraryInsightFilterState();
  }
}

final mostPlayedFilterProvider =
    NotifierProvider<LibraryInsightFilterNotifier, LibraryInsightFilterState>(
  LibraryInsightFilterNotifier.new,
);

final recentlyPlayedFilterProvider =
    NotifierProvider<LibraryInsightFilterNotifier, LibraryInsightFilterState>(
  LibraryInsightFilterNotifier.new,
);

final recentlyAddedFilterProvider =
    NotifierProvider<LibraryInsightFilterNotifier, LibraryInsightFilterState>(
  LibraryInsightFilterNotifier.new,
);

/// TimeMachineAlbumEntry 转换为 AlbumSummary 便于使用专辑卡片渲染
extension TimeMachineAlbumEntryX on TimeMachineAlbumEntry {
  /// 与专辑库一致的稳定标识，用于多选 key、Hero tag 与详情页路由。
  String get stableId => '${album.toLowerCase()}::${artist.toLowerCase()}';

  AlbumSummary toAlbumSummary() {
    final rep = songs.firstWhere(
      (s) =>
          (s.artworkPath != null && s.artworkPath!.isNotEmpty) ||
          (s.thumbnailPath != null && s.thumbnailPath!.isNotEmpty),
      orElse: () => songs.isNotEmpty
          ? songs.first
          : MusicFile(
              path: '',
              name: album,
              title: album,
              artist: artist,
              album: album,
              artworkPath: artworkPath,
              thumbnailPath: thumbnailPath,
            ),
    );
    return AlbumSummary(
      id: stableId,
      title: album,
      artist: artist,
      songs: songs,
      representativeSong: rep,
      totalDurationMillis: songs.fold<int>(
        0,
        (sum, s) => sum + (s.durationMillis ?? 0),
      ),
    );
  }
}

/// 最近添加专辑 Provider：
/// 根据歌曲最近添加时间排序，提取出最近入库的专辑
final recentlyAddedAlbumsProvider = Provider<AsyncValue<List<AlbumSummary>>>((ref) {
  final recentSongsAsync = ref.watch(recentlyAddedSongsProvider(LibraryTimeRange.allTime));
  final albumsAsync = ref.watch(albumLibraryProvider);

  if (recentSongsAsync.isLoading || albumsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (recentSongsAsync.hasError) {
    return AsyncValue.error(recentSongsAsync.error!, recentSongsAsync.stackTrace!);
  }
  if (albumsAsync.hasError) {
    return AsyncValue.error(albumsAsync.error!, albumsAsync.stackTrace!);
  }

  final albums = albumsAsync.value ?? const <AlbumSummary>[];
  if (albums.isEmpty) return const AsyncValue.data([]);

  final albumMap = <String, AlbumSummary>{
    for (final a in albums) a.id: a,
    for (final a in albums) '${a.title.toLowerCase()}::${a.artist.toLowerCase()}': a,
  };

  final orderedList = <AlbumSummary>[];
  final seenIds = <String>{};

  final recentSongs = recentSongsAsync.value ?? const <LibraryInsightSongEntry>[];
  for (final entry in recentSongs) {
    final albumName = (entry.song.album ?? 'Unknown Album').trim().toLowerCase();
    final artistName = (entry.song.artist ?? 'Unknown Artist').trim().toLowerCase();
    final key = '$albumName::$artistName';
    final album = albumMap[key];
    if (album != null && seenIds.add(album.id)) {
      orderedList.add(album);
      if (orderedList.length >= 15) break;
    }
  }

  if (orderedList.length < 15) {
    final fallbackList = List<AlbumSummary>.from(albums)
      ..sort((a, b) => b.latestTimestampMillis.compareTo(a.latestTimestampMillis));
    for (final a in fallbackList) {
      if (seenIds.add(a.id)) {
        orderedList.add(a);
        if (orderedList.length >= 15) break;
      }
    }
  }

  return AsyncValue.data(orderedList);
});

/// 已评分专辑 Provider：
/// 提取包含已评分歌曲（rating >= 1）的专辑
final topRatedAlbumsProvider = Provider<AsyncValue<List<AlbumSummary>>>((ref) {
  final ratedSongsAsync = ref.watch(allRatedSongsProvider);
  final albumsAsync = ref.watch(albumLibraryProvider);

  if (ratedSongsAsync.isLoading || albumsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (ratedSongsAsync.hasError) {
    return AsyncValue.error(ratedSongsAsync.error!, ratedSongsAsync.stackTrace!);
  }
  if (albumsAsync.hasError) {
    return AsyncValue.error(albumsAsync.error!, albumsAsync.stackTrace!);
  }

  final albums = albumsAsync.value ?? const <AlbumSummary>[];
  if (albums.isEmpty) return const AsyncValue.data([]);

  final ratedSongs = ratedSongsAsync.value ?? const <LibraryInsightSongEntry>[];
  if (ratedSongs.isEmpty) return const AsyncValue.data([]);

  final albumMap = <String, AlbumSummary>{
    for (final a in albums) a.id: a,
    for (final a in albums) '${a.title.toLowerCase()}::${a.artist.toLowerCase()}': a,
  };

  final orderedList = <AlbumSummary>[];
  final seenIds = <String>{};

  for (final entry in ratedSongs) {
    final albumName = (entry.song.album ?? 'Unknown Album').trim().toLowerCase();
    final artistName = (entry.song.artist ?? 'Unknown Artist').trim().toLowerCase();
    final key = '$albumName::$artistName';
    final album = albumMap[key];
    if (album != null && seenIds.add(album.id)) {
      orderedList.add(album);
      if (orderedList.length >= 15) break;
    }
  }

  return AsyncValue.data(orderedList);
});

/// 最近播放专辑 Provider（按时间跨度）：
/// 把最近播放的歌曲按「专辑 + 艺术家」聚合，按专辑内最近一次播放时间倒序。
final recentlyPlayedAlbumsProvider =
    Provider.family<AsyncValue<List<TimeMachineAlbumEntry>>, LibraryTimeRange>((
      ref,
      range,
    ) {
      final songsAsync = ref.watch(recentlyPlayedSongsProvider(range));
      final albumsAsync = ref.watch(albumLibraryProvider);
      return _combineInsightAlbums(
        songsAsync,
        albumsAsync,
        sortKeySelector: (entry) => entry.lastPlayedAt,
      );
    });

/// 最近添加专辑 Provider（按时间跨度）：
/// 把区间内入库的歌曲按「专辑 + 艺术家」聚合，按专辑内最新入库时间倒序。
/// 与首页横流使用的 [recentlyAddedAlbumsProvider] 不同，本 Provider 支持时间跨度、
/// 保留完整专辑曲目，并额外携带入库时间供列表展示。
final recentlyAddedAlbumsRankedProvider =
    Provider.family<AsyncValue<List<TimeMachineAlbumEntry>>, LibraryTimeRange>((
      ref,
      range,
    ) {
      final songsAsync = ref.watch(recentlyAddedSongsProvider(range));
      final albumsAsync = ref.watch(albumLibraryProvider);
      return _combineInsightAlbums(
        songsAsync,
        albumsAsync,
        sortKeySelector: (entry) => entry.latestAddedAt,
      );
    });

AsyncValue<List<TimeMachineAlbumEntry>> _combineInsightAlbums(
  AsyncValue<List<LibraryInsightSongEntry>> songsAsync,
  AsyncValue<List<AlbumSummary>> albumsAsync, {
  required int? Function(TimeMachineAlbumEntry entry) sortKeySelector,
}) {
  if (songsAsync.isLoading || albumsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (songsAsync.hasError) {
    return AsyncValue.error(songsAsync.error!, songsAsync.stackTrace!);
  }
  if (albumsAsync.hasError) {
    return AsyncValue.error(albumsAsync.error!, albumsAsync.stackTrace!);
  }

  return AsyncValue.data(
    _aggregateInsightAlbums(
      songs: songsAsync.value ?? const <LibraryInsightSongEntry>[],
      albums: albumsAsync.value ?? const <AlbumSummary>[],
      sortKeySelector: sortKeySelector,
    ),
  );
}

String _insightAlbumKey(String album, String artist) =>
    '${album.trim().toLowerCase()}::${artist.trim().toLowerCase()}';

/// 把歌曲级洞察条目按专辑聚合。
///
/// 曲目列表优先取专辑库里的完整专辑，匹配不到时（例如外部来源曲目）
/// 退化为本次命中的歌曲集合，避免整条记录被丢弃。
List<TimeMachineAlbumEntry> _aggregateInsightAlbums({
  required List<LibraryInsightSongEntry> songs,
  required List<AlbumSummary> albums,
  required int? Function(TimeMachineAlbumEntry entry) sortKeySelector,
}) {
  if (songs.isEmpty) return const <TimeMachineAlbumEntry>[];

  final albumIndex = <String, AlbumSummary>{
    for (final album in albums)
      _insightAlbumKey(album.title, album.artist): album,
  };

  final buckets = <String, _InsightAlbumBucket>{};

  for (final entry in songs) {
    final song = entry.song;
    final key = _insightAlbumKey(song.album ?? '', song.artist ?? '');
    final bucket = buckets.putIfAbsent(
      key,
      () => _InsightAlbumBucket(
        album: (song.album ?? '').trim(),
        artist: (song.artist ?? '').trim(),
      ),
    );
    bucket.playCount += entry.playCount;
    bucket.matchedSongs.add(song);

    final playedAt = entry.lastPlayedAt;
    if (playedAt != null &&
        (bucket.lastPlayedAt == null || playedAt > bucket.lastPlayedAt!)) {
      bucket.lastPlayedAt = playedAt;
    }
    final addedAt = entry.createdAt;
    if (addedAt != null &&
        (bucket.latestAddedAt == null || addedAt > bucket.latestAddedAt!)) {
      bucket.latestAddedAt = addedAt;
    }
  }

  final results = <TimeMachineAlbumEntry>[];

  for (final bucket in buckets.values) {
    final album = albumIndex[_insightAlbumKey(bucket.album, bucket.artist)];
    final albumSongs =
        (album != null && album.songs.isNotEmpty) ? album.songs : bucket.matchedSongs;
    if (albumSongs.isEmpty) continue;

    final artworkPath = album?.representativeSong.artworkPath?.isNotEmpty == true
        ? album!.representativeSong.artworkPath
        : _firstArtworkPath(bucket.matchedSongs);
    final thumbnailPath = album?.representativeSong.thumbnailPath?.isNotEmpty == true
        ? album!.representativeSong.thumbnailPath
        : _firstThumbnailPath(bucket.matchedSongs);

    results.add(
      TimeMachineAlbumEntry(
        album: album?.title ?? bucket.album,
        artist: album?.artist ?? bucket.artist,
        artworkPath: artworkPath,
        thumbnailPath: thumbnailPath,
        songs: albumSongs,
        totalPlayCount: bucket.playCount,
        lastPlayedAt: bucket.lastPlayedAt,
        latestAddedAt: bucket.latestAddedAt,
      ),
    );
  }

  results.sort((a, b) {
    final keyA = sortKeySelector(a);
    final keyB = sortKeySelector(b);
    if (keyA == null && keyB == null) return 0;
    if (keyA == null) return 1;
    if (keyB == null) return -1;
    return keyB.compareTo(keyA);
  });

  return results;
}

String? _firstArtworkPath(List<MusicFile> songs) {
  for (final song in songs) {
    final path = song.artworkPath;
    if (path != null && path.isNotEmpty) return path;
  }
  return null;
}

String? _firstThumbnailPath(List<MusicFile> songs) {
  for (final song in songs) {
    final path = song.thumbnailPath;
    if (path != null && path.isNotEmpty) return path;
  }
  return null;
}

class _InsightAlbumBucket {
  _InsightAlbumBucket({required this.album, required this.artist});

  final String album;
  final String artist;
  final List<MusicFile> matchedSongs = <MusicFile>[];
  int playCount = 0;
  int? lastPlayedAt;
  int? latestAddedAt;
}
