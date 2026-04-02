/// 播放队列后台处理器
///
/// 负责在后台异步处理播放列表中的歌曲。
/// 包括：解析元数据、从封面提取配色方案、生成全曲波形图等耗时操作，不干扰主线程播放。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_core/audio_core.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';

/// Handles background processing of the playback queue (waveforms, colors, etc.)
class PlaybackQueueProcessor {
  final MetadataDatabase db;
  final AudioCoreController player;
  final SettingsService settingsService;

  int _currentProcessId = 0;
  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  PlaybackQueueProcessor({
    required this.db,
    required this.player,
    required this.settingsService,
  });

  Future<void> processQueue({
    required List<MusicFile> playlist,
    required String? currentFilePath,
    required Function(String path, Map<String, dynamic> updates) onUpdate,
    Function(String path, Uint8List bytes)? onHdArtworkLoaded,
  }) async {
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

      for (final song in sortedList) {
        // Check if we've been superseded by a newer request
        if (myId != _currentProcessId) {
          debugPrint(
            'Background process $myId superseded by $_currentProcessId, exiting.',
          );
          return;
        }

        try {
          final existing = await db.getSongMetadata(song.path);
          final bool showWaveform = settingsService.isWaveformProgressBarEnabled;

          // Decide what needs to be done
          final bool needsWaveform =
              showWaveform && (existing == null || existing.waveformBlob == null);
          final bool needsThemeColor =
              existing == null || existing.themeColorsBlob == null;

          // 1. HD PRE-FETCH & PRE-DECODE (Priority 1: For visual smoothness)
          // Pre-fetch for current, next 3, and previous 1
          if (onHdArtworkLoaded != null && currentIndex != -1) {
            final int songIndex = playlist.indexWhere(
              (s) => s.path == song.path,
            );
            final int distance =
                (songIndex - currentIndex + playlist.length) % playlist.length;
            bool isNear = distance <= 3 || distance == playlist.length - 1;

            if (isNear) {
              try {
                // Read from file stream directly to get HD artwork
                final m = readMetadata(File(song.path), getImage: true);
                final bytes =
                    m.pictures.isNotEmpty ? m.pictures.first.bytes : null;
                if (bytes != null) {
                  onHdArtworkLoaded(song.path, bytes);
                }
              } catch (e) {
                // Ignore errors for pre-fetch
              }
            }
          }

          // 2. Heavy Processing: Colors and Waveform
          if (needsWaveform || needsThemeColor) {
            debugPrint('Background processing (Colors/Waveform): ${song.path}');

            // We need a metadata object (either from DB or a quick scan) to get the artwork path
            SongMetadata? m = existing;
            if (m == null) {
              final result = await MetadataHelper.processMetadata(song.path);
              m = result?.$1;
            }

            if (m != null) {
              // Use a non-nullable reference
              SongMetadata meta = m;

              // Extract theme colors if missing
              if (meta.themeColorsBlob == null && meta.artworkPath != null) {
                try {
                  final imageProvider = FileImage(File(meta.artworkPath!));
                  final palette = await PaletteGenerator.fromImageProvider(
                    imageProvider,
                    maximumColorCount: 20,
                  );
                  final themeColorsBlob = ThemeColorHelper.paletteToBlob(
                    palette,
                  );

                  meta = meta.copyWith(themeColorsBlob: themeColorsBlob);
                  await db.insertOrUpdateSong(meta);

                  onUpdate(song.path, {
                    'themeColors': ThemeColorHelper.blobToColors(
                      themeColorsBlob,
                    ),
                  });
                } catch (e) {
                  debugPrint(
                    'Theme color extraction error for ${song.path}: $e',
                  );
                }
              }

              // Extract waveform if missing AND enabled in settings
              if (showWaveform && meta.waveformBlob == null) {
                try {
                  final waveform = await player.getWaveform(
                    expectedChunks: settingsService.waveformChunks,
                    sampleStride: settingsService.sampleStride,
                    filePath: song.path,
                  );

                  if (waveform.isNotEmpty) {
                    final float32List = Float32List.fromList(
                      waveform.map((e) => e.toDouble()).toList(),
                    );
                    final blob = float32List.buffer.asUint8List();

                    meta = meta.copyWith(waveformBlob: blob);
                    await db.insertOrUpdateSong(meta);

                    onUpdate(song.path, {'waveform': waveform});
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
}
