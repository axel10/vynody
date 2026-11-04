import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/metadata/metadata_helper.dart';

/// 保存结果的提示语必须和事实一致。
///
/// 回归背景：原来界面只拿「我请求了写文件」当结论。批量编辑里混着 `.mid`、
/// `.aac` 这种 TagLib 写不了的格式时，那些歌静默降级成「只存 App」，界面却
/// 照样报「已保存到源文件和 App」——用户以为标签进了文件，其实没有。
void main() {
  SongMetadata song(String path) =>
      SongMetadata(path: path, title: 't', album: 'a', artist: 'b');

  SongTagEditResult result({
    required int written,
    required int appOnly,
    TagWriteFallback fallback = TagWriteFallback.none,
  }) {
    return SongTagEditResult(
      metadata: song('/music/one.flac'),
      writtenToFileCount: written,
      appOnlyCount: appOnly,
      fallback: fallback,
    );
  }

  group('SongTagEditResult', () {
    test('全部写回 → savedToSourceFile 为 true', () {
      final r = result(written: 3, appOnly: 0);
      expect(r.totalCount, 3);
      expect(r.savedToSourceFile, isTrue);
    });

    test('混合格式 → 不能再声称全部写回', () {
      final r = result(
        written: 2,
        appOnly: 1,
        fallback: TagWriteFallback.unsupportedFormat,
      );
      expect(r.totalCount, 3);
      expect(r.savedToSourceFile, isFalse);
    });

    test('全部只存 App → savedToSourceFile 为 false', () {
      final r = result(
        written: 0,
        appOnly: 2,
        fallback: TagWriteFallback.fileOccupied,
      );
      expect(r.savedToSourceFile, isFalse);
    });
  });

  group('songTagEditResultMessage', () {
    final l10n = _FakeL10n();

    test('全部写回 → 报「已保存到源文件和 App」', () {
      expect(
        songTagEditResultMessage(l10n, result(written: 1, appOnly: 0)),
        'ALL_WRITTEN',
      );
      expect(
        songTagEditResultMessage(l10n, result(written: 4, appOnly: 0)),
        'BATCH_ALL_WRITTEN',
      );
    });

    test('全部只存 App → 报「已保存到 App」并附原因', () {
      final message = songTagEditResultMessage(
        l10n,
        result(
          written: 0,
          appOnly: 1,
          fallback: TagWriteFallback.unsupportedFormat,
        ),
      );
      expect(message, contains('APP_ONLY'));
      expect(message, contains('UNSUPPORTED_FORMAT'));
    });

    test('混合 → 报「几首写回、几首仅存 App」', () {
      final message = songTagEditResultMessage(
        l10n,
        result(written: 2, appOnly: 1, fallback: TagWriteFallback.fileOccupied),
      );
      expect(message, 'PARTIAL_2_1\nOCCUPIED');
    });

    test('写失败没有具体原因时只给基础提示', () {
      expect(
        songTagEditResultMessage(l10n, result(written: 0, appOnly: 1)),
        'APP_ONLY',
      );
    });
  });

  group('编辑弹窗契约', () {
    late final String source = File(
      'lib/dialogs/song_tag_edit_dialog.dart',
    ).readAsStringSync();

    test('底部只剩一个保存按钮，「保存到 App」入口不应加回来', () {
      expect(source, isNot(contains('_save(writeToFile:')));
      expect(source, isNot(contains('l10n.saveToApp')));
      expect(
        source,
        contains('onPressed: _isSaving || hasRemote ? null : _save'),
      );
    });

    test('保存时开启写失败降级，避免用户点了保存什么都没发生', () {
      expect(source, contains('fallbackToAppOnWriteFailure: true'));
    });
  });
}

/// 只实现提示语用到的几个成员，其余交给 noSuchMethod。
/// 单测里不方便起真实 Localizations，但这段分支逻辑必须被测到。
class _FakeL10n implements AppLocalizations {
  const _FakeL10n();

  @override
  String get songTagsSavedToSourceFileAndApp => 'ALL_WRITTEN';

  @override
  String batchSongTagsSavedToSourceFileAndApp(int count) => 'BATCH_ALL_WRITTEN';

  @override
  String get songTagsSavedToApp => 'APP_ONLY';

  @override
  String batchSongTagsSavedToApp(int count) => 'BATCH_APP_ONLY';

  @override
  String tagSavePartiallyWritten(int written, int appOnly) =>
      'PARTIAL_${written}_$appOnly';

  @override
  String get currentFileFormatCannotWriteBack => 'UNSUPPORTED_FORMAT';

  @override
  String get fileOccupiedByOtherApp => 'OCCUPIED';

  @override
  String get saveToSourceFileFailed => 'WRITE_FAILED';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
