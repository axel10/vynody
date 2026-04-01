import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';

import '../models/music_file.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';

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
  final MetadataDatabase _db;
  final OnAudioQuery _audioQuery;

  CurrentTrackAssetResolver({MetadataDatabase? db, OnAudioQuery? audioQuery})
    : _db = db ?? MetadataDatabase(),
      _audioQuery = audioQuery ?? OnAudioQuery();

  /// 解析当前曲目的静态资产（如封面图、波形图、元数据）
  Future<CurrentTrackAssetResolution> resolve(
    MusicFile song, {
    SongMetadata? songFromDb,
    Uint8List? cachedArtworkBytes,
  }) async {
    final path = song.path;
    // 1. 获取本地数据库中已有的元数据（快速路径的基础）
    songFromDb ??= await _db.getSongMetadata(path);

    String fileName = song.displayName;
    String? artist = song.artist;
    String? album = song.album;
    List<double> waveform = const [];
    SongMetadata? resolvedMetadata = songFromDb;
    String? artworkPath = songFromDb?.artworkPath;
    int? artworkWidth = songFromDb?.artworkWidth;
    int? artworkHeight = songFromDb?.artworkHeight;
    Uint8List? artworkBytes = cachedArtworkBytes;

    // 如果内存中有缓存的封面字节，尝试解码其尺寸
    if (cachedArtworkBytes != null) {
      final dimensions = await _decodeArtworkDimensions(cachedArtworkBytes);
      artworkWidth = dimensions.$1 ?? artworkWidth;
      artworkHeight = dimensions.$2 ?? artworkHeight;
    }

    if (songFromDb != null) {
      // 从数据库加载波形和标签
      waveform = _waveformFromBlob(songFromDb.waveformBlob);
      if (songFromDb.title.trim().isNotEmpty && songFromDb.title != 'Unknown') {
        fileName = songFromDb.title;
      }
      artist = songFromDb.artist;
      album = songFromDb.album;
    } else {
      // 2. 如果数据库没有，启动“深度扫描”：解析文件 ID3 标签、提取并压缩封面存入本地缓存
      final result = await MetadataHelper.processMetadata(path);
      if (result != null) {
        resolvedMetadata = result.$1;
        final processed = result.$1;
        final processedBytes = result.$2;

        if (processed.title.trim().isNotEmpty && processed.title != 'Unknown') {
          fileName = processed.title;
        }
        artist = processed.artist;
        album = processed.album;
        artworkPath = processed.artworkPath;
        artworkWidth = processed.artworkWidth;
        artworkHeight = processed.artworkHeight;
        waveform = _waveformFromBlob(processed.waveformBlob);

        if (processedBytes != null) {
          artworkBytes = processedBytes;
          final dimensions = await _decodeArtworkDimensions(processedBytes);
          artworkWidth = dimensions.$1 ?? artworkWidth;
          artworkHeight = dimensions.$2 ?? artworkHeight;
        }
      }
    }

    // 3. 封面图兜底逻辑：如果前面的步骤都没拿到图片字节
    if (artworkBytes == null) {
      try {
        // 尝试再次直接从文件中读取原始图片字节（高清显示需要）
        final metadata = readMetadata(File(path), getImage: true);
        final bytes = metadata.pictures.isNotEmpty
            ? metadata.pictures.first.bytes
            : null;
        if (bytes != null) {
          artworkBytes = bytes;
          final dimensions = await _decodeArtworkDimensions(bytes);
          artworkWidth = dimensions.$1 ?? artworkWidth;
          artworkHeight = dimensions.$2 ?? artworkHeight;
        } else if (Platform.isAndroid && song.id != null) {
          // Android 平台特有：尝试通过 MediaStore 查询封面
          artworkBytes = await _queryAndroidArtwork(song.id!);
        }
      } catch (e) {
        debugPrint('Error reading high-res metadata for $path: $e');
        if (Platform.isAndroid && song.id != null && artworkBytes == null) {
          artworkBytes = await _queryAndroidArtwork(song.id!);
        }
      }
    }

    // 4. Android 锁屏/通知栏适配：需要将图片存为临时文件才能由系统读取
    if (Platform.isAndroid && artworkBytes != null) {
      artworkPath = await _saveAndroidArtwork(path, song.id, artworkBytes);
    }

    return CurrentTrackAssetResolution(
      songMetadata: resolvedMetadata,
      fileName: fileName,
      artist: artist,
      album: album,
      waveform: waveform,
      artworkBytes: artworkBytes,
      artworkPath: artworkPath,
      artworkWidth: artworkWidth,
      artworkHeight: artworkHeight,
    );
  }

  List<double> _waveformFromBlob(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return const [];
    final alignedBlob = (blob.offsetInBytes % 4 == 0)
        ? blob
        : Uint8List.fromList(blob);
    final list = alignedBlob.buffer.asFloat32List(
      alignedBlob.offsetInBytes,
      alignedBlob.length ~/ 4,
    );
    return list.map((e) => e.toDouble()).toList();
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
