import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/album_summary.dart';
import '../models/music_file.dart';
import 'audio_riverpod.dart';
import 'metadata_database.dart';

final albumLibraryProvider = Provider<List<AlbumSummary>>((ref) {
  ref.watch(
    scannerServiceProvider.select((scanner) => scanner.metadataRevision),
  );
  final scanner = ref.read(scannerServiceProvider);
  return buildAlbumSummaries(scanner.metadataMap.values);
});

List<AlbumSummary> buildAlbumSummaries(Iterable<SongMetadata> songs) {
  final groups = <String, List<MusicFile>>{};

  for (final metadata in songs) {
    final title = _cleanMetadataText(metadata.album, fallback: 'Unknown Album');
    final artist = _cleanMetadataText(
      metadata.artist,
      fallback: 'Unknown Artist',
    );
    final song = MusicFile(
      path: metadata.path,
      name: p.basename(metadata.path),
      title: _cleanMetadataText(metadata.title, fallback: 'Unknown'),
      artist: artist,
      album: title,
      trackNumber: metadata.trackNumber,
      artworkPath: metadata.artworkPath,
      thumbnailPath: metadata.thumbnailPath,
      artworkWidth: metadata.artworkWidth,
      artworkHeight: metadata.artworkHeight,
      durationMillis: metadata.duration,
      themeColorsBlob: metadata.themeColorsBlob,
      waveformBlob: metadata.waveformBlob,
      lastModifiedTime: metadata.lastModifiedTime,
    );

    final key = '${title.toLowerCase()}::${artist.toLowerCase()}';
    groups.putIfAbsent(key, () => <MusicFile>[]).add(song);
  }

  final albums =
      groups.entries
          .map((entry) {
            final sortedSongs = List<MusicFile>.from(entry.value)
              ..sort(_compareAlbumSongs);
            final representativeSong = sortedSongs.firstWhere(
              (song) =>
                  (song.thumbnailPath?.isNotEmpty ?? false) ||
                  (song.artworkPath?.isNotEmpty ?? false),
              orElse: () => sortedSongs.first,
            );
            final totalDurationMillis = sortedSongs.fold<int>(
              0,
              (sum, song) => sum + (song.durationMillis ?? 0),
            );

            return AlbumSummary(
              id: entry.key,
              title: sortedSongs.first.album ?? 'Unknown Album',
              artist: sortedSongs.first.artist ?? 'Unknown Artist',
              songs: sortedSongs,
              representativeSong: representativeSong,
              totalDurationMillis: totalDurationMillis,
            );
          })
          .toList(growable: false)
        ..sort((a, b) {
          final artistCompare = a.artist.toLowerCase().compareTo(
            b.artist.toLowerCase(),
          );
          if (artistCompare != 0) return artistCompare;
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });

  return albums;
}

int _compareAlbumSongs(MusicFile a, MusicFile b) {
  final leftTrack = a.trackNumber;
  final rightTrack = b.trackNumber;
  if (leftTrack != null && rightTrack != null && leftTrack != rightTrack) {
    return leftTrack.compareTo(rightTrack);
  }
  if (leftTrack != null && rightTrack == null) return -1;
  if (leftTrack == null && rightTrack != null) return 1;

  final titleCompare = a.displayName.toLowerCase().compareTo(
    b.displayName.toLowerCase(),
  );
  if (titleCompare != 0) return titleCompare;
  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
}

String _cleanMetadataText(String? value, {required String fallback}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}
