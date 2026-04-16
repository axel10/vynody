import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'music_lyric.dart';

part 'music_file.freezed.dart';

@freezed
abstract class MusicFile with _$MusicFile {
  const MusicFile._();

  const factory MusicFile({
    required String path,
    required String name,
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    int? id, // System Media Library ID
    String? mediaUri,
    String? thumbnailPath,
    String? artworkPath,
    int? artworkWidth,
    int? artworkHeight,
    int? durationMillis,
    Uint8List? themeColorsBlob,
    Uint8List? waveformBlob,
    Uint8List? artworkBytes,
    int? lastModifiedTime,
    MusicLyric? lyrics,
    @Default(false) bool isMissing,
  }) = _MusicFile;

  List<double> get waveform {
    final blob = waveformBlob;
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

  String get displayName {
    if (title != null && title!.trim().isNotEmpty) {
      return title!;
    }
    return p.basenameWithoutExtension(path);
  }
}
