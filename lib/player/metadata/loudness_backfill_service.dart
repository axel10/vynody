import 'dart:async';
import 'dart:io';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:vynody/player/audio/loudness_normalization.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/platform/apple_file_access.dart';

@immutable
class LoudnessPriorityTarget {
  const LoudnessPriorityTarget({
    required this.path,
    this.album,
    this.albumArtist,
    this.artist,
  });

  final String path;
  final String? album;
  final String? albumArtist;
  final String? artist;
}

@immutable
class LoudnessAnalysisGroup {
  const LoudnessAnalysisGroup({
    required this.albumKey,
    required this.songs,
  });

  final String? albumKey;
  final List<SongMetadata> songs;
}

/// Resolves the adaptive worker thread count for multithreaded loudness
/// analysis based on CPU core count and platform class.
int resolveLoudnessMultithreadedCount({
  int? processorCount,
  bool? isMobile,
}) {
  final cores = processorCount ?? Platform.numberOfProcessors;
  if (cores <= 1) return 1;
  final mobile = isMobile ?? (Platform.isAndroid || Platform.isIOS);
  if (mobile) {
    return (cores ~/ 2).clamp(2, 4);
  }
  return (cores * 0.75).floor().clamp(2, 8);
}

/// Builds a normalized album-group key, or `null` for empty/unknown albums.
String? buildLoudnessAlbumGroupKey({
  required String? album,
  String? albumArtist,
  String? artist,
}) {
  final trimmedAlbum = album?.trim() ?? '';
  final lowerAlbum = trimmedAlbum.toLowerCase();
  if (trimmedAlbum.isEmpty ||
      lowerAlbum == 'unknown album' ||
      lowerAlbum == 'unknown') {
    return null;
  }
  final effectiveArtist = (albumArtist?.trim().isNotEmpty == true
          ? albumArtist!.trim()
          : (artist?.trim() ?? ''))
      .toLowerCase();
  return '$effectiveArtist\u0000$lowerAlbum';
}

/// Groups pending songs by album (or as standalone single-track groups when
/// album metadata is missing/unknown).
List<LoudnessAnalysisGroup> groupSongsForLoudnessAnalysis(
  List<SongMetadata> songs,
) {
  final grouped = <String, List<SongMetadata>>{};
  final singles = <LoudnessAnalysisGroup>[];

  for (final song in songs) {
    final key = buildLoudnessAlbumGroupKey(
      album: song.album,
      albumArtist: song.albumArtist,
      artist: song.artist,
    );
    if (key == null) {
      singles.add(LoudnessAnalysisGroup(albumKey: null, songs: [song]));
      continue;
    }
    grouped.putIfAbsent(key, () => []).add(song);
  }

  return [
    for (final entry in grouped.entries)
      LoudnessAnalysisGroup(albumKey: entry.key, songs: entry.value),
    ...singles,
  ];
}

/// Selects the next group index to analyze, prioritizing groups matching
/// [priorityTargets] in order (by album key first, then by track path).
int selectNextLoudnessGroupIndex(
  List<LoudnessAnalysisGroup> remainingGroups,
  List<LoudnessPriorityTarget> priorityTargets,
) {
  if (remainingGroups.isEmpty) return -1;
  if (priorityTargets.isEmpty) return 0;

  final albumKeyToIndex = <String, int>{};
  final pathToIndex = <String, int>{};
  for (var i = 0; i < remainingGroups.length; i++) {
    final group = remainingGroups[i];
    final albumKey = group.albumKey;
    if (albumKey != null) {
      albumKeyToIndex.putIfAbsent(albumKey, () => i);
    }
    for (final song in group.songs) {
      pathToIndex.putIfAbsent(song.path, () => i);
    }
  }

  for (final target in priorityTargets) {
    final targetAlbumKey = buildLoudnessAlbumGroupKey(
      album: target.album,
      albumArtist: target.albumArtist,
      artist: target.artist,
    );
    if (targetAlbumKey != null) {
      final albumMatch = albumKeyToIndex[targetAlbumKey];
      if (albumMatch != null) return albumMatch;
    }
    if (target.path.isNotEmpty) {
      final pathMatch = pathToIndex[target.path];
      if (pathMatch != null) return pathMatch;
    }
  }
  return 0;
}

@immutable
class LoudnessBackfillState {
  const LoudnessBackfillState({
    this.isRunning = false,
    this.isStopping = false,
    this.totalPending = 0,
    this.completedInRun = 0,
    this.failedInRun = 0,
    this.libraryTotal = 0,
    this.libraryAnalyzed = 0,
    this.libraryFailed = 0,
    this.currentFileName,
    this.lastError,
  });

  final bool isRunning;
  final bool isStopping;
  final int totalPending;
  final int completedInRun;
  final int failedInRun;
  final int libraryTotal;
  final int libraryAnalyzed;
  final int libraryFailed;
  final String? currentFileName;
  final String? lastError;

  double get libraryProgress =>
      libraryTotal > 0 ? (libraryAnalyzed / libraryTotal).clamp(0.0, 1.0) : 0.0;

  LoudnessBackfillState copyWith({
    bool? isRunning,
    bool? isStopping,
    int? totalPending,
    int? completedInRun,
    int? failedInRun,
    int? libraryTotal,
    int? libraryAnalyzed,
    int? libraryFailed,
    String? currentFileName,
    bool clearCurrentFileName = false,
    String? lastError,
    bool clearLastError = false,
  }) {
    return LoudnessBackfillState(
      isRunning: isRunning ?? this.isRunning,
      isStopping: isStopping ?? this.isStopping,
      totalPending: totalPending ?? this.totalPending,
      completedInRun: completedInRun ?? this.completedInRun,
      failedInRun: failedInRun ?? this.failedInRun,
      libraryTotal: libraryTotal ?? this.libraryTotal,
      libraryAnalyzed: libraryAnalyzed ?? this.libraryAnalyzed,
      libraryFailed: libraryFailed ?? this.libraryFailed,
      currentFileName: clearCurrentFileName
          ? null
          : (currentFileName ?? this.currentFileName),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

class LoudnessBackfillNotifier extends Notifier<LoudnessBackfillState> {
  static const int _maxAlbumGroupSize = 40;
  static int get multithreadedAnalysisThreads =>
      resolveLoudnessMultithreadedCount();
  bool _cancelRequested = false;
  Future<void>? _activeRun;
  void Function(String path)? _onSongUpdated;

  @override
  LoudnessBackfillState build() {
    Future.microtask(refreshStats);
    return const LoudnessBackfillState();
  }

  void setOnSongUpdatedCallback(void Function(String path)? callback) {
    _onSongUpdated = callback;
  }

  Future<void> refreshStats() async {
    try {
      final stats = await MetadataDatabase().getLocalLoudnessStats();
      state = state.copyWith(
        libraryTotal: stats.total,
        libraryAnalyzed: stats.analyzed,
        libraryFailed: stats.failed,
      );
    } catch (e) {
      debugPrint('[LoudnessBackfill] refreshStats failed: $e');
    }
  }

  void requestStop() {
    if (!state.isRunning) return;
    _cancelRequested = true;
    state = state.copyWith(isStopping: true);
  }

  /// Stops any active backfill run and starts a new one with the updated options.
  Future<void> restartBackfill({
    bool Function()? isPlaying,
    List<LoudnessPriorityTarget> Function()? priorityTargets,
    bool includeFailed = false,
    int threads = 1,
    bool Function()? shouldContinue,
  }) async {
    if (!state.isRunning) return;
    requestStop();
    await _activeRun;
    if (shouldContinue?.call() == false) return;
    await startBackfill(
      isPlaying: isPlaying,
      priorityTargets: priorityTargets,
      includeFailed: includeFailed,
      threads: threads,
    );
  }

  Future<void> startBackfill({
    bool Function()? isPlaying,
    List<LoudnessPriorityTarget> Function()? priorityTargets,
    bool includeFailed = false,
    int threads = 1,
  }) async {
    if (state.isRunning) {
      if (!state.isStopping) return;
      _cancelRequested = false;
      state = state.copyWith(isStopping: false);
      await _activeRun;
      if (_cancelRequested || state.isRunning) return;
    }
    _cancelRequested = false;

    final run = _runBackfill(
      isPlaying: isPlaying,
      priorityTargets: priorityTargets,
      includeFailed: includeFailed,
      threads: threads,
    );
    _activeRun = run;
    try {
      await run;
    } finally {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    }
  }

  Future<void> _runBackfill({
    bool Function()? isPlaying,
    List<LoudnessPriorityTarget> Function()? priorityTargets,
    bool includeFailed = false,
    int threads = 1,
  }) async {
    final effectiveThreads = threads < 1 ? 1 : threads;
    state = state.copyWith(
      isRunning: true,
      isStopping: false,
      completedInRun: 0,
      failedInRun: 0,
      clearCurrentFileName: true,
      clearLastError: true,
    );

    try {
      await AudioCoreController.ensureRustLibInitialized();
      final db = MetadataDatabase();
      final pending = await db.getLocalSongsNeedingLoudnessAnalysis(
        includeFailed: includeFailed,
      );
      final stats = await db.getLocalLoudnessStats();

      state = state.copyWith(
        totalPending: pending.length,
        libraryTotal: stats.total,
        libraryAnalyzed: stats.analyzed,
        libraryFailed: stats.failed,
      );

      if (pending.isEmpty) {
        return;
      }

      debugPrint(
        '[LoudnessBackfill] started: pending=${pending.length}, threads=$effectiveThreads',
      );
      final remainingGroups = groupSongsForLoudnessAnalysis(pending);

      while (remainingGroups.isNotEmpty) {
        if (_cancelRequested) break;

        final nextIndex = selectNextLoudnessGroupIndex(
          remainingGroups,
          priorityTargets?.call() ?? const [],
        );
        if (nextIndex < 0) break;
        final group = remainingGroups.removeAt(nextIndex).songs;

        if (group.length == 1 || group.length > _maxAlbumGroupSize) {
          if (effectiveThreads <= 1) {
            for (final song in group) {
              if (_cancelRequested) break;
              await _analyzeSingleSong(song);
              if (isPlaying?.call() == true) {
                await Future<void>.delayed(const Duration(milliseconds: 60));
              }
            }
          } else {
            final batch = <SongMetadata>[...group];
            if (group.length == 1) {
              while (batch.length < effectiveThreads) {
                final singleIdx = remainingGroups.indexWhere(
                  (g) => g.songs.length == 1,
                );
                if (singleIdx < 0) break;
                batch.add(remainingGroups.removeAt(singleIdx).songs.first);
              }
            }
            await _analyzeSongsConcurrently(
              batch,
              concurrency: effectiveThreads,
              isPlaying: isPlaying,
            );
          }
        } else {
          await _analyzeAlbumGroup(group, threads: effectiveThreads);
          if (isPlaying?.call() == true) {
            await Future<void>.delayed(const Duration(milliseconds: 60));
          }
        }
      }
    } catch (e) {
      state = state.copyWith(lastError: e.toString());
      debugPrint('[LoudnessBackfill] backfill aborted: $e');
    } finally {
      final stats = await MetadataDatabase().getLocalLoudnessStats();
      state = state.copyWith(
        isRunning: false,
        isStopping: false,
        libraryTotal: stats.total,
        libraryAnalyzed: stats.analyzed,
        libraryFailed: stats.failed,
        clearCurrentFileName: true,
      );
    }
  }

  Future<void> _markSongFailed(SongMetadata song, String errorMessage) async {
    try {
      await MetadataDatabase().updateSongLoudness(
        path: song.path,
        loudnessSource: LoudnessSource.failed,
      );
    } catch (e) {
      debugPrint('[LoudnessBackfill] mark failed status error (${song.path}): $e');
    }
    final wasAlreadyFailed = song.loudnessSource == LoudnessSource.failed;
    state = state.copyWith(
      failedInRun: state.failedInRun + 1,
      libraryFailed: wasAlreadyFailed
          ? state.libraryFailed
          : state.libraryFailed + 1,
      lastError: errorMessage,
    );
  }

  Future<void> _analyzeSingleSong(SongMetadata song) async {
    state = state.copyWith(currentFileName: p.basename(song.path));
    try {
      final res = await _withReadablePath(
        song.path,
        (resolvedPath) => analyzeTrackLoudness(path: resolvedPath),
      );
      if (res == null) {
        await _markSongFailed(
          song,
          'File not accessible: ${p.basename(song.path)}',
        );
        return;
      }
      await MetadataDatabase().updateSongLoudness(
        path: song.path,
        trackLufs: res.loudnessLufs,
        trackPeak: res.truePeak,
        loudnessSource: LoudnessSource.analyzedEbuR128,
      );
      _onSongUpdated?.call(song.path);
      final wasFailed = song.loudnessSource == LoudnessSource.failed;
      state = state.copyWith(
        completedInRun: state.completedInRun + 1,
        libraryAnalyzed: state.libraryAnalyzed + 1,
        libraryFailed: wasFailed && state.libraryFailed > 0
            ? state.libraryFailed - 1
            : state.libraryFailed,
      );
    } catch (e) {
      debugPrint('[LoudnessBackfill] analyzeTrackLoudness failed (${song.path}): $e');
      await _markSongFailed(song, '${p.basename(song.path)}: $e');
    }
  }

  Future<void> _analyzeSongsConcurrently(
    List<SongMetadata> songs, {
    required int concurrency,
    bool Function()? isPlaying,
  }) async {
    if (songs.isEmpty) return;
    final workerCount = concurrency.clamp(1, songs.length);
    var nextIndex = 0;

    Future<void> runWorker() async {
      while (!_cancelRequested && nextIndex < songs.length) {
        final song = songs[nextIndex++];
        await _analyzeSingleSong(song);
        if (isPlaying?.call() == true) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < workerCount; i++) runWorker(),
    ]);
  }

  Future<void> _analyzeAlbumGroup(
    List<SongMetadata> group, {
    int threads = 1,
  }) async {
    final first = group.first;
    state = state.copyWith(
      currentFileName: '${first.album} (${group.length})',
    );

    final accessibleSongs = <SongMetadata>[];
    for (final song in group) {
      if (_cancelRequested) return;
      final exists = await _withReadablePath(
        song.path,
        (resolvedPath) async => File(resolvedPath).exists(),
      );
      if (exists == true) {
        accessibleSongs.add(song);
      } else {
        await _markSongFailed(
          song,
          'File not accessible: ${p.basename(song.path)}',
        );
      }
    }

    if (accessibleSongs.isEmpty) return;
    if (accessibleSongs.length == 1) {
      await _analyzeSingleSong(accessibleSongs.first);
      return;
    }

    try {
      final albumResult = await _withReadablePaths(
        accessibleSongs.map((s) => s.path).toList(growable: false),
        (resolvedPaths) => analyzeAlbumLoudness(
          paths: resolvedPaths,
          threads: threads,
        ),
      );
      if (albumResult == null ||
          albumResult.tracks.length != accessibleSongs.length) {
        for (final song in accessibleSongs) {
          if (_cancelRequested) break;
          await _analyzeSingleSong(song);
        }
        return;
      }
      final db = MetadataDatabase();
      for (var i = 0; i < accessibleSongs.length; i++) {
        final song = accessibleSongs[i];
        final track = albumResult.tracks[i];
        await db.updateSongLoudness(
          path: song.path,
          trackLufs: track.loudnessLufs,
          trackPeak: track.truePeak,
          albumLufs: albumResult.albumLufs,
          albumPeak: albumResult.albumTruePeak,
          loudnessSource: LoudnessSource.analyzedEbuR128,
        );
        _onSongUpdated?.call(song.path);
      }
      state = state.copyWith(
        completedInRun: state.completedInRun + accessibleSongs.length,
        libraryAnalyzed: state.libraryAnalyzed + accessibleSongs.length,
      );
    } catch (e) {
      debugPrint('[LoudnessBackfill] analyzeAlbumLoudness fallback to single: $e');
      for (final song in accessibleSongs) {
        if (_cancelRequested) break;
        await _analyzeSingleSong(song);
      }
    }
  }

  Future<T?> _withReadablePath<T>(
    String rawPath,
    Future<T> Function(String resolvedPath) action,
  ) async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return await AppleFileAccess.withRead(rawPath, () async {
          if (!await File(rawPath).exists()) return null;
          return await action(rawPath);
        });
      }
      if (!await File(rawPath).exists()) return null;
      return await action(rawPath);
    } catch (_) {
      return null;
    }
  }

  Future<T?> _withReadablePaths<T>(
    List<String> rawPaths,
    Future<T> Function(List<String> resolvedPaths) action,
  ) async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return await AppleFileAccess.withReadMany(rawPaths, () async {
          return await action(rawPaths);
        });
      }
      return await action(rawPaths);
    } catch (_) {
      return null;
    }
  }
}

final loudnessBackfillProvider =
    NotifierProvider<LoudnessBackfillNotifier, LoudnessBackfillState>(
      LoudnessBackfillNotifier.new,
    );
