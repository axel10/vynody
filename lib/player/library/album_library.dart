import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/library_catalog.dart';
import 'package:vynody/player/metadata/metadata_database.dart';

/// 专辑列表 Provider：从 [libraryCatalogProvider] 派生，
/// 自身不再订阅 songs 表，因此不会重复付出全表查询与反序列化。
final albumLibraryProvider = StreamProvider<List<AlbumSummary>>(
  (ref) => catalogDerived(ref, (catalog) => catalog.albums),
);

/// 专辑聚合实现：同时被曲库快照与 `audio_service` 的「播放下一张专辑」复用。
List<AlbumSummary> buildAlbumSummaries(Iterable<SongMetadata> songs) {
  final validEntries = <(SongMetadata, MusicFile)>[];

  for (final metadata in songs) {
    final flags = metadata.sourceFlags ?? 0;
    if ((flags & SongSourceFlags.external) != 0) continue;
    final path = metadata.path;
    if (path.isEmpty) continue;

    final title = _cleanMetadataText(
      metadata.album,
      fallback: 'Unknown Album',
    );
    final rawAlbumArtist = metadata.albumArtist?.trim();
    final artist = _cleanMetadataText(
      metadata.artist,
      fallback: 'Unknown Artist',
    );
    final albumArtist = (rawAlbumArtist != null && rawAlbumArtist.isNotEmpty)
        ? rawAlbumArtist
        : null;

    final song = MusicFile(
      path: path,
      name: p.basename(path),
      title: _cleanMetadataText(
        metadata.title,
        fallback: 'Unknown',
      ),
      artist: artist,
      albumArtist: albumArtist,
      album: title,
      trackNumber: metadata.trackNumber,
      id: metadata.id,
      artworkPath: metadata.artworkPath,
      thumbnailPath: metadata.thumbnailPath,
      artworkWidth: metadata.artworkWidth,
      artworkHeight: metadata.artworkHeight,
      durationMillis: metadata.duration,
      lastModifiedTime: metadata.lastModifiedTime,
      year: metadata.year,
      genres: metadata.genres,
    );

    validEntries.add((metadata, song));
  }

  // Pre-group by directory and album to determine effective album artist if missing
  final folderAlbumToArtist = <String, String>{};
  final folderAlbumArtists = <String, Map<String, int>>{};

  for (final (_, song) in validEntries) {
    final dir = p.dirname(song.path).toLowerCase();
    final albumKey = (song.album ?? 'Unknown Album').toLowerCase();
    final folderAlbumKey = '$dir::$albumKey';

    final declaredAlbumArtist = song.albumArtist?.trim();
    if (declaredAlbumArtist != null && declaredAlbumArtist.isNotEmpty) {
      folderAlbumToArtist[folderAlbumKey] = declaredAlbumArtist;
    } else {
      final counts = folderAlbumArtists.putIfAbsent(folderAlbumKey, () => <String, int>{});
      final trackArtist = song.artist ?? 'Unknown Artist';
      counts[trackArtist] = (counts[trackArtist] ?? 0) + 1;
    }
  }

  final groups = <String, List<MusicFile>>{};
  final groupArtists = <String, String>{};

  for (final (_, song) in validEntries) {
    final dir = p.dirname(song.path).toLowerCase();
    final title = song.album ?? 'Unknown Album';
    final albumKey = title.toLowerCase();
    final folderAlbumKey = '$dir::$albumKey';

    String effectiveArtist;
    if (song.albumArtist != null && song.albumArtist!.trim().isNotEmpty) {
      effectiveArtist = song.albumArtist!.trim();
    } else if (folderAlbumToArtist.containsKey(folderAlbumKey)) {
      effectiveArtist = folderAlbumToArtist[folderAlbumKey]!;
    } else if (folderAlbumArtists.containsKey(folderAlbumKey) && folderAlbumArtists[folderAlbumKey]!.isNotEmpty) {
      final counts = folderAlbumArtists[folderAlbumKey]!;
      effectiveArtist = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    } else {
      effectiveArtist = song.artist ?? 'Unknown Artist';
    }

    final key = '${title.toLowerCase()}::${effectiveArtist.toLowerCase()}';
    (groups[key] ??= []).add(song);
    groupArtists[key] = effectiveArtist;
  }

  final albums = groups.entries.map((entry) {
    final sortedSongs = List<MusicFile>.from(entry.value)..sort(_compareAlbumMusicFiles);
    final representativeSong = sortedSongs.firstWhere(
      (song) => _hasMusicFileArtwork(song),
      orElse: () => sortedSongs.first,
    );
    final totalDurationMillis = sortedSongs.fold<int>(
      0,
      (sum, song) => sum + (song.durationMillis ?? 0),
    );

    final albumYears = <int>{};
    final genreFreq = <String, int>{};
    for (final song in sortedSongs) {
      if (song.year != null && song.year! > 0) {
        albumYears.add(song.year!);
      }
      final songGenres = song.genres;
      if (songGenres != null) {
        for (final g in songGenres) {
          final trimmed = g.trim();
          if (trimmed.isNotEmpty) {
            genreFreq[trimmed] = (genreFreq[trimmed] ?? 0) + 1;
          }
        }
      }
    }

    final sortedGenres = genreFreq.keys.toList()
      ..sort((a, b) {
        final countCompare = genreFreq[b]!.compareTo(genreFreq[a]!);
        if (countCompare != 0) return countCompare;
        return a.compareTo(b);
      });

    final int? minYear = albumYears.isNotEmpty
        ? albumYears.reduce((a, b) => a < b ? a : b)
        : null;
    final int? maxYear = albumYears.isNotEmpty
        ? albumYears.reduce((a, b) => a > b ? a : b)
        : null;

    final albumArtist = groupArtists[entry.key] ??
        sortedSongs.first.albumArtist ??
        sortedSongs.first.artist ??
        'Unknown Artist';

    return AlbumSummary(
      id: entry.key,
      title: sortedSongs.first.album ?? 'Unknown Album',
      artist: albumArtist,
      songs: sortedSongs,
      representativeSong: representativeSong,
      totalDurationMillis: totalDurationMillis,
      genres: sortedGenres,
      minYear: minYear,
      maxYear: maxYear,
    );
  }).toList(growable: false)
    ..sort((a, b) {
      final artistCompare = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
      if (artistCompare != 0) return artistCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

  return albums;
}

bool _hasMusicFileArtwork(MusicFile song) {
  final hasThumbnail = song.thumbnailPath?.isNotEmpty ?? false;
  final hasArtwork = song.artworkPath?.isNotEmpty ?? false;
  return hasThumbnail || hasArtwork;
}

int _compareAlbumMusicFiles(MusicFile a, MusicFile b) {
  final leftTrack = a.trackNumber;
  final rightTrack = b.trackNumber;
  if (leftTrack != null && rightTrack != null && leftTrack != rightTrack) {
    return leftTrack.compareTo(rightTrack);
  }
  if (leftTrack != null && rightTrack == null) return -1;
  if (leftTrack == null && rightTrack != null) return 1;

  final titleCompare = (a.title ?? p.basenameWithoutExtension(a.path))
      .toLowerCase()
      .compareTo((b.title ?? p.basenameWithoutExtension(b.path)).toLowerCase());
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

