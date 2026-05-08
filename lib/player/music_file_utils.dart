import 'package:path/path.dart' as p;

class MusicFileUtils {
  static const Set<String> supportedAudioExtensions = {
    '.aac',
    '.aif',
    '.aiff',
    '.alac',
    '.caf',
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

  static bool isMusicFilePath(String path) {
    return supportedAudioExtensions.contains(p.extension(path).toLowerCase());
  }

  static bool isAppleDoubleFilePath(String path) {
    return p.basename(path).startsWith('._');
  }
}
