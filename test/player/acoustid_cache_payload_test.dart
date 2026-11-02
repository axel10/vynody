import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vynody/player/metadata/acoustid_service.dart';

/// AcoustID 缓存的序列化回归测试。
///
/// 历史问题：四个模型的 `toJson()` 都把该层完整原始 JSON 重新塞进 `raw`，
/// 导致同一份数据在磁盘上被复制 3~5 层（实测平均 120 KB/首、峰值 894 KB/首）。
/// 这里锁住三件事：不写 `raw`、不重复写同名字段、往返后关键字段不丢。
void main() {
  Map<String, dynamic> heavyRaw() => <String, dynamic>{
    'artists': [
      {'id': 'artist-1', 'name': 'Artist', 'joinphrase': ''},
    ],
    'releasegroups': List.generate(
      20,
      (index) => <String, dynamic>{
        'id': 'rg-bulk-$index',
        'title': 'Bulk Release Group $index',
        'secondarytypes': ['Compilation', 'Live'],
        'releases': List.generate(
          10,
          (releaseIndex) => <String, dynamic>{
            'id': 'rel-bulk-$index-$releaseIndex',
            'title': 'Bulk Release $releaseIndex',
            'country': 'US',
            'date': {'year': 2001, 'month': 5, 'day': 15},
            'track_count': 12,
            'payload': 'x' * 200,
          },
        ),
      },
    ),
  };

  AcoustIDResult buildResult() {
    final release = AcoustIDRelease(
      id: 'rel-1',
      title: 'Album',
      country: 'US',
      dateLabel: '2001-05-15',
      trackCount: 12,
      raw: heavyRaw(),
    );
    final releaseGroup = AcoustIDReleaseGroup(
      id: 'rg-1',
      title: 'Album RG',
      type: 'Album',
      secondaryTypes: const ['Compilation'],
      releases: [release],
      raw: heavyRaw(),
    );
    final recording = AcoustIDRecording(
      id: 'rec-1',
      title: 'Song',
      artist: 'Artist',
      durationMillis: 215000,
      releaseGroups: [releaseGroup],
      raw: heavyRaw(),
    );
    return AcoustIDResult(
      id: 'res-1',
      score: 0.95,
      recordings: [recording],
      raw: heavyRaw(),
    );
  }

  String encode(List<AcoustIDResult> results) =>
      jsonEncode(results.map((result) => result.toJson()).toList());

  group('AcoustID 缓存序列化', () {
    test('不写 raw', () {
      final payload = encode([buildResult()]);
      expect(payload.contains('"raw"'), isFalse);
      expect(payload.contains('payload'), isFalse);
    });

    test('不重复写同名字段', () {
      final payload = encode([buildResult()]);
      expect(payload.contains('"releaseGroups"'), isFalse);
      expect(RegExp('"releasegroups"').allMatches(payload).length, 1);
      expect(RegExp('"duration"').allMatches(payload).length, 0);
      expect(RegExp('"length"').allMatches(payload).length, 0);
      expect(RegExp('"durationMillis"').allMatches(payload).length, 1);
    });

    test('体积不随输入 raw 膨胀', () {
      final payload = encode([buildResult()]);
      expect(
        payload.length,
        lessThan(1200),
        reason: '精简后单条缓存应小于 1.2 KB，实际 ${payload.length} B',
      );
    });

    test('往返后关键字段保持', () {
      final payload = encode([buildResult()]);
      final decoded = (jsonDecode(payload) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(AcoustIDResult.fromJson)
          .toList();

      expect(decoded, hasLength(1));
      final result = decoded.single;
      expect(result.id, 'res-1');
      expect(result.score, 0.95);
      expect(result.hasRecordings, isTrue);

      final recording = result.primaryRecording!;
      expect(recording.id, 'rec-1');
      expect(recording.title, 'Song');
      expect(recording.artist, 'Artist');
      expect(recording.durationMillis, 215000);

      final releaseGroup = recording.releaseGroups.single;
      expect(releaseGroup.id, 'rg-1');
      expect(releaseGroup.title, 'Album RG');
      expect(releaseGroup.type, 'Album');
      expect(releaseGroup.secondaryTypes, ['Compilation']);

      final release = releaseGroup.releases.single;
      expect(release.id, 'rel-1');
      expect(release.title, 'Album');
      expect(release.country, 'US');
      expect(release.dateLabel, '2001-05-15');
      expect(release.trackCount, 12);
    });
  });
}
