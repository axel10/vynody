import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/scanner/scanner_sorting.dart';

MusicFile _song(
  String name, {
  String? title,
  int? trackNumber,
  String? path,
}) {
  return MusicFile(
    path: path ?? '/music/$name',
    name: name,
    title: title,
    trackNumber: trackNumber,
  );
}

List<String> _names(List<MusicFile> files) =>
    files.map((f) => f.name).toList(growable: false);

void main() {
  const sorter = ScannerFolderSorter();

  FolderSortSettings settings(SortCriteria criteria, SortOrder order) =>
      FolderSortSettings(criteria: criteria, order: order);

  group('曲目排序', () {
    test('文件名自然排序：数字按数值大小', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [_song('10.mp3'), _song('2.mp3'), _song('1.mp3')],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.filename, SortOrder.ascending),
      );

      expect(_names(folder.files), ['1.mp3', '2.mp3', '10.mp3']);
    });

    test('降序按相反方向排列', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [_song('1.mp3'), _song('2.mp3'), _song('10.mp3')],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.filename, SortOrder.descending),
      );

      expect(_names(folder.files), ['10.mp3', '2.mp3', '1.mp3']);
    });

    test('按标题排序取标签标题，缺标签退回文件名', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [
          _song('c.mp3', title: 'Beta'),
          _song('b.mp3', title: 'Alpha'),
          _song('a.mp3'),
        ],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.title, SortOrder.ascending),
      );

      // a.mp3 无标题，displayName 退回 a（不带扩展名）
      expect(_names(folder.files), ['a.mp3', 'b.mp3', 'c.mp3']);
    });

    test('按音轨号升序时缺失音轨号排在末尾', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [
          _song('none.mp3'),
          _song('three.mp3', trackNumber: 3),
          _song('one.mp3', trackNumber: 1),
        ],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.trackNumber, SortOrder.ascending),
      );

      expect(_names(folder.files), ['one.mp3', 'three.mp3', 'none.mp3']);
    });

    test('按音轨号降序时缺失音轨号仍然排在末尾（不随方向翻转）', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [
          _song('none.mp3'),
          _song('one.mp3', trackNumber: 1),
          _song('three.mp3', trackNumber: 3),
        ],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.trackNumber, SortOrder.descending),
      );

      expect(_names(folder.files), ['three.mp3', 'one.mp3', 'none.mp3']);
    });

    test('音轨号相同时按文件名兜底', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        files: [
          _song('b.mp3', trackNumber: 1),
          _song('a.mp3', trackNumber: 1),
        ],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.trackNumber, SortOrder.ascending),
      );

      expect(_names(folder.files), ['a.mp3', 'b.mp3']);
    });
  });

  group('子目录排序', () {
    test('子目录只按名称排，方向跟随设置', () {
      final folder = MusicFolder(
        path: '/music',
        name: 'music',
        subFolders: [
          MusicFolder(path: '/music/b', name: 'b'),
          MusicFolder(path: '/music/a', name: 'a'),
        ],
      );

      sorter.sortFolderRecursiveForTree(
        folder,
        resolveSettings: (_) =>
            settings(SortCriteria.trackNumber, SortOrder.descending),
      );

      expect(folder.subFolders.map((f) => f.name), ['b', 'a']);
    });
  });

  group('按目录解析不同设置', () {
    test('父目录与子目录各用各的设置', () {
      final child = MusicFolder(
        path: '/music/child',
        name: 'child',
        files: [
          _song('x/1.mp3', path: '/music/child/1.mp3', title: 'Zulu'),
          _song('x/2.mp3', path: '/music/child/2.mp3', title: 'Alpha'),
        ],
      );
      final root = MusicFolder(
        path: '/music',
        name: 'music',
        subFolders: [child],
        files: [_song('10.mp3'), _song('2.mp3')],
      );

      final overrides = <String, FolderSortSettings>{
        '/music/child': settings(SortCriteria.title, SortOrder.ascending),
      };

      sorter.sortFoldersForTree(
        [root],
        resolveSettings: (path) =>
            overrides[path] ??
            settings(SortCriteria.filename, SortOrder.ascending),
      );

      expect(_names(root.files), ['2.mp3', '10.mp3']);
      expect(_names(child.files), ['x/2.mp3', 'x/1.mp3']);
    });

    test('sortSpecificFolders 不递归到孙目录', () {
      final grandChild = MusicFolder(
        path: '/music/child/grand',
        name: 'grand',
        files: [_song('g/2.mp3', path: '/music/child/grand/2.mp3'), _song('g/1.mp3', path: '/music/child/grand/1.mp3')],
      );
      final child = MusicFolder(
        path: '/music/child',
        name: 'child',
        subFolders: [grandChild],
        files: [_song('c/2.mp3', path: '/music/child/2.mp3'), _song('c/1.mp3', path: '/music/child/1.mp3')],
      );

      sorter.sortSpecificFolders(
        [child],
        resolveSettings: (_) =>
            settings(SortCriteria.filename, SortOrder.ascending),
      );

      expect(_names(child.files), ['c/1.mp3', 'c/2.mp3']);
      // 孙目录没被处理，保持原顺序
      expect(_names(grandChild.files), ['g/2.mp3', 'g/1.mp3']);
    });

    test('根目录列表顺序不受排序设置影响（由用户拖拽决定）', () {
      final a = MusicFolder(path: '/a-root', name: 'z-last');
      final b = MusicFolder(path: '/b-root', name: 'a-first');
      final roots = [a, b];

      sorter.sortFoldersForTree(
        roots,
        resolveSettings: (path) =>
            settings(SortCriteria.filename, SortOrder.ascending),
      );

      expect(roots.map((f) => f.path), ['/a-root', '/b-root']);
    });
  });

  group('FolderSortSettings 序列化', () {
    test('往返一致', () {
      const source = FolderSortSettings(
        criteria: SortCriteria.trackNumber,
        order: SortOrder.descending,
      );
      final restored = FolderSortSettings.fromJson(source.toJson());

      expect(restored.criteria, SortCriteria.trackNumber);
      expect(restored.order, SortOrder.descending);
    });

    test('缺字段或脏值回落到文件名 / 升序', () {
      final restored = FolderSortSettings.fromJson(const {
        'criteria': 'nonsense',
        'order': null,
      });

      expect(restored.criteria, SortCriteria.filename);
      expect(restored.order, SortOrder.ascending);
    });
  });
}
