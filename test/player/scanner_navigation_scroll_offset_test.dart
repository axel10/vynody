import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_navigation_state.dart';

void main() {
  group('ScannerNavigationState scroll offset behavior', () {
    MusicFolder makeFolder(String path, String name) {
      return MusicFolder(
        path: path,
        name: name,
        subFolders: const [],
        files: const [],
      );
    }

    test('retains active path offsets and prunes exited folder offsets on back navigation', () {
      final navState = ScannerNavigationState();

      final folderA = makeFolder('/music/a', 'a');
      final folderB = makeFolder('/music/a/b', 'b');

      // 1. 在根目录记录滚动位置
      navState.setScrollOffset('root', 120.0);
      expect(navState.getScrollOffset('root'), 120.0);

      // 2. 从根目录进入目录 A
      navState.setState(folderA, []);
      navState.setScrollOffset(folderA.path, 300.0);
      expect(navState.getScrollOffset('root'), 120.0);
      expect(navState.getScrollOffset(folderA.path), 300.0);

      // 3. 从目录 A 进入子目录 B
      navState.setState(folderB, [folderA]);
      navState.setScrollOffset(folderB.path, 500.0);
      expect(navState.getScrollOffset('root'), 120.0);
      expect(navState.getScrollOffset(folderA.path), 300.0);
      expect(navState.getScrollOffset(folderB.path), 500.0);

      // 4. 从子目录 B 返回目录 A（B 离开活动路径）
      navState.setState(folderA, []);

      // 目录 A 与 root 的滚动位置保持记住
      expect(navState.getScrollOffset('root'), 120.0);
      expect(navState.getScrollOffset(folderA.path), 300.0);
      // 被退出的目录 B 的滚动位置被清理，重置为 0.0（回到顶部）
      expect(navState.getScrollOffset(folderB.path), 0.0);

      // 5. 模拟目录 B 在退出动画/dispose 期间可能触发的惰性滚动写入，应被忽略
      navState.setScrollOffset(folderB.path, 500.0);
      expect(navState.getScrollOffset(folderB.path), 0.0);

      // 6. 再次进入目录 B 时，应从顶部（0.0）开始
      navState.setState(folderB, [folderA]);
      expect(navState.getScrollOffset(folderB.path), 0.0);

      // 7. 从目录 A 返回根目录
      navState.setState(null, []);
      // root 保持记住
      expect(navState.getScrollOffset('root'), 120.0);
      // 目录 A 离开路径，其 offset 被清理
      expect(navState.getScrollOffset(folderA.path), 0.0);
    });

    test('multi-level navigation prunes all popped descendants', () {
      final navState = ScannerNavigationState();

      final folderA = makeFolder('/music/a', 'a');
      final folderB = makeFolder('/music/a/b', 'b');
      final folderC = makeFolder('/music/a/b/c', 'c');

      navState.setState(folderA, []);
      navState.setScrollOffset(folderA.path, 150.0);

      navState.setState(folderB, [folderA]);
      navState.setScrollOffset(folderB.path, 250.0);

      navState.setState(folderC, [folderA, folderB]);
      navState.setScrollOffset(folderC.path, 350.0);

      // 直接跳回目录 A（B 与 C 均被退出）
      navState.setState(folderA, []);
      expect(navState.getScrollOffset(folderA.path), 150.0);
      expect(navState.getScrollOffset(folderB.path), 0.0);
      expect(navState.getScrollOffset(folderC.path), 0.0);
    });

    test('popHistory prunes popped folder offset', () {
      final navState = ScannerNavigationState();

      final folderA = makeFolder('/music/a', 'a');
      final folderB = makeFolder('/music/a/b', 'b');

      navState.setState(folderA, []);
      navState.setScrollOffset(folderA.path, 100.0);

      navState.pushHistory(folderB);
      navState.setScrollOffset(folderB.path, 200.0);

      expect(navState.getScrollOffset(folderB.path), 200.0);

      final popped = navState.popHistory();
      expect(popped?.path, folderB.path);
      expect(navState.getScrollOffset(folderB.path), 0.0);
      expect(navState.getScrollOffset(folderA.path), 100.0);
    });
  });
}
