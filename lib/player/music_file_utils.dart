import 'package:path/path.dart' as p;

class MusicFileUtils {
  static const Set<String> supportedAudioExtensions = {
    '.mp3',
    '.m4a',
    '.flac',
    '.ogg',
    '.opus',
    '.wav',
  };

  static bool isMusicFilePath(String path) {
    return supportedAudioExtensions.contains(p.extension(path).toLowerCase());
  }
}
