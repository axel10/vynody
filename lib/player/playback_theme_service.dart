import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'metadata_database.dart';
import 'metadata_helper.dart';
import 'settings_service.dart';
import 'theme_color_helper.dart';

class PlaybackThemeService extends ChangeNotifier {
  final SettingsService settingsService;
  final MetadataDatabase _db = MetadataDatabase();

  Color? _dynamicStartColor;
  Color? _dynamicEndColor;
  Map<String, Color> _currentThemeColorsMap = const {};
  Uint8List? _currentBlurredArtworkBytes;

  final Map<String, Uint8List> _blurredArtworkCache = {};
  static const int _maxBlurredCacheSize = 20;

  Color? get dynamicStartColor => _dynamicStartColor;
  Color? get dynamicEndColor => _dynamicEndColor;
  Map<String, Color> get currentThemeColorsMap => _currentThemeColorsMap;
  Uint8List? get currentBlurredArtworkBytes => _currentBlurredArtworkBytes;

  PlaybackThemeService(this.settingsService);

  void updateFromThemeColors(Map<String, Color> colors) {
    _applyThemeColors(colors);
    notifyListeners();
  }

  void _applyThemeColors(Map<String, Color> colors) {
    _currentThemeColorsMap = colors;
    _dynamicStartColor = colors['dominant'] ?? colors['vibrant'];
    _dynamicEndColor = (colors['vibrant']?.withValues(alpha: 0.8)) ?? colors['muted'];
  }

  Future<void> updateCurrentArtwork(String? path, Uint8List? bytes) async {
    if (path == null) {
      _currentBlurredArtworkBytes = null;
      notifyListeners();
      return;
    }

    if (_blurredArtworkCache.containsKey(path)) {
      _currentBlurredArtworkBytes = _blurredArtworkCache[path];
      notifyListeners();
    } else if (bytes != null) {
      unawaited(_processBlurForPath(path, bytes));
    }
  }

  Future<void> _processBlurForPath(String path, Uint8List bytes) async {
    if (_blurredArtworkCache.containsKey(path)) return;

    final blurred = await MetadataHelper.blurImage(bytes);
    if (blurred != null) {
      _blurredArtworkCache[path] = blurred;
      if (_blurredArtworkCache.length > _maxBlurredCacheSize) {
        _blurredArtworkCache.remove(_blurredArtworkCache.keys.first);
      }
      _currentBlurredArtworkBytes = blurred;
      notifyListeners();
    }
  }

  Future<void> updatePalette({
    required String? filePath,
    required Uint8List? artworkBytes,
    required String? artworkPath,
    SongMetadata? metadata,
  }) async {
    if (!settingsService.isVisualizerDynamicColor &&
        !settingsService.isVisualizerDynamicStartColor &&
        !settingsService.isVisualizerDynamicEndColor &&
        settingsService.playbackBackgroundType != 1) {
      _dynamicStartColor = null;
      _dynamicEndColor = null;
      notifyListeners();
      return;
    }

    if (filePath != null) {
      final songMetadata = metadata ?? await _db.getSongMetadata(filePath);
      if (songMetadata != null && songMetadata.themeColorsBlob != null) {
        final colorsMap = ThemeColorHelper.blobToColors(songMetadata.themeColorsBlob!);
        if (colorsMap.isNotEmpty) {
          _applyThemeColors(colorsMap);
          notifyListeners();
          return;
        }
      }
    }

    _dynamicStartColor = Colors.black;
    _dynamicEndColor = Colors.white;

    ImageProvider? imageProvider;
    if (artworkBytes != null) {
      imageProvider = MemoryImage(artworkBytes);
    } else if (artworkPath != null && artworkPath.isNotEmpty) {
      imageProvider = FileImage(File(artworkPath));
    }

    if (imageProvider != null && filePath != null) {
      final String pathToUpdate = filePath;

      unawaited(() async {
        try {
          final resizeProvider = ResizeImage(
            imageProvider!,
            width: 200,
            height: 200,
          );
          final palette = await PaletteGenerator.fromImageProvider(
            resizeProvider,
            maximumColorCount: 20,
          );

          final blob = ThemeColorHelper.paletteToBlob(palette);
          final songMetadata = await _db.getSongMetadata(pathToUpdate);
          if (songMetadata != null) {
            final updated = SongMetadata(
              id: songMetadata.id,
              path: songMetadata.path,
              title: songMetadata.title,
              album: songMetadata.album,
              artist: songMetadata.artist,
              duration: songMetadata.duration,
              artworkPath: songMetadata.artworkPath,
              artworkWidth: songMetadata.artworkWidth,
              artworkHeight: songMetadata.artworkHeight,
              trackNumber: songMetadata.trackNumber,
              themeColorsBlob: blob,
              waveformBlob: songMetadata.waveformBlob,
            );
            await _db.insertOrUpdateSong(updated);
          }

          final colorsMap = ThemeColorHelper.blobToColors(blob);
          _applyThemeColors(colorsMap);
          notifyListeners();
        } catch (e) {
          debugPrint('Error generating palette async: $e');
        }
      }());
    } else {
      _dynamicStartColor = Colors.blue;
      _dynamicEndColor = Colors.deepPurple;
      _currentThemeColorsMap = {
        'dominant': Colors.blue,
        'vibrant': Colors.deepPurple,
        'muted': Colors.indigo,
      };
      notifyListeners();
    }
  }

  void clear() {
    _dynamicStartColor = null;
    _dynamicEndColor = null;
    _currentThemeColorsMap = const {};
    _currentBlurredArtworkBytes = null;
    notifyListeners();
  }
}
