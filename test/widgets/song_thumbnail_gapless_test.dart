import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

/// 1x1 透明 PNG，只用于让 Image 能正常解码。
const String _kPng1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AF+g7oAAAAASUVORK5CYII=';

void main() {
  late Directory tempDir;
  late String coverPath;
  late Uint8List pngBytes;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('song_thumbnail_gapless');
    coverPath = '${tempDir.path}/cover.png';
    pngBytes = base64Decode(_kPng1x1);
    await File(coverPath).writeAsBytes(pngBytes);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );
  }

  bool imageGapless(WidgetTester tester) {
    return tester.widget<Image>(find.byType(Image)).gaplessPlayback;
  }

  testWidgets('同一首歌封面源变化时保留上一帧，避免播放时闪白', (tester) async {
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/a.mp3',
          thumbnailPath: coverPath,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    // 播放开始时扫描器会把该曲目补上 artworkBytes，
    // 图片源从 FileImage 切到 MemoryImage，若无 gapless 会清空画面。
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/a.mp3',
          thumbnailPath: coverPath,
          bytes: pngBytes,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(imageGapless(tester), isTrue);
  });

  testWidgets('换到另一首歌时不保留上一帧，避免列表复用显示旧封面', (tester) async {
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/a.mp3',
          thumbnailPath: coverPath,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/b.mp3',
          thumbnailPath: coverPath,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(imageGapless(tester), isFalse);
  });
}
