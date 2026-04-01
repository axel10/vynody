import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../models/music_file.dart';
import 'metadata_database.dart';

class CurrentTrackAssetResolution {
  final SongMetadata? songMetadata;
  final String fileName;
  final String? artist;
  final String? album;
  final List<double> waveform;
  final Uint8List? artworkBytes;
  final String? artworkPath;
  final int? artworkWidth;
  final int? artworkHeight;

  const CurrentTrackAssetResolution({
    required this.songMetadata,
    required this.fileName,
    required this.artist,
    required this.album,
    required this.waveform,
    required this.artworkBytes,
    required this.artworkPath,
    required this.artworkWidth,
    required this.artworkHeight,
  });
}

class CurrentTrackAssetResolver {
  final OnAudioQuery _audioQuery;

  CurrentTrackAssetResolver({MetadataDatabase? db, OnAudioQuery? audioQuery})
    : _audioQuery = audioQuery ?? OnAudioQuery();

  /// 直接读取文件元数据以简化流程，不再查库
  Future<CurrentTrackAssetResolution> resolve(
    MusicFile song, {
    Uint8List? cachedArtworkBytes,
  }) async {
    final path = song.path;
    
    // 1. 直接从文件读取标签和原始封面（使用 compute 避免阻塞 UI）
    final metadata = await compute(_readMetadataIsolate, path);

    String fileName = metadata.title?.trim().isNotEmpty == true 
        ? metadata.title! 
        : song.displayName;
    String? artist = metadata.artist?.trim().isNotEmpty == true 
        ? metadata.artist 
        : song.artist;
    String? album = metadata.album?.trim().isNotEmpty == true 
        ? metadata.album 
        : song.album;
        
    Uint8List? artworkBytes = cachedArtworkBytes;
    int? artworkWidth;
    int? artworkHeight;

    // 如果没有缓存的封面，则使用刚从文件读取的封面
    if (artworkBytes == null && metadata.pictures.isNotEmpty) {
      artworkBytes = metadata.pictures.first.bytes;
    }

    if (artworkBytes != null) {
      final dimensions = await _decodeArtworkDimensions(artworkBytes);
      artworkWidth = dimensions.$1;
      artworkHeight = dimensions.$2;
    } else if (Platform.isAndroid && song.id != null) {
      // Android 平台特有：如果文件中没封面，尝试通过 MediaStore 查询
      artworkBytes = await _queryAndroidArtwork(song.id!);
      if (artworkBytes != null) {
        final dimensions = await _decodeArtworkDimensions(artworkBytes);
        artworkWidth = dimensions.$1;
        artworkHeight = dimensions.$2;
      }
    }

    // 2. Android 锁屏/通知栏适配：需要将图片存为临时文件
    String? artworkPath;
    if (Platform.isAndroid && artworkBytes != null) {
      artworkPath = await _saveAndroidArtwork(path, song.id, artworkBytes);
    }

    return CurrentTrackAssetResolution(
      songMetadata: null, // 简化流程，不再传递完整的 SongMetadata 对象
      fileName: fileName,
      artist: artist,
      album: album,
      waveform: const [], // 简化流程，切换时暂不处理波形
      artworkBytes: artworkBytes,
      artworkPath: artworkPath,
      artworkWidth: artworkWidth,
      artworkHeight: artworkHeight,
    );
  }
  
  // 隔离函数，用于 compute 环境中读取元数据
  static AudioMetadata _readMetadataIsolate(String path) {
    return readMetadata(File(path), getImage: true);
  }

  Future<(int?, int?)> _decodeArtworkDimensions(Uint8List bytes) async {
    try {
      // Faster: use ImmutableBuffer + ImageDescriptor to only read metadata without decoding pixels
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (descriptor.width, descriptor.height);
    } catch (e) {
      debugPrint('Error decoding artwork dimensions: $e');
      return (null, null);
    }
  }

  Future<Uint8List?> _queryAndroidArtwork(int songId) async {
    try {
      return _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 600,
        quality: 100,
      );
    } catch (e) {
      debugPrint('Error in Android artwork fallback: $e');
      return null;
    }
  }

  Future<String?> _saveAndroidArtwork(
    String path,
    int? songId,
    Uint8List bytes,
  ) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final artworkSuffix = [
        (songId ?? path.hashCode).toString(),
        DateTime.now().microsecondsSinceEpoch.toString(),
      ].join('_');
      final artworkFile = File(
        '${tempDir.path}/current_notification_artwork_$artworkSuffix.jpg',
      );
      await artworkFile.writeAsBytes(bytes);
      return artworkFile.path;
    } catch (e) {
      debugPrint('Error saving notification artwork on Android: $e');
      return null;
    }
  }
}
