import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/remote/widgets/webdav_content_slivers.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/widgets/folder_layout_utils.dart';
import 'package:vynody/widgets/folder_zoom_gesture_layer.dart';
import 'package:vynody/widgets/song_zoom_item.dart';

/// 远程目录页（WebDAV / SMB 共用）一页挂两段网格：子目录 + 文件。
///
/// 两段必须共用页面提供的**同一个** `FolderZoomSliverBuilder`：各段自建 builder 时
/// 上游（子目录）换档后的高度变化不会算进下游（文件）的滚动补偿，下游会被顶走
/// 一个 `ΔH`；两个 builder 还会同时往同一个 `ScrollPosition` 写像素值。
///
/// 这里守住「段组件不自建 builder」这件事 —— 段组件走的是 `FolderZoomSectionHost`，
/// 只有祖先没有 `FolderZoomMetricsScope`（单独成页）时才退化成宿主。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final server = RemoteServer(
    id: 'webdav_test',
    name: 'WebDAV NAS',
    type: RemoteServerType.webdav,
    url: 'http://127.0.0.1:8080/dav',
    username: 'admin',
    createdAt: DateTime(2026, 1, 1),
  );

  const folders = [
    WebDavFile(
      path: '/Music/Pop',
      name: 'Pop',
      isDirectory: true,
      contentLength: 0,
    ),
    WebDavFile(
      path: '/Music/Rock',
      name: 'Rock',
      isDirectory: true,
      contentLength: 0,
    ),
  ];

  // 目录页只呈现「子目录 + 可播放音频」，非音频文件在加载阶段就被剔掉，
  // 所以这里用音频文件验证文件段确实渲染。
  const files = [
    WebDavFile(
      path: '/Music/01 - Song.flac',
      name: '01 - Song.flac',
      isDirectory: false,
      contentLength: 1024,
    ),
  ];

  Widget harness({required Object folderSection, required Object fileSection}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              return FolderZoomSliverBuilder(
                zoomScale: kFolderZoomTierStandardList,
                width: constraints.maxWidth,
                builder: (context, metrics) {
                  return CustomScrollView(
                    slivers: [
                      WebDavSubfoldersSliver(
                        folders: folders,
                        zoomScale: kFolderZoomTierStandardList,
                        crossAxisExtent: constraints.maxWidth,
                        section: folderSection,
                        server: server,
                        password: '',
                        onOpenFolder: (_) {},
                      ),
                      WebDavSongsSliver(
                        files: files,
                        zoomScale: kFolderZoomTierStandardList,
                        crossAxisExtent: constraints.maxWidth,
                        section: fileSection,
                        server: server,
                        password: '',
                        metadataMap: const {},
                        currentMusicPath: null,
                        isAudioPlaying: false,
                        allAudioFiles: const [],
                        selectedSongPaths: const {},
                        onSongTap: (_, __) {},
                        bottomPadding: 0,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('两段网格共用同一个缩放容器，段组件不自建 builder', (tester) async {
    await tester.pumpWidget(
      harness(folderSection: 'test.folders', fileSection: 'test.files'),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FolderZoomSliverBuilder), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    expect(find.byType(SongZoomItem), findsOneWidget);
  });

  testWidgets('没有页面级 builder 时，段组件退化成宿主（单独成页仍可用）', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                WebDavSubfoldersSliver(
                  folders: folders,
                  zoomScale: kFolderZoomTierStandardList,
                  server: server,
                  password: '',
                  onOpenFolder: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FolderZoomSliverBuilder), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
  });

  testWidgets('加载中 → 有内容的结构切换不能炸（builder 不挂 ScrollController）', (tester) async {
    // 页面真实结构：loading / error 分支是裸 `CustomScrollView`，有内容那一支
    // 套了 `RefreshIndicator`。切分支时 `RefreshIndicator` 插进祖先链，整段
    // `ScrollView` 换父级 → 新元素重建，旧 `ScrollPosition` 要到本帧 `finalizeTree`
    // 才 detach。这一帧里 `controller.positions.length == 2`。
    //
    // 所以页面**不能**给 `FolderZoomSliverBuilder` 传 `controller`：包内会读
    // `controller.position`（断言 `_positions.length == 1`）→ 抛在 sliver 布局里 →
    // 整页空白。不传时走渲染树里按布局校验挑 viewport 的路径，能容忍这一帧重叠。
    await tester.pumpWidget(const ProviderScope(child: _SwapHarness()));
    await tester.pump();

    expect(find.byType(WebDavSubfoldersSliver), findsNothing);

    await tester.tap(find.text('load'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(WebDavSubfoldersSliver), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
  });
}

class _SwapHarness extends StatefulWidget {
  const _SwapHarness();

  @override
  State<_SwapHarness> createState() => _SwapHarnessState();
}

class _SwapHarnessState extends State<_SwapHarness> {
  final ScrollController controller = ScrollController();
  bool loading = true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return FolderZoomGestureLayer(
              child: FolderZoomSliverBuilder(
                zoomScale: kFolderZoomTierStandardList,
                width: constraints.maxWidth,
                builder: (context, metrics) {
                  if (loading) {
                    return CustomScrollView(
                      controller: controller,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Center(
                            child: TextButton(
                              onPressed: () => setState(() => loading = false),
                              child: const Text('load'),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async {},
                    child: CustomScrollView(
                      controller: controller,
                      slivers: [
                        WebDavSubfoldersSliver(
                          folders: const [
                            WebDavFile(
                              path: '/Music/Pop',
                              name: 'Pop',
                              isDirectory: true,
                              contentLength: 0,
                            ),
                          ],
                          zoomScale: kFolderZoomTierStandardList,
                          crossAxisExtent: constraints.maxWidth,
                          section: 'swap.folders',
                          server: _swapHarnessServer,
                          password: '',
                          onOpenFolder: (_) {},
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

final _swapHarnessServer = RemoteServer(
  id: 'webdav_swap',
  name: 'WebDAV NAS',
  type: RemoteServerType.webdav,
  url: 'http://127.0.0.1:8080/dav',
  username: 'admin',
  createdAt: DateTime(2026, 1, 1),
);
