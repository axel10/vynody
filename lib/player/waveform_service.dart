/// 波形数据服务
///
/// 提供歌曲波形图的获取、计算、缓存同步以及 BLOB 数据的序列化与反序列化。
library;

import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:path/path.dart' as p;
import 'metadata_database.dart';
import 'metadata_helper.dart';

class WaveformService {
  final MetadataDatabase db;
  final AudioCoreController player;

  WaveformService({required this.db, required this.player});

  Future<List<double>> getWaveform({
    required String path,
    int expectedChunks = 80,
    int sampleStride = 8,
  }) async {
    var songMetadata = await db.getSongMetadata(path);
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

    if (songMetadata == null) {
      final playbackMetadata = await MetadataHelper.loadMetadataForPlayback(
        path,
        generateThumbnail: false,
      );
      songMetadata = playbackMetadata?.$1;
      if (songMetadata?.waveformBlob != null) {
        return waveformFromBlob(songMetadata!.waveformBlob);
      }
    }

    // No cache, calculate and store
    final waveform = await player.getWaveform(
      expectedChunks: expectedChunks,
      sampleStride: sampleStride,
      filePath: path,
    );
    if (waveform.isNotEmpty) {
      final float32List = Float32List.fromList(
        waveform.map((e) => e.toDouble()).toList(),
      );
      final blob = float32List.buffer.asUint8List();

      final baseMetadata =
          songMetadata ??
          SongMetadata(
            path: path,
            title: p.basenameWithoutExtension(path),
            album: 'Unknown Album',
            artist: 'Unknown Artist',
          );
      final updated = baseMetadata.copyWith(waveformBlob: blob);
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
