import 'package:path/path.dart' as p;

class MusicFileUtils {
  static const Set<String> supportedAudioExtensions = {
    '.aac',
    '.aif',
    '.aiff',
    '.alac',
    '.caf',
    '.mp3',
    '.m4a',
    '.m4b',
    '.flac',
    '.ogg',
    '.opus',
    '.wav',
  };

  static bool isMusicFilePath(String path) {
    return supportedAudioExtensions.contains(p.extension(path).toLowerCase());
  }
}
