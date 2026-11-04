import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';

/// 可写格式清单是 `isMetadataWritable` 的唯一真相，界面上的
/// 「保存到源文件和 App」、右键「保存到文件」、歌词写回全都靠它开关。
///
/// 回归背景：清单长期停在 `mp3/m4a/mp4/flac/wav`，而 `flutter_taglib` 早就
/// 打开了 APE / ASF / DSF / Matroska / RIFF / TrueAudio / Vorbis 模块，写入口
/// 是通用的 `fileRef->save()`。结果 OGG、Opus、AIFF、APE、DSF、WebM 这些
/// 明明能写的格式被硬挡在门外，按钮直接置灰。
void main() {
  group('isMetadataWritable', () {
    test('TagLib 有 save() 的容器都允许写回', () {
      const expected = [
        '.mp3',
        '.m4a',
        '.m4b',
        '.mp4',
        '.flac',
        '.ogg',
        '.opus',
        '.wav',
        '.aif',
        '.aiff',
        '.ape',
        '.dsf',
        '.webm',
      ];
      for (final ext in expected) {
        expect(
          isMetadataWritable('/music/song$ext'),
          isTrue,
          reason: '$ext 应该可以写回源文件',
        );
      }
    });

    test('TagLib 连解析器都没有的格式不允许写回', () {
      const notWritable = ['.aac', '.caf', '.dff', '.mid', '.midi', '.m4p'];
      for (final ext in notWritable) {
        expect(
          isMetadataWritable('/music/song$ext'),
          isFalse,
          reason: '$ext 不应该被判定为可写',
        );
      }
    });

    test('扩展名大小写不敏感', () {
      expect(isMetadataWritable('/music/Night.FLAC'), isTrue);
      expect(isMetadataWritable('/music/Night.Mp3'), isTrue);
      expect(isMetadataWritable('/music/Night.AAC'), isFalse);
    });

    test('没有扩展名 / 空路径不会误判', () {
      expect(isMetadataWritable('/music/no_extension'), isFalse);
      expect(isMetadataWritable(''), isFalse);
    });
  });

  group('清单与曲库扫描范围', () {
    test('扫描能收录的格式里，只有 MIDI / 裸 AAC / CAF / DFF / DRM 这几个写不了', () {
      final notWritable = MusicFileUtils.supportedAudioExtensions
          .where((ext) => !writableMetadataExtensions.contains(ext))
          .toSet();

      expect(
        notWritable,
        {'.aac', '.caf', '.dff', '.mid', '.midi', '.m4p'},
        reason: '多出一个就说明有能写的格式被挡在门外，少一个说明清单里混了假格式',
      );
    });

    test('清单只多出 .mp4（视频容器，以前就在里面），不会凭空放进库外扩展名', () {
      final extra = writableMetadataExtensions
          .difference(MusicFileUtils.supportedAudioExtensions)
          .toSet();
      expect(extra, {'.mp4'});
    });
  });

  group('保存入口契约', () {
    late final String source = File(
      'lib/player/metadata/metadata_helper.dart',
    ).readAsStringSync();

    test('写文件失败时可以降级为仅保存到 App', () {
      expect(source, contains('fallbackToAppOnWriteFailure'));
      expect(source, contains('TagWriteFallback.unsupportedFormat'));
      expect(source, contains('TagWriteFallback.fileOccupied'));
    });

    test('结果里带「到底写进文件了没有」，界面不能再靠「我请求了写文件」猜', () {
      expect(source, contains('class SelectedMetadataSaveResult'));
      expect(source, contains('wroteToFile'));
    });

    test('允许降级的调用方要保留大图，写失败后播放页才不会只剩缩略图', () {
      expect(
        source,
        contains('saveLarge: !writeToFile || fallbackToAppOnWriteFailure'),
      );
    });
  });
}
