import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('未生成缩略图时区域保持空白（不显示默认占位图标，透明度为0）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SongThumbnail(
          path: '/music/generating.mp3',
          size: 56,
        ),
      ),
    );
    await tester.pump();

    // 缩略图生成中：无 Image，也无默认占位图标，AnimatedOpacity 透明度为 0
    expect(find.byType(Image), findsNothing);
    expect(find.byType(DefaultCoverArt), findsNothing);

    final animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 0.0);
  });

  testWidgets('缩略图生成完成后淡入显示', (tester) async {
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
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0.0);

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

    // 触发第一帧淡入
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);

    // 此时动画进行中，透明度朝 1.0 过渡
    final animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 1.0);
    expect(animatedOpacity.duration, const Duration(milliseconds: 280));

    // 推进动画到结束
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1.0);
  });

  testWidgets('已存在缩略图时挂载即直接显示，不延时淡入', (tester) async {
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
    final animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 1.0);
    expect(animatedOpacity.duration, Duration.zero);
  });

  testWidgets('首次播放某首歌（同一首歌补写属性/更新）时缩略图不闪白也不重新淡入', (tester) async {
    // 初始状态：带有缩略图显示中
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
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1.0);

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

    // 必须持续展示 Image，不出现空白，不触发额外淡入动画
    expect(find.byType(Image), findsOneWidget);
    final animatedOpacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(animatedOpacity.opacity, 1.0);
    expect(animatedOpacity.duration, Duration.zero);
  });
}
