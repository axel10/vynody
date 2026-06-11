import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:audio_metadata_reader/src/parsers/containers/mp4.dart';

void main() async {
  final srcPath = r"E:\vc_space\lib\58.V collection 37 -Daylight-\Disc 1\01 Summer drop.m4a";
  final dstPath = r"E:\vc_space\lib\58.V collection 37 -Daylight-\Disc 1\01 Summer drop (1).m4a";

  print("Source file exists: ${File(srcPath).existsSync()}");
  print("Transcoded file exists: ${File(dstPath).existsSync()}");

  if (File(srcPath).existsSync()) {
    inspectFile(srcPath, "Source File");
  }
  if (File(dstPath).existsSync()) {
    inspectFile(dstPath, "Transcoded File");
  }
}

void inspectFile(String path, String label) {
  print("\n--- Inspecting $label: $path ---");
  final file = File(path);
  final raf = file.openSync();
  try {
    raf.setPositionSync(0);
    final first32 = raf.readSync(32);
    print("First 32 bytes (Hex): ${first32.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}");
    print("First 32 bytes (ASCII): ${String.fromCharCodes(first32.map((b) => (b >= 32 && b <= 126) ? b : 46))}");

    raf.setPositionSync(4);
    final boxNameBytes = raf.readSync(4);
    print("Bytes at 4-8: ${String.fromCharCodes(boxNameBytes)}");
    print("canUserParser (MP4Parser): ${MP4Parser.canUserParser(raf)}");

    raf.setPositionSync(0);
    try {
      print("Attempting readMetadata...");
      final metadata = readMetadata(file, getImage: false);
      print("readMetadata Success!");
      print("  Title: ${metadata.title}");
      print("  Artist: ${metadata.artist}");
      print("  Album: ${metadata.album}");
      print("  Duration: ${metadata.duration}");
    } catch (e, s) {
      print("readMetadata failed: $e");
      print(s);
    }

    raf.setPositionSync(0);
    try {
      print("Attempting readAllMetadata...");
      final allMetadata = readAllMetadata(file, getImage: false);
      print("readAllMetadata Success! Type: ${allMetadata.runtimeType}");
    } catch (e, s) {
      print("readAllMetadata failed: $e");
      print(s);
    }
  } finally {
    raf.closeSync();
  }
}
