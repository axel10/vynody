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
}