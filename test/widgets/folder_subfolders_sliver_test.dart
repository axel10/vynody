import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/scanner/scanner_service.dart';
import 'package:vynody/widgets/folder_content_slivers.dart';
import 'package:vynody/widgets/zoom_reorder_ui.dart';
import 'package:zoomable_sliver_grid/zoomable_sliver_grid.dart';

class _FakeScannerService extends ScannerService {
  List<String>? lastReorderedPaths;

  @override
  bool isRootPathAvailable(String path) => true;

  @override
  int getSongCountForFolder(MusicFolder folder) => folder.songCount;

  @override
  MusicFile? getRepresentativeSongForFolder(MusicFolder folder) => null;

  @override
  Future<void> reorderRootPaths(List<String> newOrder) async {
    lastReorderedPaths = newOrder;
  }
}

void main() {
  final folder1 = MusicFolder(
    path: '/music/pop',
    name: 'Pop',
    files: [
      MusicFile(
        path: '/music/pop/song1.mp3',
        name: 'song1.mp3',
        title: 'Song 1',
        artist: 'Artist',
        album: 'Album',
        durationMillis: 200,
        id: 1,
      ),
    ],
  );

  final folder2 = MusicFolder(
    path: '/music/rock',
    name: 'Rock',
    files: [
      MusicFile(
        path: '/music/rock/song2.mp3',
        name: 'song2.mp3',
        title: 'Song 2',
        artist: 'Artist',
        album: 'Album',
        durationMillis: 240,
        id: 2,
      ),
    ],
  );

  Widget buildTestWidget({
    required _FakeScannerService scanner,
    required List<MusicFolder> folders,
    bool isRoot = true,
    bool isSelectionMode = false,
    ZoomReorderController? reorderController,
  }) {
    return ProviderScope(
      overrides: [
        scannerServiceProvider.overrideWith((ref) => scanner),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              FolderSubfoldersSliver(
                folders: folders,
                zoomScale: 0.0,
                scanner: scanner,
                isRoot: isRoot,
                isSelectionMode: isSelectionMode,
                reorderController: reorderController,
                onNavigateTo: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('根目录列表在非多选态下持有 reorderController 使用 ZoomReorderableSliverGrid 但隐藏手柄', (tester) async {
    final scanner = _FakeScannerService();
    final controller = ZoomReorderController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTestWidget(
        scanner: scanner,
        folders: [folder1, folder2],
        isRoot: true,
        isSelectionMode: false,
        reorderController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ZoomReorderableSliverGrid), findsOneWidget);
    expect(find.byType(ZoomReorderHandle), findsNothing);

    final grid = tester.widget<ZoomReorderableSliverGrid>(
      find.byType(ZoomReorderableSliverGrid),
    );
    expect(grid.showHandles, isFalse);
    expect(grid.enableDirectDrag, isTrue);

    // 根目录发布包含 paths 的载荷，供队列抽屉接收
    final dragItem = await grid.itemDragItemBuilder!(0, {0}, <String, dynamic>{});
    expect(dragItem.localData, isA<Map<String, dynamic>>());
    final localData = dragItem.localData as Map<String, dynamic>;
    expect(localData['path'], equals('/music/pop'));
    expect(localData['paths'], equals(['/music/pop/song1.mp3']));

    // 触发重排
    grid.onReorder({0}, 2);
    expect(scanner.lastReorderedPaths, equals(['/music/rock', '/music/pop']));
  });

  testWidgets('根目录列表在多选态下持有 reorderController 显示手柄', (tester) async {
    final scanner = _FakeScannerService();
    final controller = ZoomReorderController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildTestWidget(
        scanner: scanner,
        folders: [folder1, folder2],
        isRoot: true,
        isSelectionMode: true,
        reorderController: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ZoomReorderableSliverGrid), findsOneWidget);
    expect(find.byType(ZoomReorderHandle), findsNWidgets(2));

    final grid = tester.widget<ZoomReorderableSliverGrid>(
      find.byType(ZoomReorderableSliverGrid),
    );
    expect(grid.showHandles, isTrue);
  });

  testWidgets('子目录视图（isRoot: false）不使用 ZoomReorderableSliverGrid', (tester) async {
    final scanner = _FakeScannerService();

    await tester.pumpWidget(
      buildTestWidget(
        scanner: scanner,
        folders: [folder1, folder2],
        isRoot: false,
        isSelectionMode: false,
        reorderController: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ZoomReorderableSliverGrid), findsNothing);
    expect(find.byType(SliverGrid), findsOneWidget);
  });
}
