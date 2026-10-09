import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/library/library_insights_service.dart';
import 'package:vynody/player/library/library_source_filter.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

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

/// 流派统计摘要
class GenreSummary {
  const GenreSummary({
    required this.name,
    required this.songCount,
    this.representativeArtworkPath,
    this.representativeThumbnailPath,
    required this.sampleSongs,
  });

  final String name;
  final int songCount;
  final String? representativeArtworkPath;
  final String? representativeThumbnailPath;
  final List<MusicFile> sampleSongs;
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
          sampleSongs: entry.value,
        ),
      );
    }

    list.sort((a, b) => b.songCount.compareTo(a.songCount));
    yield list;
  }
});

/// 你的收藏 / 高评分歌曲 Provider（4~5 星）
final topRatedSongsProvider = StreamProvider<List<LibraryInsightSongEntry>>((ref) async* {
  final db = MetadataDatabase();
  final ratingService = ref.watch(songRatingServiceProvider);
  final allRatings = ratingService.allRatings;

  await for (final songs in db.watchAllSongMetadata()) {
    final list = <LibraryInsightSongEntry>[];

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;

      final normalizedPath = s.path.replaceAll('\\', '/');
      final rating = allRatings[normalizedPath] ?? allRatings[s.path] ?? 0;
      if (rating < 4) continue;

      list.add(
        LibraryInsightSongEntry(
          song: MusicFile(
            path: s.path,
            name: s.path.split(RegExp(r'[/\\]')).last,
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

  await for (final songs in db.watchAllSongMetadata()) {
    final list = <LibraryInsightSongEntry>[];

    for (final s in songs) {
      if (s.deletedAt != null) continue;
      final flags = s.sourceFlags ?? 0;
      if ((flags & SongSourceFlags.external) != 0) continue;

      final normalizedPath = s.path.replaceAll('\\', '/');
      final rating = allRatings[normalizedPath] ?? allRatings[s.path] ?? 0;
      if (rating <= 0) continue;

      list.add(
        LibraryInsightSongEntry(
          song: MusicFile(
            path: s.path,
            name: s.path.split(RegExp(r'[/\\]')).last,
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
            name: s.path.split(RegExp(r'[/\\]')).last,
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
