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
class LoudnessBackfillState {
  const LoudnessBackfillState({
    this.isRunning = false,
    this.isStopping = false,
    this.totalPending = 0,
    this.completedInRun = 0,
    this.failedInRun = 0,
    this.libraryTotal = 0,
    this.libraryAnalyzed = 0,
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
      currentFileName: clearCurrentFileName
          ? null
          : (currentFileName ?? this.currentFileName),
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }
}

class LoudnessBackfillNotifier extends Notifier<LoudnessBackfillState> {
  static const int _maxAlbumGroupSize = 40;
  bool _cancelRequested = false;
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

  Future<void> startBackfill({bool Function()? isPlaying}) async {
    if (state.isRunning) return;
    _cancelRequested = false;

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
      final pending = await db.getLocalSongsNeedingLoudnessAnalysis();
      final stats = await db.getLocalLoudnessStats();

      state = state.copyWith(
        totalPending: pending.length,
        libraryTotal: stats.total,
        libraryAnalyzed: stats.analyzed,
      );

      if (pending.isEmpty) {
        return;
      }

      final groups = _groupSongsForAnalysis(pending);

      for (final group in groups) {
        if (_cancelRequested) break;

        if (group.length == 1 || group.length > _maxAlbumGroupSize) {
          for (final song in group) {
            if (_cancelRequested) break;
            await _analyzeSingleSong(song);
            if (isPlaying?.call() == true) {
              await Future<void>.delayed(const Duration(milliseconds: 60));
            }
          }
        } else {
          await _analyzeAlbumGroup(group);
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
        clearCurrentFileName: true,
      );
    }
  }

  List<List<SongMetadata>> _groupSongsForAnalysis(List<SongMetadata> songs) {
    final grouped = <String, List<SongMetadata>>{};
    final singles = <List<SongMetadata>>[];

    for (final song in songs) {
      final album = song.album.trim();
      final isUnknownAlbum = album.isEmpty ||
          album.toLowerCase() == 'unknown album' ||
          album.toLowerCase() == 'unknown';
      if (isUnknownAlbum) {
        singles.add([song]);
        continue;
      }
      final artistKey = (song.albumArtist?.trim().isNotEmpty == true
              ? song.albumArtist!.trim()
              : song.artist.trim())
          .toLowerCase();
      final key = '$artistKey\u0000${album.toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(song);
    }

    return [...grouped.values, ...singles];
  }

  Future<void> _analyzeSingleSong(SongMetadata song) async {
    state = state.copyWith(currentFileName: p.basename(song.path));
    try {
      final res = await _withReadablePath(
        song.path,
        (resolvedPath) => analyzeTrackLoudness(path: resolvedPath),
      );
      if (res == null) {
        state = state.copyWith(
          failedInRun: state.failedInRun + 1,
          lastError: 'File not accessible: ${p.basename(song.path)}',
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
      state = state.copyWith(
        completedInRun: state.completedInRun + 1,
        libraryAnalyzed: state.libraryAnalyzed + 1,
      );
    } catch (e) {
      debugPrint('[LoudnessBackfill] analyzeTrackLoudness failed (${song.path}): $e');
      state = state.copyWith(
        failedInRun: state.failedInRun + 1,
        lastError: '${p.basename(song.path)}: $e',
      );
    }
  }

  Future<void> _analyzeAlbumGroup(List<SongMetadata> group) async {
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
        state = state.copyWith(failedInRun: state.failedInRun + 1);
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
        (resolvedPaths) => analyzeAlbumLoudness(paths: resolvedPaths),
      );
      if (albumResult == null) {
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
