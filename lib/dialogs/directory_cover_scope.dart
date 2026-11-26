import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';

enum DirectoryCoverEligibilityReason {
  eligible,
  externalOrRemote,
  singleTrack,
  inconsistentOrEmptyAlbum,
}

class DirectoryCoverScope {
  const DirectoryCoverScope({
    required this.reason,
    this.albumName,
    this.siblingSongs = const [],
  });

  final DirectoryCoverEligibilityReason reason;
  final String? albumName;
  final List<SongMetadata> siblingSongs;

  bool get isEligible =>
      reason == DirectoryCoverEligibilityReason.eligible &&
      siblingSongs.isNotEmpty;
}

String _normalizeDirEvalPath(String rawPath) {
  var normalized = rawPath.trim().replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _dirEvalPathsEqual(String a, String b, {required bool caseInsensitive}) {
  final na = _normalizeDirEvalPath(a);
  final nb = _normalizeDirEvalPath(b);
  return caseInsensitive ? na.toLowerCase() == nb.toLowerCase() : na == nb;
}

/// Evaluates whether the current song's directory is eligible for batch cover
/// application (all library songs in the same folder share the same non-empty
/// album name, and there is at least one sibling song).
DirectoryCoverScope evaluateDirectoryCoverScope({
  required String songPath,
  required Map<String, SongMetadata> metadataMap,
  String? unknownAlbumLabel,
  bool? isWindowsOverride,
}) {
  final trimmedPath = songPath.trim();
  if (trimmedPath.isEmpty ||
      RemoteMediaResolver.isRemoteUri(trimmedPath) ||
      trimmedPath.startsWith('content://')) {
    return const DirectoryCoverScope(
      reason: DirectoryCoverEligibilityReason.externalOrRemote,
    );
  }

  final caseInsensitive = isWindowsOverride ?? Platform.isWindows;
  SongMetadata? currentMeta = metadataMap[songPath] ?? metadataMap[trimmedPath];
  if (currentMeta == null) {
    for (final entry in metadataMap.entries) {
      if (_dirEvalPathsEqual(
        entry.key,
        trimmedPath,
        caseInsensitive: caseInsensitive,
      )) {
        currentMeta = entry.value;
        break;
      }
    }
  }

  if (currentMeta == null ||
      ((currentMeta.sourceFlags ?? 0) & SongSourceFlags.external) != 0) {
    return const DirectoryCoverScope(
      reason: DirectoryCoverEligibilityReason.externalOrRemote,
    );
  }

  final normalizedSongPath = _normalizeDirEvalPath(currentMeta.path);
  final targetDir = p.posix.dirname(normalizedSongPath);

  final dirSongs = <SongMetadata>[];
  for (final meta in metadataMap.values) {
    final pTrimmed = meta.path.trim();
    if (pTrimmed.isEmpty ||
        RemoteMediaResolver.isRemoteUri(pTrimmed) ||
        pTrimmed.startsWith('content://')) {
      continue;
    }
    if (((meta.sourceFlags ?? 0) & SongSourceFlags.external) != 0) {
      continue;
    }
    final dir = p.posix.dirname(_normalizeDirEvalPath(pTrimmed));
    if (_dirEvalPathsEqual(dir, targetDir, caseInsensitive: caseInsensitive)) {
      dirSongs.add(meta);
    }
  }

  if (dirSongs.length < 2) {
    return const DirectoryCoverScope(
      reason: DirectoryCoverEligibilityReason.singleTrack,
    );
  }

  final unknownTrimmed = unknownAlbumLabel?.trim();
  String? sharedAlbum;
  for (final meta in dirSongs) {
    final album = meta.album.trim();
    if (album.isEmpty ||
        (unknownTrimmed != null &&
            unknownTrimmed.isNotEmpty &&
            album == unknownTrimmed)) {
      return const DirectoryCoverScope(
        reason: DirectoryCoverEligibilityReason.inconsistentOrEmptyAlbum,
      );
    }
    if (sharedAlbum == null) {
      sharedAlbum = album;
    } else if (album != sharedAlbum) {
      return const DirectoryCoverScope(
        reason: DirectoryCoverEligibilityReason.inconsistentOrEmptyAlbum,
      );
    }
  }

  final siblings = dirSongs
      .where(
        (m) => !_dirEvalPathsEqual(
          m.path,
          currentMeta!.path,
          caseInsensitive: caseInsensitive,
        ),
      )
      .toList(growable: false);

  if (siblings.isEmpty) {
    return const DirectoryCoverScope(
      reason: DirectoryCoverEligibilityReason.singleTrack,
    );
  }

  return DirectoryCoverScope(
    reason: DirectoryCoverEligibilityReason.eligible,
    albumName: sharedAlbum,
    siblingSongs: siblings,
  );
}
