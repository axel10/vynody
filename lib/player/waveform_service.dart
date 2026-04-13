/// 波形数据服务
///
/// 提供歌曲波形图的获取、计算、缓存同步以及 BLOB 数据的序列化与反序列化。
library;

import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'metadata_database.dart';

class WaveformService {
  final MetadataDatabase db;
  final AudioCoreController player;

  WaveformService({required this.db, required this.player});

  Future<List<double>> getWaveform({
    required String path,
    int expectedChunks = 80,
    int sampleStride = 8,
  }) async {
    final songMetadata = await db.getSongMetadata(path);
    if (songMetadata != null && songMetadata.waveformBlob != null) {
      final blob = songMetadata.waveformBlob!;
      // Ensure the offset is aligned to 4 bytes for asFloat32List
      final alignedBlob = (blob.offsetInBytes % 4 == 0)
          ? blob
          : Uint8List.fromList(blob);
      final list = alignedBlob.buffer.asFloat32List(
        alignedBlob.offsetInBytes,
        alignedBlob.length ~/ 4,
      );
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

      final updated = songMetadata.copyWith(waveformBlob: blob);
      await db.insertOrUpdateSong(updated);
    }

    return waveform;
  }

  List<double> waveformFromBlob(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return const [];
    // Ensure the offset is aligned to 4 bytes for asFloat32List
    final alignedBlob = (blob.offsetInBytes % 4 == 0)
        ? blob
        : Uint8List.fromList(blob);
    final list = alignedBlob.buffer.asFloat32List(
      alignedBlob.offsetInBytes,
      alignedBlob.length ~/ 4,
    );
    return list.map((e) => e.toDouble()).toList();
  }
}
