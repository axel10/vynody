import 'dart:io';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/containers/mp4.dart';

void main() {
  final srcPath = r"E:\vc_space\lib\58.V collection 37 -Daylight-\Disc 1\01 Summer drop.m4a";
  final dstPath = r"E:\vc_space\lib\58.V collection 37 -Daylight-\Disc 1\01 Summer drop (1).m4a";

  final srcFile = File(srcPath);
  final dstFile = File(dstPath);

  if (!srcFile.existsSync() || !dstFile.existsSync()) {
    print("One of the files does not exist!");
    return;
  }

  print("=== Source File All Metadata ===");
  dumpMetadata(srcFile);

  print("\n=== Transcoded File All Metadata ===");
  dumpMetadata(dstFile);
}

void dumpMetadata(File file) {
  try {
    final Mp4Metadata meta = readAllMetadata(file, getImage: true) as Mp4Metadata;
    print("Title: ${meta.title}");
    print("Artist: ${meta.artist}");
    print("Album: ${meta.album}");
    print("Genre: ${meta.genre}");
    print("Year: ${meta.year}");
    print("Track Number: ${meta.trackNumber}");
    print("Total Tracks: ${meta.totalTracks}");
    print("Disc Number: ${meta.discNumber}");
    print("Total Discs: ${meta.totalDiscs}");
    print("Lyrics: ${meta.lyrics}");
    print("Duration: ${meta.duration}");
    print("Bitrate: ${meta.bitrate}");
    print("Sample Rate: ${meta.sampleRate}");
    print("Chapters Count: ${meta.chapters.length}");
    if (meta.picture != null) {
      print("Picture MIME: ${meta.picture!.mimetype}");
      print("Picture Size: ${meta.picture!.bytes.length} bytes");
    } else {
      print("Picture: null");
    }
  } catch (e, s) {
    print("Error parsing: $e");
    print(s);
  }
}
