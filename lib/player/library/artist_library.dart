import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vibe_flow/models/artist_summary.dart';
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/utils/network_client.dart';
import 'package:vibe_flow/player/metadata/metadata_database.dart';

final artistLibraryProvider = StreamProvider<List<ArtistSummary>>((ref) async* {
  final repository = ArtistLibraryRepository();
  yield* repository.watchArtistSummaries();
});

int _artistLibrarySessionSeq = 0;

void _artistLibraryLog(String message) {
  debugPrint('[ArtistLibrary] $message');
}

class ArtistLibraryRepository {
  ArtistLibraryRepository({
    MetadataDatabase? database,
    NetworkClient? networkClient,
  }) : _database = database ?? MetadataDatabase(),
       _networkClient = networkClient ?? NetworkClient.instance;

  final MetadataDatabase _database;
  final NetworkClient _networkClient;

  static Future<void> _musicBrainzQueue = Future<void>.value();
  static DateTime _lastMusicBrainzRequestAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  Stream<List<ArtistSummary>> watchArtistSummaries() async* {
    final sessionId = ++_artistLibrarySessionSeq;
    _artistLibraryLog('session#$sessionId start');

    final songs = await _database.getAllSongMetadata();
    final groups = _groupSongsByArtist(songs);

    final cacheKeys = groups
        .map((group) => group.queryKey)
        .toList(growable: false);
    final caches = await _database.getArtistCachesByKeys(cacheKeys);
    final orderedGroups = _sortGroupsForDisplay(groups, caches);
    _artistLibraryLog(
      'session#$sessionId loaded songs=${songs.length} groups=${groups.length} '
      'caches=${caches.length}',
    );
    yield _buildSummaries(orderedGroups, caches);
    _artistLibraryLog(
      'session#$sessionId initial yield summaries=${orderedGroups.length}',
    );

    final pendingGroups = orderedGroups
        .where((group) => _needsArtistRefresh(group, caches[group.queryKey]))
        .toList(growable: false);
    _artistLibraryLog(
      'session#$sessionId pendingGroups=${pendingGroups.length}',
    );
    if (pendingGroups.isEmpty) {
      _artistLibraryLog('session#$sessionId complete: nothing to refresh');
      return;
    }

    final currentCaches = <String, ArtistCacheRecord>{...caches};
    await for (final updated in _refreshMissingArtistCaches(
      groups: orderedGroups,
      pendingGroups: pendingGroups,
      cacheMap: currentCaches,
      sessionId: sessionId,
    )) {
      yield updated;
    }
    _artistLibraryLog('session#$sessionId complete');
  }

  Stream<List<ArtistSummary>> _refreshMissingArtistCaches({
    required List<_ArtistGroup> groups,
    required List<_ArtistGroup> pendingGroups,
    required Map<String, ArtistCacheRecord> cacheMap,
    required int sessionId,
  }) async* {
    final pending = List<_ArtistGroup>.from(pendingGroups);
    while (pending.isNotEmpty) {
      final batch = pending.take(20).toList(growable: false);
      pending.removeRange(0, batch.length);
      _artistLibraryLog(
        'session#$sessionId batch size=${batch.length} remaining=${pending.length}',
      );

      final searchGroups = <_ArtistGroup>[];
      for (final group in batch) {
        final existing = cacheMap[group.queryKey];
        if (existing == null) {
          searchGroups.add(group);
          continue;
        }

        if (existing.noData) {
          continue;
        }

        if (!existing.imageFetchCompleted) {
          searchGroups.add(group);
        }
      }

      if (searchGroups.isEmpty) {
        continue;
      }

      final searchResults = await _searchArtistsByBatch(searchGroups);
      for (final group in searchGroups) {
        final searchHit = searchResults[group.queryKey];
        if (searchHit == null) {
          final record = ArtistCacheRecord(
            queryKey: group.queryKey,
            artistName: group.displayName,
            noData: true,
            imageFetchCompleted: true,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          );
          await _database.insertOrUpdateArtistCache(record);
          cacheMap[group.queryKey] = record;
          _artistLibraryLog(
            'session#$sessionId search miss key=${group.queryKey} '
            'name=${group.displayName}',
          );
          yield _buildSummaries(groups, cacheMap);
          continue;
        }

        _artistLibraryLog(
          'session#$sessionId search hit key=${group.queryKey} '
          'artistId=${searchHit.id} name=${searchHit.name}',
        );
        cacheMap[group.queryKey] = _loadingCacheRecord(group, searchHit);
        yield _buildSummaries(groups, cacheMap, loadingKey: group.queryKey);

        final detail = await _fetchArtistDetail(searchHit.id);
        final record = ArtistCacheRecord(
          queryKey: group.queryKey,
          artistId: searchHit.id,
          artistName: searchHit.name.isNotEmpty
              ? searchHit.name
              : group.displayName,
          sortName: searchHit.sortName,
          disambiguation: detail?.disambiguation ?? searchHit.disambiguation,
          country: detail?.country ?? searchHit.country,
          areaName: detail?.areaName,
          beginDate: detail?.beginDate,
          endDate: detail?.endDate,
          tagsJson: detail?.tagsJson,
          rawSearchJson: jsonEncode(searchHit.raw),
          rawDetailJson: detail == null ? null : jsonEncode(detail.raw),
          noData: false,
          imageFetchCompleted: true,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        await _database.insertOrUpdateArtistCache(record);
        cacheMap[group.queryKey] = record;
        _artistLibraryLog(
          'session#$sessionId search refresh saved key=${group.queryKey} '
          'artistId=${searchHit.id}',
        );
        yield _buildSummaries(groups, cacheMap);
      }
    }
  }

  bool _needsArtistRefresh(_ArtistGroup group, ArtistCacheRecord? cache) {
    if (cache == null) return true;
    if (cache.noData) return false;
    return !cache.imageFetchCompleted || cache.artistId == null;
  }

  Future<Map<String, _ArtistSearchHit?>> _searchArtistsByBatch(
    List<_ArtistGroup> groups,
  ) async {
    final query = groups
        .map((group) => 'artist:"${_escapeLucene(group.displayName)}"')
        .join(' OR ');

    final data = await _runMusicBrainzRequest(() async {
      final response = await _networkClient.get<Map<String, dynamic>>(
        'https://musicbrainz.org/ws/2/artist/',
        queryParameters: {'query': query, 'fmt': 'json'},
      );
      return response.data ?? <String, dynamic>{};
    });

    final artists = data['artists'];
    final rawArtists = artists is List ? artists : const [];
    final normalizedHits = <String, _ArtistSearchHit>{};
    for (final item in rawArtists) {
      if (item is! Map<String, dynamic>) continue;
      final hit = _ArtistSearchHit.fromJson(item);
      final key = normalizeArtistKey(hit.name);
      if (key.isEmpty || normalizedHits.containsKey(key)) {
        continue;
      }
      normalizedHits[key] = hit;
    }

    return {
      for (final group in groups)
        group.queryKey: normalizedHits[group.queryKey],
    };
  }

  Future<_ArtistDetailResult?> _fetchArtistDetail(String artistId) async {
    if (artistId.trim().isEmpty) return null;

    final detail = await _runMusicBrainzRequest(() async {
      final response = await _networkClient.get<Map<String, dynamic>>(
        'https://musicbrainz.org/ws/2/artist/$artistId',
        queryParameters: {'inc': 'url-rels', 'fmt': 'json'},
      );
      return response.data;
    });

    if (detail == null || detail.isEmpty) return null;

    final tags = (detail['tags'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((tag) => tag['name']?.toString() ?? '')
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false);

    return _ArtistDetailResult(
      raw: detail,
      disambiguation: detail['disambiguation'] as String?,
      country: detail['country'] as String?,
      areaName: _readNestedString(detail, ['area', 'name']),
      beginDate: _readNestedString(detail, ['life-span', 'begin']),
      endDate: _readNestedString(detail, ['life-span', 'end']),
      tagsJson: jsonEncode(tags),
    );
  }

  Future<T> _runMusicBrainzRequest<T>(Future<T> Function() task) async {
    final previous = _musicBrainzQueue;
    final ready = Completer<void>();
    _musicBrainzQueue = ready.future;

    try {
      await previous;
      final elapsed = DateTime.now().difference(_lastMusicBrainzRequestAt);
      const minimumSpacing = Duration(milliseconds: 1100);
      if (elapsed < minimumSpacing) {
        await Future<void>.delayed(minimumSpacing - elapsed);
      }
      final result = await task();
      _lastMusicBrainzRequestAt = DateTime.now();
      return result;
    } finally {
      ready.complete();
    }
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
    ArtistCacheRecord? cache, {
    bool isImageLoading = false,
  }) {
    final representativeSong = group.songs.firstWhere(
      _hasArtwork,
      orElse: () => group.songs.first,
    );
    final tags = _decodeStringList(cache?.tagsJson);
    return ArtistSummary(
      queryKey: group.queryKey,
      name: cache?.artistName?.trim().isNotEmpty == true
          ? cache!.artistName!.trim()
          : group.displayName,
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
      imageFileTitle: null,
      imageUrl: null,
      thumbnailUrl: null,
      cachedImagePath: null,
      isImageLoading: isImageLoading,
      tags: tags,
      noData: cache?.noData ?? false,
    );
  }

  List<ArtistSummary> _buildSummaries(
    List<_ArtistGroup> groups,
    Map<String, ArtistCacheRecord> caches, {
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

  ArtistCacheRecord _loadingCacheRecord(
    _ArtistGroup group,
    _ArtistSearchHit searchHit,
  ) {
    return ArtistCacheRecord(
      queryKey: group.queryKey,
      artistId: searchHit.id,
      artistName: searchHit.name.isNotEmpty
          ? searchHit.name
          : group.displayName,
      sortName: searchHit.sortName,
      disambiguation: searchHit.disambiguation,
      country: searchHit.country,
      noData: false,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
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

class _ArtistSearchHit {
  const _ArtistSearchHit({
    required this.id,
    required this.name,
    required this.sortName,
    required this.country,
    required this.disambiguation,
    required this.raw,
  });

  final String id;
  final String name;
  final String? sortName;
  final String? country;
  final String? disambiguation;
  final Map<String, dynamic> raw;

  factory _ArtistSearchHit.fromJson(Map<String, dynamic> json) {
    return _ArtistSearchHit(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      sortName: json['sort-name']?.toString(),
      country: json['country']?.toString(),
      disambiguation: json['disambiguation']?.toString(),
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class _ArtistDetailResult {
  const _ArtistDetailResult({
    required this.raw,
    required this.disambiguation,
    required this.country,
    required this.areaName,
    required this.beginDate,
    required this.endDate,
    required this.tagsJson,
  });

  final Map<String, dynamic> raw;
  final String? disambiguation;
  final String? country;
  final String? areaName;
  final String? beginDate;
  final String? endDate;
  final String? tagsJson;
}

String _groupSortLabel(_ArtistGroup group, ArtistCacheRecord? cache) {
  final cachedSortName = cache?.sortName?.trim();
  if (cachedSortName != null && cachedSortName.isNotEmpty) {
    return cachedSortName.toLowerCase();
  }
  final cachedName = cache?.artistName?.trim();
  if (cachedName != null && cachedName.isNotEmpty) {
    return cachedName.toLowerCase();
  }
  return group.displayName.toLowerCase();
}

String _groupDisplayName(_ArtistGroup group, ArtistCacheRecord? cache) {
  final cachedName = cache?.artistName?.trim();
  if (cachedName != null && cachedName.isNotEmpty) {
    return cachedName;
  }
  return group.displayName;
}

String _artistDisplayName(_ArtistGroup group, ArtistCacheRecord? cache) {
  return _groupDisplayName(group, cache);
}

bool _hasArtwork(MusicFile song) {
  return (song.thumbnailPath?.trim().isNotEmpty ?? false) ||
      (song.artworkPath?.trim().isNotEmpty ?? false);
}

List<String> splitArtistNames(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return const <String>[];

  return raw
      .split(RegExp(r'\s*[,/&;]\s*'))
      .map((artist) => artist.trim())
      .where((artist) => artist.isNotEmpty)
      .toList(growable: false);
}

String _escapeLucene(String value) {
  const specialChars = r'+-!(){}[]^"~*?:\/&|';
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (specialChars.contains(char)) {
      buffer.write('\\');
    }
    buffer.write(char);
  }
  return buffer.toString();
}

String? _readNestedString(Map<String, dynamic> data, List<String> path) {
  Object? current = data;
  for (final segment in path) {
    if (current is! Map<String, dynamic>) return null;
    current = current[segment];
  }
  return current?.toString();
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
