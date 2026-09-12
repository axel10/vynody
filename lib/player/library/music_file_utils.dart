import 'package:path/path.dart' as p;

class MusicFileUtils {
  static const Set<String> supportedAudioExtensions = {
    '.aac',
    '.aif',
    '.aiff',
    '.alac',
    '.ape',
    '.caf',
    '.dff',
    '.dsf',
    '.flac',
    '.m4a',
    '.m4b',
    '.m4p',
    '.mid',
    '.midi',
    '.mp3',
    '.ogg',
    '.opus',
    '.wav',
    '.webm',
  };

  /// List of supported extensions without leading dot (e.g. ['mp3', 'flac', ...])
  /// convenient for file pickers and platform method channels.
  static final List<String> supportedExtensionsWithoutDot =
      supportedAudioExtensions
          .map((ext) => ext.startsWith('.') ? ext.substring(1) : ext)
          .toList(growable: false);

  static bool isMusicFilePath(String path) {
    return supportedAudioExtensions.contains(p.extension(path).toLowerCase());
  }

  static bool isAppleDoubleFilePath(String path) {
    return p.basename(path).startsWith('._');
  }
}
