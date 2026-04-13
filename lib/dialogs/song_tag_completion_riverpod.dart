import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../player/acoustid_service.dart';
import '../player/metadata_helper.dart';
import '../player/metadata_database.dart';
import '../player/musicbrainz_tag_completion_service.dart';

final songTagCompletionControllerProvider = ChangeNotifierProvider.autoDispose
    .family<SongTagCompletionController, String>((ref, songPath) {
      return SongTagCompletionController(songPath: songPath);
    });

class SongTagCompletionController extends ChangeNotifier {
  SongTagCompletionController({required this.songPath});

  final String songPath;
  final MusicBrainzTagCompletionService service =
      MusicBrainzTagCompletionService();

  List<MusicBrainzTrackMatch> musicBrainzMatches = const [];
  List<AcoustIDResult> acoustidResults = const [];
  bool isMusicBrainzLoading = true;
  bool isAcoustIDLoading = true;
  bool isApplying = false;
  String? musicBrainzErrorMessage;
  String? errorMessage;

  int _musicBrainzQueryRevision = 0;
  bool _disposed = false;

  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> loadMusicBrainzMatches({
    required String? title,
    required String? artist,
    required String? album,
    required int? durationMillis,
    required bool enableTitleQuery,
    required bool enableArtistQuery,
    required bool enableAlbumQuery,
    required bool enableDurationQuery,
  }) async {
    if (_disposed) return;

    final revision = ++_musicBrainzQueryRevision;
    isMusicBrainzLoading = true;
    musicBrainzErrorMessage = null;
    errorMessage = null;
    _emit();

    try {
      final results = await service.searchMatches(
        songPath: songPath,
        title: title,
        artist: artist,
        album: album,
        durationMillis: durationMillis,
        enableTitleQuery: enableTitleQuery,
        enableArtistQuery: enableArtistQuery,
        enableAlbumQuery: enableAlbumQuery,
        enableDurationQuery: enableDurationQuery,
      );

      if (_disposed || revision != _musicBrainzQueryRevision) return;
      musicBrainzMatches = results;
      isMusicBrainzLoading = false;
      musicBrainzErrorMessage = null;
      _emit();
    } catch (e) {
      if (_disposed || revision != _musicBrainzQueryRevision) return;
      musicBrainzErrorMessage = 'MusicBrainz 查询失败：$e';
      isMusicBrainzLoading = false;
      _emit();
    }
  }

  Future<void> loadAcoustIDResult({required int? durationMillis}) async {
    if (_disposed) return;

    isAcoustIDLoading = true;
    _emit();

    try {
      final apiKeyFile = File('api_keys.json');
      String apiKey;
      if (await apiKeyFile.exists()) {
        final content = await apiKeyFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        apiKey = json['AcoustID_API_KEY'] as String? ?? '';
      } else {
        debugPrint('AcoustID: api_keys.json not found');
        if (_disposed) return;
        isAcoustIDLoading = false;
        _emit();
        return;
      }

      if (apiKey.isEmpty) {
        debugPrint('AcoustID: API key is empty');
        if (_disposed) return;
        isAcoustIDLoading = false;
        _emit();
        return;
      }

      final acoustidService = AcoustIDService(apiKey: apiKey);
      final durationSec = (durationMillis ?? 0) ~/ 1000;
      final results = await acoustidService.lookupByFingerprint(
        filePath: songPath,
        durationSeconds: durationSec,
      );

      if (_disposed) return;
      acoustidResults = results;
      isAcoustIDLoading = false;
      _emit();
    } catch (e) {
      debugPrint('AcoustID: Failed to load result: $e');
      if (_disposed) return;
      isAcoustIDLoading = false;
      _emit();
    }
  }

  Future<MusicBrainzTagSelectionResult?> applyAcoustIDSelection({
    required AcoustIDResult trackResult,
    required AcoustIDRecording recording,
    required String albumTitle,
    required String sourceLabel,
    required String fallbackTitle,
    required int? fallbackDurationMillis,
    String? releaseId,
    String? releaseGroupId,
    String? coverLargeUrl,
    String? coverThumbnailUrl,
    Map<String, dynamic>? raw,
    String? country,
    String? releaseDate,
    SongMetadata? existingMetadata,
  }) async {
    if (_disposed || isApplying) return null;

    isApplying = true;
    errorMessage = null;
    _emit();

    try {
      final acoustidService = AcoustIDService(apiKey: '');
      final coverArtBytes = await acoustidService.downloadCoverBytes(
        candidateUrls: [coverLargeUrl, coverThumbnailUrl],
      );
      final durationMillis = recording.durationMillis ?? fallbackDurationMillis;
      final saved = await MetadataHelper.saveSelectedSongMetadata(
        filePath: songPath,
        title: recording.title.isNotEmpty ? recording.title : fallbackTitle,
        artist: recording.artist.isNotEmpty
            ? recording.artist
            : 'Unknown Artist',
        album: albumTitle,
        duration: durationMillis,
        artworkBytes: coverArtBytes,
        existingMetadata: existingMetadata,
      );

      if (saved == null) {
        throw StateError('写入标签和文件同步失败');
      }

      final updated = saved.$1;
      final resolvedCover = coverLargeUrl != null || coverThumbnailUrl != null
          ? ResolvedCover(
              endpoint: releaseId != null ? 'release' : 'release-group',
              id: releaseId ?? releaseGroupId ?? '',
              largeUrl: coverLargeUrl,
              thumbnailUrl: coverThumbnailUrl ?? coverLargeUrl,
            )
          : null;

      final result = MusicBrainzTagSelectionResult(
        metadata: updated,
        artworkBytes: coverArtBytes,
        match: _buildAcoustIDSelectionMatch(
          trackResult: trackResult,
          recording: recording,
          albumTitle: albumTitle,
          releaseId: releaseId,
          releaseGroupId: releaseGroupId,
          releaseDate: releaseDate,
          country: country,
          raw: raw,
          resolvedCover: resolvedCover,
          sourceLabel: sourceLabel,
          fallbackTitle: fallbackTitle,
          fallbackDurationMillis: fallbackDurationMillis,
        ),
      );

      if (_disposed) return null;
      isApplying = false;
      _emit();
      return result;
    } catch (e) {
      if (_disposed) return null;
      isApplying = false;
      errorMessage = '保存失败：$e';
      _emit();
      return null;
    }
  }

  Future<MusicBrainzTagSelectionResult?> applyMusicBrainzRelease({
    required MusicBrainzTrackMatch match,
    required MusicBrainzReleaseMatch release,
    required int? fallbackDurationMillis,
    SongMetadata? existingMetadata,
  }) async {
    if (_disposed || isApplying) return null;

    isApplying = true;
    errorMessage = null;
    _emit();

    try {
      final result = await service.applySelection(
        songPath: songPath,
        match: match,
        selectedRelease: release,
        fallbackDurationMillis: fallbackDurationMillis,
        existingMetadata: existingMetadata,
      );

      if (_disposed) return null;
      isApplying = false;
      _emit();
      return result;
    } catch (e) {
      if (_disposed) return null;
      isApplying = false;
      errorMessage = '保存失败：$e';
      _emit();
      return null;
    }
  }
}

MusicBrainzTrackMatch _buildAcoustIDSelectionMatch({
  required AcoustIDResult trackResult,
  required AcoustIDRecording recording,
  required String albumTitle,
  required String sourceLabel,
  required String fallbackTitle,
  required int? fallbackDurationMillis,
  String? releaseId,
  String? releaseGroupId,
  String? releaseDate,
  String? country,
  Map<String, dynamic>? raw,
  ResolvedCover? resolvedCover,
}) {
  return MusicBrainzTrackMatch(
    recordingId: recording.id.isNotEmpty ? recording.id : trackResult.id,
    title: recording.title.isNotEmpty ? recording.title : fallbackTitle,
    artist: recording.artist.isNotEmpty ? recording.artist : 'Unknown Artist',
    album: albumTitle,
    releaseId: releaseId,
    releaseGroupId: releaseGroupId,
    releaseDate: releaseDate,
    country: country,
    durationMillis: recording.durationMillis ?? fallbackDurationMillis,
    trackNumber: null,
    score: (trackResult.score * 100).round().clamp(0, 100),
    disambiguation: sourceLabel,
    releases: const [],
    raw: raw ?? {'track': trackResult.raw, 'recording': recording.raw},
    resolvedCover: resolvedCover,
  );
}
