import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_taglib/flutter_taglib.dart' as taglib;

import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';

typedef CoverProbeFunction = Future<bool> Function(String filePath);
typedef CoverProbeFunctionSync = bool Function(String filePath);

/// Resolver responsible for determining representative songs for folders.
///
/// Features:
/// 1. Bottom-up post-order DFS traversal of directory trees.
/// 2. Deterministic sorting: songs are strictly sorted by Title ascending (fallback to filename ascending),
///    completely decoupled from dynamic user-defined UI sort criteria.
/// 3. Lazy short-circuit probing: probes `tagFile.hasCover` sequentially and immediately stops (breaks)
///    at the first song with artwork.
/// 4. Subtree inheritance: if a folder has no direct songs with artwork, it inherits the representative
///    song from its first child subfolder that has a representative song.
class FolderCoverResolver {
  const FolderCoverResolver._();

  /// Default synchronous probe function using lightweight `flutter_taglib` tag inspection.
  /// Does not decode or extract heavy image byte payloads.
  /// Best suited for execution within background worker isolates.
  static bool defaultProbeSongHasCoverSync(String filePath) {
    try {
      if (!taglib.TagLibFile.isSupported) {
        return false;
      }
      final tagFile = taglib.TagLibFile.open(filePath);
      if (tagFile == null) {
        return false;
      }
      try {
        return tagFile.hasCover;
      } finally {
        tagFile.close();
      }
    } catch (e) {
      debugPrint('[FolderCoverResolver] TagLib sync cover probe error for $filePath: $e');
      return false;
    }
  }

  /// Default probe function offloading TagLib FFI inspection to a background isolate
  /// so that it never blocks the Flutter UI thread / Main Isolate.
  static Future<bool> defaultProbeSongHasCover(String filePath) async {
    try {
      if (!taglib.TagLibFile.isSupported) {
        return false;
      }
      return await Isolate.run(() => defaultProbeSongHasCoverSync(filePath));
    } catch (e) {
      debugPrint('[FolderCoverResolver] TagLib cover probe error for $filePath: $e');
      return false;
    }
  }

  /// Strictly compares songs for folder cover resolution:
  /// 1. Prioritizes valid positive track numbers (trackNumber > 0) in ascending order.
  /// 2. If track numbers are identical or missing/non-positive, falls back to Title ascending (case-insensitive).
  /// 3. If titles are empty/missing, falls back to filename ascending.
  static int compareSongsForFolderCover(MusicFile a, MusicFile b) {
    final hasTrackA = a.trackNumber != null && a.trackNumber! > 0;
    final hasTrackB = b.trackNumber != null && b.trackNumber! > 0;

    if (hasTrackA && hasTrackB) {
      final trackCompare = a.trackNumber!.compareTo(b.trackNumber!);
      if (trackCompare != 0) {
        return trackCompare;
      }
    } else if (hasTrackA && !hasTrackB) {
      return -1;
    } else if (!hasTrackA && hasTrackB) {
      return 1;
    }

    final titleA = (a.title != null && a.title!.trim().isNotEmpty)
        ? a.title!.trim()
        : a.name;
    final titleB = (b.title != null && b.title!.trim().isNotEmpty)
        ? b.title!.trim()
        : b.name;
    return titleA.toLowerCase().compareTo(titleB.toLowerCase());
  }

  /// Alias for backward compatibility.
  static int compareSongsByTitle(MusicFile a, MusicFile b) => compareSongsForFolderCover(a, b);

  /// Strictly compares folders by Name ascending (case-insensitive).
  static int compareFoldersByName(MusicFolder a, MusicFolder b) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  /// Evaluates representative song for a single folder [folder].
  ///
  /// Evaluates files sorted strictly by track number then title ascending, probing each file lazily
  /// until the first song with a cover is found.
  /// If no direct files have a cover, returns the first subfolder's representative song
  /// in deterministic folder name ascending order.
  static Future<MusicFile?> evaluateRepresentativeSongForFolder(
    MusicFolder folder, {
    CoverProbeFunction probeCover = defaultProbeSongHasCover,
  }) async {
    if (folder.files.isNotEmpty) {
      final sortedFiles = List<MusicFile>.from(folder.files)
        ..sort(compareSongsForFolderCover);

      for (final file in sortedFiles) {
        // Fast-path: if the in-memory object already has known artwork bytes or paths or hasArtwork flag, accept immediately
        if ((file.artworkPath != null && file.artworkPath!.isNotEmpty) ||
            (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) ||
            (file.artworkBytes != null && file.artworkBytes!.isNotEmpty) ||
            file.hasArtwork == true) {
          return file;
        }

        // If file is known to have no artwork, skip probing
        if (file.hasArtwork == false) {
          continue;
        }

        // Lazy short-circuit TagLib probing
        final hasCover = await probeCover(file.path);
        if (hasCover) {
          return file;
        }
      }
    }

    // Priority 2: Subfolder representative (evaluated in deterministic name ascending order)
    if (folder.subFolders.isNotEmpty) {
      final sortedSubFolders = List<MusicFolder>.from(folder.subFolders)
        ..sort(compareFoldersByName);
      for (final sub in sortedSubFolders) {
        final subRep = sub.representativeSongCache;
        if (subRep != null) {
          return subRep;
        }
      }
    }

    return null;
  }

  /// Evaluates representative song for a single folder [folder] synchronously.
  static MusicFile? evaluateRepresentativeSongForFolderSync(
    MusicFolder folder, {
    CoverProbeFunctionSync probeCoverSync = defaultProbeSongHasCoverSync,
  }) {
    if (folder.files.isNotEmpty) {
      final sortedFiles = List<MusicFile>.from(folder.files)
        ..sort(compareSongsForFolderCover);

      for (final file in sortedFiles) {
        if ((file.artworkPath != null && file.artworkPath!.isNotEmpty) ||
            (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) ||
            (file.artworkBytes != null && file.artworkBytes!.isNotEmpty) ||
            file.hasArtwork == true) {
          return file;
        }

        if (file.hasArtwork == false) {
          continue;
        }

        final hasCover = probeCoverSync(file.path);
        if (hasCover) {
          return file;
        }
      }
    }

    if (folder.subFolders.isNotEmpty) {
      final sortedSubFolders = List<MusicFolder>.from(folder.subFolders)
        ..sort(compareFoldersByName);
      for (final sub in sortedSubFolders) {
        final subRep = sub.representativeSongCache;
        if (subRep != null) {
          return subRep;
        }
      }
    }

    return null;
  }

  /// Computes representative songs for all folders in the subtree rooted at [root]
  /// synchronously using a bottom-up (post-order DFS) traversal.
  ///
  /// Returns a map of `normalizedFolderPath -> normalizedSongPath`.
  static Map<String, String> computeFolderCoversBottomUpSync(
    MusicFolder root, {
    CoverProbeFunctionSync probeCoverSync = defaultProbeSongHasCoverSync,
    String Function(String path)? normalizePath,
  }) {
    final result = <String, String>{};
    final normalize = normalizePath ?? (p) => p;

    MusicFile? postOrder(MusicFolder folder) {
      MusicFile? firstSubRep;
      if (folder.subFolders.isNotEmpty) {
        final sortedSubFolders = List<MusicFolder>.from(folder.subFolders)
          ..sort(compareFoldersByName);
        for (final sub in sortedSubFolders) {
          final subRep = postOrder(sub);
          firstSubRep ??= subRep;
        }
      }

      MusicFile? directRep;
      if (folder.files.isNotEmpty) {
        final sortedFiles = List<MusicFile>.from(folder.files)
          ..sort(compareSongsForFolderCover);

        for (final file in sortedFiles) {
          if ((file.artworkPath != null && file.artworkPath!.isNotEmpty) ||
              (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) ||
              (file.artworkBytes != null && file.artworkBytes!.isNotEmpty) ||
              file.hasArtwork == true) {
            directRep = file;
            break;
          }

          if (file.hasArtwork == false) {
            continue;
          }

          final hasCover = probeCoverSync(file.path);
          if (hasCover) {
            directRep = file;
            break;
          }
        }
      }

      final selected = directRep ?? firstSubRep;
      if (selected != null) {
        folder.representativeSongCache = selected;
        final normFolder = normalize(folder.path);
        final normSong = normalize(selected.path);
        result[normFolder] = normSong;
      } else {
        folder.representativeSongCache = null;
      }

      return selected;
    }

    postOrder(root);
    return result;
  }

  /// Computes representative songs for all folders in the subtree rooted at [root]
  /// using a bottom-up (post-order DFS) traversal.
  ///
  /// Returns a map of `normalizedFolderPath -> normalizedSongPath`.
  static Future<Map<String, String>> computeFolderCoversBottomUp(
    MusicFolder root, {
    CoverProbeFunction probeCover = defaultProbeSongHasCover,
    String Function(String path)? normalizePath,
  }) async {
    final result = <String, String>{};
    final normalize = normalizePath ?? (p) => p;

    Future<MusicFile?> postOrder(MusicFolder folder) async {
      // 1. Recurse into all subfolders first (bottom-up post-order DFS in deterministic name ascending order)
      MusicFile? firstSubRep;
      if (folder.subFolders.isNotEmpty) {
        final sortedSubFolders = List<MusicFolder>.from(folder.subFolders)
          ..sort(compareFoldersByName);
        for (final sub in sortedSubFolders) {
          final subRep = await postOrder(sub);
          firstSubRep ??= subRep;
        }
      }

      // 2. Evaluate direct files with deterministic title ascending order and short-circuit probe
      MusicFile? directRep;
      if (folder.files.isNotEmpty) {
        final sortedFiles = List<MusicFile>.from(folder.files)
          ..sort(compareSongsForFolderCover);

        for (final file in sortedFiles) {
          if ((file.artworkPath != null && file.artworkPath!.isNotEmpty) ||
              (file.thumbnailPath != null && file.thumbnailPath!.isNotEmpty) ||
              (file.artworkBytes != null && file.artworkBytes!.isNotEmpty) ||
              file.hasArtwork == true) {
            directRep = file;
            break;
          }

          if (file.hasArtwork == false) {
            continue;
          }

          final hasCover = await probeCover(file.path);
          if (hasCover) {
            directRep = file;
            break; // Short-circuit: stop probing remaining files in this folder
          }
        }
      }

      // 3. Current folder direct file with cover has higher priority than subfolder
      final selected = directRep ?? firstSubRep;

      if (selected != null) {
        folder.representativeSongCache = selected;
        final normFolder = normalize(folder.path);
        final normSong = normalize(selected.path);
        result[normFolder] = normSong;
      } else {
        folder.representativeSongCache = null;
      }

      return selected;
    }

    await postOrder(root);
    return result;
  }

  /// Computes representative songs for multiple root folders completely in a background isolate.
  /// Returns a unified map of `folderPath -> representativeSongPath`.
  static Future<Map<String, String>> computeAllFolderCoversInBackground(
    List<MusicFolder> rootFolders,
  ) async {
    if (rootFolders.isEmpty) {
      return const <String, String>{};
    }
    return await compute(_computeAllFolderCoversWorker, rootFolders);
  }
}

/// Top-level worker function for background isolate computation.
Map<String, String> _computeAllFolderCoversWorker(List<MusicFolder> folders) {
  final allCovers = <String, String>{};
  for (final root in folders) {
    final covers = FolderCoverResolver.computeFolderCoversBottomUpSync(
      root,
      probeCoverSync: FolderCoverResolver.defaultProbeSongHasCoverSync,
    );
    allCovers.addAll(covers);
  }
  return allCovers;
}
