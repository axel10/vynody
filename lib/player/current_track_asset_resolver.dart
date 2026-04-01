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

  Future<CurrentTrackAssetResolution> resolve(
    MusicFile song, {
    SongMetadata? songFromDb,
    Uint8List? cachedArtworkBytes,
  }) async {
    final path = song.path;
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

    if (cachedArtworkBytes != null) {
      final dimensions = await _decodeArtworkDimensions(cachedArtworkBytes);
      artworkWidth = dimensions.$1 ?? artworkWidth;
      artworkHeight = dimensions.$2 ?? artworkHeight;
    }

    if (songFromDb != null) {
      waveform = _waveformFromBlob(songFromDb.waveformBlob);
      if (songFromDb.title.trim().isNotEmpty && songFromDb.title != 'Unknown') {
        fileName = songFromDb.title;
      }
      artist = songFromDb.artist;
      album = songFromDb.album;
    } else {
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

    if (artworkBytes == null) {
      try {
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
          artworkBytes = await _queryAndroidArtwork(song.id!);
        }
      } catch (e) {
        debugPrint('Error reading high-res metadata for $path: $e');
        if (Platform.isAndroid && song.id != null && artworkBytes == null) {
          artworkBytes = await _queryAndroidArtwork(song.id!);
        }
      }
    }

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
