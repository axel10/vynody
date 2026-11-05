import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/artwork_fade.dart';
import 'package:vynody/widgets/remote_artwork_widget.dart';

const String _kPng1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AF+g7oAAAAASUVORK5CYII=';

void main() {
  final server = RemoteServer(
    id: 'server-1',
    name: 'Test',
    type: RemoteServerType.subsonic,
    url: 'http://127.0.0.1:4533',
    username: 'tester',
    createdAt: DateTime(2026),
  );
  const coverId = 'al-1';
  const otherCoverId = 'al-2';
  const size = 300.0;

  late Directory tempDir;

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  Widget artwork([String id = coverId]) => RemoteArtworkWidget(
        server: server,
        password: 'pw',
        coverArtId: id,
        size: size,
      );

  String keyFor(String id, [double s = size]) =>
      RemoteArtworkWidget.diskKeyFor(
        serverId: server.id,
        serverType: server.type.name,
        coverArtId: id,
        size: s,
      );

  AnimatedOpacity fade(WidgetTester tester) => tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity).first,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('remote_artwork');
    RemoteArtworkWidget.debugThumbnailsDir = tempDir.path;
    RemoteArtworkWidget.debugResetCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    final bytes = base64Decode(_kPng1x1);
    await RemoteArtworkWidget.debugSeedDiskCache(keyFor(coverId), bytes);
    await RemoteArtworkWidget.debugSeedDiskCache(keyFor(otherCoverId), bytes);
  });

  tearDown(() async {
    RemoteArtworkWidget.debugThumbnailsDir = null;
    RemoteArtworkWidget.debugResetCaches();
    imageCache.clear();
    imageCache.clearLiveImages();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('首次加载：默认图标垫底 + 280ms 淡入，磁盘命中不发网络请求',
      (tester) async {
    await tester.pumpWidget(wrap(artwork()));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(fade(tester).duration, kArtworkFadeInDuration);
    // 首帧尚未到达时从透明开始，是首次加载的正常反馈。
    expect(fade(tester).opacity, 0.0);
    // A1：一次下载同时服务解码与落盘；命中磁盘缓存时一次网络都不发。
    expect(RemoteArtworkWidget.debugNetworkRequests, 0);
  });

  testWidgets('行回收重挂载：不画默认图标、不重播淡入（封面不闪）',
      (tester) async {
    await tester.pumpWidget(wrap(artwork()));
    await tester.pump();
    // 模拟首帧到达后 frameBuilder 的登记动作。
    RemoteArtworkWidget.debugRecordFrame(keyFor(coverId));

    // SliverGrid 条目滚出视口被回收，再滚回来是全新 State。
    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    await tester.pump();
    await tester.pumpWidget(wrap(artwork()));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    expect(fade(tester).duration, Duration.zero);
    expect(fade(tester).opacity, 1.0);
    expect(RemoteArtworkWidget.debugNetworkRequests, 0);
  });

  testWidgets('行复用换成另一张封面：重新走占位 + 淡入', (tester) async {
    await tester.pumpWidget(wrap(artwork()));
    await tester.pump();
    RemoteArtworkWidget.debugRecordFrame(keyFor(coverId));

    await tester.pumpWidget(wrap(artwork(otherCoverId)));
    await tester.pump();

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(fade(tester).duration, kArtworkFadeInDuration);
  });

  testWidgets('已显示过的封面进入失败冷却时也不再画默认图标', (tester) async {
    RemoteArtworkWidget.debugRecordFrame(keyFor(coverId));
    for (var i = 0; i < 3; i++) {
      // 直接驱动冷却计数，避免依赖真实网络失败。
      RemoteArtworkWidget.debugRecordFailure(keyFor(coverId));
    }

    await tester.pumpWidget(wrap(artwork()));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
  });

  test('尺寸档位稳定：同档不同 widget.size 共用缓存 key', () {
    // 200 / 220 / 300 都落 320 档，不会因尺寸抖动重新下载。
    expect(keyFor(coverId, 200), keyFor(coverId, 220));
    expect(keyFor(coverId, 220), keyFor(coverId, 300));
    // 小图标与大封面是不同档位（各自的解码尺寸不同）。
    expect(keyFor(coverId, 52), isNot(keyFor(coverId, 300)));
    // diskKey 不含 password / token。
    expect(keyFor(coverId), isNot(contains('pw')));
  });
}
