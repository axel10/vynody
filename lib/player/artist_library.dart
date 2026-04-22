import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/artist_summary.dart';
import '../models/music_file.dart';
import '../utils/network_client.dart';
import 'metadata_database.dart';

final artistLibraryProvider = FutureProvider<List<ArtistSummary>>((ref) async {
  final repository = ArtistLibraryRepository();
  return repository.loadArtistSummaries();
});

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

  Future<List<ArtistSummary>> loadArtistSummaries() async {
    final songs = await _database.getAllSongMetadata();
    final groups = _groupSongsByArtist(songs);

    final cacheKeys = groups.map((group) => group.queryKey).toList(
      growable: false,
    );
    final existingCaches = await _database.getArtistCachesByKeys(cacheKeys);
    final missingGroups = groups
        .where((group) => !existingCaches.containsKey(group.queryKey))
        .toList(growable: false);

    if (missingGroups.isNotEmpty) {
      await _refreshMissingArtistCaches(missingGroups);
    }

    final refreshedCaches = await _database.getArtistCachesByKeys(cacheKeys);
    final summaries = groups
        .map((group) => _buildSummary(group, refreshedCaches[group.queryKey]))
        .toList(growable: false)
      ..sort((left, right) {
        final leftName = _artistSortLabel(left);
        final rightName = _artistSortLabel(right);
        final compare = leftName.compareTo(rightName);
        if (compare != 0) return compare;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

    return summaries;
  }

  Future<void> _refreshMissingArtistCaches(List<_ArtistGroup> groups) async {
    final pending = List<_ArtistGroup>.from(groups);
    while (pending.isNotEmpty) {
      final batch = pending.take(20).toList(growable: false);
      pending.removeRange(0, batch.length);

      final searchResults = await _searchArtistsByBatch(batch);
      for (final group in batch) {
        final searchHit = searchResults[group.queryKey];
        if (searchHit == null) {
          await _database.insertOrUpdateArtistCache(
            ArtistCacheRecord(
              queryKey: group.queryKey,
              artistName: group.displayName,
              noData: true,
              updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
            ),
          );
          continue;
        }

        final detail = await _fetchArtistDetail(searchHit.id);
        await _database.insertOrUpdateArtistCache(
          ArtistCacheRecord(
            queryKey: group.queryKey,
            artistId: searchHit.id,
            artistName: searchHit.name.isNotEmpty
                ? searchHit.name
                : group.displayName,
            sortName: searchHit.sortName,
            disambiguation: detail?.disambiguation ?? searchHit.disambiguation,
            country: detail?.country ?? searchHit.country,
            imageFileTitle: detail?.imageFileTitle,
            imageUrl: detail?.imageUrl,
            thumbnailUrl: detail?.thumbnailUrl ?? detail?.imageUrl,
            areaName: detail?.areaName,
            beginDate: detail?.beginDate,
            endDate: detail?.endDate,
            tagsJson: detail?.tagsJson,
            rawSearchJson: jsonEncode(searchHit.raw),
            rawDetailJson: detail == null ? null : jsonEncode(detail.raw),
            noData: false,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    }
  }

  Future<Map<String, _ArtistSearchHit?>> _searchArtistsByBatch(
    List<_ArtistGroup> groups,
  ) async {
    final query = groups
        .map(
          (group) => 'artist:"${_escapeLucene(group.displayName)}"',
        )
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

    final imageRelation = _extractImageRelation(detail);
    final imageFileTitle = imageRelation == null
        ? null
        : _extractFileTitle(imageRelation);
    final imageInfo = imageFileTitle == null
        ? null
        : await _fetchWikimediaImage(imageFileTitle);

    final tags = (detail['tags'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((tag) => tag['name']?.toString() ?? '')
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false);

    return _ArtistDetailResult(
      raw: detail,
      disambiguation: detail['disambiguation'] as String?,
      country: detail['country'] as String?,
      imageFileTitle: imageFileTitle,
      imageUrl: imageInfo?.url,
      thumbnailUrl: imageInfo?.url,
      areaName: _readNestedString(detail, ['area', 'name']),
      beginDate: _readNestedString(detail, ['life-span', 'begin']),
      endDate: _readNestedString(detail, ['life-span', 'end']),
      tagsJson: jsonEncode(tags),
    );
  }

  Future<_WikimediaImageInfo?> _fetchWikimediaImage(String fileTitle) async {
    final response = await _networkClient.get<Map<String, dynamic>>(
      'https://commons.wikimedia.org/w/api.php',
      queryParameters: {
        'action': 'query',
        'titles': fileTitle.startsWith('File:') ? fileTitle : 'File:$fileTitle',
        'prop': 'imageinfo',
        'iiprop': 'url',
        'format': 'json',
      },
    );

    final data = response.data;
    final pages = data?['query'];
    if (pages is! Map<String, dynamic>) return null;
    final pageMap = pages['pages'];
    if (pageMap is! Map<String, dynamic>) return null;

    for (final page in pageMap.values) {
      if (page is! Map<String, dynamic>) continue;
      final imageinfo = page['imageinfo'];
      if (imageinfo is! List || imageinfo.isEmpty) continue;
      final first = imageinfo.first;
      if (first is! Map<String, dynamic>) continue;
      final url = first['url']?.toString();
      if (url == null || url.isEmpty) continue;
      return _WikimediaImageInfo(url: url);
    }

    return null;
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
      final rawName = song.artist.trim();
      if (rawName.isEmpty) continue;
      final queryKey = normalizeArtistKey(rawName);
      if (queryKey.isEmpty) continue;

      final group = groups.putIfAbsent(queryKey, () {
        order.add(queryKey);
        return _ArtistGroup(
          queryKey: queryKey,
          displayName: rawName,
          songs: <MusicFile>[],
        );
      });

      group.addSong(song);
      if (group.displayName == 'Unknown Artist' &&
          rawName.toLowerCase() != 'unknown artist') {
        group.displayName = rawName;
      }
      if (group.displayName.trim().isEmpty) {
        group.displayName = rawName;
      }
    }

    final result = order.map((key) => groups[key]!).toList(growable: false);
    return result;
  }

  ArtistSummary _buildSummary(
    _ArtistGroup group,
    ArtistCacheRecord? cache,
  ) {
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
      imageFileTitle: cache?.imageFileTitle,
      imageUrl: cache?.imageUrl,
      thumbnailUrl: cache?.thumbnailUrl,
      tags: tags,
      noData: cache?.noData ?? false,
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
    required this.imageFileTitle,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.areaName,
    required this.beginDate,
    required this.endDate,
    required this.tagsJson,
  });

  final Map<String, dynamic> raw;
  final String? disambiguation;
  final String? country;
  final String? imageFileTitle;
  final String? imageUrl;
  final String? thumbnailUrl;
  final String? areaName;
  final String? beginDate;
  final String? endDate;
  final String? tagsJson;
}

class _WikimediaImageInfo {
  const _WikimediaImageInfo({required this.url});

  final String url;
}

String _artistSortLabel(ArtistSummary summary) {
  return summary.sortName?.trim().isNotEmpty == true
      ? summary.sortName!.trim().toLowerCase()
      : summary.name.toLowerCase();
}

bool _hasArtwork(MusicFile song) {
  return (song.thumbnailPath?.trim().isNotEmpty ?? false) ||
      (song.artworkPath?.trim().isNotEmpty ?? false);
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

String? _extractImageRelation(Map<String, dynamic> detail) {
  final relations = detail['relations'];
  if (relations is! List) return null;
  for (final relation in relations) {
    if (relation is! Map<String, dynamic>) continue;
    if (relation['type']?.toString().toLowerCase() != 'image') continue;
    final url = relation['url'];
    if (url is! Map<String, dynamic>) continue;
    final resource = url['resource']?.toString();
    if (resource == null || resource.isEmpty) continue;
    return resource;
  }
  return null;
}

String? _extractFileTitle(String resourceUrl) {
  final uri = Uri.tryParse(resourceUrl);
  if (uri == null) return null;
  if (uri.pathSegments.isEmpty) return null;
  final last = uri.pathSegments.last.trim();
  return last.isEmpty ? null : last;
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
      .map((item) => item?.toString() ?? '')
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
}
