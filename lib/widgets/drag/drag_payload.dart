import 'dart:io';

import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/remote_server_models.dart';

/// Kinds of remote (Navidrome / Jellyfin) collections that can be dragged.
enum RemoteCollectionKind {
  album('album'),
  artist('artist'),
  playlist('playlist');

  const RemoteCollectionKind(this.slug);

  final String slug;

  static RemoteCollectionKind? fromSlug(String slug) {
    for (final kind in RemoteCollectionKind.values) {
      if (kind.slug == slug) return kind;
    }
    return null;
  }
}

/// A reference to one remote library collection.
///
/// This class owns the *only* definition of the `subsonic-album://<serverId>/<id>`
/// virtual path format. That virtual path is the transport for remote drags:
/// the standalone queue window runs in a separate isolate and other
/// applications share no memory with us, so the reference has to travel as a
/// string. Encode with [toVirtualPath] and decode with [tryParse] — never
/// hand-roll `startsWith` checks against the scheme again.
class RemoteCollectionRef {
  const RemoteCollectionRef({
    required this.serverType,
    required this.serverId,
    required this.kind,
    required this.id,
  });

  final RemoteServerType serverType;
  final String serverId;
  final RemoteCollectionKind kind;
  final String id;

  static const _jellyfinPrefix = 'jellyfin';
  static const _subsonicPrefix = 'subsonic';

  String get scheme => serverType == RemoteServerType.jellyfin
      ? '$_jellyfinPrefix-${kind.slug}'
      : '$_subsonicPrefix-${kind.slug}';

  String toVirtualPath() => '$scheme://$serverId/$id';

  /// Decodes a virtual path produced by [toVirtualPath].
  ///
  /// Returns `null` for anything that is not a remote *collection* reference —
  /// notably per-track remote URIs (`subsonic://…`, handled by
  /// [RemoteMediaResolver]) and ordinary local file paths.
  static RemoteCollectionRef? tryParse(String raw) {
    if (raw.isEmpty) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    final scheme = uri.scheme;
    final separator = scheme.indexOf('-');
    if (separator <= 0) return null;

    final prefix = scheme.substring(0, separator);
    final serverType = switch (prefix) {
      _jellyfinPrefix => RemoteServerType.jellyfin,
      _subsonicPrefix => RemoteServerType.subsonic,
      _ => null,
    };
    if (serverType == null) return null;

    final kind = RemoteCollectionKind.fromSlug(scheme.substring(separator + 1));
    if (kind == null) return null;

    final serverId = uri.host;
    final id = uri.pathSegments.join('/');
    if (serverId.isEmpty || id.isEmpty) return null;

    return RemoteCollectionRef(
      serverType: serverType,
      serverId: serverId,
      kind: kind,
      id: id,
    );
  }

  @override
  String toString() => toVirtualPath();
}

/// Everything a drag source needs to describe what is being dragged.
///
/// There are two transport channels and this class is the single place that
/// fills both:
/// * [localData] — structured, only readable inside this isolate. Used as a
///   fast path by `DropDataUtils.extractPathsFromDrop` and as the marker that
///   tells the global backdrop target a drag is internal.
/// * [publish] — the file/URI/text formats handed to the native drag session,
///   which is what survives into other windows and other applications.
sealed class DragPayload {
  const DragPayload();

  /// In-memory payload for same-isolate drops.
  Map<String, dynamic> get localData;

  /// Adds the system-level representations other windows and applications read.
  void publish(DragItem item);

  DragItem toDragItem() {
    final item = DragItem(localData: localData);
    publish(item);
    return item;
  }
}

/// One or more local (or remote per-track) files.
///
/// When [paths] holds more than one entry the drag is published as plain text
/// only: a multi-file `fileUri` has no useful meaning for external targets.
class SongPathsPayload extends DragPayload {
  const SongPathsPayload({required this.paths});

  /// Builds a payload out of several song collections (the songs of every
  /// selected artist, genre or year), keeping one path per song, in selection
  /// order, with duplicates collapsed so a song shared by two collections is not
  /// queued twice.
  factory SongPathsPayload.flattened(Iterable<Iterable<MusicFile>> groups) {
    final paths = <String>{};
    for (final group in groups) {
      for (final song in group) {
        paths.add(song.path);
      }
    }
    return SongPathsPayload(paths: paths.toList());
  }

  final List<String> paths;

  @override
  Map<String, dynamic> get localData => {
        if (paths.length == 1) 'path': paths.first,
        'paths': paths,
      };

  @override
  void publish(DragItem item) {
    if (paths.isEmpty) return;

    final first = paths.first;
    if (_isRemotePath(first)) {
      // Single remote track: hand over the stream URL. A batch of remote
      // tracks is only meaningful to our own windows, so text is enough.
      if (paths.length == 1) {
        final uri = Uri.tryParse(first);
        if (uri != null) item.add(Formats.uri(NamedUri(uri)));
      }
    } else if (File(first).existsSync()) {
      item.add(Formats.fileUri(Uri.file(first)));
    }

    item.add(Formats.plainText(paths.join('\n')));
  }

  static bool _isRemotePath(String path) =>
      RemoteMediaResolver.isRemoteUri(path) ||
      path.startsWith('http://') ||
      path.startsWith('https://');
}

/// A folder, published as the folder itself so external targets receive the
/// directory rather than its individual tracks.
class FolderDragPayload extends DragPayload {
  const FolderDragPayload({
    required this.folderPath,
    required this.songPaths,
  });

  /// Local directory, the `system` sentinel, or a remote URI.
  final String folderPath;

  /// Resolved tracks, used for in-isolate drops where the receiver wants the
  /// songs rather than a path it would have to re-scan.
  final List<String> songPaths;

  @override
  Map<String, dynamic> get localData => {
        'path': folderPath,
        if (songPaths.isNotEmpty) 'paths': songPaths,
      };

  @override
  void publish(DragItem item) {
    if (_isLocalDirectory(folderPath)) {
      item.add(Formats.fileUri(Uri.file(folderPath)));
      item.add(Formats.plainText(folderPath));
      return;
    }

    if (songPaths.isNotEmpty) {
      final first = songPaths.first;
      if (!RemoteMediaResolver.isRemoteUri(first) && File(first).existsSync()) {
        item.add(Formats.fileUri(Uri.file(first)));
      }
      item.add(Formats.plainText(songPaths.join('\n')));
      return;
    }

    item.add(Formats.plainText(folderPath));
    final uri = Uri.tryParse(folderPath);
    if (uri != null) {
      item.add(Formats.uri(NamedUri(uri)));
    }
  }

  static bool _isLocalDirectory(String path) {
    if (path.isEmpty || path == 'system') return false;
    if (RemoteMediaResolver.isRemoteUri(path)) return false;
    return Directory(path).existsSync();
  }
}

/// One or more remote library collections (album / artist / playlist).
class RemoteCollectionPayload extends DragPayload {
  const RemoteCollectionPayload(this.refs);

  final List<RemoteCollectionRef> refs;

  int get count => refs.length;

  List<String> get virtualPaths => [
        for (final ref in refs) ref.toVirtualPath(),
      ];

  @override
  Map<String, dynamic> get localData => {'paths': virtualPaths};

  @override
  void publish(DragItem item) {
    if (refs.isEmpty) return;

    final uri = Uri.tryParse(virtualPaths.first);
    if (uri != null) {
      item.add(Formats.uri(NamedUri(uri)));
    }
    item.add(Formats.plainText(virtualPaths.join('\n')));
  }
}
