import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/player/lastfm/lastfm_api_client.dart';
import 'package:vynody/player/lastfm/lastfm_scrobble_entry.dart';
import 'package:vynody/player/lastfm/scrobble_tracker.dart';
import 'package:vynody/models/music_file.dart';

void main() {
  group('签名', () {
    test('参数按 key 升序拼接，format 与 api_sig 不参与', () {
      final signature = signLastFmParams(
        <String, String>{
          'method': 'track.scrobble',
          'api_key': 'abc123',
          'artist[0]': 'A&B',
          'track[0]': 'T',
          'timestamp[0]': '1700000000',
          'format': 'json',
          'api_sig': 'ignored',
        },
        'secret',
      );

      // 期望值由 md5("api_keyabc123" "artist[0]A&B" "methodtrack.scrobble"
      // "timestamp[0]1700000000" "track[0]T" "secret") 独立算出。
      expect(signature, '56d85cf56e864257e28a0e7da750409e');
    });

    test('值不做 URL 编码', () {
      final signature = signLastFmParams(
        <String, String>{
          'method': 'auth.getToken',
          'api_key': 'abc123',
        },
        'secret',
      );
      expect(signature, '8cd9f5ee867001c9f506b4b5a30f8440');
    });
  });

  group('上报条目', () {
    MusicFile buildSong({
      String? title,
      String? artist,
      String? albumArtist,
      int? durationMillis,
    }) {
      return MusicFile(
        path: '/music/test.flac',
        name: 'test.flac',
        title: title,
        artist: artist,
        albumArtist: albumArtist,
        durationMillis: durationMillis,
      );
    }

    test('标题为空时跳过而不是上报垃圾数据', () {
      final entry = LastFmScrobbleEntry.fromSong(
        buildSong(title: null, artist: 'A'),
        playedAt: DateTime(2026),
      );
      expect(entry, isNull);
    });

    test('artist 为空时回退到 albumArtist', () {
      final entry = LastFmScrobbleEntry.fromSong(
        buildSong(title: 'T', artist: '  ', albumArtist: 'VA'),
        playedAt: DateTime(2026),
      );
      expect(entry?.artist, 'VA');
    });

    test('批量参数使用数组下标且时间戳取秒', () {
      final entry = LastFmScrobbleEntry.fromSong(
        buildSong(title: 'T', artist: 'A', durationMillis: 200000),
        playedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      )!;
      final params = entry.toScrobbleParams(1);
      expect(params['artist[1]'], 'A');
      expect(params['timestamp[1]'], '1700000000');
      expect(params['duration[1]'], '200');
      expect(params.containsKey('album[1]'), isFalse);
    });
  });

  group('阈值状态机', () {
    const path = '/music/a.flac';

    /// 从 [from] 按 1 秒步进推进到 [to]，返回首次出现的信号。
    ScrobbleSignal advance(
      ScrobbleTracker tracker, {
      required Duration from,
      required Duration to,
      Duration? duration,
      bool isPlaying = true,
    }) {
      var position = from;
      while (position < to) {
        position += const Duration(seconds: 1);
        final signal = tracker.update(
          path: path,
          position: position,
          isPlaying: isPlaying,
          duration: duration,
        );
        if (signal != ScrobbleSignal.none) return signal;
      }
      return ScrobbleSignal.none;
    }

    test('新曲目返回 nowPlaying', () {
      final tracker = ScrobbleTracker();
      expect(
        tracker.update(
          path: path,
          position: Duration.zero,
          isPlaying: true,
          duration: const Duration(minutes: 3),
        ),
        ScrobbleSignal.nowPlaying,
      );
    });

    test('时长过半才计入', () {
      final tracker = ScrobbleTracker();
      const duration = Duration(seconds: 200);
      tracker.update(
        path: path,
        position: Duration.zero,
        isPlaying: true,
        duration: duration,
      );
      expect(
        advance(
          tracker,
          from: Duration.zero,
          to: const Duration(seconds: 90),
          duration: duration,
        ),
        ScrobbleSignal.none,
      );
      expect(
        advance(
          tracker,
          from: const Duration(seconds: 90),
          to: const Duration(seconds: 110),
          duration: duration,
        ),
        ScrobbleSignal.scrobble,
      );
    });

    test('长曲目以 4 分钟封顶', () {
      final tracker = ScrobbleTracker();
      const duration = Duration(minutes: 10);
      expect(
        ScrobbleTracker.thresholdFor(duration),
        const Duration(minutes: 4),
      );
      tracker.update(
        path: path,
        position: Duration.zero,
        isPlaying: true,
        duration: duration,
      );
      expect(
        advance(
          tracker,
          from: Duration.zero,
          to: const Duration(minutes: 3, seconds: 50),
          duration: duration,
        ),
        ScrobbleSignal.none,
      );
    });

    test('时长未知时按 4 分钟兜底', () {
      expect(ScrobbleTracker.thresholdFor(null), const Duration(minutes: 4));
    });

    test('不足 30 秒的曲目永不计入', () {
      final tracker = ScrobbleTracker();
      const duration = Duration(seconds: 20);
      expect(
        tracker.update(
          path: path,
          position: Duration.zero,
          isPlaying: true,
          duration: duration,
        ),
        ScrobbleSignal.none,
      );
      expect(
        advance(
          tracker,
          from: Duration.zero,
          to: const Duration(seconds: 19),
          duration: duration,
        ),
        ScrobbleSignal.none,
      );
    });

    test('暂停期间不累计', () {
      final tracker = ScrobbleTracker();
      const duration = Duration(seconds: 100);
      tracker.update(
        path: path,
        position: Duration.zero,
        isPlaying: true,
        duration: duration,
      );
      advance(
        tracker,
        from: Duration.zero,
        to: const Duration(seconds: 40),
        duration: duration,
      );
      // 暂停时位置不动
      for (var i = 0; i < 30; i++) {
        tracker.update(
          path: path,
          position: const Duration(seconds: 40),
          isPlaying: false,
          duration: duration,
        );
      }
      expect(
        advance(
          tracker,
          from: const Duration(seconds: 40),
          to: const Duration(seconds: 49),
          duration: duration,
        ),
        ScrobbleSignal.none,
      );
    });

    test('向前拖动不计入已听时长', () {
      final tracker = ScrobbleTracker();
      const duration = Duration(minutes: 5);
      tracker.update(
        path: path,
        position: Duration.zero,
        isPlaying: true,
        duration: duration,
      );
      advance(
        tracker,
        from: Duration.zero,
        to: const Duration(seconds: 20),
        duration: duration,
      );
      // 直接跳到 4:30，属于 seek，不应触发计入
      expect(
        tracker.update(
          path: path,
          position: const Duration(minutes: 4, seconds: 30),
          isPlaying: true,
          duration: duration,
        ),
        ScrobbleSignal.none,
      );
    });

    test('回拖到开头视为重播，可再次计入', () {
      final tracker = ScrobbleTracker();
      const duration = Duration(seconds: 100);
      tracker.update(
        path: path,
        position: Duration.zero,
        isPlaying: true,
        duration: duration,
      );
      expect(
        advance(
          tracker,
          from: Duration.zero,
          to: const Duration(seconds: 55),
          duration: duration,
        ),
        ScrobbleSignal.scrobble,
      );
      expect(tracker.hasScrobbled, isTrue);

      expect(
        tracker.update(
          path: path,
          position: Duration.zero,
          isPlaying: true,
          duration: duration,
        ),
        ScrobbleSignal.nowPlaying,
      );
      expect(tracker.hasScrobbled, isFalse);
    });
  });
}
