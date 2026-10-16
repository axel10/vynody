import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/library_catalog.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/stream_utils.dart';

/// 艺术家列表 Provider：从 [libraryCatalogProvider] 派生，
/// 自身不再订阅 songs 表；艺术家缓存表查询由快照 Lazy 承担。
final artistLibraryProvider = StreamProvider<List<ArtistSummary>>(
  (ref) => catalogDerived(ref, (catalog) => catalog.artists),
);

int _artistLibrarySessionSeq = 0;

void _artistLibraryLog(String message) {
  debugPrint('[ArtistLibrary] $message');
}

class ArtistLibraryRepository {
  ArtistLibraryRepository({
    MetadataDatabase? database,
  }) : _database = database ?? MetadataDatabase();

  final MetadataDatabase _database;

  /// 一次性把歌曲列表聚合为艺术家摘要（含两张缓存表查询）。
  ///
  /// 曲库快照 [LibraryCatalog] 与下方的流式版本共用这一份实现，
  /// 避免出现两套聚合逻辑。
  Future<List<ArtistSummary>> buildSummariesFor(
    Iterable<SongMetadata> songs,
  ) async {
    final stopwatch = Stopwatch()..start();
    final filteredSongs = songs
        .where(
          (song) => ((song.sourceFlags ?? 0) & SongSourceFlags.external) == 0,
        )
        .toList(growable: false);
    final groups = _groupSongsByArtist(filteredSongs);

    final cacheKeys = groups
        .map((group) => group.queryKey)
        .toList(growable: false);
    final caches = await _database.getArtistCachesByKeys(cacheKeys);
    final imageCaches = await _database.getArtistImageCachesByIds(cacheKeys);
    final orderedGroups = _sortGroupsForDisplay(groups, caches);
    stopwatch.stop();
    _artistLibraryLog(
      'loaded songs=${filteredSongs.length} groups=${groups.length} '
      'caches=${caches.length} imageCaches=${imageCaches.length} in ${stopwatch.elapsedMilliseconds}ms',
    );
    return _buildSummaries(orderedGroups, caches, imageCaches);
  }

  /// 流式版本：`audio_service` 在「播放下一首 / 上一首艺术家」时取首帧使用。
  /// 主页面的艺术家列表已改由曲库快照提供，这里只服务这条低频路径。
  Stream<List<ArtistSummary>> watchArtistSummaries() async* {
    final sessionId = ++_artistLibrarySessionSeq;
    _artistLibraryLog('session#$sessionId start');

    await for (final songs in _database
        .watchAllSongMetadata()
        .throttleLeadingAndTrailing(const Duration(seconds: 1))) {
      yield await buildSummariesFor(songs);
    }
    _artistLibraryLog('session#$sessionId complete');
  }

  List<_ArtistGroup> _groupSongsByArtist(List<SongMetadata> songs) {
    final groups = <String, _ArtistGroup>{};
    final order = <String>[];

    for (final song in songs) {
      final artistNames = splitArtistNames(song.artist);
      if (artistNames.isEmpty) continue;

      final seenKeys = <String>{};
      for (final artistName in artistNames) {
        final queryKey = normalizeArtistKey(artistName);
        if (queryKey.isEmpty || !seenKeys.add(queryKey)) {
          continue;
        }

        final group = groups.putIfAbsent(queryKey, () {
          order.add(queryKey);
          return _ArtistGroup(
            queryKey: queryKey,
            displayName: artistName,
            songs: <MusicFile>[],
          );
        });

        group.addSong(song);
        if (group.displayName == 'Unknown Artist' &&
            artistName.toLowerCase() != 'unknown artist') {
          group.displayName = artistName;
        }
        if (group.displayName.trim().isEmpty) {
          group.displayName = artistName;
        }
      }
    }

    return order.map((key) => groups[key]!).toList(growable: false);
  }

  ArtistSummary _buildSummary(
    _ArtistGroup group,
    ArtistCacheRecord? cache,
    ArtistImageCacheRecord? imageCache, {
    bool isImageLoading = false,
  }) {
    final representativeSong = group.songs.firstWhere(
      _hasArtwork,
      orElse: () => group.songs.first,
    );
    final tags = _decodeStringList(cache?.tagsJson);
    final alternateNames = _extractAlternateNames(cache);
    final cachedPath = (imageCache?.imagePath != null &&
            imageCache!.imagePath.isNotEmpty &&
            File(imageCache.imagePath).existsSync())
        ? imageCache.imagePath
        : null;
    final rawCanonical = cache?.artistName?.trim();
    final canonicalName =
        (rawCanonical != null && rawCanonical.isNotEmpty) ? rawCanonical : null;

    return ArtistSummary(
      queryKey: group.queryKey,
      name: group.displayName,
      canonicalName: canonicalName,
      alternateNames: alternateNames,
      songs: List<MusicFile>.unmodifiable(group.songs),
      representativeSong: representativeSong,
      songCount: group.songs.length,
      artistId: cache?.artistId,
      sortName: cache?.sortName,
      disambiguation: cache?.disambiguation,
      country: cache?.country,
      areaName: cache?.areaName,
      beginDate: cache?.beginDate,
      endDate: cache?.endDate,
      imageFileTitle: cache?.imageFileTitle,
      imageUrl: cache?.imageUrl,
      thumbnailUrl: cache?.thumbnailUrl,
      cachedImagePath: cachedPath,
      isImageLoading: isImageLoading,
      tags: tags,
      noData: cache?.noData ?? false,
    );
  }

  List<ArtistSummary> _buildSummaries(
    List<_ArtistGroup> groups,
    Map<String, ArtistCacheRecord> caches,
    Map<String, ArtistImageCacheRecord> imageCaches, {
    String? loadingKey,
  }) {
    // Keep the list order stable while artist metadata refreshes in the
    // background. Re-sorting on every incremental update makes the grid jump and
    // looks like a loading flash to the user.
    return groups
        .map(
          (group) => _buildSummary(
            group,
            caches[group.queryKey],
            imageCaches[group.queryKey],
            isImageLoading: loadingKey == group.queryKey,
          ),
        )
        .toList(growable: false);
  }

  List<_ArtistGroup> _sortGroupsForDisplay(
    List<_ArtistGroup> groups,
    Map<String, ArtistCacheRecord> caches,
  ) {
    final sorted = groups.toList(growable: false);
    sorted.sort((left, right) {
      final leftCache = caches[left.queryKey];
      final rightCache = caches[right.queryKey];
      final leftLabel = _groupSortLabel(left, leftCache);
      final rightLabel = _groupSortLabel(right, rightCache);
      final compare = leftLabel.compareTo(rightLabel);
      if (compare != 0) return compare;
      return _artistDisplayName(
        left,
        leftCache,
      ).compareTo(_artistDisplayName(right, rightCache));
    });
    return sorted;
  }
}

class _ArtistGroup {
  _ArtistGroup({
    required this.queryKey,
    required this.displayName,
    required this.songs,
  });

  final String queryKey;
  String displayName;
  final List<MusicFile> songs;

  void addSong(SongMetadata metadata) {
    songs.add(
      MusicFile(
        path: metadata.path,
        name: metadata.path.split(RegExp(r'[\\/]+')).last,
        title: metadata.title,
        artist: metadata.artist,
        albumArtist: metadata.albumArtist,
        album: metadata.album,
        trackNumber: metadata.trackNumber,
        id: metadata.id,
        artworkPath: metadata.artworkPath,
        thumbnailPath: metadata.thumbnailPath,
        artworkWidth: metadata.artworkWidth,
        artworkHeight: metadata.artworkHeight,
        durationMillis: metadata.duration,
        lastModifiedTime: metadata.lastModifiedTime,
      ),
    );
  }
}

String _groupSortLabel(_ArtistGroup group, ArtistCacheRecord? cache) {
  final cachedSortName = cache?.sortName?.trim();
  if (cachedSortName != null && cachedSortName.isNotEmpty) {
    return cachedSortName.toLowerCase();
  }
  return group.displayName.toLowerCase();
}

String _groupDisplayName(_ArtistGroup group, ArtistCacheRecord? cache) {
  return group.displayName;
}

String _artistDisplayName(_ArtistGroup group, ArtistCacheRecord? cache) {
  return _groupDisplayName(group, cache);
}

List<String> _extractAlternateNames(ArtistCacheRecord? cache) {
  if (cache == null) return const <String>[];
  final alternates = <String>{};

  void parseJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final alt = decoded['strArtistAlternate']?.toString();
        if (alt != null && alt.trim().isNotEmpty) {
          for (final part in alt.split(RegExp(r'\s*[,;，/]\s*'))) {
            final trimmed = part.trim();
            if (trimmed.isNotEmpty) {
              alternates.add(trimmed);
            }
          }
        }
      }
    } catch (_) {}
  }

  parseJson(cache.rawSearchJson);
  parseJson(cache.rawDetailJson);
  return alternates.toList(growable: false);
}

bool _hasArtwork(MusicFile song) {
  return (song.thumbnailPath?.trim().isNotEmpty ?? false) ||
      (song.artworkPath?.trim().isNotEmpty ?? false);
}

List<String> splitArtistNames(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return const <String>[];

  return raw
      .split(RegExp(r'\s*[,;]\s*'))
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toList(growable: false);
}

List<String> _decodeStringList(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const <String>[];
  return decoded
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
