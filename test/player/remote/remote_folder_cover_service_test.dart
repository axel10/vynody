import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/services/remote_folder_cover_service.dart';

/// 远程目录「代表封面」的选取规则。
///
/// 这几条规则决定了一次进目录要为网络付多少次代价，比较难靠人工回归覆盖，
/// 所以把纯函数部分（文件名识别）单独钉住。
void main() {
  WebDavFile file(String path, {bool isDirectory = false}) => WebDavFile(
        path: path,
        name: path.split('/').last,
        isDirectory: isDirectory,
        contentLength: 0,
      );

  group('RemoteFolderCoverService.pickCoverImage', () {
    test('优先取名字完全匹配的封面图', () {
      final items = <WebDavFile>[
        file('/a/1.mp3'),
        file('/a/scan.jpg'),
        file('/a/folder.jpg'),
        file('/a/cover.png'),
      ];

      // folder.jpg 排在 cover.png 前面，先命中完全匹配的那个。
      expect(RemoteFolderCoverService.pickCoverImage(items)?.name, 'folder.jpg');
    });

    test('没有完全匹配时退化为名字里带 cover/front/folder 的图片', () {
      final items = <WebDavFile>[
        file('/a/x.jpg'),
        file('/a/album-front.jpg'),
      ];

      expect(
        RemoteFolderCoverService.pickCoverImage(items)?.name,
        'album-front.jpg',
      );
    });

    test('忽略子目录与非常规图片扩展名', () {
      final items = <WebDavFile>[
        file('/a/cover', isDirectory: true),
        file('/a/cover.tiff'),
      ];

      expect(RemoteFolderCoverService.pickCoverImage(items), isNull);
    });

    test('没有任何图片时返回 null，交给内嵌封面兜底', () {
      final items = <WebDavFile>[file('/a/1.mp3')];

      expect(RemoteFolderCoverService.pickCoverImage(items), isNull);
    });
  });

  group('RemoteFolderCoverService.searchSubtree', () {
    /// 按「路径 → 子项」搭一棵假目录树，并记录被列过的目录。
    /// 子项以 `/` 结尾表示目录。
    ({
      Future<List<WebDavFile>> Function(String path) list,
      List<String> visited,
    }) tree(Map<String, List<String>> spec) {
      final visited = <String>[];
      Future<List<WebDavFile>> list(String path) async {
        visited.add(path);
        final children = spec[path];
        if (children == null) throw StateError('不该列这个目录: $path');
        return [
          for (final child in children)
            if (child.endsWith('/'))
              file(
                '$path/${child.substring(0, child.length - 1)}',
                isDirectory: true,
              )
            else
              file('$path/$child'),
        ];
      }

      return (list: list, visited: visited);
    }

    RemoteFolderCoverHit hitFor(String source) =>
        RemoteFolderCoverHit(thumbnailPath: '/cache/$source.jpg');

    test('深搜：分类/歌手/专辑三层就命中，不用把整层列完', () async {
      final t = tree({
        '/cat': ['singerA/', 'singerB/'],
        '/cat/singerA': ['album1/', 'album2/'],
        '/cat/singerA/album1': ['01.mp3', '02.mp3'],
      });

      final result = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/cat',
        listDirectory: t.list,
        probeImage: (_) async => null,
        // 只有专辑里的歌带封面。
        probeSong: (song) async =>
            song.path == '/cat/singerA/album1/01.mp3' ? hitFor('album1') : null,
      );

      expect(result.hit?.thumbnailPath, '/cache/album1.jpg');
      expect(t.visited, ['/cat', '/cat/singerA', '/cat/singerA/album1']);
    });

    test('同层目录封面图优先于歌曲标签，且不再白读标签', () async {
      final t = tree({
        '/a': ['cover.jpg', '01.mp3'],
      });
      var songProbes = 0;

      final result = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/a',
        listDirectory: t.list,
        probeImage: (image) async => hitFor('cover'),
        probeSong: (_) async {
          songProbes++;
          return hitFor('song');
        },
      );

      expect(result.hit?.thumbnailPath, '/cache/cover.jpg');
      expect(songProbes, 0);
    });

    test('深度上限 5 层：第 5 层还能列，第 6 层不再往下', () async {
      // /d0 是根，一路单链下到 d4 正好 5 层；d4 下面的 d5 属于第 6 层。
      const d1 = '/d0/d1';
      const d2 = '$d1/d2';
      const d3 = '$d2/d3';
      const d4 = '$d3/d4';
      final deep = <String, List<String>>{
        '/d0': ['d1/'],
        d1: ['d2/'],
        d2: ['d3/'],
        d3: ['d4/'],
        d4: ['d5/'],
      };

      // 第 5 层没有封面：完整走完，不越界去列它的子目录。
      final noCover = tree(deep);
      final missed = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/d0',
        listDirectory: noCover.list,
        probeImage: (_) async => null,
        probeSong: (_) async => null,
      );
      expect(noCover.visited, ['/d0', d1, d2, d3, d4]);
      expect(missed.hit, isNull);
      expect(missed.conclusive, isTrue);

      // 第 5 层有封面：能拿到，说明上限是「含第 5 层」而不是「到第 5 层前停」。
      final withCover = tree({...deep, d4: ['cover.jpg']});
      String? probed;
      final found = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/d0',
        listDirectory: withCover.list,
        probeImage: (image) async {
          probed = image.path;
          return hitFor('deep');
        },
        probeSong: (_) async => null,
      );
      expect(probed, '$d4/cover.jpg');
      expect(found.hit?.thumbnailPath, '/cache/deep.jpg');
      expect(withCover.visited, isNot(contains('$d4/d5')));
    });

    test('预算耗尽时标记 truncated，不当成「确认没封面」', () async {
      // 一个宽目录，每个子目录都没有封面。
      final spec = <String, List<String>>{
        '/wide': [for (var i = 0; i < 50; i++) 's$i/'],
        for (var i = 0; i < 50; i++) '/wide/s$i': ['01.mp3'],
      };
      final t = tree(spec);

      final result = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/wide',
        listDirectory: t.list,
        probeImage: (_) async => null,
        probeSong: (_) async => null,
        maxListedDirectories: 6,
      );

      expect(result.hit, isNull);
      expect(result.truncated, isTrue);
      expect(result.conclusive, isFalse);
      expect(result.listedDirectories, 6);
      expect(t.visited.length, 6);
    });

    test('列目录失败标记 failed，不能据此判死', () async {
      final result = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/gone',
        listDirectory: (_) async => throw const SocketExceptionStub(),
        probeImage: (_) async => null,
        probeSong: (_) async => null,
      );

      expect(result.hit, isNull);
      expect(result.failed, isTrue);
      expect(result.truncated, isFalse);
      expect(result.conclusive, isFalse);
    });

    test('整棵树都没有封面时 conclusive 为真，才会写跳过标记', () async {
      final t = tree({
        '/empty': ['sub/'],
        '/empty/sub': [],
      });

      final result = await RemoteFolderCoverService.searchSubtree(
        rootPath: '/empty',
        listDirectory: t.list,
        probeImage: (_) async => null,
        probeSong: (_) async => null,
      );

      expect(result.hit, isNull);
      expect(result.conclusive, isTrue);
      expect(t.visited, ['/empty', '/empty/sub']);
    });
  });
}

/// 只为了让「列目录抛异常」走到 catch 分支，不依赖 dart:io。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}