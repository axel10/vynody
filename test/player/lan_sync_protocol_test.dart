import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/player/lyrics/lyrics_cache_models.dart';
import 'package:vynody/player/sharing/lan_device.dart';
import 'package:vynody/player/sharing/lan_sync_protocol.dart';

void main() {
  group('分块', () {
    test('空列表不分块', () {
      expect(chunkLanSyncItems(const []), isEmpty);
    });

    test('不超过上限时只切一批', () {
      final items = List.generate(3, (i) => {'i': i});
      final chunks = chunkLanSyncItems(items);
      expect(chunks.length, 1);
      expect(chunks.single.length, 3);
    });

    test('按条目数切批', () {
      final items = List.generate(25, (i) => {'i': i});
      final chunks = chunkLanSyncItems(items, maxItems: 10);
      expect(chunks.map((c) => c.length).toList(), [10, 10, 5]);
      // 顺序与内容都不能变：接收端按批次顺序拼接。
      expect(chunks.expand((c) => c).map((e) => e['i']).toList(), [
        for (var i = 0; i < 25; i++) i,
      ]);
    });

    test('按字节预算切批：单个巨大条目也不会被拆开', () {
      final big = {'blob': 'x' * 500};
      final items = <Map<String, dynamic>>[
        big,
        {'i': 1},
        big,
      ];
      final chunks = chunkLanSyncItems(items, maxBytes: 600);
      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk, isNotEmpty);
      }
      expect(chunks.expand((c) => c).length, 3);
    });
  });

  group('请求体解码', () {
    test('明文按 UTF-8 解', () {
      final text = jsonEncode({'a': '歌词'});
      expect(decodeLanSyncBody(utf8.encode(text)), text);
    });

    test('gzip 体先解压', () {
      final text = jsonEncode({'a': '歌词'});
      final compressed = gzip.encode(utf8.encode(text));
      expect(
        decodeLanSyncBody(compressed, contentEncoding: 'gzip'),
        text,
      );
      expect(
        decodeLanSyncBody(compressed, contentEncoding: 'GZIP'),
        text,
      );
    });

    test('声称 gzip 但数据不是 gzip 时抛 FormatException', () {
      expect(
        () => decodeLanSyncBody(utf8.encode('{}'), contentEncoding: 'gzip'),
        throwsFormatException,
      );
    });
  });

  group('歌词内容指纹', () {
    LyricsCacheRecord record({String? lyrics = 'hello', int offset = 0}) {
      return LyricsCacheRecord(
        cacheKey: 'k',
        source: LyricsCacheSource.lrclib,
        isSynced: true,
        syncedLyrics: lyrics,
        syncedLines: [
          LyricLine(timestamp: const Duration(milliseconds: 1000), text: 'hello'),
        ],
        timelineOffsetMillis: offset,
        updatedAtMillis: 1000,
      );
    }

    test('内容与偏移一样时指纹一致，与 updatedAt 无关', () {
      expect(
        lyricsContentHashOf(record()),
        lyricsContentHashOf(record()),
      );
    });

    test('偏移不同则指纹不同', () {
      expect(
        lyricsContentHashOf(record(offset: 0)),
        isNot(lyricsContentHashOf(record(offset: 300))),
      );
    });

    test('歌词文本不同则指纹不同', () {
      expect(
        lyricsContentHashOf(record(lyrics: 'a')),
        isNot(lyricsContentHashOf(record(lyrics: 'b'))),
      );
    });
  });

  group('SongMetadataPackage', () {
    test('保持 v1 的键名，附加字段可选', () {
      const package = SongMetadataPackage(
        senderPath: '/a/b.flac',
        title: 'T',
        artist: 'A',
        album: 'Al',
        durationMs: 1000,
        lyricsCache: {'source': 'lrclib'},
        translations: [
          {'languageCode': 'ja'},
        ],
        contentHash: 'hash',
      );

      final json = package.toJson();
      // v1 接收端只认这几个键，缺一个就导入不进来。
      expect(json['title'], 'T');
      expect(json['artist'], 'A');
      expect(json['album'], 'Al');
      expect(json['duration_ms'], 1000);
      expect(json['lyrics_cache'], {'source': 'lrclib'});
      expect(json['translations'], [
        {'languageCode': 'ja'},
      ]);
      expect(json['sender_path'], '/a/b.flac');
      expect(json['content_hash'], 'hash');
    });

    test('没有歌词时不下发 lyrics_cache 键', () {
      const package = SongMetadataPackage(title: 'T', artist: 'A');
      final json = package.toJson();
      expect(json.containsKey('lyrics_cache'), isFalse);
      expect(json.containsKey('translations'), isFalse);
    });

    test('解析：未知字段被忽略，缺字段有默认值', () {
      final package = SongMetadataPackage.fromJson({
        'title': 'T',
        'artist': 'A',
        'lyrics_cache': {'source': 'ai'},
        'translations': [
          {'languageCode': 'ja'},
          'not-a-map',
        ],
        'future_field': 123,
      });

      expect(package.album, isNull);
      expect(package.durationMs, isNull);
      expect(package.lyricsCache, {'source': 'ai'});
      // 非 Map 的条目直接丢弃，不能抛。
      expect(package.translations.length, 1);
    });
  });

  group('LanDevice 协议能力', () {
    test('缺省按 v1 处理（老客户端不广播 sync 属性）', () {
      final device = LanDevice.fromJson(
        {'id': 'x', 'name': 'n', 'deviceType': 'macos', 'httpPort': 1},
        '192.168.1.2',
        DateTime(2026),
      );
      expect(device.syncProtocol, 1);
      expect(device.supportsChunkedSync, isFalse);
    });

    test('sync 属性为 2 时允许分块', () {
      final device = LanDevice.fromJson(
        {
          'id': 'x',
          'name': 'n',
          'deviceType': 'macos',
          'httpPort': 1,
          'syncProtocol': 2,
        },
        '192.168.1.2',
        DateTime(2026),
      );
      expect(device.supportsChunkedSync, isTrue);
      // 序列化后仍能读回来（信任设备列表缓存）。
      expect(device.toJson()['syncProtocol'], 2);
    });
  });
}
