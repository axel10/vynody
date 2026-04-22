import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/artist_summary.dart';
import '../models/music_file.dart';
import '../utils/network_client.dart';
import 'metadata_database.dart';

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
    final artistIds = await _collectArtistIds(groups);

    final cacheKeys = groups.map((group) => group.queryKey).toList(
      growable: false,
    );
    final caches = await _database.getArtistCachesByKeys(cacheKeys);
    final imageCaches = await _database.getArtistImageCachesByIds(artistIds);
    final orderedGroups = _sortGroupsForDisplay(groups, caches);
    _artistLibraryLog(
      'session#$sessionId loaded songs=${songs.length} groups=${groups.length} '
      'caches=${caches.length} imageCaches=${imageCaches.length}',
    );
    yield _buildSummaries(orderedGroups, caches, imageCaches);
    _artistLibraryLog(
      'session#$sessionId initial yield summaries=${orderedGroups.length}',
    );

    final pendingGroups = orderedGroups
        .where((group) => _needsArtistRefresh(group, caches[group.queryKey]))
        .toList(growable: false);
    _artistLibraryLog('session#$sessionId pendingGroups=${pendingGroups.length}');
    if (pendingGroups.isEmpty) {
      _artistLibraryLog('session#$sessionId complete: nothing to refresh');
      return;
    }

    final currentCaches = <String, ArtistCacheRecord>{...caches};
    final currentImageCaches = <String, ArtistImageCacheRecord>{...imageCaches};
    await for (final updated in _refreshMissingArtistCaches(
      groups: orderedGroups,
      pendingGroups: pendingGroups,
      cacheMap: currentCaches,
      imageCacheMap: currentImageCaches,
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
    required Map<String, ArtistImageCacheRecord> imageCacheMap,
    required int sessionId,
  }) async* {
    final pending = List<_ArtistGroup>.from(pendingGroups);
    while (pending.isNotEmpty) {
      final batch = pending.take(20).toList(growable: false);
      pending.removeRange(0, batch.length);
      _artistLibraryLog(
        'session#$sessionId batch size=${batch.length} remaining=${pending.length}',
      );

      final imageRefreshGroups = <_ArtistGroup>[];
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

        if (existing.artistId != null &&
            existing.artistId!.trim().isNotEmpty &&
            !existing.imageFetchCompleted) {
          imageRefreshGroups.add(group);
          continue;
        }

        if (!existing.imageFetchCompleted) {
          searchGroups.add(group);
        }
      }

      if (searchGroups.isNotEmpty) {
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
            yield _buildSummaries(groups, cacheMap, imageCacheMap);
            continue;
          }

          _artistLibraryLog(
            'session#$sessionId search hit key=${group.queryKey} '
            'artistId=${searchHit.id} name=${searchHit.name}',
          );
          cacheMap[group.queryKey] = _loadingCacheRecord(group, searchHit);
          yield _buildSummaries(
            groups,
            cacheMap,
            imageCacheMap,
            loadingKey: group.queryKey,
          );

          final detail = await _fetchArtistDetail(searchHit.id);
          final imageCache = await _ensureArtistImageCache(
            artistId: searchHit.id,
            artistName: searchHit.name.isNotEmpty
                ? searchHit.name
                : group.displayName,
            imageUrl: detail?.imageUrl,
          );
          final record = ArtistCacheRecord(
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
            imageFetchCompleted: true,
            updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
          );
          await _database.insertOrUpdateArtistCache(record);
          cacheMap[group.queryKey] = record;
          if (imageCache != null) {
            imageCacheMap[searchHit.id] = imageCache;
          }
          _artistLibraryLog(
            'session#$sessionId search refresh saved key=${group.queryKey} '
            'artistId=${searchHit.id} imageCached=${imageCache != null}',
          );
          yield _buildSummaries(groups, cacheMap, imageCacheMap);
        }
      }

      for (final group in imageRefreshGroups) {
        final existing = cacheMap[group.queryKey];
        if (existing == null ||
            existing.artistId == null ||
            existing.artistId!.trim().isEmpty) {
          continue;
        }

        final artistId = existing.artistId!.trim();
        _artistLibraryLog(
          'session#$sessionId image refresh key=${group.queryKey} artistId=$artistId',
        );
        cacheMap[group.queryKey] = existing.copyWith(
          imageFetchCompleted: true,
        );
        yield _buildSummaries(
          groups,
          cacheMap,
          imageCacheMap,
          loadingKey: group.queryKey,
        );

        final detail = await _fetchArtistDetail(artistId);
        final imageCache = await _ensureArtistImageCache(
          artistId: artistId,
          artistName: existing.artistName?.trim().isNotEmpty == true
              ? existing.artistName!.trim()
              : group.displayName,
          imageUrl: detail?.imageUrl,
        );

        final record = existing.copyWith(
          imageFileTitle: detail?.imageFileTitle ?? existing.imageFileTitle,
          imageUrl: detail?.imageUrl ?? existing.imageUrl,
          thumbnailUrl: detail?.thumbnailUrl ??
              detail?.imageUrl ??
              existing.thumbnailUrl,
          areaName: detail?.areaName ?? existing.areaName,
          beginDate: detail?.beginDate ?? existing.beginDate,
          endDate: detail?.endDate ?? existing.endDate,
          tagsJson: detail?.tagsJson ?? existing.tagsJson,
          rawDetailJson: detail == null
              ? existing.rawDetailJson
              : jsonEncode(detail.raw),
          imageFetchCompleted: true,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        await _database.insertOrUpdateArtistCache(record);
        cacheMap[group.queryKey] = record;
        if (imageCache != null) {
          imageCacheMap[artistId] = imageCache;
        }
        _artistLibraryLog(
          'session#$sessionId image refresh saved key=${group.queryKey} '
          'artistId=$artistId imageCached=${imageCache != null}',
        );
        yield _buildSummaries(groups, cacheMap, imageCacheMap);
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
    ArtistImageCacheRecord? imageCache, {
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
      imageFileTitle: cache?.imageFileTitle,
      imageUrl: cache?.imageUrl,
      thumbnailUrl: cache?.thumbnailUrl,
      cachedImagePath: imageCache?.imagePath,
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
    // Keep the list order stable while artist metadata and images refresh in the
    // background. Re-sorting on every incremental update makes the grid jump and
    // looks like a loading flash to the user.
    return groups
        .map(
          (group) => _buildSummary(
            group,
            caches[group.queryKey],
            _artistImageCacheForGroup(group, caches, imageCaches),
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
      return _artistDisplayName(left, leftCache)
          .compareTo(_artistDisplayName(right, rightCache));
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
      artistName: searchHit.name.isNotEmpty ? searchHit.name : group.displayName,
      sortName: searchHit.sortName,
      disambiguation: searchHit.disambiguation,
      country: searchHit.country,
      noData: false,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<ArtistImageCacheRecord?> _ensureArtistImageCache({
    required String artistId,
    required String artistName,
    required String? imageUrl,
  }) async {
    final existing = await _database.getArtistImageCache(artistId);
    if (existing != null && await File(existing.imagePath).exists()) {
      _artistLibraryLog(
        'image cache hit artistId=$artistId path=${existing.imagePath}',
      );
      return existing;
    }

    final sourceUrl = imageUrl?.trim();
    if (sourceUrl == null || sourceUrl.isEmpty) {
      _artistLibraryLog('image cache skip artistId=$artistId no sourceUrl');
      return existing;
    }

    _artistLibraryLog('image download start artistId=$artistId url=$sourceUrl');
    final imageBytes = await _downloadArtistImageBytes(sourceUrl);
    if (imageBytes == null || imageBytes.isEmpty) {
      _artistLibraryLog('image download empty artistId=$artistId');
      return existing;
    }

    final processed = _resizeAndEncodeArtistImage(imageBytes);
    if (processed == null) {
      _artistLibraryLog('image process failed artistId=$artistId');
      return existing;
    }

    final outputFile = await _writeArtistImageFile(
      artistId: artistId,
      artistName: artistName,
      bytes: processed.bytes,
    );

    final record = ArtistImageCacheRecord(
      artistId: artistId,
      imagePath: outputFile.path,
      sourceUrl: sourceUrl,
      width: processed.width,
      height: processed.height,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await _database.insertOrUpdateArtistImageCache(record);
    _artistLibraryLog(
      'image cache saved artistId=$artistId path=${outputFile.path} '
      'size=${processed.width}x${processed.height}',
    );
    return record;
  }

  Future<Uint8List?> _downloadArtistImageBytes(String imageUrl) async {
    try {
      final response = await _networkClient.get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data ?? const <int>[];
      if (data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  _ProcessedImage? _resizeAndEncodeArtistImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final maxSide = _artistImageMaxSide;
    final resized = decoded.width >= decoded.height
        ? (decoded.width <= maxSide
              ? decoded
              : img.copyResize(
                  decoded,
                  width: maxSide,
                  interpolation: img.Interpolation.average,
                ))
        : (decoded.height <= maxSide
              ? decoded
              : img.copyResize(
                  decoded,
                  height: maxSide,
                  interpolation: img.Interpolation.average,
                ));

    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 90));
    return _ProcessedImage(
      bytes: encoded,
      width: resized.width,
      height: resized.height,
    );
  }

  Future<File> _writeArtistImageFile({
    required String artistId,
    required String artistName,
    required Uint8List bytes,
  }) async {
    final directory = await _artistImageDirectory();
    final safeName = _sanitizeFileName(artistName);
    final fileName = '${safeName.isEmpty ? artistId : safeName}_$artistId.jpg';
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Directory> _artistImageDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'artist_images'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
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

Future<Set<String>> _collectArtistIds(List<_ArtistGroup> groups) async {
  final database = MetadataDatabase();
  final artistIds = <String>{};
  for (final group in groups) {
    final cache = await database.getArtistCache(group.queryKey);
    final artistId = cache?.artistId?.trim();
    if (artistId != null && artistId.isNotEmpty) {
      artistIds.add(artistId);
    }
  }
  return artistIds;
}

String _artistDisplayName(_ArtistGroup group, ArtistCacheRecord? cache) {
  return _groupDisplayName(group, cache);
}

ArtistImageCacheRecord? _artistImageCacheForGroup(
  _ArtistGroup group,
  Map<String, ArtistCacheRecord> caches,
  Map<String, ArtistImageCacheRecord> imageCaches,
) {
  final artistId = caches[group.queryKey]?.artistId?.trim();
  if (artistId == null || artistId.isEmpty) return null;
  final cache = imageCaches[artistId];
  if (cache == null) return null;
  if (!File(cache.imagePath).existsSync()) return null;
  return cache;
}

String _sanitizeFileName(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
  return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
}

int get _artistImageMaxSide {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS ? 1000 : 600;
}

class _ProcessedImage {
  const _ProcessedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
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
