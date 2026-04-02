import 'dart:typed_data';
import 'package:path/path.dart' as p;

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
    );
  }
}
