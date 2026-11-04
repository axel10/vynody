import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/audio/audio_service.dart';

Uint8List _bytes(int length, int fill) =>
    Uint8List(length)..fillRange(0, length, fill);

void main() {
  group('AudioService URI & Artwork Cache Tests', () {
    test('safeDecodeUri returns raw string if no % present without decode overhead', () {
      const plainPath = '/storage/emulated/0/Music/Album/Song.mp3';
      expect(AudioService.safeDecodeUri(plainPath), plainPath);
      expect(AudioService.safeDecodeUri(null), '');
      expect(AudioService.safeDecodeUri(''), '');
    });

    test('safeDecodeUri correctly decodes percent-encoded URI', () {
      const encoded = 'file:///storage/emulated/0/Music/%E6%AD%8C%E6%9B%B2.mp3';
      const expected = 'file:///storage/emulated/0/Music/歌曲.mp3';
      expect(AudioService.safeDecodeUri(encoded), expected);
    });

    test('safeDecodeUri gracefully handles malformed percent encoding', () {
      const malformed = '/storage/100%_pure_music.mp3';
      expect(AudioService.safeDecodeUri(malformed), malformed);
    });
  });

  group('封面被替换后内存缓存必须失效', () {
    // 回归：磁盘上的封面文件按内容 md5 命名，换封面天然换路径，列表页
    // （SongThumbnail 读 artworkPath/thumbnailPath）会跟着刷新；而 AudioService
    // 的封面内存缓存以**曲目路径**为 key，不主动失效就一直是旧图，播放页
    // （CoverCarousel 优先读这份缓存）永远停在旧封面上。
    test('新封面比旧封面小时同样覆盖（不能靠字节数判断新旧）', () {
      final cache = <String, Uint8List>{};
      // 旧值：播放时从文件里解码出的内嵌原图，通常比网络封面大得多。
      final oldCover = _bytes(1024 * 1024, 1);
      // 新值：MusicBrainz / 网络补全下载的封面。
      final newCover = _bytes(300 * 1024, 2);
      cache['/music/album/track.flac'] = oldCover;

      AudioService.syncArtworkCacheAfterReplace(
        cache,
        path: '/music/album/track.flac',
        artworkBytes: newCover,
      );

      expect(cache['/music/album/track.flac'], same(newCover));
    });

    test('artworkBytes 为 null 时丢弃旧字节（清理封面）', () {
      final cache = <String, Uint8List>{
        '/music/album/track.flac': _bytes(64, 1),
      };

      AudioService.syncArtworkCacheAfterReplace(
        cache,
        path: '/music/album/track.flac',
        artworkBytes: null,
      );

      expect(cache.containsKey('/music/album/track.flac'), isFalse);
    });

    test('artworkBytes 为空字节视同没有封面', () {
      final cache = <String, Uint8List>{
        '/music/album/track.flac': _bytes(64, 1),
      };

      AudioService.syncArtworkCacheAfterReplace(
        cache,
        path: '/music/album/track.flac',
        artworkBytes: Uint8List(0),
      );

      expect(cache.containsKey('/music/album/track.flac'), isFalse);
    });

    test('百分号编码与解码路径两个槽位一起换新', () {
      const encoded = 'file:///music/%E6%AD%8C%E6%9B%B2.flac';
      const decoded = 'file:///music/歌曲.flac';
      final oldCover = _bytes(512, 1);
      final newCover = _bytes(128, 2);
      final cache = <String, Uint8List>{
        encoded: oldCover,
        decoded: oldCover,
      };

      AudioService.syncArtworkCacheAfterReplace(
        cache,
        path: encoded,
        artworkBytes: newCover,
      );

      expect(cache[encoded], same(newCover));
      expect(cache[decoded], same(newCover));
      expect(cache.values.any((entry) => identical(entry, oldCover)), isFalse);
    });

    test('写入不越过容量上限', () {
      const maxEntries = 8;
      final cache = <String, Uint8List>{};
      for (var i = 0; i < maxEntries; i++) {
        AudioService.syncArtworkCacheAfterReplace(
          cache,
          path: '/music/track_$i.flac',
          artworkBytes: _bytes(4, i),
          maxEntries: maxEntries,
        );
      }

      final newCover = _bytes(4, 99);
      AudioService.syncArtworkCacheAfterReplace(
        cache,
        path: '/music/brand_new.flac',
        artworkBytes: newCover,
        maxEntries: maxEntries,
      );

      expect(cache.length, lessThanOrEqualTo(maxEntries));
      expect(cache['/music/brand_new.flac'], same(newCover));
    });
  });

  group('applyUpdatedSongMetadata 的封面缓存契约', () {
    // AudioService 是 Riverpod Notifier、且依赖 Rust 音频内核，单测里起不了实例，
    // 这里退一步锁住源码契约：只要这个入口还在改写封面，就必须同步缓存。
    //
    // 少这一行时的现象：MusicBrainz 补全 / 手动改标签后，队列页封面是新的，
    // 播放页仍旧。删掉这行请连带删掉本测试，并确认 CoverCarousel 有了别的来源。
    test('改写元数据的入口必须调用 syncArtworkCacheAfterReplace', () {
      final source =
          File('lib/player/audio/audio_service.dart').readAsStringSync();
      final start = source.indexOf('Future<void> applyUpdatedSongMetadata(');
      expect(start, greaterThanOrEqualTo(0),
          reason: 'applyUpdatedSongMetadata 被改名或删除，请同步更新本测试');

      final end = source.indexOf('Future<void> _refreshCurrentWaveform(', start);
      expect(end, greaterThan(start), reason: '定位不到 applyUpdatedSongMetadata 的函数体');

      final body = source.substring(start, end);
      expect(
        body.contains('syncArtworkCacheAfterReplace('),
        isTrue,
        reason: 'applyUpdatedSongMetadata 不再同步封面内存缓存：'
            '播放页（CoverCarousel 优先读 AudioService 的封面缓存）会继续显示旧封面',
      );
    });
  });
}
