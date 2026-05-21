import 'dart:math' as math;

/// 播放队列后台处理器
///
/// 负责在后台异步处理播放列表中的歌曲。
/// 包括：解析元数据、从封面提取配色方案、生成全曲波形图等耗时操作，不干扰主线程播放。
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_core/audio_core.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';
import 'track_artwork_theme_service.dart';
import 'waveform_service.dart';

/// Handles background processing of the playback queue (waveforms, colors, etc.)
class PlaybackQueueProcessor {
  final MetadataDatabase db;
  final AudioCoreController player;
  final SettingsService settingsService;
  final WaveformService waveformService;

  int _currentProcessId = 0;
  bool _isProcessing = false;
  bool _isPaused = false;
  bool _disposed = false;
  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;

  PlaybackQueueProcessor({
    required this.db,
    required this.player,
    required this.settingsService,
    required this.waveformService,
  });

  void pause() {
    _isPaused = true;
    debugPrint('PlaybackQueueProcessor: Paused background processing.');
  }

  void resume() {
    _isPaused = false;
    debugPrint('PlaybackQueueProcessor: Resumed background processing.');
  }

  Future<void> _waitUntilResumed() async {
    while (_isPaused && !_disposed) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Checks if a song already has all required background data (waveform, colors).
  Future<bool> isSongReady(String path) async {
    final existing = await db.getSongMetadata(path);
    if (existing == null) return false;

    final bool showWaveform = settingsService.isWaveformProgressBarEnabled;
    final bool needsWaveform =
        showWaveform && !await waveformService.hasCachedWaveform(path);
    final bool needsThemeColor = existing.themeColorsBlob == null;

    return !needsWaveform && !needsThemeColor;
  }

  Future<void> processQueue({
    required List<MusicFile> playlist,
    required String? currentFilePath,
    required Function(String path, Map<String, dynamic> updates) onUpdate,
    Function(String path, Uint8List bytes)? onHdArtworkLoaded,
  }) async {
    if (_disposed) return;
    final artworkThemeService = TrackArtworkThemeService(db: db);
    // If already processing, we signal to stop the current one and start fresh with new priority
    _currentProcessId++;
    final int myId = _currentProcessId;

    if (_isProcessing) {
      debugPrint('Signaling background processor to re-prioritize');
    }

    _isProcessing = true;

    try {
      debugPrint('Starting background queue processing (ID: $myId)');

      // 1. Sort the processing list to prioritize current and upcoming songs
      final List<MusicFile> sortedList = List.from(playlist);
      int currentIndex = -1;
      if (currentFilePath != null) {
        if (_disposed) return;
        currentIndex = playlist.indexWhere((s) => s.path == currentFilePath);
        if (currentIndex != -1) {
          final Set<String> processed = <String>{};
          final List<MusicFile> prioritized = <MusicFile>[];

          void addIfUnique(int index) {
            final idx = index % playlist.length;
            final song = playlist[idx < 0 ? idx + playlist.length : idx];
            if (processed.add(song.path)) {
              prioritized.add(song);
            }
          }

          // 1 & 2: Next 15 songs (even more than before to avoid gaps)
          for (int i = 0; i <= 15; i++) {
            addIfUnique(currentIndex + i);
          }
          // 3: Previous 2 songs
          for (int i = 1; i <= 2; i++) {
            addIfUnique(currentIndex - i);
          }
          // 4: Everything else
          for (int i = 0; i < playlist.length; i++) {
            addIfUnique(i);
          }

          sortedList.clear();
          sortedList.addAll(prioritized);
        }
      }

      // Phase 1: FAST PASS - Immediately load HD artwork for prioritized songs
      // This ensures that when skipping fast, covers are already in memory.
      // We look at the top 15 songs from our sorted list (which includes current and upcoming).
      final int topCount = math.min(15, sortedList.length);
      for (int i = 0; i < topCount; i++) {
        if (_disposed || myId != _currentProcessId) return;
        final song = sortedList[i];

        // Skip if already has artwork bytes in memory
        if (song.artworkBytes != null) continue;

        try {
          final existing = await db.getSongMetadata(song.path);
          Uint8List? finalBytes;

          // Try external artwork path first (usually higher quality from online match)
          if (existing?.artworkPath != null &&
              existing!.artworkPath!.isNotEmpty) {
            try {
              final coverFile = File(existing.artworkPath!);
              if (await coverFile.exists()) {
                finalBytes = await coverFile.readAsBytes();
              }
            } catch (e) {
              debugPrint(
                'Failed to read external artwork for ${song.path}: $e',
              );
            }
          }

          // Fallback to embedded artwork
          if (finalBytes == null) {
            try {
              final m = readMetadata(File(song.path), getImage: true);
              finalBytes = m.pictures.isNotEmpty
                  ? m.pictures.first.bytes
                  : null;
            } catch (e) {
              // Ignore failure
            }
          }

          if (finalBytes != null && onHdArtworkLoaded != null) {
            onHdArtworkLoaded(song.path, finalBytes);
          }
        } catch (e) {
          debugPrint('Error loading HD artwork in fast pass: $e');
        }
      }

      // Phase 2: SLOW PASS - Process thumbnails, colors and waveforms
      for (final song in sortedList) {
        // Check if we've been superseded by a newer request
        if (_disposed || myId != _currentProcessId) {
          debugPrint(
            'Background process $myId superseded by $_currentProcessId, exiting.',
          );
          return;
        }

        await _waitUntilResumed();

        try {
          final existing = await db.getSongMetadata(song.path);
          final bool showWaveform =
              settingsService.isWaveformProgressBarEnabled;

          // Decide what needs to be done
          final bool needsWaveform =
              showWaveform &&
              (existing == null || existing.waveformBlob == null);
          final bool needsThemeColor =
              existing == null || existing.themeColorsBlob == null;

          // Heavy Processing: Thumbnails, Colors and Waveform
          if (needsWaveform ||
              needsThemeColor ||
              existing.thumbnailPath == null) {
            if (_disposed) return;

            debugPrint(
              'Background processing (Thumbnail/Colors/Waveform): ${song.path}',
            );

            // We need a metadata object (either from DB or a quick scan) to get the artwork path
            SongMetadata? m = existing;
            if (m == null) {
              final result = await MetadataHelper.processMetadata(
                song.path,
                generateThumbnail: false,
              );
              if (_disposed) return;
              m = result?.$1;
            }

            if (m != null) {
              // Use a non-nullable reference
              SongMetadata meta = m;

              final artworkTheme = await artworkThemeService
                  .getTrackArtworkTheme(
                    song.path,
                    controller: player,
                    saveLargeArtwork: !Platform.isWindows,
                    thumbnailSize: generatedArtworkThumbnailSize,
                  );
              if (_disposed) return;

              if (artworkTheme != null &&
                  (artworkTheme.hasArtworkPath ||
                      artworkTheme.hasThemeColors)) {
                meta = artworkTheme.toSongMetadata(base: meta);
                await db.insertOrUpdateSong(meta);

                final updates = <String, dynamic>{
                  'thumbnailPath':
                      artworkTheme.thumbnailPath ?? meta.thumbnailPath,
                  'artworkPath': artworkTheme.artworkPath ?? meta.artworkPath,
                  'artworkWidth': meta.artworkWidth,
                  'artworkHeight': meta.artworkHeight,
                };
                if (meta.themeColorsBlob != null) {
                  updates['themeColorsBlob'] = meta.themeColorsBlob;
                  updates['themeColors'] = ThemeColorHelper.blobToColors(
                    meta.themeColorsBlob!,
                  );
                }

                onUpdate(song.path, updates);
              } else if (meta.themeColorsBlob == null) {
                try {
                  final paletteBytes =
                      song.artworkBytes ??
                      (meta.artworkPath != null
                          ? await File(meta.artworkPath!).readAsBytes()
                          : null);
                  Uint8List? themeColorsBlob =
                      await TrackArtworkThemeService.generateThemeColorsBlob(
                        bytes: paletteBytes,
                        path: meta.artworkPath ?? meta.thumbnailPath,
                      );

                  if (themeColorsBlob == null) {
                    final extractedBytes =
                        await MetadataHelper.decodeEmbeddedArtwork(song.path);
                    if (_disposed) return;
                    themeColorsBlob =
                        await TrackArtworkThemeService.generateThemeColorsBlob(
                          bytes: extractedBytes,
                        );
                  }

                  if (themeColorsBlob != null) {
                    meta = meta.copyWith(themeColorsBlob: themeColorsBlob);
                    await db.insertOrUpdateSong(meta);

                    onUpdate(song.path, {
                      'themeColors': ThemeColorHelper.blobToColors(
                        themeColorsBlob,
                      ),
                      'themeColorsBlob': themeColorsBlob,
                    });
                  }
                } catch (e) {
                  debugPrint(
                    'Theme color extraction error for ${song.path}: $e',
                  );
                }
              }

              // Extract waveform if missing AND enabled in settings
              if (showWaveform && meta.waveformBlob == null) {
                try {
                  final waveformResult = await waveformService.getWaveformData(
                    path: song.path,
                    expectedChunks: settingsService.waveformChunks,
                    sampleStride: settingsService.sampleStride,
                    baseMetadata: meta,
                  );
                  if (_disposed) return;

                  if (waveformResult.waveform.isNotEmpty) {
                    meta = meta.copyWith(waveformBlob: waveformResult.waveformBlob);
                    onUpdate(song.path, {
                      'waveform': waveformResult.waveform,
                      'waveformBlob': waveformResult.waveformBlob,
                    });
                  }
                } catch (e) {
                  debugPrint('Waveform extraction error for ${song.path}: $e');
                }
              }
            }

            // Small delay between songs to keep main thread snappy
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          debugPrint('Error processing background song ${song.path}: $e');
        }
      }
    } finally {
      _isProcessing = false;
      debugPrint('Background queue processing finished');
    }
  }

  void dispose() {
    _disposed = true;
  }
}
