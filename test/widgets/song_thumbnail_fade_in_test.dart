import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/artwork_fade.dart';
import 'package:vynody/widgets/default_cover_art.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

const String _kPng1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AF+g7oAAAAASUVORK5CYII=';

void main() {
  late Directory tempDir;
  late String coverPath;
  late Uint8List pngBytes;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('song_thumbnail_fade_in');
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

  /// 最外层（解析级）淡入包装：树序上永远排第一。
  AnimatedOpacity outerFade(WidgetTester tester) {
    return tester
        .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
        .first;
  }

  testWidgets('未生成缩略图时区域保持空白（不显示默认占位图标，透明度为 0）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SongThumbnail(
          path: '/music/generating.mp3',
          size: 56,
        ),
      ),
    );
    await tester.pump();

    // 缩略图生成中：无 Image，也无默认占位图标，整体透明度为 0
    expect(find.byType(Image), findsNothing);
    expect(find.byType(DefaultCoverArt), findsNothing);
    expect(outerFade(tester).opacity, 0.0);
  });

  testWidgets('缩略图生成完成后整体淡入', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SongThumbnail(
          path: '/music/fade_test.mp3',
          size: 56,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(outerFade(tester).opacity, 0.0);

    // 模拟生成完毕补上 thumbnailPath
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/fade_test.mp3',
          thumbnailPath: coverPath,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    final fade = outerFade(tester);
    expect(fade.opacity, 1.0);
    expect(fade.duration, kArtworkFadeInDuration);

    await tester.pumpAndSettle();
    expect(outerFade(tester).opacity, 1.0);
  });

  testWidgets('已存在缩略图时挂载即进入就位态，首帧直接展示无需淡入', (tester) async {
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/existing.mp3',
          thumbnailPath: coverPath,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    final fade = outerFade(tester);
    expect(fade.opacity, 1.0);
    // 已有缩略图时无需淡入动画，首帧直接展示
    expect(fade.duration, Duration.zero);
    // 仅外层一层管理透明度，内层无多余嵌套 AnimatedOpacity
    expect(find.byType(AnimatedOpacity), findsOneWidget);
  });

  testWidgets('首次播放某首歌（同一首歌补写属性/换图片源）时不再重新淡入', (tester) async {
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/play_test.mp3',
          thumbnailPath: coverPath,
          size: 56,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(outerFade(tester).opacity, 1.0);

    // 播放时更新（同一首歌，模拟 AudioService / 扫描器补齐属性重建）
    await tester.pumpWidget(
      wrap(
        SongThumbnail(
          path: '/music/play_test.mp3',
          thumbnailPath: coverPath,
          bytes: pngBytes,
          size: 56,
        ),
      ),
    );
    await tester.pump();

    // 已经露过面：保留上一帧，不再套一层淡入（否则会闪白）
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(outerFade(tester).opacity, 1.0);
  });

  testWidgets('换到另一首无缩略图的歌时进入生成态并在就绪后淡入', (tester) async {
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
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(outerFade(tester).opacity, 1.0);

    // 列表行复用成另一首尚未生成缩略图的歌
    await tester.pumpWidget(
      wrap(
        const SongThumbnail(
          path: '/music/b.mp3',
          size: 56,
        ),
      ),
    );
    await tester.pump();

    // 进入生成态：区域空白
    expect(find.byType(Image), findsNothing);
    expect(outerFade(tester).opacity, 0.0);

    // 异步生成完毕补上缩略图
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

    // 统一淡入
    expect(find.byType(Image), findsOneWidget);
    final fade = outerFade(tester);
    expect(fade.opacity, 1.0);
    expect(fade.duration, kArtworkFadeInDuration);
  });
}
