import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_service.dart';

void main() {
  group('队列项二进制列剥离规则', () {
    // 队列是会话级常驻，只允许当前曲带 artworkBytes / waveformBlob；
    // 其余必须剥成 null，否则每播一首就多留一份原图（100KB~3MB，
    // 且不走 ImageCache）。

    test('没有当前曲时一律剥离', () {
      expect(
        AudioService.shouldStripQueueBinaryBlobs(
          songPath: '/music/a.mp3',
          keepPath: null,
        ),
        isTrue,
      );
      expect(
        AudioService.shouldStripQueueBinaryBlobs(
          songPath: '/music/a.mp3',
          keepPath: '',
        ),
        isTrue,
      );
    });

    test('当前曲保留二进制列', () {
      expect(
        AudioService.shouldStripQueueBinaryBlobs(
          songPath: '/music/a.mp3',
          keepPath: '/music/a.mp3',
        ),
        isFalse,
      );
    });

    test('非当前曲剥离', () {
      expect(
        AudioService.shouldStripQueueBinaryBlobs(
          songPath: '/music/a.mp3',
          keepPath: '/music/b.mp3',
        ),
        isTrue,
      );
    });

    test('同一目录下的兄弟曲目互不影响', () {
      for (final other in const <String>[
        '/music/a.flac',
        '/music/a.mp3.bak',
        '/music/aa.mp3',
      ]) {
        expect(
          AudioService.shouldStripQueueBinaryBlobs(
            songPath: other,
            keepPath: '/music/a.mp3',
          ),
          isTrue,
          reason: '$other 不是当前曲，不该保留二进制列',
        );
      }
    });

    test('空路径绝不被当成当前曲保留', () {
      expect(
        AudioService.shouldStripQueueBinaryBlobs(songPath: '', keepPath: ''),
        isTrue,
      );
    });
  });

  group('MusicFile.copyWith 必须能真的把二进制列置 null', () {
    // 整套收口依赖 freezed 的 sentinel：copyWith(artworkBytes: null) 会真的写
    // null，而不是像手写 copyWith 那样 `?? this.artworkBytes` 静默保留旧值。
    // 一旦有人把 MusicFile 改成手写 copyWith，清理会静默失效、内存问题原样回来，
    // 而不会报任何错 —— 这条测试就是那个哨兵。

    test('artworkBytes 与 waveformBlob 都能被置 null', () {
      final song = MusicFile(
        path: '/music/a.mp3',
        name: 'a.mp3',
        artworkBytes: Uint8List.fromList(<int>[1, 2, 3]),
        waveformBlob: Uint8List.fromList(<int>[4, 5, 6]),
      );

      expect(song.artworkBytes, isNotNull);
      expect(song.waveformBlob, isNotNull);

      final stripped =
          song.copyWith(artworkBytes: null, waveformBlob: null);

      expect(stripped.artworkBytes, isNull);
      expect(stripped.waveformBlob, isNull);
      // 其余字段不能被顺带清掉。
      expect(stripped.path, '/music/a.mp3');
      expect(stripped.name, 'a.mp3');
    });

    test('只传一个字段时另一个保持不变', () {
      final song = MusicFile(
        path: '/music/a.mp3',
        name: 'a.mp3',
        artworkBytes: Uint8List.fromList(<int>[1, 2, 3]),
        waveformBlob: Uint8List.fromList(<int>[4, 5, 6]),
      );

      final onlyArtworkCleared = song.copyWith(artworkBytes: null);

      expect(onlyArtworkCleared.artworkBytes, isNull);
      expect(onlyArtworkCleared.waveformBlob, isNotNull);
    });
  });
}
