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
  bool _isPaused = false;
  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;


  PlaybackQueueProcessor({
    required this.db,
    required this.player,
    required this.settingsService,
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
    while (_isPaused) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Checks if a song already has all required background data (waveform, colors).
  Future<bool> isSongReady(String path) async {
    final existing = await db.getSongMetadata(path);
    if (existing == null) return false;

    final bool showWaveform = settingsService.isWaveformProgressBarEnabled;
    final bool needsWaveform =
        showWaveform && (existing.waveformBlob == null);
    final bool needsThemeColor = existing.themeColorsBlob == null;

    return !needsWaveform && !needsThemeColor;
  }


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

        await _waitUntilResumed();

        try {

          final existing = await db.getSongMetadata(song.path);
          final bool showWaveform = settingsService.isWaveformProgressBarEnabled;

          // Decide what needs to be done
          final bool needsWaveform =
              showWaveform && (existing == null || existing.waveformBlob == null);
          final bool needsThemeColor =
              existing == null || existing.themeColorsBlob == null;

          // 1. 高清封面预取与预处理 (优先级最高)
          // 策略：优先从数据库记录的路径读取大图文件，避免重复解析音频嵌入封面。
          // 理由：数据库里的大图（通常是通过在线匹配获取的）质量通常更高。
          if (onHdArtworkLoaded != null && currentIndex != -1) {
            final int songIndex = playlist.indexWhere((s) => s.path == song.path);
            final int distance = (songIndex - currentIndex + playlist.length) % playlist.length;
            bool isNear = distance <= 3 || distance == playlist.length - 1;

            if (isNear) {
              Uint8List? finalBytes;
              
              // 优先尝试从数据库的大图路径加载
              if (existing?.artworkPath != null && existing!.artworkPath!.isNotEmpty) {
                try {
                  final coverFile = File(existing.artworkPath!);
                  if (await coverFile.exists()) {
                    finalBytes = await coverFile.readAsBytes();
                  }
                } catch (e) {
                  debugPrint('Failed to read external artwork for ${song.path}: $e');
                }
              }

              // 如果没有外部大图路径，则回退到歌曲内嵌封面
              if (finalBytes == null) {
                try {
                  final m = readMetadata(File(song.path), getImage: true);
                  finalBytes = m.pictures.isNotEmpty ? m.pictures.first.bytes : null;
                } catch (e) {
                  // 回退也失败时，不做任何操作
                }
              }

              if (finalBytes != null) {
                onHdArtworkLoaded(song.path, finalBytes);
              }
            }
          }



          // 2. Heavy Processing: Thumbnails, Colors and Waveform
          if (needsWaveform || needsThemeColor || existing.thumbnailPath == null) {
            debugPrint('Background processing (Thumbnail/Colors/Waveform): ${song.path}');

            // We need a metadata object (either from DB or a quick scan) to get the artwork path
            SongMetadata? m = existing;
            if (m == null) {
              final result = await MetadataHelper.processMetadata(
                song.path,
                generateThumbnail: false,
              );
              m = result?.$1;
            }

            if (m != null) {
              // Use a non-nullable reference
              SongMetadata meta = m;

              // Extract thumbnail if missing
              if (meta.thumbnailPath == null) {
                try {
                  // Extract raw artwork data first
                  final rawMetadata = await compute(
                    MetadataHelper.readMetadataIsolate,
                    song.path,
                  );
                  final artworkData = rawMetadata.pictures.isNotEmpty
                      ? rawMetadata.pictures.first.bytes
                      : null;

                  if (artworkData != null) {
                    final artworkInfo = await MetadataHelper.saveArtworkAndThumbnail(
                      song.path,
                      artworkData,
                      saveLarge: !Platform.isWindows,
                    );

                    if (artworkInfo != null) {
                      final thumbPath = artworkInfo['thumbnailPath'] as String?;

                      meta = meta.copyWith(
                        thumbnailPath: thumbPath,
                        artworkPath: artworkInfo['artworkPath'] as String?,
                        artworkWidth: artworkInfo['width'] as int?,
                        artworkHeight: artworkInfo['height'] as int?,
                      );
                      await db.insertOrUpdateSong(meta);

                      onUpdate(song.path, {
                        'thumbnailPath': thumbPath,
                        'artworkWidth': meta.artworkWidth,
                        'artworkHeight': meta.artworkHeight,
                      });
                    }
                  }
                } catch (e) {
                  debugPrint('Thumbnail extraction error for ${song.path}: $e');
                }
              }

              // Extract theme colors if missing
              if (meta.themeColorsBlob == null) {
                try {
                  final colorSourcePath = meta.thumbnailPath ?? meta.artworkPath;
                  if (colorSourcePath != null) {
                    final imageProvider = FileImage(File(colorSourcePath));
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

                    onUpdate(song.path, {
                      'waveform': waveform,
                      'waveformBlob': blob,
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
}
