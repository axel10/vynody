import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:dio/dio.dart';
import 'package:vynody/utils/network_client.dart';
import 'package:vynody/utils/clean_helper.dart';
import 'package:vynody/utils/lyrics_id_utils.dart';
import 'package:vynody/utils/lrc_utils.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_repository.dart';
import 'package:vynody/player/lyrics/sources/embedded_tag_provider.dart';
import 'package:vynody/player/lyrics/sources/lyrics_resolver.dart';
import 'package:vynody/player/lyrics/sources/lyrics_source_provider.dart';
import 'package:vynody/player/lyrics/sources/media_server_lyrics_provider.dart';
import 'package:vynody/player/lyrics/sources/media_server_lyrics_result.dart';
import 'package:vynody/player/lyrics/sources/sidecar_lrc_provider.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/scanner/scanner_path_utils.dart';

part 'lyrics_service.freezed.dart';

@freezed
abstract class LyricsQuery with _$LyricsQuery {
  const LyricsQuery._();

  const factory LyricsQuery({
    required String filePath,
    required String fileName,
    required String title,
    String? artist,
    String? album,
    Duration? duration,
  }) = _LyricsQuery;

  String get cacheKey {
    return ScannerPathUtils.normalizeLyricCacheKey(filePath);
  }

  /// 获取候选缓存键集合（直接返回精准 cacheKey）
  List<String> get candidateCacheKeys => [cacheKey];

  /// 获取基于物理文件路径的前缀
  String get fileBasedCacheKeyPrefix => cacheKey;
}

@freezed
abstract class LyricTrack with _$LyricTrack {
  const LyricTrack._();

  const factory LyricTrack({
    int? id,
    String? lyricsId,
    String? name,
    String? trackName,
    String? artistName,
    String? albumName,
    double? duration,
    @Default(false) bool instrumental,
    String? plainLyrics,
    String? syncedLyrics,
  }) = _LyricTrack;

  factory LyricTrack.fromJson(Map<String, dynamic> json) {
    return LyricTrack(
      id: json['id'] as int?,
      lyricsId: json['lyricsId'] as String?,
      name: json['name'] as String?,
      trackName: json['trackName'] as String?,
      artistName: json['artistName'] as String?,
      albumName: json['albumName'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
      instrumental: json['instrumental'] as bool? ?? false,
      plainLyrics: json['plainLyrics'] as String?,
      syncedLyrics: json['syncedLyrics'] as String?,
    );
  }

  String get displayTitle => (trackName?.trim().isNotEmpty ?? false)
      ? trackName!.trim()
      : (name?.trim().isNotEmpty ?? false ? name!.trim() : '');

  bool get hasLyrics =>
      (plainLyrics?.trim().isNotEmpty ?? false) ||
      (syncedLyrics?.trim().isNotEmpty ?? false);

  bool get hasSyncedLyrics => syncedLyrics?.trim().isNotEmpty ?? false;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lyricsId': lyricsId,
      'name': name,
      'trackName': trackName,
      'artistName': artistName,
      'albumName': albumName,
      'duration': duration,
      'instrumental': instrumental,
      'plainLyrics': plainLyrics,
      'syncedLyrics': syncedLyrics,
    };
  }
}

class ScoredLyricTrack {
  final LyricTrack track;
  final double score;

  const ScoredLyricTrack(this.track, this.score);
}


@freezed
abstract class LyricScoreBreakdown with _$LyricScoreBreakdown {
  const LyricScoreBreakdown._();

  const factory LyricScoreBreakdown({
    required double title,
    required double artist,
    required double album,
    required double duration,
    required double lyricsQuality,
    required double instrumentalPenalty,
  }) = _LyricScoreBreakdown;

  double get total =>
      title + artist + album + duration + lyricsQuality + instrumentalPenalty;
}

@freezed
abstract class LyricSelectionResult with _$LyricSelectionResult {
  const LyricSelectionResult._();

  const factory LyricSelectionResult({
    required LyricTrack track,
    required bool fromGetApi,
    required String source,
    required double score,
    required LyricScoreBreakdown breakdown,
    required int durationDiffSeconds,
    @Default(<LyricLine>[]) List<LyricLine> syncedLines,
    required String lyricsText,
    @Default(Duration.zero) Duration timelineOffset,
  }) = _LyricSelectionResult;

  bool get isSynced => syncedLines.any((line) => line.isTimed);
}

class LyricsService {
  LyricsService({
    NetworkClient? client,
    MetadataDatabase? db,
    LyricsCacheRepository? cacheRepository,
    Future<MediaServerLyricsResult> Function(
      LyricsQuery query, {
      CancelToken? cancelToken,
    })?
    remoteLyricsFetcher,
    Future<String?> Function(String songPath)? remoteSidecarReader,
    Future<String?> Function(String songPath)? remoteEmbeddedLyricsReader,
    List<LyricsSourceProvider>? providers,
  })  : _client = client ?? NetworkClient.instance,
        _cacheRepository = cacheRepository ?? LyricsCacheRepository(db: db) {
    _sidecarProvider = SidecarLrcProvider(
      cacheRepository: _cacheRepository,
      remoteSidecarReader: remoteSidecarReader,
    );
    _embeddedProvider = EmbeddedTagProvider(
      cacheRepository: _cacheRepository,
      remoteLyricsReader: remoteEmbeddedLyricsReader,
    );
    _mediaServerProvider = MediaServerLyricsProvider(
      cacheRepository: _cacheRepository,
      remoteLyricsFetcher: remoteLyricsFetcher,
    );
    _resolver = LyricsResolver(
      cacheRepository: _cacheRepository,
      // 顺序即优先级，与改造前的 fetchBestLyrics 判定次序逐条对应：
      // 服务端歌词 → 旁挂 lrc → 内嵌标签 → 在线兜底（见 _resolveOnline）。
      providers: providers ??
          <LyricsSourceProvider>[
            _mediaServerProvider,
            _sidecarProvider,
            _embeddedProvider,
          ],
    );
  }

  final NetworkClient _client;
  final LyricsCacheRepository _cacheRepository;
  final Map<String, Future<LyricSelectionResult?>> _inFlight = {};

  late final SidecarLrcProvider _sidecarProvider;
  late final EmbeddedTagProvider _embeddedProvider;
  late final MediaServerLyricsProvider _mediaServerProvider;
  late final LyricsResolver _resolver;

  /// 有序来源列表，顺序即优先级。换源与偏好逻辑后续从这里派生。
  List<LyricsSourceProvider> get lyricsSourceProviders => _resolver.providers;

  static const double _acceptThreshold = 65.0;

  /// 仅基于歌曲标题发起 lrclib 在线搜索。
  Future<List<LyricTrack>> searchTracksByTitle({
    required String title,
    CancelToken? cancelToken,
  }) {
    return searchTracksByQuery(title: title, cancelToken: cancelToken);
  }

  /// 基于标题、艺术家和专辑发起 lrclib 在线搜索。
  Future<List<LyricTrack>> searchTracksByQuery({
    required String title,
    String? artist,
    String? album,
    String? q,
    CancelToken? cancelToken,
  }) {
    final normalizedTitle = _cleanField(title);
    if (normalizedTitle == null && q == null) {
      return Future.value(const []);
    }

    return _searchByQuery(
      normalizedTitle ?? '',
      artist: _cleanField(artist),
      album: _cleanField(album),
      q: q,
      cancelToken: cancelToken,
    );
  }

  /// Scores and sorts a list of [LyricTrack] candidates based on query metadata.
  List<ScoredLyricTrack> scoreAndSortTracks({
    required List<LyricTrack> tracks,
    required String queryTitle,
    String? queryArtist,
    String? queryAlbum,
    Duration? queryDuration,
  }) {
    final query = LyricsQuery(
      filePath: '',
      fileName: '',
      title: _cleanField(queryTitle) ?? queryTitle,
      artist: _cleanField(queryArtist),
      album: _cleanField(queryAlbum),
      duration: queryDuration,
    );

    final results = <LyricSelectionResult>[];
    for (final track in tracks) {
      final scored = _scoreCandidate(query, track, fromGetApi: true);
      if (scored != null) {
        results.add(scored);
      } else {
        results.add(LyricSelectionResult(
          track: track,
          fromGetApi: false,
          source: 'lrclib',
          score: 0.0,
          breakdown: const LyricScoreBreakdown(
            title: 0,
            artist: 0,
            album: 0,
            duration: 0,
            lyricsQuality: 0,
            instrumentalPenalty: 0,
          ),
          durationDiffSeconds: 1 << 30,
          lyricsText: '',
        ));
      }
    }

    results.sort(_compareSelectionResults);

    return results.map((r) => ScoredLyricTrack(r.track, r.score)).toList();
  }

  /// 获取当前曲目的所有可用歌词版本记录（去重）。
  /// 优先从数据库缓存读取；若尚无本地外挂或内嵌歌词记录，
  /// 则探测本地 .lrc 文件和音频 TagLib 内嵌歌词，仅在内存中组装候选源供用户选择，
  /// 避免仅打开换源菜单就冲掉当前激活的歌词缓存。
  Future<List<LyricsCacheRecord>> getOrPopulateAvailableLyricRecords(
    LyricsQuery query,
  ) async {
    final records = await _cacheRepository.getLyricsCachesTolerant(
      query,
      ignoreNone: true,
    );

    // 远程不再提前返回：旁挂 lrc 与内嵌标签对 SMB / WebDAV 同样存在，
    // 统一交给 provider 探测（saveToDb: false，只取回候选，不覆盖当前缓存）。

    final hasExternal = records.any(
      (r) => r.source == LyricsCacheSource.external,
    );
    final hasEmbedded = records.any(
      (r) => r.source == LyricsCacheSource.embedded,
    );

    final resultRecords = List<LyricsCacheRecord>.from(records);
    if (!hasExternal) {
      final local = await _tryLoadFromLocalLrcFile(query, saveToDb: false);
      if (local != null) {
        resultRecords.add(LyricsCacheRecord(
          cacheKey: query.cacheKey,
          source: LyricsCacheSource.external,
          isSynced: local.track.hasSyncedLyrics,
          syncedLyrics: local.lyricsText,
          syncedLines: local.syncedLines,
          timelineOffsetMillis: 0,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }
    if (!hasEmbedded) {
      final embedded = await _tryLoadFromMetadata(query, saveToDb: false);
      if (embedded != null) {
        resultRecords.add(LyricsCacheRecord(
          cacheKey: query.cacheKey,
          source: LyricsCacheSource.embedded,
          isSynced: embedded.track.hasSyncedLyrics,
          syncedLyrics: embedded.lyricsText,
          syncedLines: embedded.syncedLines,
          timelineOffsetMillis: 0,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }

    return resultRecords;
  }

  /// 核心歌词获取入口。
  /// 实现了一个分层的查找策略：SQLite 数据库缓存 -> 本地/内嵌/媒体库 -> 在线 API。
  Future<LyricSelectionResult?> fetchBestLyrics({
    required LyricsQuery query,
    bool debugLog = false,
    CancelToken? cancelToken,
  }) async {
    // 对原始查询进行统一清洗，确保“查询键”与“保存键”逻辑完全一致。
    // 解决如“Song [Live]”与“Song”因为括号过滤逻辑不一导致的缓存不命中问题。
    final normalizedQuery = LyricsQuery(
      filePath: query.filePath,
      fileName: query.fileName,
      title:
          _cleanField(query.title) ??
          CleanHelper.deriveCleanTitleFromFileName(query.fileName),
      artist: _cleanField(query.artist),
      album: _cleanField(query.album),
      duration: query.duration,
    );

    final cacheKey = normalizedQuery.cacheKey;

    _logDebug(
      'fetch entry -> key="$cacheKey" title="${normalizedQuery.title}" '
      'artist="${normalizedQuery.artist ?? ''}" album="${normalizedQuery.album ?? ''}" '
      'duration=${normalizedQuery.duration?.inSeconds ?? 'n/a'}s '
      'cancelToken=${cancelToken == null ? 'none' : identityHashCode(cancelToken)}',
    );

    // 缓存命中与来源顺序统一交给 LyricsResolver：
    // 原始键 → 规范化键 → providers（服务端歌词 / 旁挂 lrc / 内嵌标签）→ 在线兜底。
    final result = await _resolver.resolve(
      rawQuery: query,
      normalizedQuery: normalizedQuery,
      cancelToken: cancelToken,
      onlineFallback: () => _resolveOnline(normalizedQuery, cancelToken),
    );

    if (debugLog) {
      debugPrintSelection(normalizedQuery, result);
    }

    return result;
  }

  /// 在线兜底：合并同一首歌的并发请求，再发起 lrclib 检索。
  ///
  /// 仍留在本类而没有拆成 provider，是因为检索与评分逻辑复用 `_client`
  /// 及一组私有方法，拆分统一放到阶段三处理。
  Future<LyricSelectionResult?> _resolveOnline(
    LyricsQuery normalizedQuery,
    CancelToken? cancelToken,
  ) {
    final cacheKey = normalizedQuery.cacheKey;

    // 忽略数据库中的空缓存（none），直接向下走网络流程，避免偶发网络失败导致永久判定为暂无歌词
    final existing = _inFlight[cacheKey];
    if (existing != null) {
      _logDebug('fetch joined in-flight request -> key="$cacheKey"');
      return existing;
    }

    final future =
        _fetchBestLyricsInternal(
          normalizedQuery,
          cancelToken: cancelToken,
        ).whenComplete(() {
          _inFlight.remove(cacheKey);
        });
    _inFlight[cacheKey] = future;

    _logDebug('fetch queued network pipeline -> key="$cacheKey"');
    return future;
  }

  /// 尝试从同目录下和歌曲同名的lrc歌词文件解析
  /// 旁挂同名 lrc。实现已下沉到 [SidecarLrcProvider]，
  /// 这里保留方法签名只为「换源」候选探测复用同一份读取逻辑。
  Future<LyricSelectionResult?> _tryLoadFromLocalLrcFile(
    LyricsQuery query, {
    bool saveToDb = true,
  }) {
    return _sidecarProvider.load(query, saveToDb: saveToDb);
  }

  /// 内嵌标签。实现已下沉到 [EmbeddedTagProvider]，理由同上。
  Future<LyricSelectionResult?> _tryLoadFromMetadata(
    LyricsQuery query, {
    bool saveToDb = true,
  }) {
    return _embeddedProvider.load(query, saveToDb: saveToDb);
  }

  /// 在线搜索逻辑：基于标题+艺术家/专辑的单次全文检索与客户端加权评分。
  ///
  /// 逻辑概述：
  /// - 构建全文检索词 q：优先 "$title $artist"，无艺术家时使用 "$title $album"，均无则使用 "$title"。
  /// - 发起单次全文搜索 (https://lrclib.net/api/search?q=...)。
  /// - 在客户端结合当前播放歌曲的完整元数据（标题、歌手、专辑、精确时长）进行加权综合打分。
  /// - 只有综合评分高于阈值（默认 65 分）的最佳候选才会保存至本地数据库并返回。
  Future<LyricSelectionResult?> _fetchBestLyricsInternal(
    LyricsQuery query, {
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return null;
    }
    _logDebug(
      'pipeline start -> title="${query.title}" artist="${query.artist ?? ''}" '
      'album="${query.album ?? ''}" duration=${query.duration?.inSeconds ?? 'n/a'}s',
    );

    final result = await _fetchBestLyricsWithSearch(
      query,
      cacheQuery: query,
      searchTitle: query.title,
      searchArtist: query.artist,
      searchAlbum: query.album,
      cacheEmptyResult: false,
      cancelToken: cancelToken,
    );
    if (result != null) {
      _logDebug('pipeline success on primary query -> title="${query.title}"');
      return result;
    }

    if (cancelToken?.isCancelled == true) {
      _logDebug('pipeline cancelled -> title="${query.title}"');
      return null;
    }

    _logDebug('pipeline finished without lyrics -> title="${query.title}"');
    return null;
  }

  Future<LyricSelectionResult?> _fetchBestLyricsWithSearch(
    LyricsQuery query, {
    required LyricsQuery cacheQuery,
    required String searchTitle,
    String? searchArtist,
    String? searchAlbum,
    required bool cacheEmptyResult,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return null;
    }
    final trimmedTitle = searchTitle.trim();
    if (trimmedTitle.isEmpty) {
      return null;
    }

    final searchText = _buildSearchText(
      title: trimmedTitle,
      artist: searchArtist,
      album: searchAlbum,
    );

    _logDebug(
      'phase single-search -> query="$searchText" '
      'artist="${searchArtist ?? ''}" album="${searchAlbum ?? ''}" '
      'duration=${query.duration?.inSeconds ?? 'n/a'}s',
    );

    final List<LyricTrack> rawTracks;
    try {
      rawTracks = await searchTracksByQuery(
        title: trimmedTitle,
        q: searchText,
        cancelToken: cancelToken,
      );
    } catch (e) {
      _logDebug('search error for "$searchText": $e');
      return null;
    }

    if (cancelToken?.isCancelled == true) {
      return null;
    }

    // 提取并去重有效歌词候选
    final candidateTracks = <LyricTrack>[];
    final seenKeys = <String>{};

    for (final track in rawTracks) {
      if (!track.hasLyrics) continue;
      final trackId = track.id?.toString() ?? '';
      final trackKey = trackId.isNotEmpty
          ? trackId
          : '${track.displayTitle}|${track.artistName ?? ''}|${track.albumName ?? ''}|${track.lyricsId ?? ''}|${track.duration ?? ''}';
      if (seenKeys.add(trackKey)) {
        candidateTracks.add(track);
      }
    }

    if (candidateTracks.isEmpty) {
      _logDebug('phase search empty -> query="$searchText"');
      return null;
    }

    // 使用完整的 query 元数据（包含原曲歌手、专辑、时长）进行综合加权评分
    final scoredResults = <LyricSelectionResult>[];
    for (final candidate in candidateTracks) {
      if (cancelToken?.isCancelled == true) {
        return null;
      }
      final scored = _scoreCandidate(query, candidate, fromGetApi: false);
      if (scored != null) {
        scoredResults.add(scored);
      }
    }

    if (cancelToken?.isCancelled == true) {
      return null;
    }

    if (scoredResults.isEmpty) {
      _logDebug('phase scoring empty -> query="$searchText"');
      return null;
    }

    scoredResults.sort(_compareSelectionResults);
    final bestCandidate = scoredResults.first;
    _logDebug(
      'phase scored -> query="$searchText" '
      'bestScore=${bestCandidate.score.toStringAsFixed(1)} '
      'bestArtist="${bestCandidate.track.artistName ?? ''}" '
      'durationDiff=${bestCandidate.durationDiffSeconds}s '
      'totalCandidates=${candidateTracks.length}',
    );

    if (bestCandidate.score < _acceptThreshold) {
      _logDebug(
        'phase rejected all -> query="$searchText" '
        'bestScore=${bestCandidate.score.toStringAsFixed(1)} threshold=$_acceptThreshold',
      );
      return null;
    }

    if (cancelToken?.isCancelled == true) {
      return null;
    }

    _logDebug(
      'phase accepted -> query="$searchText" '
      'candidateTitle="${bestCandidate.track.displayTitle}" artist="${bestCandidate.track.artistName}" '
      'score=${bestCandidate.score.toStringAsFixed(1)}',
    );
    await _saveToDatabase(query: cacheQuery, result: bestCandidate);
    return bestCandidate;
  }

  Future<List<LyricTrack>> _searchByQuery(
    String title, {
    String? artist,
    String? album,
    String? q,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> params;
    if (q != null && q.trim().isNotEmpty) {
      params = <String, dynamic>{
        'q': q,
      };
    } else {
      params = <String, dynamic>{
        'track_name': title,
        if (artist != null && artist.trim().isNotEmpty) 'artist_name': artist,
        if (album != null && album.trim().isNotEmpty) 'album_name': album,
        'q': _buildSearchText(
          title: title,
          artist: artist,
          album: album,
        ),
      };
    }

    const maxRetries = 2;
    const retryDelays = [
      Duration(milliseconds: 1000),
      Duration(milliseconds: 1500),
    ];

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (cancelToken?.isCancelled == true) {
        return const [];
      }

      try {
        final response = await _client.get(
          'https://lrclib.net/api/search',
          queryParameters: params,
          cancelToken: cancelToken,
        );
        _logDebug(
          'http search done -> q="${q ?? title}" attempt=$attempt '
          'resultType=${response.data.runtimeType}',
        );

        final data = response.data;
        if (data is List) {
          return data
              .whereType<Map>()
              .map((item) => LyricTrack.fromJson(Map<String, dynamic>.from(item)))
              .where((track) => track.hasLyrics)
              .toList(growable: false);
        }
        return const [];
      } on DioException catch (e) {
        if (CancelToken.isCancel(e) || cancelToken?.isCancelled == true) {
          _logDebug('http search canceled -> track="$title"');
          return const [];
        }

        final statusCode = e.response?.statusCode;
        final isTransientError = statusCode == 429 ||
            (statusCode != null && statusCode >= 500 && statusCode < 600) ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;

        if (isTransientError && attempt < maxRetries) {
          final delay = retryDelays[attempt];
          _logDebug(
            'http search transient error (${statusCode ?? e.type.name}) -> track="$title", '
            'retry attempt ${attempt + 1}/$maxRetries after ${delay.inMilliseconds}ms',
          );
          await Future.delayed(delay);
          if (cancelToken?.isCancelled == true) {
            _logDebug('http search canceled during transient backoff -> track="$title"');
            return const [];
          }
          continue;
        }

        debugPrint('[Lyrics] SEARCH failed for "$title": ${e.message}');
        rethrow;
      } catch (e) {
        debugPrint('[Lyrics] SEARCH error for "$title": $e');
        rethrow;
      }
    }

    return const [];
  }

  Future<void> _saveToDatabase({
    required LyricsQuery query,
    required LyricSelectionResult result,
  }) async {
    try {
      final lyricsText = result.lyricsText.trim();
      final record = LyricsCacheRecord(
        cacheKey: query.cacheKey,
        source: LyricsCacheSource.lrclib,
        isSynced: result.isSynced,
        syncedLyrics: result.track.syncedLyrics ?? lyricsText,
        syncedLines: result.syncedLines,
        timelineOffsetMillis: result.timelineOffset.inMilliseconds,
        updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _cacheRepository.saveLyricsCache(record);
    } catch (e) {
      debugPrint('[Lyrics] Failed to cache lyrics for "${query.title}": $e');
    }
  }

  String _buildSearchText({
    required String title,
    String? artist,
    String? album,
  }) {
    final cleanTitle = title.trim();
    final cleanArtist = artist?.trim();
    if (cleanArtist != null && cleanArtist.isNotEmpty) {
      return '$cleanTitle $cleanArtist'.trim();
    }
    final cleanAlbum = album?.trim();
    if (cleanAlbum != null && cleanAlbum.isNotEmpty) {
      return '$cleanTitle $cleanAlbum'.trim();
    }
    return cleanTitle;
  }

  LyricSelectionResult? _scoreCandidate(
    LyricsQuery query,
    LyricTrack candidate, {
    required bool fromGetApi,
  }) {
    if (!candidate.hasLyrics) {
      return null;
    }

    final queryTitle = _normalizeTitle(query.title);
    final candidateTitle = _normalizeTitle(candidate.displayTitle);
    final queryArtist = _normalizeText(query.artist);
    final candidateArtist = _normalizeText(candidate.artistName);
    final queryAlbum = _normalizeText(query.album);
    final candidateAlbum = _normalizeText(candidate.albumName);
    final durationSeconds = query.duration?.inSeconds;
    final candidateDuration = candidate.duration?.round();
    final durationDiffSeconds =
        durationSeconds == null || candidateDuration == null
        ? (1 << 30)
        : (durationSeconds - candidateDuration).abs();

    final titleScore = _similarity(queryTitle, candidateTitle);
    final artistScore = _similarity(queryArtist, candidateArtist);
    final albumScore = _similarity(queryAlbum, candidateAlbum);
    final durationScore = _durationScore(durationSeconds, candidateDuration);
    final lyricsQualityScore = candidate.hasSyncedLyrics ? 1.0 : 0.65;
    final instrumentalPenalty =
        candidate.instrumental &&
            !candidate.hasSyncedLyrics &&
            candidate.plainLyrics == null
        ? -20.0
        : candidate.instrumental
        ? -8.0
        : 0.0;

    if (!fromGetApi) {
      final hasBothArtists =
          queryArtist.isNotEmpty && candidateArtist.isNotEmpty;
      final artistConflict = hasBothArtists && artistScore < 0.2;
      final obviousMismatch =
          (titleScore < 0.18 && artistScore < 0.18) ||
          artistConflict ||
          (durationSeconds != null &&
              candidateDuration != null &&
              (durationSeconds - candidateDuration).abs() > 8);
      if (obviousMismatch) {
        return null;
      }
    }

    final weighted = <double>[];
    final weights = <double>[];

    void addWeighted(double weight, double? score) {
      if (score == null) return;
      weights.add(weight);
      weighted.add(weight * score);
    }

    addWeighted(35.0, queryTitle.isEmpty ? null : titleScore);
    addWeighted(35.0, durationSeconds == null ? null : durationScore);
    addWeighted(15.0, queryArtist.isEmpty ? null : artistScore);
    addWeighted(10.0, queryAlbum.isEmpty ? null : albumScore);
    addWeighted(5.0, lyricsQualityScore);

    final totalWeight = weights.fold<double>(0, (sum, value) => sum + value);
    if (totalWeight <= 0) {
      return null;
    }

    var total = weighted.fold<double>(0, (sum, value) => sum + value);
    total = (total / totalWeight) * 100.0;
    total += instrumentalPenalty;
    total = total.clamp(0.0, 100.0);

    final syncedLines = _parseSyncedLyrics(candidate.syncedLyrics);
    final lyricsText = candidate.hasSyncedLyrics
        ? candidate.syncedLyrics!.trim()
        : candidate.plainLyrics!.trim();
    final lyricsId = LyricsIdUtils.fromLyricsText(lyricsText);

    return LyricSelectionResult(
      track: candidate.copyWith(lyricsId: lyricsId),
      fromGetApi: fromGetApi,
      source: 'lrclib',
      score: total,
      breakdown: LyricScoreBreakdown(
        title: titleScore * 35.0,
        artist: artistScore * 15.0,
        album: albumScore * 10.0,
        duration: durationScore * 35.0,
        lyricsQuality: lyricsQualityScore * 5.0,
        instrumentalPenalty: instrumentalPenalty,
      ),
      durationDiffSeconds: durationDiffSeconds,
      syncedLines: syncedLines,
      lyricsText: lyricsText,
      timelineOffset: Duration.zero,
    );
  }

  int _compareSelectionResults(LyricSelectionResult a, LyricSelectionResult b) {
    final scoreDiff = b.score.compareTo(a.score);
    if (scoreDiff != 0) return scoreDiff;

    if (a.isSynced != b.isSynced) {
      return b.isSynced ? 1 : -1;
    }

    final durationDiff = a.durationDiffSeconds.compareTo(b.durationDiffSeconds);
    if (durationDiff != 0) return durationDiff;

    final titleScoreDiff = b.breakdown.title.compareTo(a.breakdown.title);
    if (titleScoreDiff != 0) return titleScoreDiff;

    final artistScoreDiff = b.breakdown.artist.compareTo(a.breakdown.artist);
    if (artistScoreDiff != 0) return artistScoreDiff;

    return 0;
  }

  double _durationScore(int? querySeconds, int? candidateSeconds) {
    if (querySeconds == null || querySeconds <= 0) {
      return 0.75;
    }
    if (candidateSeconds == null || candidateSeconds <= 0) {
      return 0.55;
    }

    final diff = (querySeconds - candidateSeconds).abs();
    if (diff <= 2) return 1.0;
    if (diff <= 5) return 0.8;
    if (diff <= 8) return 0.45;
    return 0.0;
  }

  double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return 0.0;
    }
    if (a == b) {
      return 1.0;
    }

    final levenshtein = _levenshteinSimilarity(a, b);
    final token = _tokenSimilarity(a, b);
    final prefixBonus = (a.startsWith(b) || b.startsWith(a)) ? 0.05 : 0.0;
    return (levenshtein * 0.65 + token * 0.35 + prefixBonus).clamp(0.0, 1.0);
  }

  double _levenshteinSimilarity(String a, String b) {
    final maxLen = math.max(a.length, b.length);
    if (maxLen == 0) return 1.0;
    final distance = _levenshteinDistance(a, b);
    return (1.0 - (distance / maxLen)).clamp(0.0, 1.0);
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = math.min(
          math.min(curr[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }

    return prev[b.length];
  }

  double _tokenSimilarity(String a, String b) {
    final tokensA = a.split(' ').where((token) => token.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((token) => token.isNotEmpty).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) {
      return 0.0;
    }
    final intersection = tokensA.intersection(tokensB).length.toDouble();
    final union = tokensA.union(tokensB).length.toDouble();
    if (union == 0) {
      return 0.0;
    }
    return (intersection / union).clamp(0.0, 1.0);
  }

  List<LyricLine> _parseSyncedLyrics(String? syncedLyrics) {
    return LrcUtils.parseTimedLyrics(syncedLyrics);
  }

  void debugPrintSelection(
    LyricsQuery query,
    LyricSelectionResult? result, {
    String? source,
  }) {
    final buffer = StringBuffer()
      ..writeln('[Lyrics] ${source ?? 'fetch'} ${query.fileName}')
      ..writeln(
        '[Lyrics] query title="${query.title}" artist="${query.artist ?? ''}" album="${query.album ?? ''}" duration="${query.duration?.inSeconds ?? 'n/a'}s"',
      );

    if (result == null) {
      buffer.writeln('[Lyrics] no reliable lyrics found');
      debugPrint(buffer.toString());
      return;
    }

    buffer.writeln(
      '[Lyrics] selected id=${result.track.id ?? 'n/a'} score=${result.score.toStringAsFixed(1)} source=${result.source} synced=${result.isSynced} instrumental=${result.track.instrumental}',
    );
    buffer.writeln(
      '[Lyrics] breakdown title=${result.breakdown.title.toStringAsFixed(1)} artist=${result.breakdown.artist.toStringAsFixed(1)} album=${result.breakdown.album.toStringAsFixed(1)} duration=${result.breakdown.duration.toStringAsFixed(1)} lyrics=${result.breakdown.lyricsQuality.toStringAsFixed(1)} penalty=${result.breakdown.instrumentalPenalty.toStringAsFixed(1)}',
    );

    if (result.isSynced) {
      buffer.writeln('[Lyrics] synced lyrics:');
      for (final line in result.syncedLines) {
        buffer.writeln('[${LrcUtils.formatLrcTimestamp(line.timestamp)}] ${line.text}');
      }
    } else {
      buffer.writeln('[Lyrics] plain lyrics:');
      buffer.writeln(result.lyricsText);
    }

    // debugPrint(buffer.toString());
  }

  void _logDebug(String message) {
    if (kReleaseMode) return;
    debugPrint('[Lyrics] $message');
  }
}

String? _cleanField(String? value) {
  var text = value?.trim();
  if (text == null || text.isEmpty) return null;

  text = CleanHelper.removeBrackets(text);
  text = CleanHelper.stripSequenceNumber(text); // 增加：对不完美的 Tag 也尝试进行序号擦除
  if (text.isEmpty) return null;

  final lower = text.toLowerCase();
  if (lower == 'unknown' ||
      lower == 'unknown artist' ||
      lower == 'unknown album') {
    return null;
  }
  return text;
}

String _normalizeText(String? value) {
  if (value == null) return '';
  var text = value.toLowerCase().trim();
  if (text.isEmpty) return '';

  text = text.replaceAll(RegExp(r'[\u2013\u2014]'), '-');
  text = text.replaceAll(RegExp(r'[\(\[\{（【][^\)\]\}）】]*[\)\]\}）】]'), ' ');
  text = text.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ');
  text = text.replaceAll(
    RegExp(
      r'\b(live|remaster(?:ed)?|radio edit|album version|instrumental|karaoke|mono|stereo|official audio|edit)\b',
    ),
    ' ',
  );
  text = text.replaceAll(RegExp(r'[\p{P}\p{S}]+', unicode: true), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text;
}

String _normalizeTitle(String? value) {
  final text = _normalizeText(value);
  if (text.isEmpty) return text;

  final tokens = text.split(' ').where((token) => token.isNotEmpty).toList();
  if (tokens.isEmpty) return text;

  final filteredTokens = tokens.where((token) {
    return !<String>{
      'live',
      'remaster',
      'remastered',
      'radio',
      'edit',
      'version',
      'album',
      'instrumental',
      'karaoke',
      'mono',
      'stereo',
    }.contains(token);
  }).toList();

  return filteredTokens.isEmpty ? text : filteredTokens.join(' ');
}
