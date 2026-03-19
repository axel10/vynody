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
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';

/// Handles background processing of the playback queue (waveforms, colors, etc.)
class PlaybackQueueProcessor {
  final MetadataDatabase db;
  final AudioVisualizerPlayerController player;
  final SettingsService settingsService;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  PlaybackQueueProcessor({
    required this.db,
    required this.player,
    required this.settingsService,
  });

  /// Starts processing the queue in the background.
  /// [playlist] - current list of music files
  /// [currentFilePath] - path of the song currently playing
  /// [onUpdate] - callback when a song is updated, especially if it matches [currentFilePath]
  Future<void> processQueue({
    required List<MusicFile> playlist,
    required String? currentFilePath,
    required Function(String path, Map<String, dynamic> updates) onUpdate,
  }) async {
    if (_isProcessing || playlist.isEmpty) return;
    _isProcessing = true;

    try {
      debugPrint('Starting background queue processing');
      final List<MusicFile> processingList = List.from(playlist);

      for (final song in processingList) {
        // Here we'd ideally check if the song is still in the playlist,
        // but that check needs to happen in the loop or passed via another mechanism.
        // For simplicity, we process what we have.

        try {
          final existing = await db.getSongMetadata(song.path);

          bool needsWaveform = existing == null || existing.waveformBlob == null;
          bool needsThemeColor = existing == null || existing.themeColorsBlob == null;

          if (needsWaveform || needsThemeColor) {
            debugPrint('Background processing: ${song.path}');

            // 1. Process basic metadata
            final SongMetadata? initialMetadata = await MetadataHelper.processMetadata(song.path);

            if (initialMetadata != null) {
              SongMetadata m = initialMetadata;

              // If theme colors are missing but artwork exists, extract them
              if (m.themeColorsBlob == null && m.artworkPath != null) {
                try {
                  final imageProvider = FileImage(File(m.artworkPath!));
                  final palette = await PaletteGenerator.fromImageProvider(
                    imageProvider,
                    maximumColorCount: 20,
                  );
                  final themeColorsBlob = ThemeColorHelper.paletteToBlob(palette);

                  m = SongMetadata(
                    id: m.id,
                    path: m.path,
                    title: m.title,
                    album: m.album,
                    artist: m.artist,
                    duration: m.duration,
                    artworkPath: m.artworkPath,
                    artworkWidth: m.artworkWidth,
                    artworkHeight: m.artworkHeight,
                    trackNumber: m.trackNumber,
                    themeColorsBlob: themeColorsBlob,
                    waveformBlob: m.waveformBlob,
                  );
                  await db.insertOrUpdateSong(m);

                  // Notify caller about color update
                  onUpdate(song.path, {
                    'themeColors': ThemeColorHelper.blobToColors(themeColorsBlob),
                  });
                } catch (e) {
                  debugPrint('Theme color extraction error for ${song.path}: $e');
                }
              }

              // 2. Process waveform if still missing
              if (m.waveformBlob == null) {
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

                    final updated = SongMetadata(
                      id: m.id,
                      path: m.path,
                      title: m.title,
                      album: m.album,
                      artist: m.artist,
                      duration: m.duration,
                      artworkPath: m.artworkPath,
                      artworkWidth: m.artworkWidth,
                      artworkHeight: m.artworkHeight,
                      trackNumber: m.trackNumber,
                      themeColorsBlob: m.themeColorsBlob,
                      waveformBlob: blob,
                    );
                    await db.insertOrUpdateSong(updated);

                    // Notify caller about waveform update
                    onUpdate(song.path, {'waveform': waveform});
                  }
                } catch (e) {
                  debugPrint('Waveform extraction error for ${song.path}: $e');
                }
              }
            }

            // Small delay between songs to avoid heavy load
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
