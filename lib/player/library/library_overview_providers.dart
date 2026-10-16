import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/genre_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/year_summary.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/album_library.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_source_filter.dart';
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
  });

  final String album;
  final String artist;
  final String? artworkPath;
  final String? thumbnailPath;
  final List<MusicFile> songs;
  final int totalPlayCount;
  final int maxRating;
  final int? lastPlayedAt;
}

/// 流派列表 Provider：仅返回包含有效歌曲的流派，并按歌曲数量从多到少排序
final genreLibraryProvider = StreamProvider<List<GenreSummary>>((ref) async* {
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

  await for (final songs in db.watchAllSongMetadata()) {
    final genreMap = <String, List<MusicFile>>{};

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;
      if (shouldFilter && !scanner.isPathInActiveRoots(s.path)) continue;
      if (!sourceFilter.matchesSongPath(s.path)) continue;

      final parsedGenres = s.genres;
      if (parsedGenres == null || parsedGenres.isEmpty) continue;

      final musicFile = MusicFile(
        path: s.path,
        name: s.path.split(RegExp(r'[/\\]')).last,
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
    yield list;
  }
});

/// 发行年份列表 Provider：
/// 按音频元数据中的发行年份聚合歌曲，年份由新到旧排列；
/// 未提取到年份的歌曲统一归入「未知年份」分组并固定排在列表末尾。
final yearLibraryProvider = StreamProvider<List<YearSummary>>((ref) async* {
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

  await for (final songs in db.watchAllSongMetadata()) {
    final yearMap = <int?, List<MusicFile>>{};

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;
      if (shouldFilter && !scanner.isPathInActiveRoots(s.path)) continue;
      if (!sourceFilter.matchesSongPath(s.path)) continue;

      final musicFile = MusicFile(
        path: s.path,
        name: s.path.split(RegExp(r'[/\\]')).last,
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
    yield list;
  }
});

/// 你的收藏 / 高评分歌曲 Provider（4~5 星）
final topRatedSongsProvider = StreamProvider<List<LibraryInsightSongEntry>>((ref) async* {
  final db = MetadataDatabase();
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  if (allRatings.isEmpty) {
    yield const <LibraryInsightSongEntry>[];
    return;
  }

  await for (final songs in db.watchAllSongMetadata()) {
    if (allRatings.isEmpty) {
      yield const <LibraryInsightSongEntry>[];
      continue;
    }

    final list = <LibraryInsightSongEntry>[];

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;

      final normalizedPath = s.path.replaceAll('\\', '/');
      final rating = allRatings[normalizedPath] ??
          allRatings[s.path] ??
          ratingService.getRating(s.path);
      if (rating < 4) continue;

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

    yield list;
  }
});

/// 全部已打分歌曲 Provider（用于二级页已评分曲目列表）
final allRatedSongsProvider = StreamProvider<List<LibraryInsightSongEntry>>((ref) async* {
  final db = MetadataDatabase();
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  if (allRatings.isEmpty) {
    yield const <LibraryInsightSongEntry>[];
    return;
  }

  await for (final songs in db.watchAllSongMetadata()) {
    if (allRatings.isEmpty) {
      yield const <LibraryInsightSongEntry>[];
      continue;
    }

    final list = <LibraryInsightSongEntry>[];

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;

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

    yield list;
  }
});

/// 拾光机 / 重温旧爱专辑 Provider：
/// 满足历史高频播放（playCount >= 2）或主动打分（rating >= 4），且在近 30 天内未曾播放的专辑
final timeMachineAlbumsProvider = StreamProvider<List<TimeMachineAlbumEntry>>((ref) async* {
  final mostPlayedAsync = ref.watch(mostPlayedSongsProvider(LibraryTimeRange.allTime));
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  final mostPlayedList = mostPlayedAsync.value ?? const [];
  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final thirtyDaysAgoMillis = nowMillis - const Duration(days: 30).inMilliseconds;

  final insightMap = <String, LibraryInsightSongEntry>{};
  for (final item in mostPlayedList) {
    insightMap[item.song.path.replaceAll('\\', '/')] = item;
  }

  final db = MetadataDatabase();
  await for (final songs in db.watchAllSongMetadata()) {
    final albumGroups = <String, List<(SongMetadata, int playCount, int rating, int? lastPlayed)>>{};

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;

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

    yield results.take(12).toList();
  }
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

/// 最多播放页面筛选状态模型
class MostPlayedFilterState {
  const MostPlayedFilterState({
    this.type = SectionItemType.songs,
    this.range = LibraryTimeRange.allTime,
  });

  final SectionItemType type;
  final LibraryTimeRange range;

  MostPlayedFilterState copyWith({
    SectionItemType? type,
    LibraryTimeRange? range,
  }) {
    return MostPlayedFilterState(
      type: type ?? this.type,
      range: range ?? this.range,
    );
  }
}

class MostPlayedFilterNotifier extends Notifier<MostPlayedFilterState> {
  @override
  MostPlayedFilterState build() => const MostPlayedFilterState();

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
      state = MostPlayedFilterState(type: type, range: range);
    }
  }

  void reset() {
    state = const MostPlayedFilterState();
  }
}

final mostPlayedFilterProvider =
    NotifierProvider<MostPlayedFilterNotifier, MostPlayedFilterState>(
  MostPlayedFilterNotifier.new,
);

/// 拾光机 / 重温旧爱单曲 Provider：
/// 满足历史高频播放（playCount >= 2）或主动打分（rating >= 4），且在近 30 天内未曾播放的单曲
final timeMachineSongsProvider = StreamProvider<List<LibraryInsightSongEntry>>((ref) async* {
  final mostPlayedAsync = ref.watch(mostPlayedSongsProvider(LibraryTimeRange.allTime));
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  final mostPlayedList = mostPlayedAsync.value ?? const [];
  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  final thirtyDaysAgoMillis = nowMillis - const Duration(days: 30).inMilliseconds;

  final insightMap = <String, LibraryInsightSongEntry>{};
  for (final item in mostPlayedList) {
    insightMap[item.song.path.replaceAll('\\', '/')] = item;
  }

  final db = MetadataDatabase();
  await for (final songs in db.watchAllSongMetadata()) {
    final list = <LibraryInsightSongEntry>[];

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;

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
          playCount: playCount,
          lastPlayedAt: lastPlayedAt,
          createdAt: s.createdAt,
          sourceFlags: s.sourceFlags,
        ),
      );
    }

    list.sort((a, b) {
      final ratingA = allRatings[a.song.path.replaceAll('\\', '/')] ?? allRatings[a.song.path] ?? 0;
      final ratingB = allRatings[b.song.path.replaceAll('\\', '/')] ?? allRatings[b.song.path] ?? 0;
      final scoreA = a.playCount + (ratingA * 3);
      final scoreB = b.playCount + (ratingB * 3);
      final scoreCmp = scoreB.compareTo(scoreA);
      if (scoreCmp != 0) return scoreCmp;
      return (b.lastPlayedAt ?? 0).compareTo(a.lastPlayedAt ?? 0);
    });

    yield list.take(12).toList();
  }
});

/// TimeMachineAlbumEntry 转换为 AlbumSummary 便于使用专辑卡片渲染
extension TimeMachineAlbumEntryX on TimeMachineAlbumEntry {
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
      id: '${album.toLowerCase()}::${artist.toLowerCase()}',
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
