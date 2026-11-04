import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';

/// 主题色是「当前这张封面」的衍生数据，必须跟着封面一起换。
///
/// 回归背景：MusicBrainz 补全走「先 `saveArtworkAndThumbnail` 把封面落盘，
/// 再把产物路径传进 `saveSelectedSongMetadata`」的分支，`needsArtworkSave`
/// 为 false，本方法没有机会重新提取配色。于是曲目库里保留的是**旧封面**算出的
/// blob：封面换了，而动态流变背景、歌词高亮、播放控件辉光全都还是旧颜色。
void main() {
  Uint8List blob(int fill) => Uint8List(8)..fillRange(0, 8, fill);

  group('selectThemeColorsBlob', () {
    test('调用方带来了新封面的配色 → 用新的', () {
      final incoming = blob(2);
      final existing = blob(1);

      expect(
        selectThemeColorsBlob(
          incoming: incoming,
          existing: existing,
          artworkCleared: false,
        ),
        same(incoming),
      );
    });

    test('纯文本编辑（没有新配色）→ 沿用库里原值', () {
      final existing = blob(1);

      expect(
        selectThemeColorsBlob(
          incoming: null,
          existing: existing,
          artworkCleared: false,
        ),
        same(existing),
      );
    });

    test('清除封面 → 连配色一起清掉，即使调用方还传了配色', () {
      expect(
        selectThemeColorsBlob(
          incoming: blob(2),
          existing: blob(1),
          artworkCleared: true,
        ),
        isNull,
      );
    });

    test('库里本来没有配色时也不会凭空造一个', () {
      expect(
        selectThemeColorsBlob(
          incoming: null,
          existing: null,
          artworkCleared: false,
        ),
        isNull,
      );
    });
  });
}
