import 'dart:io';

/// Returns the first candidate that points at an existing local file.
///
/// Drag previews are snapshotted the instant a drag starts, which means only
/// files already on disk can be shown — a remote artwork URL is never an
/// option here (it would still be loading when the snapshot is taken).
/// Callers pass the same paths their list tile uses, in priority order.
String? resolveDragCoverPath({
  String? cachedImagePath,
  String? thumbnailPath,
  String? artworkPath,
}) {
  for (final path in [cachedImagePath, thumbnailPath, artworkPath]) {
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return path;
    }
  }
  return null;
}
