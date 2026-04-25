import 'package:audio_core/audio_core.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'metadata_database.dart';
import 'theme_color_helper.dart';

class TrackArtworkThemeResult {
  const TrackArtworkThemeResult({
    required this.path,
    required this.artworkPath,
    required this.thumbnailPath,
    required this.artworkWidth,
    required this.artworkHeight,
    required this.themeColorsBlob,
    required this.artworkFound,
  });

  final String path;
  final String? artworkPath;
  final String? thumbnailPath;
  final int? artworkWidth;
  final int? artworkHeight;
  final Uint8List? themeColorsBlob;
  final bool artworkFound;

  static bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

  bool get hasThumbnailPath => _hasText(thumbnailPath);

  bool get hasArtworkPath => _hasText(artworkPath) || hasThumbnailPath;

  bool get hasThemeColors =>
      themeColorsBlob != null && themeColorsBlob!.isNotEmpty;

  bool get hasCompleteData => hasThumbnailPath && hasThemeColors;

  TrackArtworkThemeResult copyWith({
    String? artworkPath,
    String? thumbnailPath,
    int? artworkWidth,
    int? artworkHeight,
    Uint8List? themeColorsBlob,
    bool? artworkFound,
  }) {
    return TrackArtworkThemeResult(
      path: path,
      artworkPath: artworkPath ?? this.artworkPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      artworkWidth: artworkWidth ?? this.artworkWidth,
      artworkHeight: artworkHeight ?? this.artworkHeight,
      themeColorsBlob: themeColorsBlob ?? this.themeColorsBlob,
      artworkFound: artworkFound ?? this.artworkFound,
    );
  }

  static TrackArtworkThemeResult? fromMetadata(
    String path,
    SongMetadata? metadata,
  ) {
    if (metadata == null) return null;

    final artworkPath = _hasText(metadata.artworkPath)
        ? metadata.artworkPath
        : null;
    final thumbnailPath = _hasText(metadata.thumbnailPath)
        ? metadata.thumbnailPath
        : null;
    final themeColorsBlob = metadata.themeColorsBlob;
    final artworkFound = artworkPath != null || thumbnailPath != null;

    if (!artworkFound && (themeColorsBlob == null || themeColorsBlob.isEmpty)) {
      return null;
    }

    return TrackArtworkThemeResult(
      path: path,
      artworkPath: artworkPath,
      thumbnailPath: thumbnailPath,
      artworkWidth: metadata.artworkWidth,
      artworkHeight: metadata.artworkHeight,
      themeColorsBlob: themeColorsBlob,
      artworkFound: artworkFound,
    );
  }

  SongMetadata toSongMetadata({SongMetadata? base}) {
    final resolvedBase =
        base ??
        SongMetadata(
          path: path,
          title: p.basenameWithoutExtension(path),
          album: 'Unknown Album',
          artist: 'Unknown Artist',
        );

    return resolvedBase.copyWith(
      artworkPath: artworkPath ?? resolvedBase.artworkPath,
      thumbnailPath: thumbnailPath ?? resolvedBase.thumbnailPath,
      artworkWidth: artworkWidth ?? resolvedBase.artworkWidth,
      artworkHeight: artworkHeight ?? resolvedBase.artworkHeight,
      themeColorsBlob: themeColorsBlob ?? resolvedBase.themeColorsBlob,
    );
  }
}

class TrackArtworkThemeService {
  TrackArtworkThemeService({MetadataDatabase? db})
    : _db = db ?? MetadataDatabase();

  final MetadataDatabase _db;

  static final Map<String, Future<TrackArtworkThemeResult?>> _inFlight = {};

  Future<TrackArtworkThemeResult?> getTrackArtworkTheme(
    String path, {
    AudioCoreController? controller,
    String? cacheRootPath,
    bool saveLargeArtwork = true,
    int thumbnailSize = generatedArtworkThumbnailSize,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) return null;

    final cached = await _db.getSongMetadata(normalizedPath);
    final cachedResult = TrackArtworkThemeResult.fromMetadata(
      normalizedPath,
      cached,
    );
    if (cachedResult != null && cachedResult.hasCompleteData) {
      return cachedResult;
    }

    final inFlight = _inFlight[normalizedPath];
    if (inFlight != null) {
      return inFlight;
    }

    if (controller == null) {
      return cachedResult;
    }

    final resolvedCacheRootPath = (cacheRootPath?.trim().isNotEmpty ?? false)
        ? cacheRootPath!.trim()
        : (await getApplicationSupportDirectory()).path;

    final future = _resolveTrackArtworkTheme(
      path: normalizedPath,
      controller: controller,
      cacheRootPath: resolvedCacheRootPath,
      saveLargeArtwork: saveLargeArtwork,
      thumbnailSize: thumbnailSize,
      cached: cached,
    );

    _inFlight[normalizedPath] = future;
    try {
      return await future;
    } finally {
      if (_inFlight[normalizedPath] == future) {
        _inFlight.remove(normalizedPath);
      }
    }
  }

  Future<TrackArtworkThemeResult?> _resolveTrackArtworkTheme({
    required String path,
    required AudioCoreController controller,
    required String cacheRootPath,
    required bool saveLargeArtwork,
    required int thumbnailSize,
    required SongMetadata? cached,
  }) async {
    final baseMetadata =
        cached ??
        SongMetadata(
          path: path,
          title: p.basenameWithoutExtension(path),
          album: 'Unknown Album',
          artist: 'Unknown Artist',
        );

    try {
      final artwork = await controller.generateTrackArtwork(
        path: path,
        cacheRootPath: cacheRootPath,
        saveLargeArtwork: saveLargeArtwork,
        thumbnailSize: thumbnailSize,
      );

      if (!artwork.artworkFound &&
          !(artwork.thumbnailPath?.trim().isNotEmpty ?? false) &&
          (artwork.themeColorsBlob == null ||
              artwork.themeColorsBlob!.isEmpty)) {
        return TrackArtworkThemeResult.fromMetadata(path, cached);
      }

      final resolvedMetadata = baseMetadata.copyWith(
        artworkPath: artwork.artworkPath ?? baseMetadata.artworkPath,
        thumbnailPath: artwork.thumbnailPath ?? baseMetadata.thumbnailPath,
        artworkWidth: artwork.artworkWidth ?? baseMetadata.artworkWidth,
        artworkHeight: artwork.artworkHeight ?? baseMetadata.artworkHeight,
        themeColorsBlob:
            artwork.themeColorsBlob ?? baseMetadata.themeColorsBlob,
      );

      await _db.insertOrUpdateSong(resolvedMetadata);

      return TrackArtworkThemeResult.fromMetadata(path, resolvedMetadata) ??
          TrackArtworkThemeResult(
            path: path,
            artworkPath: resolvedMetadata.artworkPath,
            thumbnailPath: resolvedMetadata.thumbnailPath,
            artworkWidth: resolvedMetadata.artworkWidth,
            artworkHeight: resolvedMetadata.artworkHeight,
            themeColorsBlob: resolvedMetadata.themeColorsBlob,
            artworkFound: artwork.artworkFound,
          );
    } catch (e) {
      debugPrint('TrackArtworkThemeService failed for $path: $e');
      return TrackArtworkThemeResult.fromMetadata(path, cached);
    }
  }

  static Future<Uint8List?> generateThemeColorsBlob({
    Uint8List? bytes,
    String? path,
    bool useMaster = false,
  }) async {
    if ((bytes == null || bytes.isEmpty) &&
        (path == null || path.trim().isEmpty)) {
      return null;
    }

    try {
      final palette = useMaster
          ? await ThemeColorHelper.generatePaletteMaster(
              bytes: bytes,
              path: path,
            )
          : await ThemeColorHelper.generatePalette(bytes: bytes, path: path);
      if (palette.colorsMap.isEmpty) return null;
      return ThemeColorHelper.colorsMapToBlob(palette.colorsMap);
    } catch (e) {
      debugPrint('TrackArtworkThemeService palette generation failed: $e');
      return null;
    }
  }

  static Future<Uint8List?> generateThemeColorsBlobFromImage(
    img.Image image, {
    bool useMaster = false,
  }) async {
    if (image.width <= 0 || image.height <= 0) {
      return null;
    }

    try {
      final encoded = Uint8List.fromList(img.encodePng(image));
      return generateThemeColorsBlob(bytes: encoded, useMaster: useMaster);
    } catch (e) {
      debugPrint('TrackArtworkThemeService image palette failed: $e');
      return null;
    }
  }
}
