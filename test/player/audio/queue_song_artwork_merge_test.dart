import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_service.dart';

/// 队列项合并规则：「新值为 null 就沿用旧值」不能把**已清除的封面**搬回来。
///
/// 回归背景：清除封面走的是 `artworkBytes: Uint8List(0)`，`_songFromMetadata`
/// 会把它规整成 null；随后旧的合并规则用 `?? existing.artworkBytes` 又把旧
/// 字节填回去，于是队列里始终留着一张已经删掉的封面，播放页背景 / 轮播 /
/// 网格纹理都跟着停在旧图上。
void main() {
  Uint8List bytesOf(int length, int fill) =>
      Uint8List(length)..fillRange(0, length, fill);

  MusicFile song({
    Uint8List? artworkBytes,
    Uint8List? themeColorsBlob,
    String? artworkPath,
    String title = 'Song',
  }) {
    return MusicFile(
      path: '/music/song.flac',
      name: 'song.flac',
      artworkBytes: artworkBytes,
      themeColorsBlob: themeColorsBlob,
      artworkPath: artworkPath,
      title: title,
    );
  }

  group('clearArtwork', () {
    test('清除封面时丢掉旧字节与旧主题色', () {
      final existing = song(
        artworkBytes: bytesOf(512, 1),
        themeColorsBlob: bytesOf(8, 2),
        artworkPath: '/cache/old_cover.jpg',
      );
      // 更新后的曲目已经没有任何封面信息（对应 metadata 里被清空的字段）。
      final updated = song(artworkPath: null);

      final merged = AudioService.mergeQueueSongUpdate(
        updated,
        existing,
        clearArtwork: true,
      );

      expect(merged.artworkBytes, isNull);
      expect(merged.themeColorsBlob, isNull);
      expect(merged.artworkPath, isNull);
    });

    test('清除封面时不能把波形一起丢掉（波形与封面无关）', () {
      final existing = song(
        artworkBytes: bytesOf(64, 1),
        themeColorsBlob: bytesOf(4, 2),
      ).copyWith(waveformBlob: bytesOf(32, 9));
      final updated = song();

      final merged = AudioService.mergeQueueSongUpdate(
        updated,
        existing,
        clearArtwork: true,
      );

      expect(merged.artworkBytes, isNull);
      expect(merged.waveformBlob, isNotNull);
    });

    test('换上新封面时新字节不会被旧值覆盖', () {
      final existing = song(
        artworkBytes: bytesOf(1024, 1),
        themeColorsBlob: bytesOf(8, 2),
      );
      final newBytes = bytesOf(256, 3); // 比旧封面小，正是线上踩到的区间

      final merged = AudioService.mergeQueueSongUpdate(
        song(artworkBytes: newBytes),
        existing,
      );

      expect(merged.artworkBytes, same(newBytes));
    });
  });

  group('纯文本编辑', () {
    test('未提供封面时沿用旧字节与旧主题色', () {
      final oldBytes = bytesOf(128, 1);
      final oldColors = bytesOf(8, 2);
      final existing = song(
        artworkBytes: oldBytes,
        themeColorsBlob: oldColors,
      );

      // 只改了标题：`artworkBytes == null` 表示「这次没动封面」。
      final merged = AudioService.mergeQueueSongUpdate(
        song(title: 'Renamed'),
        existing,
      );

      expect(merged.artworkBytes, same(oldBytes));
      expect(merged.themeColorsBlob, same(oldColors));
      expect(merged.title, 'Renamed');
    });
  });
}
