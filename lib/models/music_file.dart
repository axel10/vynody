import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'music_lyric.dart';

class MusicFile {
  final String path;
  final String name;
  final String? title;
  final String? artist;
  final String? album;
  final int? trackNumber;
  final int? id; // System Media Library ID
  final String? hdArtworkPath;
  final String? thumbnailPath;
  final int? artworkWidth;
  final int? artworkHeight;
  final Uint8List? themeColorsBlob;
  final Uint8List? waveformBlob;
  final Uint8List? artworkBytes;
  final MusicLyric? lyrics;

  List<double> get waveform {
    final blob = waveformBlob;
    if (blob == null || blob.isEmpty) return const [];
    final alignedBlob =
        (blob.offsetInBytes % 4 == 0) ? blob : Uint8List.fromList(blob);
    final list = alignedBlob.buffer.asFloat32List(
      alignedBlob.offsetInBytes,
      alignedBlob.length ~/ 4,
    );
    return list.map((e) => e.toDouble()).toList();
  }

  MusicFile({
    required this.path,
    required this.name,
    this.title,
    this.artist,
    this.album,
    this.trackNumber,
    this.id,
    this.hdArtworkPath,
    this.thumbnailPath,
    this.artworkWidth,
    this.artworkHeight,
    this.themeColorsBlob,
    this.waveformBlob,
    this.artworkBytes,
    this.lyrics,
  });

  String get displayName {
    if (title != null && title!.trim().isNotEmpty) {
      return title!;
    }
    return p.basenameWithoutExtension(path);
  }

  MusicFile copyWith({
    String? path,
    String? name,
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    int? id,
    String? artworkPath,
    String? thumbnailPath,
    int? artworkWidth,
    int? artworkHeight,
    Uint8List? themeColorsBlob,
    Uint8List? waveformBlob,
    Uint8List? artworkBytes,
    MusicLyric? lyrics,
  }) {
    return MusicFile(
      path: path ?? this.path,
      name: name ?? this.name,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      trackNumber: trackNumber ?? this.trackNumber,
      id: id ?? this.id,
      hdArtworkPath: artworkPath ?? this.hdArtworkPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      artworkWidth: artworkWidth ?? this.artworkWidth,
      artworkHeight: artworkHeight ?? this.artworkHeight,
      themeColorsBlob: themeColorsBlob ?? this.themeColorsBlob,
      waveformBlob: waveformBlob ?? this.waveformBlob,
      artworkBytes: artworkBytes ?? this.artworkBytes,
      lyrics: lyrics ?? this.lyrics,
    );
  }
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MusicFile &&
        other.path == path &&
        other.name == name &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.trackNumber == trackNumber &&
        other.id == id &&
        other.hdArtworkPath == hdArtworkPath &&
        other.thumbnailPath == thumbnailPath &&
        other.artworkWidth == artworkWidth &&
        other.artworkHeight == artworkHeight &&
        other.lyrics == lyrics;
  }

  @override
  int get hashCode => Object.hash(
        path,
        name,
        title,
        artist,
        album,
        trackNumber,
        id,
        hdArtworkPath,
        thumbnailPath,
        artworkWidth,
        artworkHeight,
      );
}
