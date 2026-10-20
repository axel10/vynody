import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/services/remote_download_service.dart';

/// 远程下载落盘层级由页面 / 栏目决定，与「勾一首还是勾多首」无关。
/// 这里锁住三种 layout 的目录形状，避免某个入口漏传参数又退回默认值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final server = RemoteServer(
    id: 'subsonic_layout',
    name: 'Navidrome',
    type: RemoteServerType.subsonic,
    url: 'http://example.com:4533',
    username: 'alice',
    createdAt: DateTime.now(),
  );

  const base = '/downloads';

  MusicFile song({
    String? artist = 'Track Artist',
    String? albumArtist = 'Album Artist',
    String? album = 'The Album',
  }) {
    return MusicFile(
      path: 'subsonic://subsonic_layout/track-1',
      name: 'Title.mp3',
      title: 'Title',
      artist: artist,
      albumArtist: albumArtist,
      album: album,
      trackNumber: 1,
    );
  }

  final notifier = RemoteDownloadNotifier();

  test('album layout 只按专辑落一层，与单曲下载保持一致', () async {
    final path = await notifier.buildLocalTrackPath(
      song: song(),
      baseFolder: base,
      server: server,
    );
    expect(path, p.join(base, 'The Album', '01 - Title.mp3'));
  });

  test('artist layout 带艺术家与专辑两层（艺术家页单曲/批量同构）', () async {
    final path = await notifier.buildLocalTrackPath(
      song: song(),
      baseFolder: base,
      server: server,
      collectionFolder: 'Page Artist',
      layout: RemoteDownloadLayout.artist,
    );
    expect(path, p.join(base, 'Page Artist', 'The Album', '01 - Title.mp3'));
  });

  test('artist layout 缺集合名时逐曲回落到专辑艺术家，不拆散合辑', () async {
    final path = await notifier.buildLocalTrackPath(
      song: song(artist: 'Various Artists', albumArtist: 'Compilation Owner'),
      baseFolder: base,
      server: server,
      layout: RemoteDownloadLayout.artist,
    );
    expect(
      path,
      p.join(base, 'Compilation Owner', 'The Album', '01 - Title.mp3'),
    );
  });

  test('playlist layout 只有歌单一层，不再按专辑分层', () async {
    final path = await notifier.buildLocalTrackPath(
      song: song(),
      baseFolder: base,
      server: server,
      collectionFolder: 'My Mix',
      layout: RemoteDownloadLayout.playlist,
    );
    expect(path, p.join(base, 'My Mix', '01 - Title.mp3'));
  });

  test('playlist layout 缺集合名时退回专辑层，不铺到下载根目录', () async {
    final path = await notifier.buildLocalTrackPath(
      song: song(),
      baseFolder: base,
      server: server,
      layout: RemoteDownloadLayout.playlist,
    );
    expect(path, p.join(base, 'The Album', '01 - Title.mp3'));
  });

  group('RemoteDownloadRequest', () {
    MusicFile track(String id) => MusicFile(
          path: 'subsonic://subsonic_layout/$id',
          name: '$id.mp3',
          title: id,
          album: 'The Album',
        );

    test('单集合构造：一批，layout 与集合名原样透传', () {
      final request = RemoteDownloadRequest(
        server: server,
        password: 'pw',
        songs: [track('a'), track('b')],
        layout: RemoteDownloadLayout.artist,
        collectionFolder: 'Page Artist',
      );

      expect(request.batches, hasLength(1));
      expect(request.batches.single.layout, RemoteDownloadLayout.artist);
      expect(request.batches.single.collectionFolder, 'Page Artist');
      expect(request.songCount, 2);
      expect(request.isEmpty, isFalse);
    });

    test('多集合构造：每个集合各带自己的目录名，songCount 忽略空批', () {
      final request = RemoteDownloadRequest.grouped(
        server: server,
        password: 'pw',
        batches: [
          RemoteDownloadBatch(
            songs: [track('a')],
            layout: RemoteDownloadLayout.artist,
            collectionFolder: 'Artist One',
          ),
          RemoteDownloadBatch(
            songs: [track('b'), track('c')],
            layout: RemoteDownloadLayout.artist,
            collectionFolder: 'Artist Two',
          ),
          const RemoteDownloadBatch(songs: []),
        ],
      );

      expect(request.batches, hasLength(3));
      expect(request.nonEmptyBatches, hasLength(2));
      expect(request.songCount, 3);
      expect(request.nonEmptyBatches[1].collectionFolder, 'Artist Two');
    });

    test('空曲目列表的请求 isEmpty，不会进队列', () {
      final request = RemoteDownloadRequest(
        server: server,
        password: 'pw',
        songs: const [],
      );

      expect(request.isEmpty, isTrue);
      expect(request.batches, isEmpty);
    });
  });
}
