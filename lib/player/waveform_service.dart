/// 波形数据服务
/// 
/// 提供歌曲波形图的获取、计算、缓存同步以及 BLOB 数据的序列化与反序列化。
import 'dart:typed_data';
import 'package:audio_visualizer_player/audio_visualizer_player.dart';
import 'metadata_database.dart';

class WaveformService {
  final MetadataDatabase db;
  final AudioVisualizerPlayerController player;

  WaveformService({required this.db, required this.player});

  Future<List<double>> getWaveform({
    required String path,
    int expectedChunks = 80,
    int sampleStride = 3,
  }) async {
    final songMetadata = await db.getSongMetadata(path);
    if (songMetadata != null && songMetadata.waveformBlob != null) {
      final list = Float32List.view(songMetadata.waveformBlob!.buffer);
      return list.map((e) => e.toDouble()).toList();
    }

    // No cache, calculate and store
    final waveform = await player.getWaveform(
      expectedChunks: expectedChunks,
      sampleStride: sampleStride,
      filePath: path,
    );

    if (waveform.isNotEmpty && songMetadata != null) {
      final float32List = Float32List.fromList(
        waveform.map((e) => e.toDouble()).toList(),
      );
      final blob = float32List.buffer.asUint8List();

      final updated = SongMetadata(
        id: songMetadata.id,
        path: songMetadata.path,
        title: songMetadata.title,
        album: songMetadata.album,
        artist: songMetadata.artist,
        duration: songMetadata.duration,
        artworkPath: songMetadata.artworkPath,
        artworkWidth: songMetadata.artworkWidth,
        artworkHeight: songMetadata.artworkHeight,
        trackNumber: songMetadata.trackNumber,
        themeColorsBlob: songMetadata.themeColorsBlob,
        waveformBlob: blob,
      );
      await db.insertOrUpdateSong(updated);
    }

    return waveform;
  }

  List<double> waveformFromBlob(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return const [];
    final list = Float32List.view(blob.buffer, blob.offsetInBytes);
    return list.map((e) => e.toDouble()).toList();
  }
}
