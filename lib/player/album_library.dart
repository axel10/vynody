import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/album_summary.dart';
import '../models/music_file.dart';
import 'metadata_database.dart';

final albumLibraryProvider = StreamProvider<List<AlbumSummary>>((ref) async* {
  final db = MetadataDatabase();
  await for (final songs in db.watchAllSongMetadata()) {
    final payload = songs.map(_metadataToPayload).toList(growable: false);
    final albumPayloads = await compute(_buildAlbumSummaryPayloads, payload);
    yield _hydrateAlbumSummaries(albumPayloads);
  }
});

List<AlbumSummary> buildAlbumSummaries(Iterable<SongMetadata> songs) {
  return _hydrateAlbumSummaries(
    _buildAlbumSummaryPayloads(
      songs.map(_metadataToPayload).toList(growable: false),
    ),
  );
}

Map<String, Object?> _metadataToPayload(SongMetadata metadata) {
  return {
    'path': metadata.path,
    'title': metadata.title,
    'artist': metadata.artist,
    'album': metadata.album,
    'trackNumber': metadata.trackNumber,
    'id': metadata.id,
    'thumbnailPath': metadata.thumbnailPath,
    'artworkPath': metadata.artworkPath,
    'artworkWidth': metadata.artworkWidth,
    'artworkHeight': metadata.artworkHeight,
    'duration': metadata.duration,
    'lastModifiedTime': metadata.lastModifiedTime,
  };
}

List<Map<String, Object?>> _buildAlbumSummaryPayloads(
  List<Map<String, Object?>> songs,
) {
  final groups = <String, List<Map<String, Object?>>>{};

  for (final metadata in songs) {
    final path = metadata['path'] as String? ?? '';
    if (path.isEmpty) {
      continue;
    }
    final title = _cleanMetadataText(
      metadata['album'] as String?,
      fallback: 'Unknown Album',
    );
    final artist = _cleanMetadataText(
      metadata['artist'] as String?,
      fallback: 'Unknown Artist',
    );
    final song = _musicFileToPayload(
      MusicFile(
        path: path,
        name: p.basename(path),
        title: _cleanMetadataText(
          metadata['title'] as String?,
          fallback: 'Unknown',
        ),
        artist: artist,
        album: title,
        trackNumber: metadata['trackNumber'] as int?,
        id: metadata['id'] as int?,
        artworkPath: metadata['artworkPath'] as String?,
        thumbnailPath: metadata['thumbnailPath'] as String?,
        artworkWidth: metadata['artworkWidth'] as int?,
        artworkHeight: metadata['artworkHeight'] as int?,
        durationMillis: metadata['duration'] as int?,
        lastModifiedTime: metadata['lastModifiedTime'] as int?,
      ),
    );

    final key = '${title.toLowerCase()}::${artist.toLowerCase()}';
    groups.putIfAbsent(key, () => <Map<String, Object?>>[]).add(song);
  }

  final albums =
      groups.entries
          .map((entry) {
            final sortedSongs = List<Map<String, Object?>>.from(entry.value)
              ..sort(_compareAlbumSongs);
            final representativeSong = sortedSongs.firstWhere(
              (song) => _hasArtwork(song),
              orElse: () => sortedSongs.first,
            );
            final totalDurationMillis = sortedSongs.fold<int>(
              0,
              (sum, song) => sum + (_songDuration(song) ?? 0),
            );

            return <String, Object?>{
              'id': entry.key,
              'title': _songAlbum(sortedSongs.first),
              'artist': _songArtist(sortedSongs.first),
              'songs': sortedSongs,
              'representativeSong': representativeSong,
              'totalDurationMillis': totalDurationMillis,
            };
          })
          .toList(growable: false)
        ..sort((a, b) {
          final leftArtist = a['artist'] as String? ?? 'Unknown Artist';
          final rightArtist = b['artist'] as String? ?? 'Unknown Artist';
          final artistCompare = leftArtist.toLowerCase().compareTo(
            rightArtist.toLowerCase(),
          );
          if (artistCompare != 0) return artistCompare;
          final leftTitle = a['title'] as String? ?? 'Unknown Album';
          final rightTitle = b['title'] as String? ?? 'Unknown Album';
          return leftTitle.toLowerCase().compareTo(rightTitle.toLowerCase());
        });

  return albums;
}

List<AlbumSummary> _hydrateAlbumSummaries(List<Map<String, Object?>> payloads) {
  return payloads.map(_albumSummaryFromPayload).toList(growable: false);
}

AlbumSummary _albumSummaryFromPayload(Map<String, Object?> payload) {
  final songs = (payload['songs'] as List)
      .cast<Map<String, Object?>>()
      .map(_musicFileFromPayload)
      .toList(growable: false);
  return AlbumSummary(
    id: payload['id'] as String? ?? '',
    title: payload['title'] as String? ?? 'Unknown Album',
    artist: payload['artist'] as String? ?? 'Unknown Artist',
    songs: songs,
    representativeSong: _musicFileFromPayload(
      payload['representativeSong'] as Map<String, Object?>,
    ),
    totalDurationMillis: payload['totalDurationMillis'] as int? ?? 0,
  );
}

Map<String, Object?> _musicFileToPayload(MusicFile song) {
  return {
    'path': song.path,
    'name': song.name,
    'title': song.title,
    'artist': song.artist,
    'album': song.album,
    'trackNumber': song.trackNumber,
    'id': song.id,
    'artworkPath': song.artworkPath,
    'thumbnailPath': song.thumbnailPath,
    'artworkWidth': song.artworkWidth,
    'artworkHeight': song.artworkHeight,
    'durationMillis': song.durationMillis,
    'lastModifiedTime': song.lastModifiedTime,
  };
}

MusicFile _musicFileFromPayload(Map<String, Object?> payload) {
  return MusicFile(
    path: payload['path'] as String? ?? '',
    name: payload['name'] as String? ?? '',
    title: payload['title'] as String?,
    artist: payload['artist'] as String?,
    album: payload['album'] as String?,
    trackNumber: payload['trackNumber'] as int?,
    id: payload['id'] as int?,
    artworkPath: payload['artworkPath'] as String?,
    thumbnailPath: payload['thumbnailPath'] as String?,
    artworkWidth: payload['artworkWidth'] as int?,
    artworkHeight: payload['artworkHeight'] as int?,
    durationMillis: payload['durationMillis'] as int?,
    lastModifiedTime: payload['lastModifiedTime'] as int?,
  );
}

String _songAlbum(Map<String, Object?> payload) {
  return payload['album'] as String? ?? 'Unknown Album';
}

String _songArtist(Map<String, Object?> payload) {
  return payload['artist'] as String? ?? 'Unknown Artist';
}

int? _songDuration(Map<String, Object?> payload) {
  return payload['durationMillis'] as int?;
}

bool _hasArtwork(Map<String, Object?> payload) {
  final hasThumbnail =
      (payload['thumbnailPath'] as String?)?.isNotEmpty ?? false;
  final hasArtwork = (payload['artworkPath'] as String?)?.isNotEmpty ?? false;
  return hasThumbnail || hasArtwork;
}

int _compareAlbumSongs(Map<String, Object?> a, Map<String, Object?> b) {
  final leftTrack = a['trackNumber'] as int?;
  final rightTrack = b['trackNumber'] as int?;
  if (leftTrack != null && rightTrack != null && leftTrack != rightTrack) {
    return leftTrack.compareTo(rightTrack);
  }
  if (leftTrack != null && rightTrack == null) return -1;
  if (leftTrack == null && rightTrack != null) return 1;

  final titleCompare = _songDisplayName(
    a,
  ).toLowerCase().compareTo(_songDisplayName(b).toLowerCase());
  if (titleCompare != 0) return titleCompare;
  return (_songPath(a)).toLowerCase().compareTo(_songPath(b).toLowerCase());
}

String _cleanMetadataText(String? value, {required String fallback}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return fallback;
  }
  return trimmed;
}

String _songDisplayName(Map<String, Object?> payload) {
  final title = payload['title'] as String?;
  if (title != null && title.trim().isNotEmpty) {
    return title;
  }
  return p.basenameWithoutExtension(_songPath(payload));
}

String _songPath(Map<String, Object?> payload) {
  return payload['path'] as String? ?? '';
}
